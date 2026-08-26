package com.xiaozhu.piggy_count

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 收支速览 · 小（ADR-061）。
 * 今日支出大数字→金额隐私切换；其余→记支出。无眼睛图标。
 */
class GlanceSmallWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val TAG = "GlanceSmallWidget"
        private const val IMAGE_KEY = "widget_glance_small"
    }

    override fun onReceive(context: Context, intent: android.content.Intent) {
        when (intent.action) {
            AppWidgetManager.ACTION_APPWIDGET_UPDATE -> {
                if (!WidgetRefreshBridge.isTriggeredFromFlutter(intent)) {
                    WidgetRefreshBridge.requestFlutterRefresh(context)
                }
            }
        }
        super.onReceive(context, intent)
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            try {
                val imagePath = widgetData.getString(IMAGE_KEY, null)
                val bitmap = imagePath?.let { BitmapFactory.decodeFile(it) }
                // ADR-027：解码失败则跳过，保留上一帧；禁止回退 ic_launcher。
                if (imagePath != null && bitmap == null) {
                    Log.w(TAG, "decode failed for $imagePath, skip update $widgetId")
                    return@forEach
                }

                val views = RemoteViews(context.packageName, R.layout.glance_small_widget).apply {
                    if (bitmap != null) {
                        setImageViewBitmap(R.id.widget_image, bitmap)
                    }

                    setOnClickPendingIntent(
                        R.id.widget_click,
                        WidgetLaunch.activityPendingIntent(
                            context,
                            widgetId,
                            "piggycount://new?type=expense",
                        ),
                    )
                    setOnClickPendingIntent(
                        R.id.click_amount,
                        HomeWidgetBackgroundIntent.getBroadcast(
                            context,
                            Uri.parse("piggycount://privacy?size=small"),
                        ),
                    )
                }
                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update widget $widgetId", e)
            }
        }
    }
}
