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
 * MediaStore ContentObserver：单关联窗 + 短观察 + 删原短等（ADR-068；取代 045/048/064 中稳定期与 ±15s 补扫）。
 *
 * - 关联窗 15s：自首次检出起算；同路径不重置；检出即原生 FGS 早期进度，窗满才回调 Dart 入账。
 * - 同路径再 offer：名称+size 未变则忽略；有变也不重置时钟（门闩读当前磁盘文件）。
 * - 短观察 2s：原仍在又来新图 → 旧消失=替换，仍在=连拍。
 * - 删原短等 2s：原不在且内存无后继 → 等新候选；来了=替换，超时取消。
 * - 真替换：立刻入账门闩（不再等剩余关联窗）。
 * - 非候选过滤：回收站 / IS_TRASHED / trash·@delete 编码名不进候选。
 * - 监听目录 ∩ 关键词（ADR-070）：空目录时不应注册本 Observer。
 */
class ScreenshotObserver(
    private val context: Context,
    private val onScreenshotDetected: (String) -> Unit,
    private val onScreenshotProgress: (String) -> Unit = {},
    private val onScreenshotSuperseded: (oldPath: String, newPath: String) -> Unit = { _, _ -> },
    private val onScreenshotCancelled: (String) -> Unit = {},
    private val     onSettleLog: (String) -> Unit = {},
    initialWatchDirectories: Collection<String> = emptyList(),
) : ContentObserver(Handler(Looper.getMainLooper())) {

    companion object {
        private const val TAG = "PiggyScreenshot"
        private const val MAX_AGE_SECONDS = 30L
        private const val PREFS = "piggy_screenshot_monitor"
        private const val KEY_PATHS = "processed_paths"
        private const val MAX_PATHS = 200
        private const val RETRY_MS = 600L
        private const val MAX_ATTEMPTS = 6
        /** 自首次检出起的替换关联窗（ADR-068）。 */
        private const val ASSOC_MS = 15000L
        /** 原仍在 + 新图出现时的短观察。 */
        private const val OBSERVE_MS = 2000L
        /** 删原且内存无后继时，等待新候选出现。 */
        private const val DELETE_WAIT_MS = 2000L
    }

    private data class Candidate(
        val path: String,
        val name: String,
        var lastSize: Long,
        val firstSeenAt: Long,
        var progressSent: Boolean = false,
        /** 删原短等中：文件已不在，等新 path。 */
        var awaitingSuccessor: Boolean = false,
        var gateRunnable: Runnable? = null,
        var observeRunnable: Runnable? = null,
        var deleteWaitRunnable: Runnable? = null,
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
    private val watchDirectories = initialWatchDirectories
        .mapNotNull { ScreenshotWatchPaths.normalize(it) }
        .toMutableSet()

    init {
        val raw = prefs.getString(KEY_PATHS, null)
        if (raw != null) {
            processed.addAll(raw.split("|").filter { it.isNotEmpty() })
        }
    }

    /** 热更新监听目录；返回更新后是否仍有有效目录。 */
    fun setWatchDirectories(dirs: Collection<String>): Boolean {
        watchDirectories.clear()
        watchDirectories.addAll(dirs.mapNotNull { ScreenshotWatchPaths.normalize(it) })
        return watchDirectories.isNotEmpty()
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
        val keywordHit = ScreenshotWatchPaths.keywordHit(path, name)
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
        if (watchDirectories.isEmpty()) return
        if (!ScreenshotWatchPaths.matches(path, watchDirectories)) return
        if (processed.contains(path)) return

        val existing = candidates[path]
        if (existing != null) {
            handleSamePathOffer(existing, name, size)
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

        val waiter = candidates.values.firstOrNull {
            it.path != path && it.awaitingSuccessor
        }
        if (waiter != null) {
            settleLog("删原短等：命中后继 file=$name ← ${waiter.name}")
            applyReplace(oldPath = waiter.path, new = c)
            return
        }

        settleLog(
            "关联窗：检测到新截图，等待 ${ASSOC_MS / 1000}s；" +
                "短观察/删原短等各 ${OBSERVE_MS / 1000}s file=$name size=$size",
        )
        emitEarlyProgress(c)

        for (other in candidates.values.toList()) {
            if (other.path == path) continue
            if (other.awaitingSuccessor) continue
            if (!fileAlive(other.path)) continue
            beginObservation(other, c)
            return
        }

        scheduleGate(c)
    }

    private fun handleSamePathOffer(existing: Candidate, name: String, size: Long) {
        if (existing.awaitingSuccessor) {
            if (fileAlive(existing.path)) {
                existing.awaitingSuccessor = false
                existing.deleteWaitRunnable?.let { handler.removeCallbacks(it) }
                existing.deleteWaitRunnable = null
                existing.lastSize = size
                settleLog("删原短等：原路径恢复，继续关联窗 file=${existing.name}")
                scheduleGate(existing)
            }
            return
        }
        if (existing.name == name && existing.lastSize == size) {
            settleLog("同路径：忽略（名称与大小未变）file=$name size=$size")
            return
        }
        existing.lastSize = size
        settleLog("同路径：不重置关联窗 file=$name size=$size")
    }

    private fun emitEarlyProgress(c: Candidate) {
        if (c.progressSent) return
        c.progressSent = true
        try {
            onScreenshotProgress(c.path)
        } catch (e: Exception) {
            Log.e(TAG, "onScreenshotProgress failed", e)
        }
    }

    private fun scheduleGate(c: Candidate) {
        c.gateRunnable?.let { handler.removeCallbacks(it) }
        c.gateRunnable = null
        if (c.awaitingSuccessor) return
        if (c.observingPeer != null) return

        val now = System.currentTimeMillis()
        val remaining = (c.firstSeenAt + ASSOC_MS) - now
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
        if (c.observingPeer != null) return
        if (c.awaitingSuccessor) return
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

        settleLog("短观察：开始 ${OBSERVE_MS / 1000}s a=${a.name} b=${b.name}")

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
        val aAlive = a != null && !a.awaitingSuccessor && fileAlive(pathA)
        val bAlive = b != null && !b.awaitingSuccessor && fileAlive(pathB)

        if (a != null) clearObservation(a)
        if (b != null) clearObservation(b)

        when {
            aAlive && bAlive -> {
                settleLog("短观察：两张都在 → 连拍 a=${a!!.name} b=${b!!.name}")
                scheduleGate(a)
                scheduleGate(b)
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
        settleLog("替换：立刻入账 file=${new.name}")
        try {
            onScreenshotSuperseded(oldPath, new.path)
        } catch (e: Exception) {
            Log.e(TAG, "onScreenshotSuperseded failed", e)
        }

        new.awaitingSuccessor = false
        clearObservation(new)
        new.gateRunnable?.let { handler.removeCallbacks(it) }
        new.gateRunnable = null
        new.deleteWaitRunnable?.let { handler.removeCallbacks(it) }
        new.deleteWaitRunnable = null
        tryAccept(new)
    }

    private fun tryAccept(c: Candidate) {
        if (processed.contains(c.path)) {
            dropCandidate(c.path)
            return
        }
        if (c.awaitingSuccessor) return
        if (!fileAlive(c.path)) {
            settleLog("门闩：文件已不存在 file=${c.name}")
            handleMissing(c.path)
            return
        }
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
        val gone = candidates.keys.filter { path ->
            val c = candidates[path] ?: return@filter false
            if (c.awaitingSuccessor) return@filter false
            !fileAlive(path)
        }
        for (path in gone) {
            handleMissing(path)
        }
    }

    private fun handleMissing(path: String) {
        val c = candidates[path] ?: return
        if (c.awaitingSuccessor) return

        val peerPath = c.observingPeer
        if (peerPath != null) {
            val peer = candidates[peerPath]
            if (peer != null && fileAlive(peerPath) && !peer.awaitingSuccessor) {
                settleLog("删除：观察中旧图消失 → 立即按替换处理 file=${c.name}")
                clearObservation(c)
                clearObservation(peer)
                applyReplace(oldPath = path, new = peer)
                return
            }
        }

        val successor = candidates.values
            .filter {
                it.path != path &&
                    !it.awaitingSuccessor &&
                    fileAlive(it.path) &&
                    it.firstSeenAt >= c.firstSeenAt
            }
            .maxByOrNull { it.firstSeenAt }

        if (successor != null) {
            settleLog("删除：内存有后继 → 替换为 file=${successor.name}")
            applyReplace(oldPath = path, new = successor)
            return
        }

        startDeleteWait(c)
    }

    private fun startDeleteWait(c: Candidate) {
        c.gateRunnable?.let { handler.removeCallbacks(it) }
        c.gateRunnable = null
        clearObservation(c)
        c.awaitingSuccessor = true
        c.deleteWaitRunnable?.let { handler.removeCallbacks(it) }
        settleLog("删原短等：等待 ${DELETE_WAIT_MS / 1000}s 内出现新截图 file=${c.name}")
        val r = Runnable { onDeleteWaitDue(c.path) }
        c.deleteWaitRunnable = r
        handler.postDelayed(r, DELETE_WAIT_MS)
    }

    private fun onDeleteWaitDue(path: String) {
        val c = candidates[path] ?: return
        if (!c.awaitingSuccessor) return
        val successor = candidates.values
            .filter {
                it.path != path &&
                    !it.awaitingSuccessor &&
                    fileAlive(it.path)
            }
            .maxByOrNull { it.firstSeenAt }
        if (successor != null) {
            settleLog("删原短等：到期命中后继 file=${successor.name}")
            applyReplace(oldPath = path, new = successor)
            return
        }
        settleLog("删原短等：超时无后继，取消 file=${c.name}")
        cancelWithNotify(path)
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
        c.gateRunnable?.let { handler.removeCallbacks(it) }
        c.deleteWaitRunnable?.let { handler.removeCallbacks(it) }
        clearObservation(c)
        c.gateRunnable = null
        c.deleteWaitRunnable = null
        c.awaitingSuccessor = false
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
