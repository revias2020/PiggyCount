package com.xiaozhu.piggy_count

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import androidx.activity.OnBackPressedCallback
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 主 Activity：截图 MediaStore 监听 + 接收 [ShareRelayActivity] / [WidgetRelayActivity] 转发。
 *
 * launchMode=singleTask，保证热启动分享 / 小组件深链走 [onNewIntent]（ADR-027）。
 * 分享、小组件均经透明中转，避免热启再走 LaunchTheme。
 *
 * 后台直存进行中：[setRetainOnBack] 使返回键 [moveTaskToBack] 而非 finish，
 * 避免分享后回到截图编辑时拆掉 Flutter 引擎导致识别静默中断。
 */
class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "PiggyMain"
        const val SCREENSHOT_CHANNEL = "com.xiaozhu.piggy_count/screenshot"
        const val SHARE_CHANNEL = "com.xiaozhu.piggy_count/share"
        const val ACTIVITY_CHANNEL = "com.xiaozhu.piggy_count/activity"
    }

    private var screenshotObserver: ScreenshotObserver? = null
    private var pendingSharedPaths: ArrayList<String>? = null
    private var pendingSharedTruncated: Boolean = false
    private var flutterEngineRef: FlutterEngine? = null
    private var widgetRefreshReceiver: BroadcastReceiver? = null

    /** 后台直存进行中：返回键送后台，不销毁。 */
    private val retainOnBackCallback = object : OnBackPressedCallback(false) {
        override fun handleOnBackPressed() {
            moveTaskToBack(true)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent.getBooleanExtra(WidgetRelayActivity.EXTRA_SKIP_LAUNCH_SPLASH, false)) {
            setTheme(R.style.NormalTheme)
        }
        super.onCreate(savedInstanceState)
        onBackPressedDispatcher.addCallback(this, retainOnBackCallback)
        handleSharedImage(intent, pushIfReady = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleSharedImage(intent, pushIfReady = true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngineRef = flutterEngine

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startScreenshotObserver" -> {
                        @Suppress("UNCHECKED_CAST")
                        val dirs = (call.arguments as? Map<*, *>)
                            ?.get("directories") as? List<*>
                        val normalized = dirs
                            ?.mapNotNull { (it as? String)?.let(ScreenshotWatchPaths::normalize) }
                            ?: emptyList()
                        if (normalized.isEmpty()) {
                            stopScreenshotObserver()
                            result.success(false)
                        } else {
                            startScreenshotObserver(flutterEngine, normalized)
                            result.success(true)
                        }
                    }
                    "stopScreenshotObserver" -> {
                        stopScreenshotObserver()
                        result.success(true)
                    }
                    "resumeScreenshotScan" -> {
                        val obs = screenshotObserver
                        if (obs == null) {
                            result.success(false)
                        } else {
                            @Suppress("UNCHECKED_CAST")
                            val args = call.arguments as? Map<*, *>
                            val since = (args?.get("sinceEpochSeconds") as? Number)
                                ?.toLong()
                            obs.scanMissedForResume(sinceEpochSeconds = since)
                            result.success(true)
                        }
                    }
                    "setWatchDirectories" -> {
                        @Suppress("UNCHECKED_CAST")
                        val dirs = (call.arguments as? Map<*, *>)
                            ?.get("directories") as? List<*>
                        val normalized = dirs
                            ?.mapNotNull { (it as? String)?.let(ScreenshotWatchPaths::normalize) }
                            ?: emptyList()
                        if (normalized.isEmpty()) {
                            stopScreenshotObserver()
                            result.success(false)
                        } else {
                            val obs = screenshotObserver
                            if (obs != null) {
                                obs.setWatchDirectories(normalized)
                                result.success(true)
                            } else {
                                startScreenshotObserver(flutterEngine, normalized)
                                result.success(true)
                            }
                        }
                    }
                    "discoverScreenshotDirectories" -> {
                        result.success(ScreenshotDirectoryDiscovery.discover(this))
                    }
                    "normalizeWatchDirectory" -> {
                        val raw = call.arguments as? String
                        result.success(raw?.let(ScreenshotWatchPaths::normalize))
                    }
                    "getPrimaryStorageRoot" -> {
                        @Suppress("DEPRECATION")
                        val root = Environment.getExternalStorageDirectory()
                            .absolutePath
                            .trimEnd('/')
                        result.success(root)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHARE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getPendingSharedImages" -> {
                        val paths = pendingSharedPaths
                        val truncated = pendingSharedTruncated
                        pendingSharedPaths = null
                        pendingSharedTruncated = false
                        if (paths.isNullOrEmpty()) {
                            result.success(null)
                        } else {
                            result.success(
                                mapOf(
                                    "paths" to paths,
                                    "truncated" to truncated,
                                ),
                            )
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACTIVITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setRetainOnBack" -> {
                        val enabled = call.arguments as? Boolean ?: false
                        retainOnBackCallback.isEnabled = enabled
                        result.success(null)
                    }
                    "moveTaskToBack" -> {
                        moveTaskToBack(true)
                        result.success(null)
                    }
                    "startBillingForeground" -> {
                        val args = call.arguments as? Map<*, *>
                        val title = args?.get("title") as? String ?: "智能记账"
                        val body = args?.get("body") as? String ?: "识别进行中…"
                        AutoBillingForegroundService.start(this, title, body)
                        result.success(null)
                    }
                    "stopBillingForeground" -> {
                        AutoBillingForegroundService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Dart 侧挂好 handler 即可；原生只负责推送 onWidgetRefresh。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WidgetRefreshBridge.CHANNEL)

        VoiceAudioSessionBridge.register(
            flutterEngine.dartExecutor.binaryMessenger,
            this,
        )

        registerWidgetRefreshReceiver()

        // 冷启：只保留 pending，由 Dart bind → getPendingSharedImages 取走（ADR-063）。
        // 勿在此处 notify：handler 往往尚未挂上，固定 delay 已废止。
    }

    private fun handleSharedImage(intent: Intent?, pushIfReady: Boolean) {
        // 优先：ShareRelay 已拷好的路径（热启走 onNewIntent，冷启走 onCreate）
        SharedImageIngress.pathsFromIntent(intent)?.let { copied ->
            acceptSharedPaths(copied, pushIfReady = pushIfReady)
            return
        }

        // 兼容：若仍有 ACTION_SEND / SEND_MULTIPLE 直达（旧入口 / 调试）
        val uris = SharedImageIngress.imageUrisFromIntent(intent)
        if (uris.isEmpty()) return
        try {
            val copied = SharedImageIngress.copyUrisToCache(this, uris)
            if (copied.paths.isEmpty()) return
            // 直达路径无 ShareRelay：此处补早期 FGS（ADR-063）；调试/旧入口保留（ADR-066 S2）
            AutoBillingForegroundService.start(
                this,
                SharedImageIngress.SHARE_PROGRESS_TITLE,
                SharedImageIngress.earlyProgressBody(copied.truncated),
            )
            acceptSharedPaths(copied, pushIfReady = pushIfReady)
        } catch (e: Exception) {
            Log.e(TAG, "handleSharedImage failed", e)
        }
    }

    /**
     * 写入 pending。
     * [pushIfReady]：热启立即推送；冷启为 false，只靠 getPending，避免 handler 未挂上丢事件（ADR-063）。
     */
    private fun acceptSharedPaths(
        copied: SharedImageIngress.CopiedShare,
        pushIfReady: Boolean,
    ) {
        pendingSharedPaths = copied.paths
        pendingSharedTruncated = copied.truncated
        if (pushIfReady) {
            tryNotifyShared()
        }
    }

    private fun tryNotifyShared() {
        val paths = pendingSharedPaths ?: return
        if (paths.isEmpty()) return
        if (flutterEngineRef == null) return
        notifyShared(paths, pendingSharedTruncated)
    }

    private fun notifyShared(paths: List<String>, truncated: Boolean) {
        if (paths.isEmpty()) return
        try {
            val messenger = flutterEngineRef?.dartExecutor?.binaryMessenger ?: return
            MethodChannel(messenger, SHARE_CHANNEL).invokeMethod(
                "onImagesShared",
                mapOf(
                    "paths" to paths,
                    "truncated" to truncated,
                ),
            )
            // 已推送则清空 pending，避免 getPending 重复
            pendingSharedPaths = null
            pendingSharedTruncated = false
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

    private fun startScreenshotObserver(
        engine: FlutterEngine,
        watchDirectories: Collection<String>,
    ) {
        stopScreenshotObserver()
        if (watchDirectories.isEmpty()) return
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
        screenshotObserver = ScreenshotObserver(
            this,
            onScreenshotDetected = { path ->
                channel.invokeMethod("onScreenshotDetected", path)
            },
            onScreenshotProgress = { path, resume ->
                // 与关联窗检出日志同拍：原生先贴 FGS，避免仅靠 Dart 通知在后台迟到。
                // 补扫立刻门闩，用独立文案（ADR-076），禁止「等待确认」。
                if (resume) {
                    AutoBillingForegroundService.start(
                        this,
                        "补扫到截图",
                        "正在补识别…",
                    )
                } else {
                    AutoBillingForegroundService.start(
                        this,
                        "检测到截图",
                        "等待确认后识别…",
                    )
                }
                channel.invokeMethod(
                    "onScreenshotProgress",
                    mapOf("path" to path, "resume" to resume),
                )
            },
            onScreenshotSuperseded = { oldPath, newPath ->
                channel.invokeMethod(
                    "onScreenshotSuperseded",
                    mapOf("oldPath" to oldPath, "newPath" to newPath),
                )
            },
            onScreenshotCancelled = { path ->
                channel.invokeMethod("onScreenshotCancelled", path)
            },
            onSettleLog = { message ->
                channel.invokeMethod("onScreenshotSettleLog", message)
            },
            initialWatchDirectories = watchDirectories,
        )
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        contentResolver.registerContentObserver(uri, true, screenshotObserver!!)
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
