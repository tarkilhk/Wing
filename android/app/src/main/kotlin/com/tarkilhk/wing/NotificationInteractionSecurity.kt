package com.tarkilhk.wing

import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** Strict decoding at native intent/storage boundaries; malformed data is discarded. */
internal object NotificationInteractionSchema {
    const val maxChars = 64 * 1024
    private val choices = setOf("", "once", "session", "always", "deny")

    fun parse(raw: String?): JSONObject? = try {
        if (raw == null || raw.length > maxChars) null else {
            val value = JSONObject(raw)
            if (valid(value)) value else null
        }
    } catch (_: Exception) { null }

    private fun string(value: JSONObject, key: String, limit: Int, nonempty: Boolean = false): Boolean {
        val item = value.opt(key)
        return item is String && item.length <= limit && (!nonempty || item.isNotEmpty())
    }

    private fun valid(value: JSONObject): Boolean {
        if (value.opt("dismiss") == true) {
            return value.keys().asSequence().all { it in setOf("dismiss", "chat", "revision", "interaction_id") } &&
                string(value, "chat", 16 * 1024, true) && string(value, "revision", 2048, true) &&
                (!value.has("interaction_id") || string(value, "interaction_id", 36, true))
        }
        if (!value.keys().asSequence().all { it in setOf("payload", "choice", "review", "chat", "revision", "notification_id") } ||
            !string(value, "payload", 32 * 1024) || value.opt("choice") !in choices ||
            value.opt("review") !is Boolean) return false
        if (value.has("notification_id") && value.opt("notification_id") !is Int) return false
        for (key in listOf("chat", "revision")) {
            if (value.has(key) && !value.isNull(key) && !string(value, key, if (key == "chat") 16 * 1024 else 2048)) return false
        }
        val payload = value.getString("payload")
        if (payload.isEmpty()) return value.getString("choice").isEmpty()
        val target = JSONObject(payload)
        if (!listOf("connection", "connection_identity", "profile", "session").all { string(target, it, 4096, true) }) return false
        val focus = target.optJSONObject("focus")
        if (focus != null) {
            if (focus.opt("kind") !in setOf("answer", "side", "background", "approval", "question", "secure", "status") ||
                !string(focus, "id", 4096, true)) return false
            if (focus.has("message_id") && focus.opt("message_id") !is Int && focus.opt("message_id") !is Long) return false
        } else if (target.has("focus")) return false
        return value.getString("choice").isEmpty() || focus?.opt("kind") == "approval"
    }
}

/** Opaque, single-use authorizations. Only the private action activity mints main handoffs. */
internal class NotificationHandleStore(
    private val read: () -> String?,
    private val write: (String) -> Boolean,
    private val now: () -> Long = System::currentTimeMillis,
    private val random: () -> String = { UUID.randomUUID().toString() },
) {
    companion object {
        const val actionPurpose = "action"
        const val mainPurpose = "main"
        const val dismissPurpose = "dismiss"
        private const val maxHandles = 512
        private const val maxStoredChars = 4 * 1024 * 1024
        private val tokenPattern = Regex("[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}")
    }

    private fun entries(): MutableList<JSONObject> = try {
        val raw = read()
        if (raw == null || raw.length > maxStoredChars) mutableListOf() else {
            val array = JSONArray(raw)
            if (array.length() > maxHandles) mutableListOf() else (0 until array.length()).mapNotNull { index ->
                val entry = array.optJSONObject(index) ?: return@mapNotNull null
                val expires = entry.opt("expires")
                if (expires !is Long && expires !is Int) return@mapNotNull null
                val value = entry.optJSONObject("value") ?: return@mapNotNull null
                if (!tokenPattern.matches(entry.optString("token")) ||
                    entry.opt("purpose") !in setOf(actionPurpose, mainPurpose, dismissPurpose) ||
                    entry.opt("notification") !is Int || entry.getLong("expires") <= now() ||
                    NotificationInteractionSchema.parse(value.toString()) == null) null else entry
            }.toMutableList()
        }
    } catch (_: Exception) { mutableListOf() }

    @Synchronized fun issue(notification: Int, purpose: String, value: JSONObject): String? {
        if (purpose !in setOf(actionPurpose, mainPurpose, dismissPurpose) || NotificationInteractionSchema.parse(value.toString()) == null) return null
        val entries = entries()
        while (entries.size >= maxHandles) entries.removeAt(0)
        val token = random()
        val ttl = if (purpose == mainPurpose) 5 * 60 * 1000L else 7 * 24 * 60 * 60 * 1000L
        entries.add(JSONObject().put("token", token).put("purpose", purpose).put("notification", notification)
            .put("expires", now() + ttl).put("value", JSONObject(value.toString())))
        var raw = JSONArray(entries).toString()
        while (raw.length > maxStoredChars && entries.size > 1) {
            entries.removeAt(0)
            raw = JSONArray(entries).toString()
        }
        return if (raw.length <= maxStoredChars && write(raw)) token else null
    }

    @Synchronized fun consume(token: String?, purpose: String): JSONObject? {
        if (token == null || token.length != 36 || !tokenPattern.matches(token)) return null
        val entries = entries()
        val index = entries.indexOfFirst { it.optString("token") == token && it.optString("purpose") == purpose }
        if (index < 0) return null
        val entry = entries.removeAt(index)
        // Never deliver an action unless its deletion is durably acknowledged.
        return if (write(JSONArray(entries).toString())) entry.getJSONObject("value") else null
    }

    @Synchronized fun invalidate(notification: Int? = null): Boolean =
        write(JSONArray(entries().filter { notification != null && it.optInt("notification") != notification }).toString())

    @Synchronized fun replace(notification: Int, payload: String?, revision: String?): Boolean =
        write(JSONArray(entries().filter { entry ->
            entry.optInt("notification") != notification ||
                // Startup/configuration can re-render the same alert while Main waits for unlock.
                // Keep only its already-minted review handoff, with exactly the same target.
                (entry.optString("purpose") == mainPurpose &&
                    entry.getJSONObject("value").optString("payload") == payload &&
                    entry.getJSONObject("value").optString("revision") == revision)
        }).toString())
}

/** External shares must carry a read grant and resolve to a different app's provider. */
internal object ExternalShareUriPolicy {
    fun allows(scheme: String?, authority: String?, providerPackage: String?, ownPackage: String, granted: Boolean): Boolean =
        scheme == "content" && !authority.isNullOrBlank() && !authority.contains('@') &&
            !providerPackage.isNullOrBlank() && providerPackage != ownPackage && granted
}
