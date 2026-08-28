package com.xiaozhu.piggy_count

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.util.Log

/**
 * 系统分享入口（透明、无启动页）。
 *
 * 热启动时直接打进已有 [MainActivity]（SINGLE_TOP|CLEAR_TOP|NEW_TASK），
 * 避免分享 Intent 把带 LaunchTheme 的主界面再走一遍 onCreate 闪启动页。
 *
 * 支持单张 [Intent.ACTION_SEND] 与多选 [Intent.ACTION_SEND_MULTIPLE]（ADR-058）。
 * 拷图成功即拉起进度 FGS（ADR-063），不等 Dart 就绪。
 */
class ShareRelayActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val uris = SharedImageIngress.imageUrisFromIntent(intent)
            if (uris.isEmpty()) {
                Log.w(TAG, "share relay: no image uri")
                finish()
                return
            }
            val copied = SharedImageIngress.copyUrisToCache(this, uris)
            if (copied.paths.isEmpty()) {
                Log.e(TAG, "share relay: copy failed")
                finish()
                return
            }
            val body = if (copied.truncated) {
                "已收到（已截取前 9 张），准备识别…"
            } else {
                "已收到，准备识别…"
            }
            AutoBillingForegroundService.start(this, "分享入账", body)
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    action = SharedImageIngress.ACTION_SHARED_IMAGE
                    putStringArrayListExtra(
                        SharedImageIngress.EXTRA_SHARED_IMAGE_PATHS,
                        copied.paths,
                    )
                    putExtra(SharedImageIngress.EXTRA_SHARED_TRUNCATED, copied.truncated)
                    // 兼容旧单路径读取
                    putExtra(
                        SharedImageIngress.EXTRA_SHARED_IMAGE_PATH,
                        copied.paths.first(),
                    )
                    addFlags(
                        Intent.FLAG_ACTIVITY_NEW_TASK or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_ACTIVITY_CLEAR_TOP,
                    )
                },
            )
        } catch (e: Exception) {
            Log.e(TAG, "share relay failed", e)
        }
        finish()
    }

    companion object {
        private const val TAG = "PiggyShareRelay"
    }
}
