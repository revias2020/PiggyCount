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
 * MediaStore ContentObserver：检测新截图（含 Android 10+ pending 写入重试 + 截图稳定期）。
 *
 * 稳定期（ADR-045）：候选出现后等待文件静止再回调 Dart；同路径再变更则重置计时；
 * 稳定期结束前不写入已处理集。覆盖同路径的系统编辑（小米/华为/OPPO/vivo 常见）友好。
 */
class ScreenshotObserver(
    private val context: Context,
    private val onScreenshotDetected: (String) -> Unit,
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
        /** 自最近一次 MediaStore 变更起的安静期（多 OEM 截图后编辑窗）。 */
        private const val SETTLE_MS = 2000L
    }

    private data class SettleCandidate(
        val path: String,
        val name: String,
        var lastSize: Long,
        var runnable: Runnable,
    )

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val handler = Handler(Looper.getMainLooper())
    private val processed = mutableSetOf<String>()
    private val pendingRetries = mutableSetOf<String>()
    private val settling = mutableMapOf<String, SettleCandidate>()
    private var lastAcceptedAt = 0L

    init {
        val raw = prefs.getString(KEY_PATHS, null)
        if (raw != null) {
            processed.addAll(raw.split("|").filter { it.isNotEmpty() })
        }
    }

    /** 停止监听时取消未完成的稳定期与重试。 */
    fun dispose() {
        for (c in settling.values) {
            handler.removeCallbacks(c.runnable)
        }
        settling.clear()
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
                    // 条目消失：可能是预览里删除
                    pruneMissingSettles()
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

    /**
     * 进入或重置稳定期；**此时不**写入 [processed]、不回调 Dart。
     */
    private fun offerCandidate(path: String, name: String, size: Long) {
        val lowerPath = path.lowercase()
        val lowerName = name.lowercase()
        if (KEYWORDS.none { lowerPath.contains(it) || lowerName.contains(it) }) return
        if (processed.contains(path)) return

        val existing = settling[path]
        if (existing != null) {
            handler.removeCallbacks(existing.runnable)
            existing.lastSize = size
            existing.runnable = settleRunnable(path)
            handler.postDelayed(existing.runnable, SETTLE_MS)
            settleLog(
                "稳定期：检测到截图变动（可能编辑/覆盖），重置计时 ${SETTLE_MS}ms file=$name size=$size",
            )
            return
        }

        val runnable = settleRunnable(path)
        settling[path] = SettleCandidate(path, name, size, runnable)
        handler.postDelayed(runnable, SETTLE_MS)
        settleLog(
            "稳定期：检测到新截图，等待 ${SETTLE_MS}ms 静止后入账 file=$name size=$size",
        )
    }

    private fun settleRunnable(path: String): Runnable = Runnable {
        finishSettle(path)
    }

    private fun finishSettle(path: String) {
        val candidate = settling.remove(path) ?: return
        if (processed.contains(path)) return

        val file = File(path)
        if (!file.exists() || file.length() <= 0L) {
            settleLog("稳定期：截图已不存在，取消入账 file=${candidate.name}")
            return
        }

        // 期满瞬间仍在变大：再等一轮（部分 OEM 写完后才更新 MediaStore）
        val len = file.length()
        if (len != candidate.lastSize && candidate.lastSize > 0L) {
            candidate.lastSize = len
            candidate.runnable = settleRunnable(path)
            settling[path] = candidate
            handler.postDelayed(candidate.runnable, SETTLE_MS)
            settleLog(
                "稳定期：文件大小仍在变化，延长等待 ${SETTLE_MS}ms file=${candidate.name} size=$len",
            )
            return
        }

        val now = System.currentTimeMillis()
        if (now - lastAcceptedAt < 500) {
            // 极短连发保护：稍后再试，仍不入 processed
            candidate.runnable = settleRunnable(path)
            settling[path] = candidate
            handler.postDelayed(candidate.runnable, 500L)
            return
        }

        processed.add(path)
        lastAcceptedAt = now
        persist()
        settleLog("稳定期：已静止，开始入账 file=${candidate.name}")
        onScreenshotDetected(path)
        if (processed.size > MAX_PATHS) {
            val drop = processed.take(50).toSet()
            processed.removeAll(drop)
            persist()
        }
    }

    /** 稳定期内文件已被删（系统预览删除）→ 取消，避免误入账。 */
    private fun pruneMissingSettles() {
        val gone = settling.keys.filter { path ->
            try {
                !File(path).exists()
            } catch (_: Exception) {
                true
            }
        }
        for (path in gone) {
            val c = settling.remove(path) ?: continue
            handler.removeCallbacks(c.runnable)
            settleLog("稳定期：检测到截图被删除，取消入账 file=${c.name}")
        }
    }

    /** Logcat + 程序日志（经 MethodChannel）。 */
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
