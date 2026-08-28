package com.xiaozhu.piggy_count

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.util.SizeF
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * 收支速览中号跟槽尺寸（ADR-062）。
 * 与 Dart [WidgetSpec.mediumSlotWidthKey] / [WidgetSpec.mediumSlotHeightKey] 对齐。
 */
object WidgetSlotSize {
    private const val TAG = "WidgetSlotSize"

    const val KEY_SLOT_W = "glance_medium_slot_w"
    const val KEY_SLOT_H = "glance_medium_slot_h"

    /** 设计稿兜底（BeeCount 4×2 ≈ 364×182，宽高比 2:1）。 */
    const val FALLBACK_W = 364
    const val FALLBACK_H = 182

    /** 与 [glance_medium_widget_info.xml] `android:minWidth` 一致。 */
    const val PROVIDER_MIN_WIDTH_DP = 320

    /** 与 [glance_medium_widget_info.xml] `android:targetCellWidth` 一致。 */
    const val MEDIUM_CELL_SPAN = 4

    /**
     * Vivo/HyperOS 等常见 5 列桌面格网，用于估算视觉宿主宽（options 常偏小）。
     * 见 [estimateHostWidthDp]。
     */
    const val LAUNCHER_GRID_COLUMNS = 5

    /** 中号目标宽高比（多候选 tie-break；单候选不依赖）。 */
    private val targetAspect = FALLBACK_W.toFloat() / FALLBACK_H

    private fun prefs(context: Context) =
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

    /**
     * 按屏宽 ÷ 桌面列数 × 占位格估算宿主宽（dp）。
     * 与 options 上报取 max，弥补位图 + fitCenter 时宿主宽于 API 宽的情况。
     */
    fun estimateHostWidthDp(
        context: Context,
        cellSpan: Int = MEDIUM_CELL_SPAN,
        gridColumns: Int = LAUNCHER_GRID_COLUMNS,
    ): Int {
        if (gridColumns <= 0 || cellSpan <= 0) return 0
        val dm = context.resources.displayMetrics
        val screenWidthDp = dm.widthPixels / dm.density
        val cellWidthDp = screenWidthDp / gridColumns
        return (cellWidthDp * cellSpan).roundToInt()
    }

    /**
     * 渲图宽 = max(上报宽, provider minWidth, 设计宽, 格网估算宽)；高跟上报。
     */
    internal fun computeRenderWidthDp(reportedW: Int, estimatedGridW: Int): Int =
        max(max(reportedW, PROVIDER_MIN_WIDTH_DP), max(FALLBACK_W, estimatedGridW))

    fun normalizeRenderSize(context: Context, reported: Pair<Int, Int>): Pair<Int, Int> {
        val (reportedW, reportedH) = reported
        val estimatedGridW = estimateHostWidthDp(context)
        val renderW = computeRenderWidthDp(reportedW, estimatedGridW)
        val renderH = reportedH
        return renderW to renderH
    }

    /**
     * 从 options 解析系统上报槽位 dp：
     * 1. 收集 `OPTION_APPWIDGET_SIZES` 各档 + min/max 回退档
     * 2. 单候选直接取；多候选优先面积，再比接近 2:1（避免误选 808×99 扁条）
     * 3. 皆无则 null
     */
    fun resolveSlotDp(opts: Bundle): Pair<Int, Int>? {
        val candidates = mutableListOf<Pair<Int, Int>>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            sizesList(opts)?.forEach { s ->
                if (s.width <= 0f || s.height <= 0f) return@forEach
                val w = s.width.roundToInt().coerceAtLeast(1)
                val h = s.height.roundToInt().coerceAtLeast(1)
                candidates.add(w to h)
            }
        }

        minMaxFallback(opts)?.let { candidates.add(it) }

        if (candidates.isEmpty()) return null

        return pickCandidate(candidates)
    }

    /** 多候选优先面积最大，同面积再比接近 2:1。 */
    internal fun pickCandidate(candidates: List<Pair<Int, Int>>): Pair<Int, Int> {
        require(candidates.isNotEmpty())
        if (candidates.size == 1) return candidates[0]
        return candidates.maxWith(
            compareByDescending<Pair<Int, Int>> { it.first * it.second }
                .thenBy { aspectDistance(it) },
        )
    }

    /** min/max 回退：宽取下界、高取上界 → 典型 4×2 当前铺开（如 373×203）。 */
    private fun minMaxFallback(opts: Bundle): Pair<Int, Int>? {
        val minW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val maxW = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        val minH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val maxH = opts.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        val w = when {
            minW > 0 && maxW > 0 -> min(minW, maxW)
            minW > 0 -> minW
            maxW > 0 -> maxW
            else -> 0
        }
        val h = when {
            minH > 0 && maxH > 0 -> max(minH, maxH)
            minH > 0 -> minH
            maxH > 0 -> maxH
            else -> 0
        }
        if (w <= 0 || h <= 0) return null
        return w to h
    }

    private fun aspectDistance(size: Pair<Int, Int>): Float {
        val aspect = size.first.toFloat() / size.second
        return abs(aspect - targetAspect)
    }

    private fun sizesList(opts: Bundle): ArrayList<SizeF>? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return opts.getParcelableArrayList(
                AppWidgetManager.OPTION_APPWIDGET_SIZES,
                SizeF::class.java,
            )
        }
        @Suppress("DEPRECATION")
        return opts.getParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES)
    }

    /**
     * 扫描全部中号实例，取面积最大的槽写入 prefs。
     * @return 宽或高是否相对上次发生变化
     */
    fun syncLargestSlot(
        context: Context,
        appWidgetManager: AppWidgetManager = AppWidgetManager.getInstance(context),
    ): Boolean {
        return try {
            val component = ComponentName(context, GlanceMediumWidgetProvider::class.java)
            val ids = appWidgetManager.getAppWidgetIds(component)
            var bestW = 0
            var bestH = 0
            var bestArea = 0
            for (id in ids) {
                val opts = appWidgetManager.getAppWidgetOptions(id) ?: continue
                val resolved = resolveSlotDp(opts) ?: continue
                val (w, h) = resolved
                val area = w * h
                if (area > bestArea) {
                    bestArea = area
                    bestW = w
                    bestH = h
                }
            }
            val prevW = prefs(context).getInt(KEY_SLOT_W, -1)
            val prevH = prefs(context).getInt(KEY_SLOT_H, -1)
            val (nextW, nextH) = when {
                bestW > 0 && bestH > 0 -> normalizeRenderSize(context, bestW to bestH)
                prevW > 0 && prevH > 0 -> prevW to prevH
                else -> FALLBACK_W to FALLBACK_H
            }
            if (prevW == nextW && prevH == nextH) return false
            prefs(context).edit()
                .putInt(KEY_SLOT_W, nextW)
                .putInt(KEY_SLOT_H, nextH)
                .remove("glance_medium_bucket_w")
                .apply()
            Log.i(TAG, "slot ${prevW}x${prevH} → ${nextW}x${nextH} (instances=${ids.size})")
            true
        } catch (e: Exception) {
            Log.e(TAG, "syncLargestSlot failed", e)
            false
        }
    }
}
