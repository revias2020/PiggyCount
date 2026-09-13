package com.xiaozhu.piggy_count

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns

/**
 * 近期截图/分享原名 FIFO（长度 50；ADR-077）。
 *
 * 用于分享入账（cache 路径）与相册原图路径不一致时，补扫/门闩按 DISPLAY_NAME 兜底去重。
 * 查不到原名或低区分度名（如 image.jpg）不入队。
 */
internal object ScreenshotNameFifo {
    private const val PREFS = "piggy_screenshot_monitor"
    private const val KEY = "processed_names_fifo"
    private const val MAX = 50

    private val lowSignalNames = setOf(
        "image.jpg",
        "image.jpeg",
        "image.png",
        "image.webp",
        "image.gif",
        "photo.jpg",
        "photo.jpeg",
        "photo.png",
        "img.jpg",
        "img.jpeg",
        "img.png",
        "picture.jpg",
        "picture.jpeg",
        "picture.png",
    )

    fun remember(context: Context, name: String?) {
        val n = usableName(name) ?: return
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val list = load(prefs).toMutableList()
        list.removeAll { it.equals(n, ignoreCase = true) }
        list.add(n)
        while (list.size > MAX) {
            list.removeAt(0)
        }
        prefs.edit().putString(KEY, list.joinToString("|")).apply()
    }

    fun contains(context: Context, name: String?): Boolean {
        val n = usableName(name) ?: return false
        return load(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE))
            .any { it.equals(n, ignoreCase = true) }
    }

    /** 从分享 Uri 解析原 DISPLAY_NAME；失败返回 null（调用方应跳过入队）。 */
    fun displayNameOf(context: Context, uri: Uri): String? {
        try {
            context.contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { c ->
                if (c.moveToFirst()) {
                    val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        val raw = c.getString(idx)
                        usableName(raw)?.let { return it }
                    }
                }
            }
        } catch (_: Exception) {
            // 查不到则不入队
        }
        val seg = uri.lastPathSegment ?: return null
        // content 主键段（纯数字）不是文件名
        if (seg.all { it.isDigit() }) return null
        return usableName(seg.substringAfterLast('/'))
    }

    private fun usableName(raw: String?): String? {
        val n = raw?.trim().orEmpty()
        if (n.isEmpty()) return null
        if (lowSignalNames.contains(n.lowercase())) return null
        return n
    }

    private fun load(prefs: android.content.SharedPreferences): List<String> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        return raw.split("|").map { it.trim() }.filter { it.isNotEmpty() }
    }
}
