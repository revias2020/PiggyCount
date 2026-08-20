package com.xiaozhu.piggy_count

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * 小组件打开主界面：经透明 [WidgetRelayActivity] 中转（ADR-027）。
 * 冷/热启动均不得出现启动页；冷启可接受 NormalTheme 下短暂浅色等待。
 */
internal object WidgetLaunch {
    fun activityPendingIntent(
        context: Context,
        requestCode: Int,
        url: String,
    ): PendingIntent {
        val intent = Intent(context, WidgetRelayActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse(url)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
