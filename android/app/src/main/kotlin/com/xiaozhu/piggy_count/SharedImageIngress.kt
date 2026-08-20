package com.xiaozhu.piggy_count

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import java.io.File

/**
 * 系统分享图片落地：拷到 cache，再交给 [MainActivity] 经 MethodChannel 通知 Dart。
 */
internal object SharedImageIngress {
    const val ACTION_SHARED_IMAGE = "com.xiaozhu.piggy_count.ACTION_SHARED_IMAGE"
    const val EXTRA_SHARED_IMAGE_PATH = "shared_image_path"

    fun imageUriFromSend(intent: Intent?): Uri? {
        if (intent?.action != Intent.ACTION_SEND) return null
        if (intent.type?.startsWith("image/") != true) return null
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    fun copyToCache(context: Context, uri: Uri): String? {
        val input = context.contentResolver.openInputStream(uri) ?: return null
        val dir = File(context.cacheDir, "shared_images")
        dir.mkdirs()
        val out = File(dir, "shared_${System.currentTimeMillis()}.jpg")
        input.use { inp ->
            out.outputStream().use { o -> inp.copyTo(o) }
        }
        return out.absolutePath
    }

    fun pathFromIntent(intent: Intent?): String? {
        if (intent?.action != ACTION_SHARED_IMAGE) return null
        return intent.getStringExtra(EXTRA_SHARED_IMAGE_PATH)?.takeIf { it.isNotEmpty() }
    }
}
