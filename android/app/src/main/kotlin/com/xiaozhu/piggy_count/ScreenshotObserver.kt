package com.xiaozhu.piggy_count

import android.content.Context
import android.content.SharedPreferences
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import java.io.File

/**
 * MediaStore ContentObserver：截图稳定期 + 替换关联窗（ADR-045 / ADR-048）。
 *
 * - 稳定期 3s：写稳 / 快捷进编辑；同路径变更重置；可发早期进度，不落库。
 * - 关联窗 15s：另存新文件+删原；窗满（或替换/连拍已决）才回调 Dart 入账。
 * - 短观察 2s：原仍在又来新图 → 旧消失=替换，仍在=连拍。
 */
class ScreenshotObserver(
    private val context: Context,
    private val onScreenshotDetected: (String) -> Unit,
    private val onScreenshotProgress: (String) -> Unit = {},
    private val onScreenshotSuperseded: (oldPath: String, newPath: String) -> Unit = { _, _ -> },
    private val onScreenshotCancelled: (String) -> Unit = {},
    private val onSettleLog: (String) -> Unit = {},
) : ContentObserver(Handler(Looper.getMainLooper())) {

    companion object {
        private const val TAG = "PiggyScreenshot"
        private val KEYWORDS = listOf(
            "screenshot", "截屏", "截图", "screen_shot", "screen shot"
        )
        private const val MAX_AGE_SECONDS = 30L
        private const val PREFS = "piggy_screenshot_monitor"
        private const val KEY_PATHS = "processed_paths"
        private const val MAX_PATHS = 200
        private const val RETRY_MS = 600L
        private const val MAX_ATTEMPTS = 6
        /** 自该路径最近变更起的安静期。 */
        private const val SETTLE_MS = 3000L
        /** 自首次检测起的替换关联窗。 */
        private const val ASSOC_MS = 15000L
        /** 原仍在 + 新图出现时的短观察。 */
        private const val OBSERVE_MS = 2000L
    }

    private data class Candidate(
        val path: String,
        val name: String,
        var lastSize: Long,
        val firstSeenAt: Long,
        /** 替换得到的后继：只再走稳定期，不开满关联窗。 */
        var skipAssocWindow: Boolean = false,
        var settleQuiet: Boolean = false,
        var progressSent: Boolean = false,
        var settleRunnable: Runnable? = null,
        var gateRunnable: Runnable? = null,
        var observeRunnable: Runnable? = null,
        /** 短观察中的对端路径。 */
        var observingPeer: String? = null,
    )

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val handler = Handler(Looper.getMainLooper())
    private val processed = mutableSetOf<String>()
    private val pendingRetries = mutableSetOf<String>()
    private val candidates = mutableMapOf<String, Candidate>()
    private var lastAcceptedAt = 0L

    init {
        val raw = prefs.getString(KEY_PATHS, null)
        if (raw != null) {
            processed.addAll(raw.split("|").filter { it.isNotEmpty() })
        }
    }

    fun dispose() {
        for (c in candidates.values) {
            clearTimers(c)
        }
        candidates.clear()
        pendingRetries.clear()
        handler.removeCallbacksAndMessages(null)
    }

    override fun onChange(selfChange: Boolean, uri: Uri?) {
        super.onChange(selfChange, uri)
        try {
            if (uri != null) {
                checkUri(uri, 0)
            } else {
                scanRecent()
            }
        } catch (e: Exception) {
            Log.e(TAG, "onChange failed", e)
        }
    }

    private fun checkUri(uri: Uri, attempt: Int) {
        try {
            val cursor = context.contentResolver.query(uri, projection(), null, null, null)
            cursor?.use {
                if (!it.moveToFirst()) {
                    pruneMissingCandidates()
                    scheduleRetry(uri, attempt, "empty")
                    return
                }
                val pathIdx = it.getColumnIndex(MediaStore.Images.Media.DATA)
                val nameIdx = it.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                val dateIdx = it.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                val sizeIdx = it.getColumnIndex(MediaStore.Images.Media.SIZE)
                if (pathIdx < 0 || nameIdx < 0 || dateIdx < 0) return

                val path = it.getString(pathIdx) ?: run {
                    scheduleRetry(uri, attempt, "null path")
                    return
                }
                val name = it.getString(nameIdx) ?: ""
                val dateAdded = it.getLong(dateIdx)
                val size = if (sizeIdx >= 0) it.getLong(sizeIdx) else fileSize(path)
                val age = System.currentTimeMillis() / 1000 - dateAdded
                if (age > MAX_AGE_SECONDS) {
                    clearRetry(uri)
                    return
                }
                if (isPending(path, name, readPending(it))) {
                    scheduleRetry(uri, attempt, "pending")
                    return
                }
                clearRetry(uri)
                offerCandidate(path, name, size)
            } ?: scheduleRetry(uri, attempt, "null cursor")
        } catch (e: Exception) {
            Log.e(TAG, "checkUri failed: $uri", e)
            scheduleRetry(uri, attempt, "error")
        }
    }

    private fun scanRecent() {
        try {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            val now = System.currentTimeMillis() / 1000
            val cursor = context.contentResolver.query(
                uri,
                projection(),
                "${MediaStore.Images.Media.DATE_ADDED} > ?",
                arrayOf((now - MAX_AGE_SECONDS).toString()),
                "${MediaStore.Images.Media.DATE_ADDED} DESC"
            )
            cursor?.use {
                val sizeIdx = it.getColumnIndex(MediaStore.Images.Media.SIZE)
                while (it.moveToNext()) {
                    val pathIdx = it.getColumnIndex(MediaStore.Images.Media.DATA)
                    val nameIdx = it.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                    if (pathIdx < 0 || nameIdx < 0) continue
                    val path = it.getString(pathIdx) ?: continue
                    val name = it.getString(nameIdx) ?: ""
                    if (isPending(path, name, readPending(it))) continue
                    val size = if (sizeIdx >= 0) it.getLong(sizeIdx) else fileSize(path)
                    offerCandidate(path, name, size)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "scanRecent failed", e)
        }
    }

    private fun offerCandidate(path: String, name: String, size: Long) {
        val lowerPath = path.lowercase()
        val lowerName = name.lowercase()
        if (KEYWORDS.none { lowerPath.contains(it) || lowerName.contains(it) }) return
        if (processed.contains(path)) return

        val existing = candidates[path]
        if (existing != null) {
            resetSettle(existing, size, reason = "变动重置")
            return
        }

        val now = System.currentTimeMillis()
        val c = Candidate(
            path = path,
            name = name,
            lastSize = size,
            firstSeenAt = now,
        )
        candidates[path] = c
        scheduleSettle(c)
        settleLog(
            "稳定期：检测到新截图，等待 ${SETTLE_MS}ms 静止；关联窗 ${ASSOC_MS}ms file=$name size=$size",
        )

        for (other in candidates.values.toList()) {
            if (other.path == path) continue
            if (!withinAssoc(other, now) && !other.skipAssocWindow) continue
            if (!fileAlive(other.path)) continue
            beginObservation(other, c)
            break
        }
    }

    private fun withinAssoc(c: Candidate, now: Long = System.currentTimeMillis()): Boolean {
        if (c.skipAssocWindow) return false
        return now - c.firstSeenAt <= ASSOC_MS
    }

    private fun resetSettle(c: Candidate, size: Long, reason: String) {
        c.lastSize = size
        c.settleQuiet = false
        c.settleRunnable?.let { handler.removeCallbacks(it) }
        scheduleSettle(c)
        settleLog(
            "稳定期：$reason，重置计时 ${SETTLE_MS}ms file=${c.name} size=$size",
        )
    }

    private fun scheduleSettle(c: Candidate) {
        val r = Runnable { onSettleDue(c.path) }
        c.settleRunnable = r
        handler.postDelayed(r, SETTLE_MS)
    }

    private fun onSettleDue(path: String) {
        val c = candidates[path] ?: return
        if (processed.contains(path)) {
            dropCandidate(path)
            return
        }

        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            settleLog("稳定期：截图已不存在，取消 file=${c.name}")
            handleMissing(path)
            return
        }

        val len = file.length()
        if (len != c.lastSize && c.lastSize > 0L) {
            c.lastSize = len
            scheduleSettle(c)
            settleLog(
                "稳定期：文件大小仍在变化，延长 ${SETTLE_MS}ms file=${c.name} size=$len",
            )
            return
        }

        c.settleQuiet = true
        settleLog("稳定期：已静止 file=${c.name}")

        if (c.observingPeer != null) {
            return
        }

        if (c.skipAssocWindow) {
            tryAccept(c)
            return
        }

        if (!c.progressSent && !hasPeerInAssoc(c)) {
            c.progressSent = true
            settleLog("进度：稳定期满，等待关联窗/入账门闩 file=${c.name}")
            try {
                onScreenshotProgress(path)
            } catch (e: Exception) {
                Log.e(TAG, "onScreenshotProgress failed", e)
            }
        }

        scheduleGate(c)
    }

    private fun hasPeerInAssoc(c: Candidate): Boolean {
        val now = System.currentTimeMillis()
        return candidates.values.any { other ->
            other.path != c.path &&
                fileAlive(other.path) &&
                (withinAssoc(c, now) || withinAssoc(other, now) || other.skipAssocWindow)
        }
    }

    private fun scheduleGate(c: Candidate) {
        c.gateRunnable?.let { handler.removeCallbacks(it) }
        val remaining = (c.firstSeenAt + ASSOC_MS) - System.currentTimeMillis()
        if (remaining <= 0L) {
            onGateDue(c.path)
            return
        }
        val r = Runnable { onGateDue(c.path) }
        c.gateRunnable = r
        handler.postDelayed(r, remaining)
        settleLog("门闩：关联窗剩余 ${remaining}ms 后尝试入账 file=${c.name}")
    }

    private fun onGateDue(path: String) {
        val c = candidates[path] ?: return
        if (c.observingPeer != null) {
            settleLog("门闩：短观察未结束，推迟 file=${c.name}")
            return
        }
        if (!c.settleQuiet) {
            settleLog("门闩：尚未静止，等待稳定期 file=${c.name}")
            return
        }
        // 连拍已由短观察拆成独立候选；此处不再因「还有另一张」而重开观察。
        tryAccept(c)
    }

    private fun beginObservation(a: Candidate, b: Candidate) {
        if (a.path == b.path) return
        if (a.observingPeer == b.path && b.observingPeer == a.path) return

        clearObservation(a)
        clearObservation(b)

        a.observingPeer = b.path
        b.observingPeer = a.path
        a.gateRunnable?.let { handler.removeCallbacks(it) }
        b.gateRunnable?.let { handler.removeCallbacks(it) }
        a.gateRunnable = null
        b.gateRunnable = null

        val r = Runnable { resolveObservation(a.path, b.path) }
        a.observeRunnable = r
        b.observeRunnable = r
        handler.postDelayed(r, OBSERVE_MS)
        settleLog("短观察：开始 ${OBSERVE_MS}ms a=${a.name} b=${b.name}")
    }

    private fun clearObservation(c: Candidate) {
        c.observeRunnable?.let { handler.removeCallbacks(it) }
        c.observeRunnable = null
        val peerPath = c.observingPeer
        c.observingPeer = null
        if (peerPath != null) {
            candidates[peerPath]?.let { peer ->
                if (peer.observingPeer == c.path) {
                    peer.observeRunnable?.let { handler.removeCallbacks(it) }
                    peer.observeRunnable = null
                    peer.observingPeer = null
                }
            }
        }
    }

    private fun resolveObservation(pathA: String, pathB: String) {
        val a = candidates[pathA]
        val b = candidates[pathB]
        val aAlive = a != null && fileAlive(pathA)
        val bAlive = b != null && fileAlive(pathB)

        if (a != null) clearObservation(a)
        if (b != null) clearObservation(b)

        when {
            aAlive && bAlive -> {
                settleLog("短观察：两张都在 → 连拍 a=${a!!.name} b=${b!!.name}")
                if (a.settleQuiet) scheduleGate(a)
                if (b.settleQuiet) scheduleGate(b)
            }
            !aAlive && bAlive -> {
                settleLog("短观察：a 消失 → 替换为 b=${b!!.name}")
                applyReplace(oldPath = pathA, new = b)
            }
            aAlive && !bAlive -> {
                settleLog("短观察：b 消失 → 替换为 a=${a!!.name}")
                applyReplace(oldPath = pathB, new = a)
            }
            else -> {
                settleLog("短观察：两张都消失，取消")
                dropCandidate(pathA)
                dropCandidate(pathB)
            }
        }
    }

    private fun applyReplace(oldPath: String, new: Candidate) {
        val old = candidates[oldPath]
        if (old != null) {
            clearTimers(old)
            candidates.remove(oldPath)
        }
        settleLog("替换：取消旧文件，新文件只再走稳定期 ${SETTLE_MS}ms file=${new.name}")
        try {
            onScreenshotSuperseded(oldPath, new.path)
        } catch (e: Exception) {
            Log.e(TAG, "onScreenshotSuperseded failed", e)
        }

        new.skipAssocWindow = true
        new.settleQuiet = false
        new.progressSent = false
        clearObservation(new)
        new.gateRunnable?.let { handler.removeCallbacks(it) }
        new.gateRunnable = null
        resetSettle(new, new.lastSize, reason = "替换后重等")
    }

    private fun tryAccept(c: Candidate) {
        if (processed.contains(c.path)) {
            dropCandidate(c.path)
            return
        }
        if (!fileAlive(c.path)) {
            settleLog("门闩：文件已不存在，取消 file=${c.name}")
            dropCandidate(c.path)
            return
        }
        if (!c.settleQuiet) return
        if (c.observingPeer != null) return

        val now = System.currentTimeMillis()
        if (now - lastAcceptedAt < 500) {
            handler.postDelayed({
                val again = candidates[c.path] ?: return@postDelayed
                tryAccept(again)
            }, 500L)
            return
        }

        processed.add(c.path)
        lastAcceptedAt = now
        persist()
        clearTimers(c)
        candidates.remove(c.path)
        settleLog("门闩：通过，开始入账 file=${c.name}")
        try {
            onScreenshotDetected(c.path)
        } catch (e: Exception) {
            Log.e(TAG, "onScreenshotDetected failed", e)
        }
        if (processed.size > MAX_PATHS) {
            val drop = processed.take(50).toSet()
            processed.removeAll(drop)
            persist()
        }
    }

    private fun pruneMissingCandidates() {
        val gone = candidates.keys.filter { !fileAlive(it) }
        for (path in gone) {
            handleMissing(path)
        }
    }

    private fun handleMissing(path: String) {
        val c = candidates[path] ?: return
        val peerPath = c.observingPeer
        if (peerPath != null) {
            val peer = candidates[peerPath]
            if (peer != null && fileAlive(peerPath)) {
                settleLog("删除：观察中旧图消失 → 立即按替换处理 file=${c.name}")
                clearObservation(c)
                clearObservation(peer)
                applyReplace(oldPath = path, new = peer)
                return
            }
        }

        val now = System.currentTimeMillis()
        val successor = candidates.values
            .filter {
                it.path != path &&
                    fileAlive(it.path) &&
                    it.firstSeenAt >= c.firstSeenAt &&
                    (withinAssoc(c, now) || withinAssoc(it, now) || it.skipAssocWindow)
            }
            .maxByOrNull { it.firstSeenAt }

        if (successor != null) {
            settleLog("删除：关联窗内有后继 → 替换为 file=${successor.name}")
            applyReplace(oldPath = path, new = successor)
            return
        }

        settleLog("删除：无后继，取消入账 file=${c.name}")
        val progressSent = c.progressSent
        dropCandidate(path)
        if (progressSent) {
            try {
                onScreenshotCancelled(path)
            } catch (e: Exception) {
                Log.e(TAG, "onScreenshotCancelled failed", e)
            }
        }
    }

    private fun dropCandidate(path: String) {
        val c = candidates.remove(path) ?: return
        clearTimers(c)
    }

    private fun clearTimers(c: Candidate) {
        c.settleRunnable?.let { handler.removeCallbacks(it) }
        c.gateRunnable?.let { handler.removeCallbacks(it) }
        clearObservation(c)
        c.settleRunnable = null
        c.gateRunnable = null
    }

    private fun fileAlive(path: String): Boolean {
        return try {
            val f = File(path)
            f.exists() && f.length() > 0L
        } catch (_: Exception) {
            false
        }
    }

    private fun settleLog(message: String) {
        Log.i(TAG, message)
        try {
            onSettleLog(message)
        } catch (e: Exception) {
            Log.e(TAG, "onSettleLog failed", e)
        }
    }

    private fun scheduleRetry(uri: Uri, attempt: Int, reason: String) {
        val next = attempt + 1
        val key = uri.toString()
        if (next > MAX_ATTEMPTS) {
            pendingRetries.remove(key)
            return
        }
        if (attempt == 0 && !pendingRetries.add(key)) return
        pendingRetries.add(key)
        handler.postDelayed({ checkUri(uri, next) }, RETRY_MS * next)
        Log.d(TAG, "retry($reason) #$next $uri")
    }

    private fun clearRetry(uri: Uri) {
        pendingRetries.remove(uri.toString())
    }

    private fun projection(): Array<String> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.SIZE,
                MediaStore.Images.Media.IS_PENDING
            )
        } else {
            arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.SIZE
            )
        }
    }

    private fun readPending(c: Cursor): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val i = c.getColumnIndex(MediaStore.Images.Media.IS_PENDING)
        return i >= 0 && c.getInt(i) == 1
    }

    private fun isPending(path: String, name: String, flag: Boolean): Boolean {
        if (flag) return true
        val p = path.lowercase()
        val n = name.lowercase()
        return n.startsWith(".pending-") || p.contains("/.pending-") || n.contains(".pending-")
    }

    private fun fileSize(path: String): Long {
        return try {
            File(path).length()
        } catch (_: Exception) {
            0L
        }
    }

    private fun persist() {
        val list = processed.toList().let {
            if (it.size > MAX_PATHS) it.takeLast(MAX_PATHS) else it
        }
        prefs.edit().putString(KEY_PATHS, list.joinToString("|")).apply()
    }
}
