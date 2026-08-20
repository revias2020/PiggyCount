package com.xiaozhu.piggy_count

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log

/**
 * 小组件点击入口（透明、无启动页）。
 *
 * 冷/热启动均经此中转再打进 [MainActivity]，避免非桌面入口走 LaunchTheme 闪启动页/空启动页。
 */
class WidgetRelayActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            val data = intent.data
            if (data == null || data.scheme != SCHEME) {
                Log.w(TAG, "widget relay: invalid uri ${intent.data}")
                finish()
                return
            }
            Log.i(TAG, "widget relay → MainActivity: $data")
            startActivity(forwardIntent(data))
        } catch (e: Exception) {
            Log.e(TAG, "widget relay failed", e)
        }
        finish()
    }

    private fun forwardIntent(data: Uri): Intent =
        Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            setData(data)
            putExtra(EXTRA_SKIP_LAUNCH_SPLASH, true)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
            )
        }

    companion object {
        private const val TAG = "PiggyWidgetRelay"
        private const val SCHEME = "piggycount"
        const val EXTRA_SKIP_LAUNCH_SPLASH = "skip_launch_splash"
    }
}
