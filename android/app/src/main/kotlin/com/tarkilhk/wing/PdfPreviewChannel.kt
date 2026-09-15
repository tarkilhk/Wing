package com.tarkilhk.wing

import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import kotlin.math.roundToInt

internal class PdfPreviewChannel(
    binaryMessenger: BinaryMessenger,
    cacheDir: File,
) {
    private val channel = MethodChannel(binaryMessenger, CHANNEL_NAME)
    private val previewDirectory = File(cacheDir, CACHE_DIRECTORY)
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val documents = mutableMapOf<String, OpenDocument>()

    @Volatile
    private var closed = false

    init {
        channel.setMethodCallHandler(::handleCall)
    }

    fun closeAll() {
        if (closed) return
        closed = true
        channel.setMethodCallHandler(null)
        try {
            executor.execute {
                documents.values.toList().forEach(::closeDocument)
                documents.clear()
            }
        } catch (_: RejectedExecutionException) {
            // A prior close already stopped the worker.
        } finally {
            executor.shutdown()
        }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) {
            result.error("pdf_preview_closed", "PDF preview is unavailable.", null)
            return
        }
        when (call.method) {
            "open" -> {
                val bytes = call.argument<ByteArray>("bytes")
                if (bytes == null || bytes.isEmpty()) {
                    result.error("pdf_invalid", "The PDF could not be opened.", null)
                } else if (bytes.size > MAX_PDF_BYTES) {
                    result.error("pdf_too_large", "The PDF is too large to preview.", null)
                } else {
                    submit(result) { open(bytes) }
                }
            }
            "render" -> {
                val documentId = call.argument<String>("documentId")?.trim().orEmpty()
                val page = call.argument<Int>("page")
                if (documentId.isEmpty() || page == null) {
                    result.error("pdf_render_invalid", "The PDF page could not be rendered.", null)
                } else {
                    submit(result) { render(documentId, page) }
                }
            }
            "close" -> {
                val documentId = call.argument<String>("documentId")?.trim().orEmpty()
                if (documentId.isEmpty()) {
                    result.error("pdf_close_invalid", "The PDF preview could not be closed.", null)
                } else {
                    submit(result) {
                        documents.remove(documentId)?.let(::closeDocument)
                        null
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun submit(result: MethodChannel.Result, action: () -> Any?) {
        try {
            executor.execute {
                try {
                    postSuccess(result, action())
                } catch (error: PreviewException) {
                    postError(result, error.code, error.safeMessage)
                } catch (_: Exception) {
                    postError(result, "pdf_preview_failed", "The PDF preview failed.")
                }
            }
        } catch (_: RejectedExecutionException) {
            result.error("pdf_preview_closed", "PDF preview is unavailable.", null)
        }
    }

    private fun open(bytes: ByteArray): Map<String, Any> {
        if (documents.size >= MAX_OPEN_DOCUMENTS) {
            throw PreviewException("pdf_limit", "Close another PDF before opening this one.")
        }
        prepareDirectory()
        cleanupOldFiles()
        val documentId = UUID.randomUUID().toString()
        val file = File(previewDirectory, "$documentId.pdf")
        var descriptor: ParcelFileDescriptor? = null
        var renderer: PdfRenderer? = null
        try {
            FileOutputStream(file).use { output ->
                output.write(bytes)
                output.fd.sync()
            }
            descriptor = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
            renderer = PdfRenderer(descriptor)
            if (renderer.pageCount <= 0) {
                throw PreviewException("pdf_invalid", "The PDF has no pages.")
            }
            documents[documentId] = OpenDocument(file, descriptor, renderer)
            return mapOf("documentId" to documentId, "pageCount" to renderer.pageCount)
        } catch (error: PreviewException) {
            closeFailedOpen(file, renderer, descriptor)
            throw error
        } catch (_: Exception) {
            closeFailedOpen(file, renderer, descriptor)
            throw PreviewException("pdf_invalid", "The PDF could not be opened.")
        }
    }

    private fun render(documentId: String, pageIndex: Int): ByteArray {
        val document = documents[documentId]
            ?: throw PreviewException("pdf_document_not_found", "The PDF preview is no longer available.")
        if (pageIndex !in 0 until document.renderer.pageCount) {
            throw PreviewException("pdf_page_out_of_range", "The requested PDF page is unavailable.")
        }
        val page = try {
            document.renderer.openPage(pageIndex)
        } catch (_: Exception) {
            throw PreviewException("pdf_render_failed", "The PDF page could not be rendered.")
        }
        try {
            val sourceWidth = page.width
            val sourceHeight = page.height
            if (sourceWidth <= 0 || sourceHeight <= 0 ||
                sourceWidth > MAX_SOURCE_PAGE_EDGE || sourceHeight > MAX_SOURCE_PAGE_EDGE
            ) {
                throw PreviewException("pdf_page_too_large", "The PDF page dimensions are unsupported.")
            }
            val scale = MAX_RENDER_EDGE.toDouble() / maxOf(sourceWidth, sourceHeight)
            val width = (sourceWidth * scale).roundToInt().coerceIn(1, MAX_RENDER_EDGE)
            val height = (sourceHeight * scale).roundToInt().coerceIn(1, MAX_RENDER_EDGE)
            val bitmap = try {
                Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            } catch (_: Exception) {
                throw PreviewException("pdf_render_failed", "The PDF page could not be rendered.")
            }
            try {
                bitmap.eraseColor(Color.WHITE)
                page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                return ByteArrayOutputStream().use { output ->
                    if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                        throw PreviewException("pdf_render_failed", "The PDF page could not be rendered.")
                    }
                    output.toByteArray()
                }
            } finally {
                bitmap.recycle()
            }
        } catch (error: PreviewException) {
            throw error
        } catch (_: Exception) {
            throw PreviewException("pdf_render_failed", "The PDF page could not be rendered.")
        } finally {
            try {
                page.close()
            } catch (_: Exception) {
                // The document close path still owns the remaining resources.
            }
        }
    }

    private fun prepareDirectory() {
        if ((!previewDirectory.exists() && !previewDirectory.mkdirs()) || !previewDirectory.isDirectory) {
            throw PreviewException("pdf_storage_failed", "The PDF preview could not be stored.")
        }
    }

    private fun cleanupOldFiles() {
        val activeFiles = documents.values.mapTo(mutableSetOf()) { it.file.name }
        val cutoff = System.currentTimeMillis() - ORPHAN_MAX_AGE_MS
        previewDirectory.listFiles()
            ?.asSequence()
            ?.filter { it.isFile && it.extension == "pdf" && it.name !in activeFiles }
            ?.filter { it.lastModified() in 1 until cutoff }
            ?.sortedBy { it.lastModified() }
            ?.take(MAX_ORPHANS_PER_OPEN)
            ?.forEach { it.delete() }
    }

    private fun closeFailedOpen(
        file: File,
        renderer: PdfRenderer?,
        descriptor: ParcelFileDescriptor?,
    ) {
        try {
            renderer?.close()
        } catch (_: Exception) {
        }
        try {
            descriptor?.close()
        } catch (_: Exception) {
        }
        file.delete()
    }

    private fun closeDocument(document: OpenDocument) {
        try {
            document.renderer.close()
        } catch (_: Exception) {
        }
        try {
            document.descriptor.close()
        } catch (_: Exception) {
        }
        document.file.delete()
    }

    private fun postSuccess(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun postError(result: MethodChannel.Result, code: String, message: String) {
        mainHandler.post { result.error(code, message, null) }
    }

    private data class OpenDocument(
        val file: File,
        val descriptor: ParcelFileDescriptor,
        val renderer: PdfRenderer,
    )

    private class PreviewException(val code: String, val safeMessage: String) : Exception()

    private companion object {
        const val CHANNEL_NAME = "com.tarkilhk.wing/pdf_preview"
        const val CACHE_DIRECTORY = "pdf_previews"
        const val MAX_PDF_BYTES = 32 * 1024 * 1024
        const val MAX_OPEN_DOCUMENTS = 3
        const val MAX_RENDER_EDGE = 2_000
        const val MAX_SOURCE_PAGE_EDGE = 100_000
        const val MAX_ORPHANS_PER_OPEN = 32
        const val ORPHAN_MAX_AGE_MS = 24L * 60L * 60L * 1_000L
    }
}
