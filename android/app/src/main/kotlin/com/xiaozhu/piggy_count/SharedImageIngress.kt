package com.xiaozhu.piggy_count

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import java.io.File

/**
 * 系统分享图片落地：拷到 cache，再交给 [MainActivity] 经 MethodChannel 通知 Dart。
 *
 * 支持 [Intent.ACTION_SEND] 与 [Intent.ACTION_SEND_MULTIPLE]（ADR-058）。
 */
internal object SharedImageIngress {
    const val ACTION_SHARED_IMAGE = "com.xiaozhu.piggy_count.ACTION_SHARED_IMAGE"
    const val EXTRA_SHARED_IMAGE_PATH = "shared_image_path"
    const val EXTRA_SHARED_IMAGE_PATHS = "shared_image_paths"
    const val EXTRA_SHARED_TRUNCATED = "shared_truncated"

    /** 与 Dart `kMaxBillingImages` / ADR-058 对齐。 */
    const val MAX_SHARED_IMAGES = 9

    data class CopiedShare(
        val paths: ArrayList<String>,
        val truncated: Boolean,
    )

    fun imageUrisFromIntent(intent: Intent?): List<Uri> {
        if (intent == null) return emptyList()
        val type = intent.type ?: return emptyList()
        if (!type.startsWith("image/") && type != "*/*") return emptyList()

        return when (intent.action) {
            Intent.ACTION_SEND -> {
                listOfNotNull(singleStreamUri(intent))
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                multipleStreamUris(intent)
            }
            else -> emptyList()
        }
    }

    /** 兼容旧单路径 / 调试直达。 */
    fun imageUriFromSend(intent: Intent?): Uri? =
        imageUrisFromIntent(intent).firstOrNull()

    fun copyUrisToCache(context: Context, uris: List<Uri>): CopiedShare {
        val truncated = uris.size > MAX_SHARED_IMAGES
        val take = if (truncated) uris.take(MAX_SHARED_IMAGES) else uris
        val paths = ArrayList<String>(take.size)
        for (uri in take) {
            copyToCache(context, uri)?.let { paths.add(it) }
        }
        return CopiedShare(paths = paths, truncated = truncated)
    }

    fun copyToCache(context: Context, uri: Uri): String? {
        val input = context.contentResolver.openInputStream(uri) ?: return null
        val dir = File(context.cacheDir, "shared_images")
        dir.mkdirs()
        val out = File(dir, "shared_${System.currentTimeMillis()}_${pathsSafeName()}.jpg")
        input.use { inp ->
            out.outputStream().use { o -> inp.copyTo(o) }
        }
        return out.absolutePath
    }

    fun pathsFromIntent(intent: Intent?): CopiedShare? {
        if (intent?.action != ACTION_SHARED_IMAGE) return null
        val list = intent.getStringArrayListExtra(EXTRA_SHARED_IMAGE_PATHS)
        if (list != null && list.isNotEmpty()) {
            val truncated = intent.getBooleanExtra(EXTRA_SHARED_TRUNCATED, false)
            return CopiedShare(paths = ArrayList(list), truncated = truncated)
        }
        val single = intent.getStringExtra(EXTRA_SHARED_IMAGE_PATH)?.takeIf { it.isNotEmpty() }
            ?: return null
        return CopiedShare(paths = arrayListOf(single), truncated = false)
    }

    /** @deprecated 用 [pathsFromIntent] */
    fun pathFromIntent(intent: Intent?): String? =
        pathsFromIntent(intent)?.paths?.firstOrNull()

    private fun singleStreamUri(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    private fun multipleStreamUris(intent: Intent): List<Uri> {
        val raw = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }
        return raw?.filterNotNull().orEmpty()
    }

    private fun pathsSafeName(): String =
        System.nanoTime().toString(36)
}
