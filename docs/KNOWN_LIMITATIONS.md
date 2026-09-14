# Known limitations

These limits describe the current client. The [product plan](PRODUCT_PLAN.md) contains selected future work; a planned capability is not a release promise.

## Connection and backend

The app requires the modern Hermes dashboard, profile/session APIs and Desktop Gateway. Older API-only/SSE installations are not supported by the active workspace. Capabilities depend on the server and provider. A slash command appearing in a catalog does not establish that it works from Android. Terminal-only, messaging-only and host-microphone operations retain those restrictions.

Some dashboard requests still lack a transport deadline. A host that accepts a connection but never answers can leave connection setup or a download pending. Tracked in [issue #18](https://github.com/tarkilhk/hermes-android/issues/18).

## Leaving the app and recovering work

Hermes runs accepted work on the server. The phone must be running and connected to drain its unsent follow-up queue or generate local alerts. Unopened chats have limited notification coverage, and Android can suspend background connections. Firebase delivery is outside the selected release scope.

If Android closes after a normal send reaches Hermes but before its acknowledgement arrives, the retained draft can return without an uncertainty warning. Check server history before sending that draft again. The client does not automatically resend it. This affects the acknowledgement window; it does not mean every reconnect duplicates a message. Tracked in [issue #17](https://github.com/tarkilhk/hermes-android/issues/17).

Pending sensitive requests, side tasks and synchronized answer-version recovery depend on server capabilities. See [Sensitive request recovery](SENSITIVE_REQUEST_RECOVERY.md), [Side-task recovery](SIDE_TASK_RECOVERY.md) and [Server chat relationships](SERVER_CHAT_RELATIONSHIPS.md). Client fixtures do not establish live-server support.

## Files and local storage

Uploads accept up to 10 attachments and 64 MiB per draft; generic files have a 16 MiB per-file limit. Output downloads are capped at 32 MiB. Interactive self-contained HTML previews are capped at 1 MiB and restrict network access. These limits do not override smaller provider/server limits.

Drafts, queued prompts, staged files and settings are local. Conversation history stays on Hermes and is fetched when needed. Configuration export transfers saved connections, credentials and allowlisted preferences; it is not a full backup of drafts, queues or app state. Removing Android app storage does not delete server data. See [Privacy](../PRIVACY.md).

## Scope and verification

Bots, Cron/messaging/webhook administration, a general remote filesystem browser and an offline conversation archive are outside the selected scope. Some server administration operations depend on backend readiness or configuration; read the displayed result rather than assuming a control guarantees success.

[Upstream bugs](UPSTREAM_HERMES_BUGS.md) records reproduced server issues. Dated QA records distinguish live server checks from fixtures and retain their original versions. Passing tests on one revision do not certify a later APK or a Play submission.

See [Bug tracker](BUG_TRACKER.md) for the current app and backend issue links.
