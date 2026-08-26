package com.xiaozhu.piggy_count

import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 小组件 → Flutter 进程内刷新。
 *
 * 中号渲图画布已固定（364×182），不再写入槽位 dp。
 * 进程仍在时发广播，由 [MainActivity] 转 MethodChannel。
 */
object WidgetRefreshBridge {
    private const val TAG = "WidgetRefreshBridge"

    const val ACTION_REFRESH = "com.xiaozhu.piggy_count.ACTION_WIDGET_REFRESH"
    const val CHANNEL = "com.xiaozhu.piggy_count/widget"

    /** 与 Dart [WidgetPrivacy.privacyToggledAtKey] 同键；HomeWidgetPreferences。 */
    private const val KEY_PRIVACY_TOGGLED_AT = "glance_privacy_toggled_at"

    /** 隐私就地重渲后，跳过主进程全量重渲的窗口（防 ~1s 二次闪烁）。 */
    private const val PRIVACY_SUPPRESS_MS = 3000L

    private fun prefs(context: Context) =
        context.getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)

    /**
     * 进程内存活时请求 Flutter 全量重渲（添加等）。
     * 眼睛隐私切换已由后台 isolate 就地重渲，窗口内不再请求，避免二次闪烁。
     */
    fun requestFlutterRefresh(context: Context) {
        if (wasPrivacyToggledRecently(context)) {
            Log.i(TAG, "skip Flutter refresh: recent privacy toggle")
            return
        }
        try {
            context.sendBroadcast(
                Intent(ACTION_REFRESH).setPackage(context.packageName),
            )
        } catch (e: Exception) {
            Log.e(TAG, "requestFlutterRefresh failed", e)
        }
    }

    private fun wasPrivacyToggledRecently(context: Context): Boolean {
        return try {
            val raw = prefs(context).all[KEY_PRIVACY_TOGGLED_AT] ?: return false
            val at = when (raw) {
                is Long -> raw
                is Int -> raw.toLong()
                else -> return false
            }
            at > 0L && System.currentTimeMillis() - at < PRIVACY_SUPPRESS_MS
        } catch (e: Exception) {
            Log.e(TAG, "wasPrivacyToggledRecently failed", e)
            false
        }
    }

    fun isTriggeredFromFlutter(intent: Intent?): Boolean {
        // home_widget 在 Flutter updateWidget 时写入该 extra
        return intent?.getBooleanExtra("triggeredFromHomeWidget", false) == true
    }
}
