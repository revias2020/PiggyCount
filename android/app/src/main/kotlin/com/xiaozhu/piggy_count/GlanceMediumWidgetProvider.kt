package com.xiaozhu.piggy_count

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 收支速览 · 中（ADR-024 / 027 / 028 / 034）。
 * 今日支出→明细；今日收入→明细；眼睛热区 44dp→隐藏；+→记支出；图→报表自定义近7天。
 */
class GlanceMediumWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val TAG = "GlanceMediumWidget"
        private const val IMAGE_KEY = "widget_glance_medium"
    }

    override fun onReceive(context: Context, intent: android.content.Intent) {
        when (intent.action) {
            AppWidgetManager.ACTION_APPWIDGET_OPTIONS_CHANGED,
            AppWidgetManager.ACTION_APPWIDGET_UPDATE,
            -> {
                val manager = AppWidgetManager.getInstance(context)
                val ids = intent.getIntArrayExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS)
                    ?: intArrayOf(
                        intent.getIntExtra(
                            AppWidgetManager.EXTRA_APPWIDGET_ID,
                            AppWidgetManager.INVALID_APPWIDGET_ID,
                        ),
                    ).filter { it != AppWidgetManager.INVALID_APPWIDGET_ID }.toIntArray()
                ids.forEach { id ->
                    WidgetRefreshBridge.saveMediumSlotSize(
                        context,
                        manager.getAppWidgetOptions(id),
                    )
                }
                if (!WidgetRefreshBridge.isTriggeredFromFlutter(intent)) {
                    WidgetRefreshBridge.requestFlutterRefresh(context)
                }
            }
        }
        super.onReceive(context, intent)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        WidgetRefreshBridge.saveMediumSlotSize(context, newOptions)
        onUpdate(
            context,
            appWidgetManager,
            intArrayOf(appWidgetId),
            HomeWidgetPlugin.getData(context),
        )
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        appWidgetIds.forEach { widgetId ->
            try {
                val options = appWidgetManager.getAppWidgetOptions(widgetId)
                WidgetRefreshBridge.saveMediumSlotSize(context, options)

                val imagePath = widgetData.getString(IMAGE_KEY, null)
                val bitmap = imagePath?.let { BitmapFactory.decodeFile(it) }
                // ADR-027：解码失败则整卡跳过更新，保留上一帧；禁止回退 ic_launcher。
                if (imagePath != null && bitmap == null) {
                    Log.w(TAG, "decode failed for $imagePath, skip update $widgetId")
                    return@forEach
                }

                val detailsPi = WidgetLaunch.activityPendingIntent(
                    context,
                    widgetId * 10 + 1,
                    "piggycount://details",
                )

                val views = RemoteViews(context.packageName, R.layout.glance_medium_widget).apply {
                    // ADR-028：XML 固定 fitCenter；禁止 setInt(setScaleType) 导致无法加载微件。
                    if (bitmap != null) {
                        setImageViewBitmap(R.id.widget_image, bitmap)
                    }

                    setOnClickPendingIntent(R.id.click_today_expense, detailsPi)
                    setOnClickPendingIntent(
                        R.id.click_today_income,
                        WidgetLaunch.activityPendingIntent(
                            context,
                            widgetId * 10 + 2,
                            "piggycount://details",
                        ),
                    )
                    setOnClickPendingIntent(
                        R.id.click_add,
                        WidgetLaunch.activityPendingIntent(
                            context,
                            widgetId * 10 + 3,
                            "piggycount://new?type=expense",
                        ),
                    )
                    setOnClickPendingIntent(
                        R.id.click_chart,
                        WidgetLaunch.activityPendingIntent(
                            context,
                            widgetId * 10 + 4,
                            "piggycount://report?mode=custom7d",
                        ),
                    )
                    setOnClickPendingIntent(
                        R.id.click_privacy,
                        HomeWidgetBackgroundIntent.getBroadcast(
                            context,
                            Uri.parse("piggycount://privacy?size=medium"),
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
