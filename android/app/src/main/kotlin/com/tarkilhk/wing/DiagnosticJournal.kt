package com.tarkilhk.wing

import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Called only by the diagnostic worker. Bounded storage, independent of Android/logcat. */
internal class DiagnosticJournal(
    private val root: File,
    private val segmentBytes: Int = 512 * 1024,
    private val segmentCount: Int = 4,
) {
    private fun segment(index: Int) = File(root, "events-$index.jsonl")

    @Synchronized fun append(line: String) {
        val bytes = (line + "\n").toByteArray(Charsets.UTF_8)
        require(bytes.size <= segmentBytes) { "Diagnostic record too large" }
        check(root.isDirectory || root.mkdirs())
        if (segment(0).length() + bytes.size > segmentBytes) {
            check(!segment(segmentCount - 1).exists() || segment(segmentCount - 1).delete())
            for (index in segmentCount - 2 downTo 0) {
                val source = segment(index)
                if (source.exists()) check(source.renameTo(segment(index + 1)))
            }
        }
        segment(0).appendBytes(bytes)
    }

    @Synchronized fun archive(destination: File, sections: Map<String, String>) {
        try {
            ZipOutputStream(destination.outputStream().buffered()).use { zip ->
                sections.forEach { (name, text) ->
                    zip.putNextEntry(ZipEntry(name))
                    zip.write(text.toByteArray(Charsets.UTF_8))
                    zip.closeEntry()
                }
                zip.putNextEntry(ZipEntry("events.jsonl"))
                for (index in segmentCount - 1 downTo 0) {
                    val file = segment(index)
                    if (file.exists()) file.inputStream().use { it.copyTo(zip) }
                }
                zip.closeEntry()
            }
        } catch (error: Exception) {
            destination.delete()
            throw error
        }
    }
}
