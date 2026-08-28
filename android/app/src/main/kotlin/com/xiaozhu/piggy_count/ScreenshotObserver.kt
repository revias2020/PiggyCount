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
import kotlin.math.min

/**
 * MediaStore ContentObserver：截图稳定期 + 替换关联窗（ADR-045 / ADR-048 / ADR-064）。
 *
 * - 稳定期 3s：写稳 / 快捷进编辑；同路径变更重置；可发早期进度，不落库。
 * - 关联窗 15s：自**最近一次稳定期满**起算；另存新文件+删原；窗满（或替换/连拍已决）才回调 Dart 入账。
 * - 候选总时限 2min：自首次检出硬切，超时取消并通知。
 * - 短观察 2s：原仍在又来新图 → 旧消失=替换，仍在=连拍。
 * - 删原补扫：原不在且无后继时，同目录 + 关键词 + ±15s 再认一张。
 * - 非候选过滤：回收站 / IS_TRASHED / trash·@delete 编码名不进稳定期。
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
        /** 自最近一次稳定期满起的替换关联窗（ADR-064）。 */
        private const val ASSOC_MS = 15000L
        /** 自首次检出起的候选总时限（ADR-064）。 */
        private const val CAP_MS = 120_000L
        /** 原仍在 + 新图出现时的短观察。 */
        private const val OBSERVE_MS = 2000L
        /** 删原补扫：新图 DATE_ADDED 相对「现在」的近时窗。 */
        private const val RESCAN_SLACK_SEC = 15L
    }

    private data class Candidate(
        val path: String,
        val name: String,
        var lastSize: Long,
        val firstSeenAt: Long,
        /** 替换得到的后继：只再走稳定期，不开满关联窗。 */
        var skipAssocWindow: Boolean = false,
        var settleQuiet: Boolean = false,
        /** 最近一次进入静止的时间；未静止为 0。 */
        var settleQuietAt: Long = 0L,
        var progressSent: Boolean = false,
        var settleRunnable: Runnable? = null,
        var gateRunnable: Runnable? = null,
        var capRunnable: Runnable? = null,
        var observeRunnable: Runnable? = null,
        /** 短观察中的对端路径。 */
        var observingPeer: String? = null,
    )

    private data class RescanHit(
        val path: String,
        val name: String,
        val size: Long,
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
                offerCandidate(path, name, size, trashed = readTrashed(it))
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
                    offerCandidate(path, name, size, trashed = readTrashed(it))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "scanRecent failed", e)
        }
    }

    private fun offerCandidate(path: String, name: String, size: Long, trashed: Boolean = false) {
        val lowerPath = path.lowercase()
        val lowerName = name.lowercase()
        val keywordHit = KEYWORDS.any { lowerPath.contains(it) || lowerName.contains(it) }
        if (ScreenshotNonCandidate.matches(path, name, trashed)) {
            if (keywordHit) {
                settleLog("非候选：trash/已删 file=$name")
            }
            if (candidates.containsKey(path)) {
                cancelWithNotify(path)
            }
            return
        }
        if (!keywordHit) return
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
        scheduleCap(c)
        settleLog(
            "稳定期：检测到新截图，等待 ${SETTLE_MS}ms 静止；关联窗 ${ASSOC_MS}ms（自稳定期满）；" +
                "总时限 ${CAP_MS}ms file=$name size=$size",
        )

        for (other in candidates.values.toList()) {
            if (other.path == path) continue
            if (!withinCap(other, now) && !other.skipAssocWindow) continue
            if (!fileAlive(other.path)) continue
            beginObservation(other, c)
            break
        }
    }

    /** 候选仍在总时限内，可与新图做短观察 / 后继关联（ADR-064）。 */
    private fun withinCap(c: Candidate, now: Long = System.currentTimeMillis()): Boolean {
        return now - c.firstSeenAt <= CAP_MS
    }

    private fun resetSettle(c: Candidate, size: Long, reason: String) {
        c.lastSize = size
        c.settleQuiet = false
        c.settleQuietAt = 0L
        c.settleRunnable?.let { handler.removeCallbacks(it) }
        c.gateRunnable?.let { handler.removeCallbacks(it) }
        c.gateRunnable = null
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

    private fun scheduleCap(c: Candidate) {
        c.capRunnable?.let { handler.removeCallbacks(it) }
        val remaining = (c.firstSeenAt + CAP_MS) - System.currentTimeMillis()
        if (remaining <= 0L) {
            onCapDue(c.path)
            return
        }
        val r = Runnable { onCapDue(c.path) }
        c.capRunnable = r
        handler.postDelayed(r, remaining)
    }

    private fun onCapDue(path: String) {
        val c = candidates[path] ?: return
        settleLog("总时限：${CAP_MS}ms 到期，取消 file=${c.name}")
        cancelWithNotify(path)
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
        c.settleQuietAt = System.currentTimeMillis()

        if (c.observingPeer != null) {
            return
        }

        if (c.skipAssocWindow) {
            tryAccept(c)
            return
        }

        if (!c.progressSent && !hasPeerInAssoc(c)) {
            c.progressSent = true
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
                (withinCap(c, now) || withinCap(other, now) || other.skipAssocWindow)
        }
    }

    private fun scheduleGate(c: Candidate) {
        c.gateRunnable?.let { handler.removeCallbacks(it) }
        if (c.skipAssocWindow) {
            onGateDue(c.path)
            return
        }
        if (!c.settleQuiet || c.settleQuietAt <= 0L) {
            return
        }
        val now = System.currentTimeMillis()
        val assocDeadline = c.settleQuietAt + ASSOC_MS
        val capDeadline = c.firstSeenAt + CAP_MS
        val deadline = min(assocDeadline, capDeadline)
        val remaining = deadline - now
        if (remaining <= 0L) {
            onGateDue(c.path)
            return
        }
        val r = Runnable { onGateDue(c.path) }
        c.gateRunnable = r
        handler.postDelayed(r, remaining)
    }

    private fun onGateDue(path: String) {
        val c = candidates[path] ?: return
        if (c.observingPeer != null) {
            return
        }
        if (!c.settleQuiet) {
            return
        }
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
                dropCandidate(pathB)
                cancelWithNotify(pathA)
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
        new.settleQuietAt = 0L
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
            settleLog("门闩：文件已不存在，尝试补扫 file=${c.name}")
            handleMissing(c.path)
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
                    (withinCap(c, now) || withinCap(it, now) || it.skipAssocWindow)
            }
            .maxByOrNull { it.firstSeenAt }

        if (successor != null) {
            settleLog("删除：关联窗内有后继 → 替换为 file=${successor.name}")
            applyReplace(oldPath = path, new = successor)
            return
        }

        val hit = rescanNearbyScreenshot(c)
        if (hit != null) {
            settleLog("删原补扫：命中 file=${hit.name}")
            val existing = candidates[hit.path]
            val newC = existing ?: Candidate(
                path = hit.path,
                name = hit.name,
                lastSize = hit.size,
                firstSeenAt = System.currentTimeMillis(),
            ).also {
                candidates[it.path] = it
                scheduleCap(it)
            }
            applyReplace(oldPath = path, new = newC)
            return
        }

        settleLog("删除：无后继，取消入账 file=${c.name}")
        cancelWithNotify(path)
    }

    /**
     * 原图已不在且内存无后继：同目录、截图关键词、DATE_ADDED 相对现在 ±15s 的最新一张。
     */
    private fun rescanNearbyScreenshot(old: Candidate): RescanHit? {
        val oldDir = try {
            File(old.path).parentFile?.canonicalPath
        } catch (_: Exception) {
            null
        } ?: return null

        val nowSec = System.currentTimeMillis() / 1000
        val minSec = nowSec - RESCAN_SLACK_SEC
        val maxSec = nowSec + RESCAN_SLACK_SEC
        try {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            val cursor = context.contentResolver.query(
                uri,
                projection(),
                "${MediaStore.Images.Media.DATE_ADDED} >= ? AND ${MediaStore.Images.Media.DATE_ADDED} <= ?",
                arrayOf(minSec.toString(), maxSec.toString()),
                "${MediaStore.Images.Media.DATE_ADDED} DESC"
            )
            cursor?.use {
                val pathIdx = it.getColumnIndex(MediaStore.Images.Media.DATA)
                val nameIdx = it.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                val sizeIdx = it.getColumnIndex(MediaStore.Images.Media.SIZE)
                if (pathIdx < 0 || nameIdx < 0) return null
                while (it.moveToNext()) {
                    val path = it.getString(pathIdx) ?: continue
                    if (path == old.path) continue
                    if (processed.contains(path)) continue
                    val name = it.getString(nameIdx) ?: ""
                    if (isPending(path, name, readPending(it))) continue
                    if (ScreenshotNonCandidate.matches(path, name, readTrashed(it))) continue
                    val lowerPath = path.lowercase()
                    val lowerName = name.lowercase()
                    if (KEYWORDS.none { k -> lowerPath.contains(k) || lowerName.contains(k) }) {
                        continue
                    }
                    val dir = try {
                        File(path).parentFile?.canonicalPath
                    } catch (_: Exception) {
                        null
                    } ?: continue
                    if (dir != oldDir) continue
                    if (!fileAlive(path)) continue
                    val size = if (sizeIdx >= 0) it.getLong(sizeIdx) else fileSize(path)
                    return RescanHit(path = path, name = name, size = size)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "rescanNearbyScreenshot failed", e)
        }
        return null
    }

    private fun cancelWithNotify(path: String) {
        if (!candidates.containsKey(path)) return
        dropCandidate(path)
        try {
            onScreenshotCancelled(path)
        } catch (e: Exception) {
            Log.e(TAG, "onScreenshotCancelled failed", e)
        }
    }

    private fun dropCandidate(path: String) {
        val c = candidates.remove(path) ?: return
        clearTimers(c)
    }

    private fun clearTimers(c: Candidate) {
        c.settleRunnable?.let { handler.removeCallbacks(it) }
        c.gateRunnable?.let { handler.removeCallbacks(it) }
        c.capRunnable?.let { handler.removeCallbacks(it) }
        clearObservation(c)
        c.settleRunnable = null
        c.gateRunnable = null
        c.capRunnable = null
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
        val cols = mutableListOf(
            MediaStore.Images.Media._ID,
            MediaStore.Images.Media.DATA,
            MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DISPLAY_NAME,
            MediaStore.Images.Media.SIZE,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            cols.add(MediaStore.Images.Media.IS_PENDING)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            cols.add(MediaStore.Images.Media.IS_TRASHED)
        }
        return cols.toTypedArray()
    }

    private fun readPending(c: Cursor): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val i = c.getColumnIndex(MediaStore.Images.Media.IS_PENDING)
        return i >= 0 && c.getInt(i) == 1
    }

    private fun readTrashed(c: Cursor): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        val i = c.getColumnIndex(MediaStore.Images.Media.IS_TRASHED)
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
