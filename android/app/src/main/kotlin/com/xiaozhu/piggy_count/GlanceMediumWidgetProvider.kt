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
 * 收支速览 · 中（ADR-061 / 027 / 028 / 034）。
 * 今日支出/收入金额行→隐私；「+」→记支出；柱图→报表近 7 日；
 * 标签与垫片等其余浮卡区→明细。无眼睛图标。渲图画布 364×182。
 */
class GlanceMediumWidgetProvider : HomeWidgetProvider() {
    companion object {
        private const val TAG = "GlanceMediumWidget"
        private const val IMAGE_KEY = "widget_glance_medium"
    }

    override fun onReceive(context: Context, intent: android.content.Intent) {
        when (intent.action) {
            AppWidgetManager.ACTION_APPWIDGET_UPDATE,
            -> {
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
                val privacyPi = HomeWidgetBackgroundIntent.getBroadcast(
                    context,
                    Uri.parse("piggycount://privacy?size=medium"),
                )

                val views = RemoteViews(context.packageName, R.layout.glance_medium_widget).apply {
                    // ADR-028：XML 固定 fitCenter；禁止 setInt(setScaleType) 导致无法加载微件。
                    if (bitmap != null) {
                        setImageViewBitmap(R.id.widget_image, bitmap)
                    }

                    setOnClickPendingIntent(R.id.click_details_top_pad, detailsPi)
                    setOnClickPendingIntent(R.id.click_details_expense_label, detailsPi)
                    setOnClickPendingIntent(R.id.click_details_income_label, detailsPi)
                    setOnClickPendingIntent(R.id.click_details_gap, detailsPi)
                    setOnClickPendingIntent(R.id.click_details_bottom_pad, detailsPi)

                    setOnClickPendingIntent(R.id.click_today_expense, privacyPi)
                    setOnClickPendingIntent(R.id.click_today_income, privacyPi)

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
                }
                appWidgetManager.updateAppWidget(widgetId, views)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to update widget $widgetId", e)
            }
        }
    }
}
