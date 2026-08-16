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

/**
 * MediaStore ContentObserver：检测新截图（含 Android 10+ pending 写入重试）。
 *
 * 思路对齐 BeeCount ScreenshotObserver，去掉日志桥接依赖。
 */
class ScreenshotObserver(
    private val context: Context,
    private val onScreenshotDetected: (String) -> Unit
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
    }

    private val prefs: SharedPreferences =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val handler = Handler(Looper.getMainLooper())
    private val processed = mutableSetOf<String>()
    private val pendingRetries = mutableSetOf<String>()
    private var lastAcceptedAt = 0L

    init {
        val raw = prefs.getString(KEY_PATHS, null)
        if (raw != null) {
            processed.addAll(raw.split("|").filter { it.isNotEmpty() })
        }
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
                    scheduleRetry(uri, attempt, "empty")
                    return
                }
                val pathIdx = it.getColumnIndex(MediaStore.Images.Media.DATA)
                val nameIdx = it.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                val dateIdx = it.getColumnIndex(MediaStore.Images.Media.DATE_ADDED)
                if (pathIdx < 0 || nameIdx < 0 || dateIdx < 0) return

                val path = it.getString(pathIdx) ?: run {
                    scheduleRetry(uri, attempt, "null path")
                    return
                }
                val name = it.getString(nameIdx) ?: ""
                val dateAdded = it.getLong(dateIdx)
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
                accept(path, name)
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
                while (it.moveToNext()) {
                    val pathIdx = it.getColumnIndex(MediaStore.Images.Media.DATA)
                    val nameIdx = it.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                    if (pathIdx < 0 || nameIdx < 0) continue
                    val path = it.getString(pathIdx) ?: continue
                    val name = it.getString(nameIdx) ?: ""
                    if (isPending(path, name, readPending(it))) continue
                    accept(path, name)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "scanRecent failed", e)
        }
    }

    private fun accept(path: String, name: String) {
        val lowerPath = path.lowercase()
        val lowerName = name.lowercase()
        if (KEYWORDS.none { lowerPath.contains(it) || lowerName.contains(it) }) return
        if (processed.contains(path)) return
        val now = System.currentTimeMillis()
        if (now - lastAcceptedAt < 500) return

        processed.add(path)
        lastAcceptedAt = now
        persist()
        Log.i(TAG, "screenshot: $path")
        onScreenshotDetected(path)
        if (processed.size > MAX_PATHS) {
            val drop = processed.take(50).toSet()
            processed.removeAll(drop)
            persist()
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
                MediaStore.Images.Media.IS_PENDING
            )
        } else {
            arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.DATE_ADDED,
                MediaStore.Images.Media.DISPLAY_NAME
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

    private fun persist() {
        val list = processed.toList().let {
            if (it.size > MAX_PATHS) it.takeLast(MAX_PATHS) else it
        }
        prefs.edit().putString(KEY_PATHS, list.joinToString("|")).apply()
    }
}
