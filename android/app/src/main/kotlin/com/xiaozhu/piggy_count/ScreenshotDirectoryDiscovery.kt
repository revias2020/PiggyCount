package com.xiaozhu.piggy_count

import android.content.Context
import android.os.Build
import android.provider.MediaStore
import android.util.Log

/**
 * 目录发现扫描：MediaStore 关键词命中 → 去重父目录（ADR-070）。
 */
object ScreenshotDirectoryDiscovery {
    private const val TAG = "PiggyScreenshot"
    private const val MAX_ROWS = 2000

    fun discover(context: Context): List<String> {
        val found = linkedSetOf<String>()
        try {
            val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }
            val cols = mutableListOf(
                MediaStore.Images.Media.DATA,
                MediaStore.Images.Media.DISPLAY_NAME,
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                cols.add(MediaStore.Images.Media.RELATIVE_PATH)
            }
            val cursor = context.contentResolver.query(
                uri,
                cols.toTypedArray(),
                null,
                null,
                "${MediaStore.Images.Media.DATE_ADDED} DESC",
            ) ?: return emptyList()
            cursor.use {
                val pathIdx = it.getColumnIndex(MediaStore.Images.Media.DATA)
                val nameIdx = it.getColumnIndex(MediaStore.Images.Media.DISPLAY_NAME)
                val relIdx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    it.getColumnIndex(MediaStore.Images.Media.RELATIVE_PATH)
                } else {
                    -1
                }
                var n = 0
                while (it.moveToNext() && n < MAX_ROWS) {
                    n++
                    val path = if (pathIdx >= 0) it.getString(pathIdx) ?: "" else ""
                    val name = if (nameIdx >= 0) it.getString(nameIdx) ?: "" else ""
                    val rel = if (relIdx >= 0) it.getString(relIdx) else null
                    val hay = listOf(path, name, rel ?: "").joinToString("\n")
                    if (!ScreenshotWatchPaths.keywordHit(hay, name)) continue
                    if (ScreenshotNonCandidate.matches(path, name)) continue
                    val key = ScreenshotWatchPaths.directoryKey(path, rel) ?: continue
                    found.add(key)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "discover watch dirs failed", e)
        }
        return found.toList().sorted()
    }
}
