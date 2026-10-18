package com.xiaozhu.piggy_count

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
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
 *
 * [ScreenshotObserver] 挂在 companion（进程级）：Activity 被系统回收或用户在
 * 「检测到截图」关联窗期间打开再划掉时，勿 dispose 门闩/候选。
 */
class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "PiggyMain"
        const val SCREENSHOT_CHANNEL = "com.xiaozhu.piggy_count/screenshot"
        const val SHARE_CHANNEL = "com.xiaozhu.piggy_count/share"
        const val ACTIVITY_CHANNEL = "com.xiaozhu.piggy_count/activity"

        /** 进程级截图监听；与 Activity 生命周期解耦。 */
        @Volatile
        private var retainedScreenshotObserver: ScreenshotObserver? = null
    }

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
                        val obs = retainedScreenshotObserver
                        if (obs == null) {
                            result.success(emptyList<String>())
                        } else {
                            @Suppress("UNCHECKED_CAST")
                            val args = call.arguments as? Map<*, *>
                            val since = (args?.get("sinceEpochSeconds") as? Number)
                                ?.toLong()
                            // ADR-080：扫完返回路径列表，由 Dart 入补扫队。
                            result.success(obs.scanMissedForResume(sinceEpochSeconds = since))
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
                            val obs = retainedScreenshotObserver
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
        if (watchDirectories.isEmpty()) {
            stopScreenshotObserver()
            return
        }
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
        val binders = screenshotDartBinders(channel)
        val existing = retainedScreenshotObserver
        if (existing != null && existing.watches(watchDirectories)) {
            // 同目录：只重绑 Dart 桥，保留关联窗候选与计时器。
            existing.attachDartBridge(
                onScreenshotDetected = binders.detected,
                onScreenshotProgress = binders.progress,
                onScreenshotSuperseded = binders.superseded,
                onScreenshotCancelled = binders.cancelled,
                onSettleLog = binders.settleLog,
            )
            return
        }
        stopScreenshotObserver()
        val observer = ScreenshotObserver(
            this,
            onScreenshotDetected = binders.detected,
            onScreenshotProgress = binders.progress,
            onScreenshotSuperseded = binders.superseded,
            onScreenshotCancelled = binders.cancelled,
            onSettleLog = binders.settleLog,
            initialWatchDirectories = watchDirectories,
        )
        retainedScreenshotObserver = observer
        for (uri in screenshotObserverUris()) {
            contentResolver.registerContentObserver(uri, true, observer)
        }
    }

    private data class ScreenshotDartBinders(
        val detected: (String) -> Unit,
        val progress: (String, Boolean) -> Unit,
        val superseded: (String, String) -> Unit,
        val cancelled: (String) -> Unit,
        val settleLog: (String) -> Unit,
    )

    private fun screenshotDartBinders(channel: MethodChannel): ScreenshotDartBinders {
        val appCtx = applicationContext
        return ScreenshotDartBinders(
            detected = { path ->
                channel.invokeMethod("onScreenshotDetected", path)
            },
            progress = { path, resume ->
                // 与关联窗检出日志同拍：原生先贴 FGS，避免仅靠 Dart 通知在后台迟到。
                // ADR-080：补扫不再走 resume 早期进度（改 Dart 1002）。
                if (!resume) {
                    AutoBillingForegroundService.start(
                        appCtx,
                        "检测到截图",
                        "等待确认后识别…",
                    )
                    channel.invokeMethod(
                        "onScreenshotProgress",
                        mapOf("path" to path, "resume" to false),
                    )
                }
            },
            superseded = { oldPath, newPath ->
                channel.invokeMethod(
                    "onScreenshotSuperseded",
                    mapOf("oldPath" to oldPath, "newPath" to newPath),
                )
            },
            cancelled = { path ->
                channel.invokeMethod("onScreenshotCancelled", path)
            },
            settleLog = { message ->
                channel.invokeMethod("onScreenshotSettleLog", message)
            },
        )
    }

    /**
     * Android 10+ 截图写入通知在 `external_primary`，只订 `external` 会收不到 onChange，
     * 但查询 fused volume 仍能补扫到文件。
     */
    private fun screenshotObserverUris(): List<Uri> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            return listOf(
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL),
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            ).distinct()
        }
        return listOf(MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
    }

    private fun stopScreenshotObserver() {
        retainedScreenshotObserver?.let {
            try {
                applicationContext.contentResolver.unregisterContentObserver(it)
            } catch (_: Exception) {
            }
            it.dispose()
            retainedScreenshotObserver = null
        }
    }

    override fun onDestroy() {
        unregisterWidgetRefreshReceiver()
        // 勿 dispose 进程级 Observer：关联窗期间 Activity 回收会拆掉门闩，
        // 表现为「检测到截图」后打开 App 流程中断。仅松绑 Dart 桥。
        retainedScreenshotObserver?.detachDartBridge()
        flutterEngineRef = null
        super.onDestroy()
    }
}
