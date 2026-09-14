# Server chat relationships

Regenerate replaces an answer in the current conversation. Branch/Fork creates a separate durable session from freshly verified saved rows. These supported actions do not require an answer-version extension. See [Conversation actions](CONVERSATION_ACTIONS_AND_READING.md#edit-regenerate-and-fork).

Parent chat appears when Hermes supplies a nonblank `parent_session_id`. An acknowledged branch can also supply `parent`, accepted only when it matches the source. Navigation keeps the original connection/profile. Explicit null clears a parent; an omitted field may retain already received metadata.

Parent does not mean previous answer. Hermes uses parent sessions for other relationships too. Do not infer siblings from matching transcript prefixes, scan pages as a complete version list or assign version numbers locally.

The phone-only answer index was removed. Startup's best-effort cleanup targets only `answer_versions_v1_*` preferences, leaving drafts and queues intact. The obsolete links are never read, and server chats remain available through Chats.

Synchronized superseded answers remain deferred. Recorded live regeneration leaves one durable replacement; Desktop's same-client alternatives do not establish shared server persistence. The rejected version-API experiment was removed and is not a setup prerequisite or supported contract.
