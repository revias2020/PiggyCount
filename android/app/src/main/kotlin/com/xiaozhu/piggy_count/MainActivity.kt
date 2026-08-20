package com.xiaozhu.piggy_count

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity：截图 MediaStore 监听 + 接收 [ShareRelayActivity] / [WidgetRelayActivity] 转发。
 *
 * launchMode=singleTask，保证热启动分享 / 小组件深链走 [onNewIntent]（ADR-027）。
 * 分享、小组件均经透明中转，避免热启再走 LaunchTheme。
 */
class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "PiggyMain"
        const val SCREENSHOT_CHANNEL = "com.xiaozhu.piggy_count/screenshot"
        const val SHARE_CHANNEL = "com.xiaozhu.piggy_count/share"
    }

    private var screenshotObserver: ScreenshotObserver? = null
    private var pendingSharedPath: String? = null
    private var flutterEngineRef: FlutterEngine? = null
    private var widgetRefreshReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent.getBooleanExtra(WidgetRelayActivity.EXTRA_SKIP_LAUNCH_SPLASH, false)) {
            setTheme(R.style.NormalTheme)
        }
        super.onCreate(savedInstanceState)
        Log.i(TAG, "onCreate action=${intent?.action}")
        handleSharedImage(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        Log.i(TAG, "onNewIntent action=${intent.action}")
        handleSharedImage(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngineRef = flutterEngine

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startScreenshotObserver" -> {
                        startScreenshotObserver(flutterEngine)
                        result.success(true)
                    }
                    "stopScreenshotObserver" -> {
                        stopScreenshotObserver()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingSharedImage" -> {
                        val path = pendingSharedPath
                        pendingSharedPath = null
                        result.success(path)
                    }
                    else -> result.notImplemented()
                }
            }

        // Dart 侧挂好 handler 即可；原生只负责推送 onWidgetRefresh。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WidgetRefreshBridge.CHANNEL)

        registerWidgetRefreshReceiver()

        // 若冷启动时已拷好分享图，延迟通知 Dart
        pendingSharedPath?.let { path ->
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                notifyShared(path)
            }, 600)
        }
    }

    private fun handleSharedImage(intent: Intent?) {
        // 优先：ShareRelay 已拷好的路径（热启走 onNewIntent，冷启走 onCreate）
        SharedImageIngress.pathFromIntent(intent)?.let { path ->
            pendingSharedPath = path
            Log.i(TAG, "shared image path: $path")
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                notifyShared(path)
            }, 500)
            return
        }

        // 兼容：若仍有 ACTION_SEND 直达（旧入口 / 调试）
        val uri = SharedImageIngress.imageUriFromSend(intent) ?: return
        try {
            val path = SharedImageIngress.copyToCache(this, uri) ?: return
            pendingSharedPath = path
            Log.i(TAG, "shared image saved: $path")
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                notifyShared(path)
            }, 500)
        } catch (e: Exception) {
            Log.e(TAG, "handleSharedImage failed", e)
        }
    }

    private fun notifyShared(path: String) {
        try {
            val messenger = flutterEngineRef?.dartExecutor?.binaryMessenger ?: return
            MethodChannel(messenger, SHARE_CHANNEL).invokeMethod("onImageShared", path)
            // 已推送则清空 pending，避免 getPending 重复
            if (pendingSharedPath == path) pendingSharedPath = null
        } catch (e: Exception) {
            Log.e(TAG, "notifyShared failed", e)
        }
    }

    private fun registerWidgetRefreshReceiver() {
        if (widgetRefreshReceiver != null) return
        widgetRefreshReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != WidgetRefreshBridge.ACTION_REFRESH) return
                notifyWidgetRefresh()
            }
        }
        val filter = IntentFilter(WidgetRefreshBridge.ACTION_REFRESH)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(widgetRefreshReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(widgetRefreshReceiver, filter)
        }
    }

    private fun unregisterWidgetRefreshReceiver() {
        widgetRefreshReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
            widgetRefreshReceiver = null
        }
    }

    private fun notifyWidgetRefresh() {
        try {
            val messenger = flutterEngineRef?.dartExecutor?.binaryMessenger ?: return
            MethodChannel(messenger, WidgetRefreshBridge.CHANNEL)
                .invokeMethod("onWidgetRefresh", null)
        } catch (e: Exception) {
            Log.e(TAG, "notifyWidgetRefresh failed", e)
        }
    }

    private fun startScreenshotObserver(engine: FlutterEngine) {
        stopScreenshotObserver()
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
        screenshotObserver = ScreenshotObserver(
            this,
            onScreenshotDetected = { path ->
                channel.invokeMethod("onScreenshotDetected", path)
            },
            onSettleLog = { message ->
                channel.invokeMethod("onScreenshotSettleLog", message)
            },
        )
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        contentResolver.registerContentObserver(uri, true, screenshotObserver!!)
        Log.i(TAG, "screenshot observer registered")
    }

    private fun stopScreenshotObserver() {
        screenshotObserver?.let {
            try {
                contentResolver.unregisterContentObserver(it)
            } catch (_: Exception) {
            }
            it.dispose()
            screenshotObserver = null
        }
    }

    override fun onDestroy() {
        unregisterWidgetRefreshReceiver()
        stopScreenshotObserver()
        flutterEngineRef = null
        super.onDestroy()
    }
}
