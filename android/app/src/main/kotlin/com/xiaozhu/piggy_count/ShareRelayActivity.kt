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
 */
class ShareRelayActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val uri = SharedImageIngress.imageUriFromSend(intent)
            if (uri == null) {
                Log.w(TAG, "share relay: no image uri")
                finish()
                return
            }
            val path = SharedImageIngress.copyToCache(this, uri)
            if (path == null) {
                Log.e(TAG, "share relay: copy failed")
                finish()
                return
            }
            Log.i(TAG, "share relay → MainActivity: $path")
            startActivity(
                Intent(this, MainActivity::class.java).apply {
                    action = SharedImageIngress.ACTION_SHARED_IMAGE
                    putExtra(SharedImageIngress.EXTRA_SHARED_IMAGE_PATH, path)
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
