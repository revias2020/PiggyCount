package com.xiaozhu.piggy_count

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * 后台直存 Vision 批次前台服务（ADR-054 / 063 / 069）。
 *
 * 保证 App 在 paused / 冷启动分享后立即退后台时，Dart 与网络仍可执行。
 * 进度通知与 Dart [BillingNotificationService.progressId] 同渠道、同 id。
 * [start] 先同 id 直发通知，再 `startForegroundService` +
 * `startForeground`（ADR-066 / ADR-069：填冷启空窗）。
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
            else -> {
                // START / UPDATE / 缺省：同一条 startForeground 路径
                val title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
                val body = intent?.getStringExtra(EXTRA_BODY) ?: DEFAULT_BODY
                startForeground(NOTIFICATION_ID, buildNotification(this, title, body))
                dispatchShareIngressReady()
            }
        }
        return START_NOT_STICKY
    }

    companion object {
        private const val TAG = "PiggyBillingFgs"
        const val CHANNEL_ID = "piggy_auto_billing"
        const val NOTIFICATION_ID = 1001

        private const val ACTION_START = "com.xiaozhu.piggy_count.billing.START"
        private const val ACTION_STOP = "com.xiaozhu.piggy_count.billing.STOP"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_BODY = "body"
        private const val DEFAULT_TITLE = "智能记账"
        private const val DEFAULT_BODY = "识别进行中…"

        /** 分享冷启：等 startForeground 或超时后再进 MainActivity，避免抢死主线程。 */
        private const val SHARE_INGRESS_READY_TIMEOUT_MS = 1500L

        private val mainHandler = Handler(Looper.getMainLooper())
        private val shareIngressReady = AtomicReference<Runnable?>(null)
        private val shareIngressTimeout = AtomicReference<Runnable?>(null)

        fun start(context: Context, title: String, body: String) {
            val app = context.applicationContext
            ensureChannel(app)
            // 冷启时 Service 可能被 Flutter 主线程拖住；先直发同 id，栏里立刻有「已收到…」(ADR-069)
            publishProgress(app, title, body)
            val intent = Intent(app, AutoBillingForegroundService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_BODY, body)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    app.startForegroundService(intent)
                } else {
                    @Suppress("DEPRECATION")
                    app.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "start() failed title=$title body=$body", e)
            }
        }

        /**
         * 分享入口专用（ADR-069）：先贴进度通知并起 FGS，在
         * [startForeground] 完成（或短超时）后再 [onReady]，避免立刻
         * `startActivity(MainActivity)` 把冷启主线程占满导致 FGS 超时/空窗。
         */
        fun startForShareIngress(
            context: Context,
            title: String,
            body: String,
            onReady: Runnable,
        ) {
            val once = AtomicBoolean(false)
            val self = AtomicReference<Runnable?>(null)
            val runOnce = Runnable {
                if (!once.compareAndSet(false, true)) return@Runnable
                shareIngressTimeout.getAndSet(null)?.let { mainHandler.removeCallbacks(it) }
                shareIngressReady.compareAndSet(self.get(), null)
                onReady.run()
            }
            self.set(runOnce)
            val timeout = Runnable {
                if (shareIngressReady.compareAndSet(runOnce, null)) {
                    Log.w(TAG, "share ingress: startForeground slow; continuing")
                    runOnce.run()
                }
            }
            shareIngressReady.set(runOnce)
            shareIngressTimeout.set(timeout)
            mainHandler.postDelayed(timeout, SHARE_INGRESS_READY_TIMEOUT_MS)
            start(context, title, body)
        }

        fun stop(context: Context) {
            val app = context.applicationContext
            val intent = Intent(app, AutoBillingForegroundService::class.java).apply {
                action = ACTION_STOP
            }
            app.startService(intent)
        }

        fun ensureChannel(context: Context) {
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

        /** 不等 Service：同渠道同 id 直发，供冷启空窗填补；随后 startForeground 会接管。 */
        private fun publishProgress(context: Context, title: String, body: String) {
            try {
                val nm = context.getSystemService(NotificationManager::class.java)
                nm.notify(NOTIFICATION_ID, buildNotification(context, title, body))
            } catch (e: Exception) {
                Log.e(TAG, "publishProgress failed title=$title body=$body", e)
            }
        }

        private fun dispatchShareIngressReady() {
            val pending = shareIngressReady.getAndSet(null) ?: return
            mainHandler.post(pending)
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
                // 每次 startForeground 都会刷新同 id 通知；横幅是否再弹取决于系统与渠道
                .setOnlyAlertOnce(false)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .build()
        }
    }
}
