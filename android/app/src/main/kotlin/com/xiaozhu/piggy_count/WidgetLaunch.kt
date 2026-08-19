package com.xiaozhu.piggy_count

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * 小组件打开主界面：打进同一 singleTask，避免另起任务（ADR-027）。
 * 不额外强制启动白猪：冷启走系统 Splash，热启直接进界面。
 */
internal object WidgetLaunch {
    fun activityPendingIntent(
        context: Context,
        requestCode: Int,
        url: String,
    ): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse(url)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
