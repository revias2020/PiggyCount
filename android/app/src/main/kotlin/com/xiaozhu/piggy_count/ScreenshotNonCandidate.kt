package com.xiaozhu.piggy_count

/**
 * 截图非候选：回收站 / 已删标记等不得进入关联窗候选。
 * 信号为 OR（宁可多滤）。
 */
object ScreenshotNonCandidate {
    fun matches(path: String, name: String, trashed: Boolean = false): Boolean {
        if (trashed) return true
        val p = path.lowercase()
        val n = name.lowercase()
        if (n.contains("@delete")) return true
        if (p.contains("trash") || n.contains("trash")) return true
        return false
    }
}
