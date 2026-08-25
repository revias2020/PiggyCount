package com.xiaozhu.piggy_count

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

/**
 * 后台直存 Vision 批次前台服务（ADR-054）。
 *
 * 保证 App 在 paused / 冷启动分享后立即退后台时，Dart 与网络仍可执行。
 * 进度通知与 Dart [BillingNotificationService.progressId] 同渠道、同 id。
 */
class AutoBillingForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannel(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    stopForeground(true)
                }
                stopSelf()
            }
            ACTION_UPDATE -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
                val body = intent.getStringExtra(EXTRA_BODY) ?: DEFAULT_BODY
                val notification = buildNotification(this, title, body)
                startForeground(NOTIFICATION_ID, notification)
            }
            else -> {
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
                val body = intent?.getStringExtra(EXTRA_BODY) ?: DEFAULT_BODY
                startForeground(NOTIFICATION_ID, buildNotification(this, title, body))
            }
        }
        return START_NOT_STICKY
    }

    companion object {
        const val CHANNEL_ID = "piggy_auto_billing"
        const val NOTIFICATION_ID = 1001

        private const val ACTION_START = "com.xiaozhu.piggy_count.billing.START"
        private const val ACTION_STOP = "com.xiaozhu.piggy_count.billing.STOP"
        private const val ACTION_UPDATE = "com.xiaozhu.piggy_count.billing.UPDATE"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        private const val DEFAULT_TITLE = "智能记账"
        private const val DEFAULT_BODY = "识别进行中…"

        fun start(context: Context, title: String, body: String) {
            val intent = Intent(context, AutoBillingForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                @Suppress("DEPRECATION")
                context.startService(intent)
            }
        }

        fun update(context: Context, title: String, body: String) {
            val intent = Intent(context, AutoBillingForegroundService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }
            context.startService(intent)
        }

        fun stop(context: Context) {
            val intent = Intent(context, AutoBillingForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val nm = context.getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                "智能记账进度",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "截图/分享识别进行中"
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }

        private fun buildNotification(
            context: Context,
            title: String,
            body: String,
        ): Notification {
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()
        }
    }
}
