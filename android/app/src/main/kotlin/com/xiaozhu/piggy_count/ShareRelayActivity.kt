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
 * 拷图成功即贴进度并拉起 FGS（ADR-063 / 069），等 startForeground（或短超时）
 * 后再进 MainActivity，避免冷启 Flutter 抢主线程造成通知空窗。
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
            val paths = copied.paths
            val truncated = copied.truncated
            AutoBillingForegroundService.startForShareIngress(
                this,
                SharedImageIngress.SHARE_PROGRESS_TITLE,
                SharedImageIngress.earlyProgressBody(truncated),
            ) {
                try {
                    startActivity(
                        Intent(this, MainActivity::class.java).apply {
                            action = SharedImageIngress.ACTION_SHARED_IMAGE
                            putStringArrayListExtra(
                                SharedImageIngress.EXTRA_SHARED_IMAGE_PATHS,
                                paths,
                            )
                            putExtra(
                                SharedImageIngress.EXTRA_SHARED_TRUNCATED,
                                truncated,
                            )
                            addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
                            )
                        },
                    )
                } catch (e: Exception) {
                    Log.e(TAG, "share relay: start MainActivity failed", e)
                } finally {
                    finish()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "share relay failed", e)
            finish()
        }
    }

    companion object {
        private const val TAG = "PiggyShareRelay"
    }
}
