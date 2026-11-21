package com.tarkilhk.wing

import android.app.Activity
import android.app.ActivityManager
import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.content.ComponentCallbacks2
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.time.Instant
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ThreadPoolExecutor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong

/** Process-owned capture; engine attachment only owns the Flutter method handler. */
internal object DiagnosticRuntime {
    private lateinit var app: Context
    private lateinit var journal: DiagnosticJournal
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())
    private val dropped = AtomicLong()
    private val failures = AtomicLong()
    private val processId = UUID.randomUUID().toString()
    private val worker = ThreadPoolExecutor(1, 1, 0, TimeUnit.MILLISECONDS,
        ArrayBlockingQueue(256), { runnable -> Thread(runnable, "WingDiagnostics").apply { isDaemon = true } })

    fun attach(context: Context, messenger: BinaryMessenger) {
        if (!::app.isInitialized) {
            app = context.applicationContext
            journal = DiagnosticJournal(File(app.noBackupFilesDir, "diagnostics"))
            registerLifecycle(app as Application)
            registerErrors()
            record("process.started", mapOf("version" to BuildConfig.VERSION_NAME,
                "build" to BuildConfig.VERSION_CODE))
        }
        channel?.setMethodCallHandler(null)
        channel = MethodChannel(messenger, "com.tarkilhk.wing/diagnostics").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "append" -> {
                        val line = call.arguments as? String
                        if (line == null || line.length > 32768) {
                            dropped.incrementAndGet()
                        } else {
                            submit {
                                try {
                                    val event = JSONObject(line)
                                    event.put("process", processId).put("uptime_ms", SystemClock.elapsedRealtime())
                                    journal.append(event.toString())
                                } catch (_: Exception) { failures.incrementAndGet() }
                            }
                        }
                        result.success(null)
                    }
                    "export" -> {
                        if (!submit {
                            try {
                                val file = createArchive()
                                main.post { result.success(file.path) }
                            } catch (_: Exception) {
                                main.post { result.error("diagnostics_export", "Could not prepare diagnostic logs.", null) }
                            }
                        }) result.error("diagnostics_busy", "Diagnostics are busy. Try again.", null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun submit(action: () -> Unit): Boolean = try {
        worker.execute(action)
        true
    } catch (_: java.util.concurrent.RejectedExecutionException) {
        dropped.incrementAndGet()
        false
    }

    fun record(event: String, fields: Map<String, Any?> = emptyMap()) {
        if (!::journal.isInitialized) return
        val line = JSONObject(fields).put("event", event).put("time", Instant.now().toString())
            .put("uptime_ms", SystemClock.elapsedRealtime()).put("process", processId).toString()
        submit {
            try { journal.append(line) } catch (_: Exception) { failures.incrementAndGet() }
        }
    }

    fun networkEvent(event: String, network: Network, capabilities: NetworkCapabilities? = null) {
        if (!::app.isInitialized) return
        try {
            record(event, mapOf("network" to network.toString(), "state" to networkState(network, capabilities)))
        } catch (_: Exception) { failures.incrementAndGet() }
    }

    private fun networkState(network: Network, supplied: NetworkCapabilities? = null): JSONObject {
        val cm = app.getSystemService(ConnectivityManager::class.java)
        val caps = supplied ?: cm.getNetworkCapabilities(network)
        val links = cm.getLinkProperties(network)
        return JSONObject().apply {
            put("id", network.toString())
            put("active", network == cm.activeNetwork)
            put("capabilities_available", caps != null)
            if (caps != null) {
                put("wifi", caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI))
                put("cellular", caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR))
                put("vpn", caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN))
                put("ethernet", caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))
                put("validated", caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED))
                put("internet", caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET))
                put("not_metered", caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED))
                put("not_roaming", caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_ROAMING))
                put("not_suspended", caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_SUSPENDED))
                put("downstream_kbps_estimate", caps.linkDownstreamBandwidthKbps)
                put("upstream_kbps_estimate", caps.linkUpstreamBandwidthKbps)
            }
            put("link_properties_available", links != null)
            if (links != null) {
                put("mtu", links.mtu)
                put("interface", links.interfaceName)
                put("private_dns_active", links.isPrivateDnsActive)
                put("dns_servers", JSONArray(links.dnsServers.map { it.hostAddress }))
                put("addresses", JSONArray(links.linkAddresses.map { it.toString() }))
                put("proxy_configured", links.httpProxy != null)
            }
        }
    }

    private fun createArchive(): File {
        val unavailable = JSONArray()
        val snapshot = JSONObject()
        fun section(name: String, read: () -> Any) {
            try { snapshot.put(name, read()) } catch (error: Exception) {
                unavailable.put(JSONObject().put("section", name).put("error_type", error.javaClass.simpleName))
            }
        }
        section("app") {
            val info = app.packageManager.getPackageInfo(app.packageName, 0)
            JSONObject().put("package", app.packageName).put("version", info.versionName)
                .put("build", info.longVersionCode).put("debug", BuildConfig.DEBUG)
                .put("first_install_ms", info.firstInstallTime).put("last_update_ms", info.lastUpdateTime)
        }
        section("device") {
            JSONObject().put("manufacturer", Build.MANUFACTURER).put("model", Build.MODEL)
                .put("android", Build.VERSION.RELEASE).put("sdk", Build.VERSION.SDK_INT)
                .put("security_patch", Build.VERSION.SECURITY_PATCH).put("abis", JSONArray(Build.SUPPORTED_ABIS.toList()))
                .put("timezone", TimeZone.getDefault().id).put("uptime_ms", SystemClock.elapsedRealtime())
                .put("locale", app.resources.configuration.locales.toLanguageTags())
        }
        section("network") {
            val cm = app.getSystemService(ConnectivityManager::class.java)
            JSONObject().put("active", cm.activeNetwork?.toString()).put("metered", cm.isActiveNetworkMetered)
                .put("data_saver_status", cm.restrictBackgroundStatus)
                .put("networks", JSONArray(cm.allNetworks.map { networkState(it) }))
        }
        section("power_and_background") {
            val pm = app.getSystemService(PowerManager::class.java)
            val am = app.getSystemService(ActivityManager::class.java)
            val battery = app.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            JSONObject().put("battery_optimization_exempt", pm.isIgnoringBatteryOptimizations(app.packageName))
                .put("power_save", pm.isPowerSaveMode).put("device_idle", pm.isDeviceIdleMode)
                .put("interactive", pm.isInteractive).put("thermal_status", pm.currentThermalStatus)
                .put("background_restricted", am.isBackgroundRestricted)
                .put("notifications_enabled", app.getSystemService(NotificationManager::class.java).areNotificationsEnabled())
                .put("monitoring_running", MonitoringRuntime.running).put("activity_visible", MonitoringRuntime.activityVisible)
                .put("battery_level", battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1))
                .put("battery_scale", battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1))
                .put("battery_plugged", battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1))
        }
        section("resources") {
            val memory = ActivityManager.MemoryInfo()
            app.getSystemService(ActivityManager::class.java).getMemoryInfo(memory)
            val vm = Runtime.getRuntime()
            JSONObject().put("available_memory_bytes", memory.availMem).put("total_memory_bytes", memory.totalMem)
                .put("low_memory", memory.lowMemory).put("heap_used_bytes", vm.totalMemory() - vm.freeMemory())
                .put("heap_max_bytes", vm.maxMemory()).put("storage_available_bytes", StatFs(app.filesDir.path).availableBytes)
        }
        section("process_exits") {
            if (Build.VERSION.SDK_INT < 30) {
                unavailable.put(JSONObject().put("section", "process_exits").put("reason", "requires_android_11"))
                JSONArray()
            } else JSONArray(app.getSystemService(ActivityManager::class.java)
                .getHistoricalProcessExitReasons(app.packageName, 0, 10).map { exit ->
                    JSONObject().put("time_ms", exit.timestamp).put("reason", exit.reason)
                        .put("status", exit.status).put("importance", exit.importance)
                        .put("pss_kb", exit.pss).put("rss_kb", exit.rss)
                })
        }
        val manifest = JSONObject().put("format_version", 1).put("created_utc", Instant.now().toString())
            .put("process", processId).put("retention_max_bytes", 4 * 512 * 1024)
            .put("dropped_events_this_process", dropped.get()).put("write_failures_this_process", failures.get())
            .put("unavailable_sections", unavailable)
        val exports = File(app.cacheDir, "diagnostic-exports").apply { mkdirs() }
        // Retire abandoned staging after a crash, while keeping recent in-flight shares intact.
        exports.listFiles()?.filter { System.currentTimeMillis() - it.lastModified() > TimeUnit.DAYS.toMillis(1) }
            ?.forEach { it.deleteRecursively() }
        val stage = File(exports, UUID.randomUUID().toString()).apply { check(mkdirs()) }
        val file = File(stage, "wing-diagnostics-${System.currentTimeMillis()}-${stage.name.take(8)}.zip")
        try {
            journal.archive(file, mapOf("manifest.json" to manifest.toString(2), "device.json" to snapshot.toString(2),
                "README.txt" to """
                    Wing diagnostic bundle
                    events.jsonl: retained structured Wing events, oldest first. UTC wall time and process/uptime correlate incidents.
                    device.json: current Android, app, network, VPN, power, resource and recent process-exit observations.
                    manifest.json: collection time, retention limit and known collection gaps.
                    Retention is a rotating 2 MiB journal, not a guaranteed duration. Capture starts with this feature's installation.
                    Events are not raw logcat. Credentials, chat/tool content, exception messages, screenshots, audio, files,
                    Wi-Fi names and hardware identifiers are not collected. Connection/profile identifiers and local network
                    addresses may be present. Network bandwidth values are Android estimates, not a speed test.
                    Process exits are Android summaries; no memory dumps or raw ANR traces are included.
                    No backend requests are made by export. Server logs are not included. Collection failure or sudden process
                    death can lose pending records; this bundle cannot establish that an unrecorded event did not happen.
                    Choosing a recipient in Android shares this ZIP. No automatic upload occurs.
                """.trimIndent()))
            return file
        } catch (error: Exception) { stage.deleteRecursively(); throw error }
    }

    private fun registerLifecycle(application: Application) {
        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            private fun event(activity: Activity, phase: String) = record("activity.$phase", mapOf("activity" to activity.javaClass.simpleName))
            override fun onActivityCreated(a: Activity, state: Bundle?) = event(a, "created")
            override fun onActivityStarted(a: Activity) = event(a, "started")
            override fun onActivityResumed(a: Activity) = event(a, "resumed")
            override fun onActivityPaused(a: Activity) = event(a, "paused")
            override fun onActivityStopped(a: Activity) = event(a, "stopped")
            override fun onActivityDestroyed(a: Activity) = event(a, "destroyed")
            override fun onActivitySaveInstanceState(a: Activity, state: Bundle) = Unit
        })
        application.registerComponentCallbacks(object : ComponentCallbacks2 {
            override fun onTrimMemory(level: Int) = record("memory.trim", mapOf("level" to level))
            override fun onLowMemory() = record("memory.low")
            override fun onConfigurationChanged(config: android.content.res.Configuration) = Unit
        })
    }

    private fun registerErrors() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            // Last-chance small synchronous write; preserve Android's crash handling.
            try {
                val frames = error.stackTrace.take(20).map {
                    "${it.className}.${it.methodName}:${it.lineNumber}"
                }
                journal.append(JSONObject().put("event", "native.uncaught_error")
                    .put("time", Instant.now().toString()).put("process", processId)
                    .put("uptime_ms", SystemClock.elapsedRealtime()).put("type", error.javaClass.name)
                    .put("stack", JSONArray(frames)).toString())
            } catch (_: Exception) { /* Crash handling must still run. */ }
            previous?.uncaughtException(thread, error)
        }
    }
}
