package com.xiaozhu.piggy_count

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log

/**
 * 小组件 → Flutter 进程内刷新（ADR-023 / 028）。
 *
 * - 写入中号槽位 dp，供 Flutter 按实际尺寸重渲
 * - 进程仍在时发广播，由 [MainActivity] 转 MethodChannel
 */
object WidgetRefreshBridge {
    private const val TAG = "WidgetRefreshBridge"

    const val ACTION_REFRESH = "com.xiaozhu.piggy_count.ACTION_WIDGET_REFRESH"
    const val CHANNEL = "com.xiaozhu.piggy_count/widget"

    const val KEY_MEDIUM_WIDTH_DP = "glance_medium_width_dp"
    const val KEY_MEDIUM_HEIGHT_DP = "glance_medium_height_dp"

    private const val FALLBACK_MEDIUM_W = 360
    private const val FALLBACK_MEDIUM_H = 152

    fun saveMediumSlotSize(context: Context, options: Bundle?) {
        val (w, h) = resolveSlotDp(options, FALLBACK_MEDIUM_W, FALLBACK_MEDIUM_H)
        try {
            context
                .getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
                .edit()
                .putInt(KEY_MEDIUM_WIDTH_DP, w)
                .putInt(KEY_MEDIUM_HEIGHT_DP, h)
                .apply()
            Log.i(TAG, "saved medium slot ${w}x${h}dp")
        } catch (e: Exception) {
            Log.e(TAG, "saveMediumSlotSize failed", e)
        }
    }

    fun requestFlutterRefresh(context: Context) {
        try {
            context.sendBroadcast(
                Intent(ACTION_REFRESH).setPackage(context.packageName),
            )
        } catch (e: Exception) {
            Log.e(TAG, "requestFlutterRefresh failed", e)
        }
    }

    fun isTriggeredFromFlutter(intent: Intent?): Boolean {
        // home_widget 在 Flutter updateWidget 时写入该 extra
        return intent?.getBooleanExtra("triggeredFromHomeWidget", false) == true
    }

    /**
     * 竖屏：宽 = MIN_WIDTH，高 = MAX_HEIGHT（ADR-028）。
     * 不再对 min/max 取平均，避免位图比例错导致 fitXY 拉字。
     */
    fun resolveSlotDp(
        options: Bundle?,
        fallbackW: Int,
        fallbackH: Int,
    ): Pair<Int, Int> {
        if (options == null) return fallbackW to fallbackH
        val minW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val maxW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        val minH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val maxH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)

        val w = when {
            minW > 0 -> minW
            maxW > 0 -> maxW
            else -> fallbackW
        }
        val h = when {
            maxH > 0 -> maxH
            minH > 0 -> minH
            else -> fallbackH
        }
        return w.coerceIn(120, 800) to h.coerceIn(80, 400)
    }
}
