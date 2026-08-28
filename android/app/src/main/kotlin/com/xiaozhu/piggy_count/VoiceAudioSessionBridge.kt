package com.xiaozhu.piggy_count

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 语音记账结束后条件还原 Android 音频模式（ADR-060）。
 *
 * 开麦前快照 mode；开麦后记下我们留下的通信类 mode；
 * 关层时仅当当前 mode 仍等于留下的值才写回快照，否则不碰。
 */
object VoiceAudioSessionBridge {
    const val CHANNEL = "com.xiaozhu.piggy_count/voice_audio"

    private var modeBefore: Int = AudioManager.MODE_NORMAL
    private var leftMode: Int? = null
    private var sessionActive: Boolean = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var captureRunnable: Runnable? = null

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "begin" -> {
                    begin(context)
                    result.success(null)
                }
                "captureLeft" -> {
                    captureLeft(context)
                    result.success(null)
                }
                "restoreIfNeeded" -> {
                    result.success(restoreIfNeeded(context))
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun audioManager(context: Context): AudioManager =
        context.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

    private fun isCommunicationMode(mode: Int): Boolean =
        mode == AudioManager.MODE_IN_COMMUNICATION ||
            mode == AudioManager.MODE_IN_CALL

    private fun begin(context: Context) {
        cancelScheduledCapture()
        val am = audioManager(context)
        modeBefore = am.mode
        leftMode = null
        sessionActive = true
        // 插件可能异步改 mode；短延迟补采 leftMode。
        val runnable = Runnable {
            if (!sessionActive) return@Runnable
            val current = am.mode
            if (isCommunicationMode(current)) {
                leftMode = current
            } else if (leftMode == null) {
                leftMode = current
            }
        }
        captureRunnable = runnable
        mainHandler.postDelayed(runnable, 250)
    }

    private fun captureLeft(context: Context) {
        if (!sessionActive) return
        leftMode = audioManager(context).mode
    }

    private fun restoreIfNeeded(context: Context): Boolean {
        cancelScheduledCapture()
        if (!sessionActive) {
            return false
        }
        val am = audioManager(context)
        val current = am.mode
        var left = leftMode
        val before = modeBefore
        sessionActive = false
        leftMode = null
        modeBefore = AudioManager.MODE_NORMAL

        // 关层过快：延迟补采未完成时，若当前已是通信类且相对快照有变，视为我们留下的 mode。
        if (left == null && isCommunicationMode(current) && current != before) {
            left = current
        }

        if (left == null) return false
        if (left == before) return false
        if (!isCommunicationMode(left)) return false
        if (current != left) return false

        am.mode = before
        return true
    }

    private fun cancelScheduledCapture() {
        captureRunnable?.let { mainHandler.removeCallbacks(it) }
        captureRunnable = null
    }
}
