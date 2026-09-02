package com.xiaozhu.piggy_count

/**
 * 监听目录路径规范化与匹配（ADR-070 · 方案 A）。
 *
 * 持久化形态优先为相对路径，如 `Pictures/Screenshots`（无首尾 `/`）。
 * 匹配时同时接受绝对前缀与「`/相对路径/`」片段。
 */
object ScreenshotWatchPaths {
    private val KEYWORDS = listOf(
        "screenshot", "截屏", "截图", "screen_shot", "screen shot",
    )

    private val STORAGE_ROOT_PREFIXES = listOf(
        "/storage/emulated/0/",
        "/sdcard/",
        "/mnt/sdcard/",
        "/storage/self/primary/",
    )

    fun normalize(raw: String): String? {
        var s = raw.trim().replace('\\', '/')
        if (s.isEmpty()) return null
        if (s.startsWith("content:", ignoreCase = true)) return null
        while (s.endsWith("/")) {
            s = s.dropLast(1)
        }
        if (s.isEmpty()) return null
        val lower = s.lowercase()
        for (root in STORAGE_ROOT_PREFIXES) {
            if (lower.startsWith(root)) {
                s = s.substring(root.length)
                break
            }
        }
        while (s.startsWith("/")) {
            s = s.drop(1)
        }
        while (s.endsWith("/")) {
            s = s.dropLast(1)
        }
        return s.ifEmpty { null }
    }

    /** 文件是否落在某一监听目录下（目录本身或其子路径）。 */
    fun matches(filePath: String, watchDirs: Collection<String>): Boolean {
        if (watchDirs.isEmpty()) return false
        val fileNorm = filePath.replace('\\', '/').trim()
        if (fileNorm.isEmpty()) return false
        val fileLower = fileNorm.lowercase()
        val parentAbs = fileNorm.substringBeforeLast('/', missingDelimiterValue = "")
        val parentRel = normalize(parentAbs) ?: ""
        val parentRelLower = parentRel.lowercase()

        for (rawDir in watchDirs) {
            val dir = normalize(rawDir) ?: continue
            val dirLower = dir.lowercase()
            if (parentRelLower == dirLower) return true
            if (parentRelLower.startsWith("$dirLower/")) return true
            // 绝对路径前缀（未剥根时仍可比）
            val absCandidates = STORAGE_ROOT_PREFIXES.map { "$it$dir" }
            for (abs in absCandidates) {
                val absLower = abs.lowercase()
                if (fileLower.startsWith("$absLower/") || fileLower == absLower) {
                    return true
                }
            }
            if (fileLower.contains("/$dirLower/")) return true
        }
        return false
    }

    fun keywordHit(path: String, name: String): Boolean {
        val lowerPath = path.lowercase()
        val lowerName = name.lowercase()
        return KEYWORDS.any { lowerPath.contains(it) || lowerName.contains(it) }
    }

    /**
     * 从完整文件路径或 MediaStore RELATIVE_PATH 推导监听目录键。
     * [relativePath] 形如 `Pictures/Screenshots/`（目录，非文件名）。
     */
    fun directoryKey(absolutePath: String?, relativePath: String?): String? {
        val fromRel = relativePath?.let { normalize(it) }
        if (!fromRel.isNullOrEmpty()) return fromRel
        if (absolutePath.isNullOrBlank()) return null
        val parent = absolutePath.replace('\\', '/').substringBeforeLast('/', "")
        return normalize(parent)
    }
}
