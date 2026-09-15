package com.tarkilhk.wing

import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/** Reads clipboard content only after an explicit Paste action. */
class ImageClipboardChannel(messenger: BinaryMessenger, private val activity: Activity) {
    private val channel = MethodChannel(messenger, "com.tarkilhk.wing/image_clipboard")
    private val executor = Executors.newSingleThreadExecutor()
    private val clipboard = activity.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private val maxBytes = 64 * 1024 * 1024

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "hasImage" -> {
                    // Description access does not read the clipboard payload.
                    val hasImage = try {
                        clipboard.primaryClipDescription?.hasMimeType("image/*") == true
                    } catch (_: Exception) {
                        false
                    }
                    result.success(hasImage)
                }
                "readImage" -> {
                    try {
                        val clip = clipboard.primaryClip
                        val uri = (0 until (clip?.itemCount ?: 0))
                            .mapNotNull { clip?.getItemAt(it)?.uri }
                            .firstOrNull { it.scheme == "content" }
                        if (uri == null) {
                            result.error("image_unavailable", "The clipboard image is no longer available. Copy it again.", null)
                        } else {
                            readImage(uri, result)
                        }
                    } catch (_: Exception) {
                        result.error("image_unavailable", "Unable to read the clipboard image. Copy it again.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun readImage(uri: Uri, result: MethodChannel.Result) {
        executor.execute {
            try {
                // Some clipboard providers report application/octet-stream for
                // valid images. The draft service validates and decodes the
                // actual bytes before accepting an image attachment.
                val bytes = activity.contentResolver.openInputStream(uri)?.use { input ->
                    val output = ByteArrayOutputStream()
                    val buffer = ByteArray(8192)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (output.size().toLong() + count > maxBytes) {
                            throw IllegalArgumentException("too_large")
                        }
                        output.write(buffer, 0, count)
                    }
                    output.toByteArray()
                }
                activity.runOnUiThread { result.success(bytes) }
            } catch (error: Exception) {
                val message = when {
                    error is SecurityException ->
                        "This clipboard image is no longer accessible. Copy it again, or insert it from your keyboard."
                    error.message == "too_large" ->
                        "The clipboard image exceeds the 64 MiB draft budget."
                    else ->
                        "Unable to read the clipboard image. Copy a JPEG, PNG, or WebP image again."
                }
                activity.runOnUiThread { result.error("image_unavailable", message, null) }
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
}
