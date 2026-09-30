package com.tarkilhk.wing

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class NotificationInteractionSecurityTest {
    private fun action(choice: String = "once", review: Boolean = false): JSONObject {
        val target = JSONObject().put("connection", "host").put("connection_identity", "credential-owner")
            .put("profile", "default").put("session", "chat-one")
            .put("focus", JSONObject().put("kind", "approval").put("id", "request-one"))
        return JSONObject().put("payload", target.toString()).put("choice", choice).put("review", review)
            .put("chat", "scoped-chat").put("revision", "approval:request-one").put("notification_id", 42)
    }

    @Test fun malformedInputsAreDiscardedWithoutThrowing() {
        for (raw in listOf(null, "", "{", "[]", "null", "false", "x".repeat(NotificationInteractionSchema.maxChars + 1))) {
            assertNull(NotificationInteractionSchema.parse(raw))
        }
        for ((key, value) in listOf("payload" to 1, "choice" to true, "choice" to "grant", "review" to "false", "chat" to JSONArray(), "revision" to false)) {
            assertNull(NotificationInteractionSchema.parse(action().put(key, value).toString()))
        }
        assertNull(NotificationInteractionSchema.parse(action().put("unexpected", true).toString()))
        assertNull(NotificationInteractionSchema.parse(action().put("payload", "x".repeat(32 * 1024 + 1)).toString()))
        assertNull(NotificationInteractionSchema.parse(action().put("payload", "{").toString()))
        val target = JSONObject(action().getString("payload")).put("connection_identity", JSONObject.NULL)
        assertNull(NotificationInteractionSchema.parse(action().put("payload", target.toString()).toString()))
        target.put("connection_identity", "owner").put("focus", JSONObject().put("kind", "approval").put("id", 13))
        assertNull(NotificationInteractionSchema.parse(action().put("payload", target.toString()).toString()))
    }

    @Test fun allChoicesKeepTheirExactTargetAndReviewPolicyAcrossProcessRestart() {
        for (choice in listOf("", "once", "session", "always", "deny")) {
            for (review in listOf(false, true)) {
                var persisted: String? = null
                fun store() = NotificationHandleStore({ persisted }, { persisted = it; true })
                val source = action(choice, review)
                val token = store().issue(42, NotificationHandleStore.actionPurpose, source)!!
                source.put("choice", "deny").put("review", !review)
                    .put("payload", action().getString("payload").replace("chat-one", "chat-two"))
                    .put("revision", "different-revision")
                // The public main entry cannot accept a notification's private-action token.
                assertNull(store().consume(token, NotificationHandleStore.mainPurpose))
                val delivered = store().consume(token, NotificationHandleStore.actionPurpose)!!
                assertEquals(choice, delivered.getString("choice"))
                assertEquals(review, delivered.getBoolean("review"))
                assertEquals("approval:request-one", delivered.getString("revision"))
                assertEquals("request-one", JSONObject(delivered.getString("payload")).getJSONObject("focus").getString("id"))
                assertEquals("chat-one", JSONObject(delivered.getString("payload")).getString("session"))
                assertNull(store().consume(token, NotificationHandleStore.actionPurpose))
            }
        }
    }

    @Test fun publicHandoffsAreBoundSingleUseAndExpire() {
        var persisted: String? = null
        var time = 1000L
        fun store() = NotificationHandleStore({ persisted }, { persisted = it; true }, { time })
        val token = store().issue(42, NotificationHandleStore.mainPurpose, action("session", true))!!
        assertNull(store().consume("forged", NotificationHandleStore.mainPurpose))
        assertNull(store().consume(action().toString(), NotificationHandleStore.mainPurpose))
        assertNull(store().consume(java.util.UUID.randomUUID().toString(), NotificationHandleStore.mainPurpose))
        assertEquals("session", store().consume(token, NotificationHandleStore.mainPurpose)!!.getString("choice"))
        assertNull(store().consume(token, NotificationHandleStore.mainPurpose))
        val expired = store().issue(42, NotificationHandleStore.mainPurpose, action())!!
        time += 5 * 60 * 1000
        assertNull(store().consume(expired, NotificationHandleStore.mainPurpose))
    }

    @Test fun replacementAndCancellationRevokeOnlyTheirNotification() {
        var persisted: String? = null
        val store = NotificationHandleStore({ persisted }, { persisted = it; true })
        val old = store.issue(42, NotificationHandleStore.actionPurpose, action())!!
        val other = store.issue(43, NotificationHandleStore.actionPurpose, action())!!
        val main = store.issue(42, NotificationHandleStore.mainPurpose, action())!!
        assertTrue(store.invalidate(42))
        assertNull(store.consume(old, NotificationHandleStore.actionPurpose))
        assertNull(store.consume(main, NotificationHandleStore.mainPurpose))
        assertNotNull(store.consume(other, NotificationHandleStore.actionPurpose))
        val latest = store.issue(42, NotificationHandleStore.actionPurpose, action())!!
        assertTrue(store.invalidate())
        assertNull(store.consume(latest, NotificationHandleStore.actionPurpose))
    }

    @Test fun storageFailureNeverDeliversAndCorruptStorageIsRecoverable() {
        var persisted: String? = "{"
        var allowWrite = true
        val store = NotificationHandleStore({ persisted }, { if (allowWrite) persisted = it; allowWrite })
        val token = store.issue(42, NotificationHandleStore.actionPurpose, action())!!
        allowWrite = false
        assertNull(store.consume(token, NotificationHandleStore.actionPurpose))
        assertNull(store.issue(42, NotificationHandleStore.mainPurpose, action()))
        allowWrite = true
        assertNotNull(store.consume(token, NotificationHandleStore.actionPurpose))
        persisted = JSONArray().put(JSONObject().put("expires", "tomorrow")).toString()
        assertNull(store.consume(token, NotificationHandleStore.actionPurpose))
        assertNotNull(store.issue(42, NotificationHandleStore.actionPurpose, action()))
    }

    @Test fun sameTargetRerenderPreservesLockedMainReviewButNewTargetRevokesIt() {
        var persisted: String? = null
        val store = NotificationHandleStore({ persisted }, { persisted = it; true })
        val value = action("once", true)
        val privateAction = store.issue(42, NotificationHandleStore.actionPurpose, value)!!
        val lockedReview = store.issue(42, NotificationHandleStore.mainPurpose, value)!!
        assertTrue(store.replace(42, value.getString("payload"), value.getString("revision")))
        assertNull(store.consume(privateAction, NotificationHandleStore.actionPurpose))
        assertTrue(store.consume(lockedReview, NotificationHandleStore.mainPurpose)!!.getBoolean("review"))
        val obsoleteReview = store.issue(42, NotificationHandleStore.mainPurpose, value)!!
        assertTrue(store.replace(42, value.getString("payload"), "new-revision"))
        assertNull(store.consume(obsoleteReview, NotificationHandleStore.mainPurpose))
    }

    @Test fun boundedStorageEvictsOldHandlesAndSchemaRejectsInvalidGrant() {
        var persisted: String? = null
        val store = NotificationHandleStore({ persisted }, { persisted = it; true })
        val first = store.issue(42, NotificationHandleStore.actionPurpose, action())!!
        repeat(512) { assertNotNull(store.issue(it, NotificationHandleStore.actionPurpose, action())) }
        assertEquals(512, JSONArray(persisted).length())
        assertNull(store.consume(first, NotificationHandleStore.actionPurpose))
        assertNull(store.issue(42, NotificationHandleStore.actionPurpose, action().put("review", "false")))
    }

    @Test fun dismissalsAreSchemaChecked() {
        val dismissal = JSONObject().put("dismiss", true).put("chat", "scoped-chat").put("revision", "rev")
        assertNotNull(NotificationInteractionSchema.parse(dismissal.toString()))
        var persisted: String? = null
        val store = NotificationHandleStore({ persisted }, { persisted = it; true })
        val token = store.issue(42, NotificationHandleStore.dismissPurpose, dismissal)!!
        assertNull(store.consume(token, NotificationHandleStore.mainPurpose))
        assertTrue(store.consume(token, NotificationHandleStore.dismissPurpose)!!.getBoolean("dismiss"))
        assertNull(store.consume(token, NotificationHandleStore.dismissPurpose))
        assertNull(NotificationInteractionSchema.parse(dismissal.put("choice", "once").toString()))
        assertNotNull(NotificationInteractionSchema.parse(JSONObject().put("payload", "").put("choice", "").put("review", true).toString()))
    }
}
