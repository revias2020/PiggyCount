package com.xiaozhu.piggy_count

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 主 Activity：截图 MediaStore 监听 + 系统分享图片入账。
 *
 * launchMode=singleTask，保证热启动分享走 [onNewIntent]。
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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleSharedImage(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
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

        // 若冷启动时已拷好分享图，延迟通知 Dart
        pendingSharedPath?.let { path ->
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                notifyShared(path)
            }, 600)
        }
    }

    private fun handleSharedImage(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        if (intent.type?.startsWith("image/") != true) return

        val uri: Uri? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
        if (uri == null) return

        try {
            val path = copySharedToTemp(uri) ?: return
            pendingSharedPath = path
            Log.i(TAG, "shared image saved: $path")
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                notifyShared(path)
            }, 500)
        } catch (e: Exception) {
            Log.e(TAG, "handleSharedImage failed", e)
        }
    }

    private fun copySharedToTemp(uri: Uri): String? {
        val input = contentResolver.openInputStream(uri) ?: return null
        val dir = File(cacheDir, "shared_images")
        dir.mkdirs()
        val out = File(dir, "shared_${System.currentTimeMillis()}.jpg")
        input.use { inp ->
            out.outputStream().use { o -> inp.copyTo(o) }
        }
        return out.absolutePath
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

    private fun startScreenshotObserver(engine: FlutterEngine) {
        stopScreenshotObserver()
        screenshotObserver = ScreenshotObserver(this) { path ->
            MethodChannel(engine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
                .invokeMethod("onScreenshotDetected", path)
        }
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
            screenshotObserver = null
        }
    }

    override fun onDestroy() {
        stopScreenshotObserver()
        flutterEngineRef = null
        super.onDestroy()
    }
}
