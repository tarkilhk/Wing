package com.tarkilhk.wing

import android.app.*
import android.content.*
import android.content.res.Configuration
import android.os.Handler
import android.os.Looper
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.view.View
import android.widget.RemoteViews
import android.widget.Toast
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.lang.ref.WeakReference

/** Render and deliver interactions on the retained app engine, including cold starts. */
object ChatNotifications {
    const val handleExtra = "wing_notification_handle"
    private const val publicRawExtra = "wing_notification_interaction"
    private const val channelName = "com.tarkilhk.wing/chat_notifications"
    private const val turnChannel = "wing_turn_notifications"
    private const val attentionChannel = "wing_attention_notifications"
    private var channel: MethodChannel? = null
    private var ready = false
    private val pendingActions = mutableListOf<JSONObject>()
    private val displayed = mutableMapOf<Int, Map<*, *>>()
    private var observesConfiguration = false
    private var handleStore: NotificationHandleStore? = null
    private var directActionHost: Pair<Int, WeakReference<Activity>>? = null
    private fun handles(context: Context): NotificationHandleStore = handleStore ?: run {
        val prefs = preferences(context.applicationContext)
        NotificationHandleStore(
            read = { prefs.getString("handles", null) },
            write = { prefs.edit().putString("handles", it).commit() },
        ).also { handleStore = it }
    }
    fun consumeAction(context: Context, intent: Intent): JSONObject? =
        consumeIntent(context, intent, NotificationHandleStore.actionPurpose)
    private fun consumeIntent(context: Context, intent: Intent?, purpose: String): JSONObject? = try {
        val token = intent?.getStringExtra(handleExtra)
        intent?.removeExtra(handleExtra)
        handles(context).consume(token, purpose)
    } catch (_: Exception) { null }
    fun mainHandoff(context: Context, value: JSONObject): String? =
        handles(context).issue(value.getInt("notification_id"), NotificationHandleStore.mainPurpose,
            JSONObject(value.toString()))
    private fun pendingDismissals(context: Context): JSONArray {
        return try {
            val raw = preferences(context).getString("pending", "[]") ?: "[]"
            if (raw.length > NotificationInteractionSchema.maxChars * 512) return JSONArray()
            val source = JSONArray(raw)
            val valid = JSONArray()
            for (index in 0 until minOf(source.length(), 512)) {
                val value = NotificationInteractionSchema.parse(source.optJSONObject(index)?.toString())
                if (value?.opt("dismiss") == true) valid.put(value)
            }
            valid
        } catch (_: Exception) { JSONArray() }
    }
    private fun preferences(context: Context) = context.getSharedPreferences("notification_interactions", Context.MODE_PRIVATE)

    fun attach(source: Context, engine: FlutterEngine) {
        // The retained engine outlives activities and their configuration.
        val context = source.applicationContext
        if (!observesConfiguration) {
            observesConfiguration = true
            context.registerComponentCallbacks(object : ComponentCallbacks {
                override fun onLowMemory() {}
                override fun onConfigurationChanged(configuration: Configuration) {
                    Handler(Looper.getMainLooper()).post {
                        val manager = context.getSystemService(NotificationManager::class.java)
                        val active = manager.activeNotifications.map { it.id }.toSet()
                        for ((id, data) in displayed.toMap()) {
                            if (id !in active) { displayed.remove(id); continue }
                            try { show(context, data + mapOf("alert" to false)) }
                            catch (_: Exception) { /* A settings change can revoke posting. */ }
                        }
                    }
                }
            })
        }
        if (channel != null) return
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, channelName).apply {
            setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "initialize" -> {
                            createChannels(context)
                            ready = true
                            val queue = pendingDismissals(context)
                            val deliveries = (0 until queue.length()).map { asMap(queue.getJSONObject(it)) } + pendingActions.map { asMap(it) }
                            pendingActions.clear()
                            result.success(deliveries)
                        }
                        "acknowledge" -> {
                            val prefs = preferences(context)
                            val queue = pendingDismissals(context)
                            val remaining = JSONArray()
                            for (index in 0 until queue.length()) {
                                val entry = queue.getJSONObject(index)
                                if (entry.optString("interaction_id") != call.arguments) remaining.put(entry)
                            }
                            prefs.edit().putString("pending", remaining.toString()).commit()
                            result.success(null)
                        }
                        "finishDirectAction" -> {
                            val host = directActionHost
                            if (host != null && host.first == call.arguments) {
                                directActionHost = null
                                result.success(null)
                                host.second.get()?.finish()
                            } else result.success(null)
                        }
                        "actionStatus" -> {
                            Toast.makeText(context, call.arguments as String, Toast.LENGTH_LONG).show()
                            result.success(null)
                        }
                        "show" -> { show(context, call.arguments as Map<*, *>); result.success(null) }
                        "cancel" -> {
                            val id = (call.arguments as Number).toInt()
                            check(handles(context).invalidate(id))
                            displayed.remove(id)
                            context.getSystemService(NotificationManager::class.java).cancel(id)
                            result.success(null)
                        }
                        "cancelAll" -> { check(handles(context).invalidate()); displayed.clear(); NotificationManagerCompat.from(context).cancelAll(); result.success(null) }
                        "channels" -> result.success(channelStates(context))
                        "openChannelSettings" -> {
                            val intent = if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                                .putExtra(Settings.EXTRA_CHANNEL_ID, call.arguments as String)
                            else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
                            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("notification_failed", "Notification operation failed", null) }
            }
        }
    }
    fun detach() { channel?.setMethodCallHandler(null); channel = null; ready = false; pendingActions.clear(); directActionHost = null }

    fun interact(context: Context, value: JSONObject, completed: (() -> Unit)? = null) {
        if (NotificationInteractionSchema.parse(value.toString()) == null) {
            completed?.invoke()
            return
        }
        // Only dismissals survive process death. A permission choice must never
        // become a deferred grant replayed on some later launch.
        if (value.optBoolean("dismiss")) {
            value.put("interaction_id", java.util.UUID.randomUUID().toString())
            val prefs = preferences(context)
            val queue = pendingDismissals(context)
            if (queue.length() < 512) queue.put(value)
            prefs.edit().putString("pending", queue.toString()).commit()
        }
        if (ready && channel != null) {
            channel!!.invokeMethod("interaction", asMap(value), object : MethodChannel.Result {
                override fun success(result: Any?) { completed?.invoke() }
                override fun error(code: String, message: String?, details: Any?) { completed?.invoke() }
                override fun notImplemented() { completed?.invoke() }
            })
        } else {
            if (!value.optBoolean("dismiss") && pendingActions.size < 512) pendingActions.add(value)
            completed?.invoke()
        }
    }
    private fun asMap(value: JSONObject): Map<String, Any?> = value.keys().asSequence().associateWith {
        val item = value.get(it)
        if (item == JSONObject.NULL) null else item
    }
    fun handleMainIntent(context: Context, intent: Intent?) {
        // MainActivity is exported. Raw JSON can never authorize an interaction.
        try { intent?.removeExtra(publicRawExtra) } catch (_: Exception) { return }
        val value = consumeIntent(context, intent, NotificationHandleStore.mainPurpose) ?: return
        if (context is Activity && value.optString("choice").isNotEmpty() && !value.optBoolean("review")) {
            directActionHost = value.getInt("notification_id") to WeakReference(context)
        }
        interact(context, value)
    }
    fun dismiss(context: Context, intent: Intent) {
        val value = consumeIntent(context, intent, NotificationHandleStore.dismissPurpose) ?: return
        interact(context, value)
    }
    fun hasLiveEngine() = ready && channel != null && MonitoringRuntime.engine != null

    private fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(turnChannel, "Replies and updates", NotificationManager.IMPORTANCE_DEFAULT))
        manager.createNotificationChannel(NotificationChannel(attentionChannel, "Input needed and failures", NotificationManager.IMPORTANCE_HIGH))
    }
    private fun channelStates(context: Context): List<Map<String, Any>> {
        createChannels(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        return listOf(turnChannel, attentionChannel, "hermes_monitoring").map { id ->
            val blocked = Build.VERSION.SDK_INT >= 26 && manager.getNotificationChannel(id)?.importance == NotificationManager.IMPORTANCE_NONE
            mapOf("id" to id, "blocked" to blocked, "name" to when(id) {
                turnChannel -> "Replies and updates"; attentionChannel -> "Input needed and failures"; else -> "Background monitoring"
            })
        }
    }
    private fun intent(context: Context, data: Map<*, *>, choice: String, review: Boolean): PendingIntent {
        val value = JSONObject().put("payload", data["payload"]).put("choice", choice).put("review", review)
            .put("command", (data["expanded"] as String).take(800))
            .put("chat", data["chat"]).put("revision", data["revision"]).put("notification_id", data["id"])
        // Immutable PendingIntent identity contains only an opaque token; trusted storage binds its target and choice.
        val token = handles(context).issue((data["id"] as Number).toInt(), NotificationHandleStore.actionPurpose, value)
            ?: throw IllegalStateException("Notification handoff could not be stored")
        val identity = Uri.Builder().scheme("wing-notification").authority("action").appendPath(token).build()
        val intent = Intent(context, NotificationActionActivity::class.java).setData(identity).putExtra(handleExtra, token)
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    private fun deleteIntent(context: Context, data: Map<*, *>): PendingIntent {
        val value = JSONObject().put("dismiss", true).put("chat", data["chat"]).put("revision", data["revision"])
        // Local test alerts do not own a chat dismissal.
        val token = handles(context).issue((data["id"] as Number).toInt(), NotificationHandleStore.dismissPurpose, value)
        val target = Intent(context, NotificationDismissReceiver::class.java)
            .setData(Uri.Builder().scheme("wing-notification").authority("dismiss").appendPath(token ?: java.util.UUID.randomUUID().toString()).build())
            .putExtra(handleExtra, token)
        return PendingIntent.getBroadcast(context, 0, target, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }
    private fun show(context: Context, data: Map<*, *>) {
        createChannels(context)
        val id = (data["id"] as Number).toInt()
        check(handles(context).replace(id, data["payload"] as? String, data["revision"] as? String))
        val kind = data["kind"] as? String
        val choices = data["choices"] as? List<*> ?: emptyList<String>()
        val approval = kind == "approval" && data["preview"] == true && choices.isNotEmpty()
        val pending = data["pending"] as? String ?: ""
        val error = data["error"] as? String
        val busy = data["submitting"] == true
        val body = listOf(pending, data["body"] as String).filter { it.isNotEmpty() }.joinToString(" · ")
        val icon = when(data["icon"]) {
            "ic_stat_wing_input" -> R.drawable.ic_stat_wing_input
            "ic_stat_wing_stopped" -> R.drawable.ic_stat_wing_stopped
            else -> R.drawable.ic_stat_wing
        }
        val builder = NotificationCompat.Builder(context, data["channel"] as String)
            .setSmallIcon(icon).setContentTitle(data["title"] as String)
            .setContentText(body).setSubText(data["scope"] as? String)
            .setAutoCancel(false).setOnlyAlertOnce(data["alert"] != true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(NotificationCompat.Builder(context, data["channel"] as String)
                .setSmallIcon(icon).setContentTitle("Wing").setContentText("Open Wing to review this chat").build())
            .setCategory(if (pending.isNotEmpty()) NotificationCompat.CATEGORY_REMINDER else NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(if (data["channel"] == attentionChannel) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(intent(context, data, "", true)).setDeleteIntent(deleteIntent(context, data))
        if (data["alert"] == true) builder.setDefaults(NotificationCompat.DEFAULT_ALL)
        else builder.setSilent(true)
        if (approval) {
            val large = context.resources.configuration.fontScale > 1.3f
            val views = RemoteViews(context.packageName, if (large) R.layout.notification_approval_grid else R.layout.notification_approval_row)
            val command = data["expanded"] as String
            views.setTextViewText(R.id.notice_title, data["title"] as String)
            views.setTextViewText(R.id.notice_pending, when { busy -> "Sending decision…"; !error.isNullOrEmpty() -> error; else -> pending })
            views.setTextViewText(R.id.notice_command, command)
            val metrics = context.resources.displayMetrics
            val paint = TextPaint().apply { textSize = 15f * metrics.scaledDensity; typeface = Typeface.MONOSPACE }
            val width = ((context.resources.configuration.screenWidthDp - 100) * metrics.density).toInt().coerceAtLeast(1)
            val layout = StaticLayout.Builder.obtain(command, 0, command.length, paint, width).setAlignment(Layout.Alignment.ALIGN_NORMAL).build()
            val needsReview = layout.lineCount > (if (large) 1 else 3)
                || command.isBlank() || command.endsWith("…")
            views.setViewVisibility(R.id.review_actions, if (needsReview) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.approval_actions, if (needsReview) View.GONE else View.VISIBLE)
            views.setBoolean(R.id.review, "setEnabled", !busy)
            views.setOnClickPendingIntent(R.id.review, intent(context, data, "", true))
            views.setViewVisibility(R.id.review_deny, if (choices.contains("deny")) View.VISIBLE else View.GONE)
            views.setBoolean(R.id.review_deny, "setEnabled", !busy)
            views.setOnClickPendingIntent(R.id.review_deny, intent(context, data, "deny", false))
            views.setViewVisibility(R.id.notice_scope, if (!needsReview && choices.contains("session")) View.VISIBLE else View.GONE)
            for ((choice, viewId) in listOf("once" to R.id.once, "session" to R.id.session, "always" to R.id.always, "deny" to R.id.deny)) {
                views.setViewVisibility(viewId, if (choices.contains(choice) && (!needsReview || choice == "deny")) View.VISIBLE else View.GONE)
                views.setBoolean(viewId, "setEnabled", !busy)
                views.setOnClickPendingIntent(viewId, intent(context, data, choice, choice == "always"))
            }
            builder.setStyle(NotificationCompat.DecoratedCustomViewStyle()).setCustomBigContentView(views)
        } else {
            val expanded = listOf(pending, data["expanded"] as String).filter { it.isNotEmpty() }.joinToString("\n")
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(expanded))
            if (pending.isNotEmpty()) builder.addAction(0, "Review", intent(context, data, "", true))
        }
        NotificationManagerCompat.from(context).notify(id, builder.build())
        displayed[id] = data
    }
}

class NotificationDismissReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        ChatNotifications.dismiss(context, intent)
    }
}

/** An activity PendingIntent permits unlock and cold-start UI without a trampoline. */
class NotificationActionActivity : Activity() {
    private var sent = false
    private var resumed = false
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        if (Build.VERSION.SDK_INT >= 27) setShowWhenLocked(true)
        val keyguard = getSystemService(KeyguardManager::class.java)
        if (keyguard.isKeyguardLocked && Build.VERSION.SDK_INT >= 26) {
            keyguard.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                override fun onDismissSucceeded() { deliver() }
                override fun onDismissCancelled() { finish() }
                override fun onDismissError() { finish() }
            })
        } else if (keyguard.isKeyguardLocked) {
            // On API 24/25 let the normal app activity wait behind the lock screen.
            val value = ChatNotifications.consumeAction(this, intent)
            if (value == null) finish() else openMain(value)
        }
    }
    override fun onResume() {
        super.onResume()
        resumed = true
        deliver()
    }
    override fun onPause() {
        resumed = false
        super.onPause()
    }
    private fun deliver() {
        if (!resumed || sent || getSystemService(KeyguardManager::class.java).isKeyguardLocked) return
        sent = true
        val value = ChatNotifications.consumeAction(this, intent) ?: return finish()
        if (value.optBoolean("review") || !ChatNotifications.hasLiveEngine()) openMain(value)
        else {
            // A retained engine does not give a background UID network access.
            // Keep this user-started activity resumed through recovery and the
            // decision acknowledgement, rather than finishing at dispatch.
            ChatNotifications.interact(this, value) { finish() }
        }
    }
    private fun openMain(value: JSONObject) {
        val token = ChatNotifications.mainHandoff(this, value) ?: return finish()
        startActivity(Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .putExtra(ChatNotifications.handleExtra, token))
        finish()
    }
}
