package com.tarkilhk.wing

import java.io.File
import java.nio.file.Files
import java.util.zip.ZipFile
import org.junit.Assert.*
import org.junit.Test

class DiagnosticJournalTest {
    @Test fun rotationSurvivesReopeningAndExportsOldestFirst() {
        val root = Files.createTempDirectory("wing-diagnostics-test").toFile()
        try {
            val logs = File(root, "logs")
            val first = DiagnosticJournal(logs, segmentBytes = 12, segmentCount = 3)
            for (n in 1..8) first.append("row-$n")
            assertTrue(logs.listFiles()!!.sumOf { it.length() } <= 36)
            val reopened = DiagnosticJournal(logs, segmentBytes = 12, segmentCount = 3)
            reopened.append("row-9")
            val zip = File(root, "bundle.zip")
            reopened.archive(zip, mapOf("manifest.json" to "{\"format_version\":1}"))
            ZipFile(zip).use { archive ->
                val events = archive.getInputStream(archive.getEntry("events.jsonl")).bufferedReader().readText()
                assertEquals("row-5\nrow-6\nrow-7\nrow-8\nrow-9\n", events)
                assertNotNull(archive.getEntry("manifest.json"))
            }
        } finally { root.deleteRecursively() }
    }

    @Test fun oversizedRecordCannotEvictPriorEvidence() {
        val root = Files.createTempDirectory("wing-diagnostics-test").toFile()
        try {
            val journal = DiagnosticJournal(File(root, "logs"), segmentBytes = 16)
            journal.append("kept")
            assertThrows(IllegalArgumentException::class.java) { journal.append("x".repeat(17)) }
            val zip = File(root, "bundle.zip")
            journal.archive(zip, emptyMap())
            ZipFile(zip).use {
                assertEquals("kept\n", it.getInputStream(it.getEntry("events.jsonl")).bufferedReader().readText())
            }
        } finally { root.deleteRecursively() }
    }

    @Test fun utf8BudgetAndEmptyArchiveAreExplicit() {
        val root = Files.createTempDirectory("wing-diagnostics-test").toFile()
        try {
            val journal = DiagnosticJournal(File(root, "logs"), segmentBytes = 8)
            assertThrows(IllegalArgumentException::class.java) { journal.append("日本語") }
            val zip = File(root, "bundle.zip")
            journal.archive(zip, mapOf("README.txt" to "No events retained"))
            ZipFile(zip).use {
                assertEquals(0, it.getInputStream(it.getEntry("events.jsonl")).readBytes().size)
                assertNotNull(it.getEntry("README.txt"))
            }
        } finally { root.deleteRecursively() }
    }
}
