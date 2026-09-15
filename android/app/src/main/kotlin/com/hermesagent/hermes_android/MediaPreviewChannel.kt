package com.hermesagent.hermes_android

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException

internal class MediaPreviewChannel(
    binaryMessenger: BinaryMessenger,
    private val activity: Activity,
    private val isActivityResumed: () -> Boolean,
) {
    private val channel = MethodChannel(binaryMessenger, CHANNEL_NAME)
    private val executor = Executors.newSingleThreadExecutor()
    private val previewDirectory = File(activity.cacheDir, MEDIA_PREVIEW_CACHE_DIRECTORY)

    @Volatile
    private var closed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "open") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val bytes = call.argument<ByteArray>("bytes")
            val mimeType = call.argument<String>("mimeType")
                ?.substringBefore(';')
                ?.trim()
                ?.lowercase()
                .orEmpty()
            val title = safeTitle(call.argument<String>("title"))
            if (closed) {
                result.error("media_preview_closed", "Media preview is unavailable.", null)
            } else if (bytes == null || bytes.isEmpty() || bytes.size > MAX_MEDIA_BYTES ||
                mimeType !in supportedMediaPreviewTypes
            ) {
                result.error("media_preview_invalid", "This media could not be opened.", null)
            } else {
                open(bytes, title, mimeType, call.argument<Map<String, Any>>("appearance").orEmpty(), result)
            }
        }
    }

    fun closeAll() {
        if (closed) return
        closed = true
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }

    private fun open(
        bytes: ByteArray,
        title: String,
        mimeType: String,
        appearance: Map<String, Any>,
        result: MethodChannel.Result,
    ) {
        try {
            executor.execute {
                if (closed) {
                    postError(result, "media_preview_closed", "Media preview is unavailable.")
                    return@execute
                }
                var output: File? = null
                try {
                    prepareDirectory()
                    cleanupOldFiles()
                    val extension = extensionForMediaPreview(mimeType)
                    output = File(previewDirectory, "${UUID.randomUUID()}.$extension")
                    FileOutputStream(output).use { stream ->
                        stream.write(bytes)
                        stream.fd.sync()
                    }
                    val savedFile = output
                    activity.runOnUiThread {
                        if (closed || activity.isFinishing || activity.isDestroyed ||
                            !isActivityResumed()
                        ) {
                            savedFile.delete()
                            result.error(
                                "media_preview_inactive",
                                "This media could not be opened.",
                                null,
                            )
                            return@runOnUiThread
                        }
                        try {
                            activity.startActivity(
                                Intent(activity, MediaPreviewActivity::class.java).apply {
                                    putExtra(MediaPreviewActivity.EXTRA_FILE_NAME, savedFile.name)
                                    putExtra(MediaPreviewActivity.EXTRA_TITLE, title)
                                    putExtra(MediaPreviewActivity.EXTRA_MIME_TYPE, mimeType)
                                    for (key in listOf("dark", "surface", "text", "accent", "onAccent", "error")) {
                                        (appearance[key] as? Number)?.let {
                                            putExtra("studio_$key", it.toInt())
                                        }
                                    }
                                },
                            )
                            result.success(true)
                        } catch (_: Exception) {
                            savedFile.delete()
                            result.error(
                                "media_preview_failed",
                                "This media could not be opened.",
                                null,
                            )
                        }
                    }
                } catch (_: Exception) {
                    output?.delete()
                    postError(result, "media_preview_failed", "This media could not be opened.")
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("media_preview_closed", "Media preview is unavailable.", null)
        }
    }

    private fun prepareDirectory() {
        if ((!previewDirectory.exists() && !previewDirectory.mkdirs()) || !previewDirectory.isDirectory) {
            throw IllegalStateException()
        }
    }

    private fun cleanupOldFiles() {
        val cutoff = System.currentTimeMillis() - ORPHAN_MAX_AGE_MS
        previewDirectory.listFiles()
            ?.asSequence()
            ?.filter { it.isFile && it.lastModified() in 1 until cutoff }
            ?.take(MAX_ORPHANS_PER_OPEN)
            ?.forEach { it.delete() }
    }

    private fun postError(result: MethodChannel.Result, code: String, message: String) {
        activity.runOnUiThread { result.error(code, message, null) }
    }

    private fun safeTitle(raw: String?): String = raw
        ?.substringAfterLast('/')
        ?.substringAfterLast('\\')
        ?.replace(Regex("[\\p{Cntrl}]"), "")
        ?.trim()
        ?.take(120)
        ?.takeIf { it.isNotEmpty() }
        ?: "Media preview"

    private companion object {
        const val CHANNEL_NAME = "com.hermesagent.hermes_android/media_preview"
        const val MAX_MEDIA_BYTES = 32 * 1024 * 1024
        const val MAX_ORPHANS_PER_OPEN = 32
        const val ORPHAN_MAX_AGE_MS = 24L * 60L * 60L * 1_000L
    }
}

internal const val MEDIA_PREVIEW_CACHE_DIRECTORY = "media_previews"

internal val supportedMediaPreviewTypes = setOf(
    "audio/aac", "audio/flac", "audio/mp4", "audio/mpeg", "audio/ogg",
    "audio/wav", "audio/webm", "audio/x-wav",
    "video/mp4", "video/mpeg", "video/quicktime", "video/webm",
    "video/x-matroska", "video/x-msvideo",
)

internal fun extensionForMediaPreview(mimeType: String): String = when (mimeType) {
    "audio/aac" -> "aac"
    "audio/flac" -> "flac"
    "audio/mp4" -> "m4a"
    "audio/mpeg" -> "mp3"
    "audio/ogg" -> "ogg"
    "audio/wav", "audio/x-wav" -> "wav"
    "audio/webm" -> "weba"
    "video/mp4" -> "mp4"
    "video/mpeg" -> "mpeg"
    "video/quicktime" -> "mov"
    "video/webm" -> "webm"
    "video/x-matroska" -> "mkv"
    "video/x-msvideo" -> "avi"
    else -> "media"
}
