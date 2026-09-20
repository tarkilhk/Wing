# Known limitations

These limits describe the current client. The [product plan](PRODUCT_PLAN.md) contains selected future work; a planned capability is not a release promise.

## Connection and backend

The app requires the modern Hermes dashboard, profile/session APIs and Desktop Gateway. Older API-only/SSE installations are not supported by the active workspace. Capabilities depend on the server and provider. A slash command appearing in a catalog does not establish that it works from Android. Terminal-only, messaging-only and host-microphone operations retain those restrictions.

New-connection verification gives each of its three checks a 15-second deadline and closes provisional HTTP/WebSocket resources on failure or cancellation. The broader dashboard client still lacks transport deadlines on authentication, API reads/writes and downloads. Callers without their own deadline can remain pending when a server never answers or stops streaming. [Issue #18](https://github.com/tarkilhk/Wing/issues/4) is therefore partially addressed, not closed.

## Leaving the app and recovering work

Hermes runs accepted work on the server. While the Wing process survives, temporary network loss retains the conversation, draft and partial reply. Recovery behavior depends on the operation; see the network continuity contract for automatic retries and explicit Retry. Notification taps retain their destination through recovery. New sends remain unavailable until recovery succeeds, and uncertain prompts are never automatically replayed. See [network continuity](design/2026-09-16-network-continuity.md).

Foreground monitoring keeps the app engine and opened connections alive while chats are working, including when the activity is destroyed. Temporary disconnection does not count as finished work, but alerts and unsent queue draining need connectivity. Screen-off delivery requires allowing background battery use. When work ends, monitoring stops and posted reply/question notifications remain. Work started elsewhere cannot wake a stopped Wing process. Force-stop, process termination and reboot require reopening the app; reconnecting cannot guarantee recovery of every missed alert.

Unopened chats have status-snapshot reconciliation on connected targets. A short turn between snapshots or a missing terminal status can still be missed ([issue #9](https://github.com/tarkilhk/Wing/issues/9)). Discovery of unopened child-only work remains dependent on the backend contract. See [background notifications](BACKGROUND_NOTIFICATIONS.md#event-coverage).

If Android closes after a normal send reaches Hermes but before its acknowledgement arrives, the retained draft can return without an uncertainty warning. Check server history before sending that draft again. The client does not automatically resend it. This affects the acknowledgement window; it does not mean every reconnect duplicates a message. Tracked in [issue #3](https://github.com/tarkilhk/Wing/issues/3).

Resume can restore pending sensitive and clarification forms when the server supplies `open_requests` for the exact runtime; typed credentials are never persisted or restored. Cold side-task recovery and synchronized superseded answers still lack verified server contracts. See [Sensitive input and side questions](SUPERVISION_AND_QUEUES.md#sensitive-input-and-approvals) and [Server chat relationships](SERVER_CHAT_RELATIONSHIPS.md). Client fixtures do not establish live-server support.

## Files and local storage

Uploads accept up to 10 attachments and 64 MiB per draft; generic files have a 16 MiB per-file limit. Output downloads are capped at 32 MiB. Interactive self-contained HTML previews accept up to 1,048,576 UTF-16 code units of source and restrict network access. These limits do not override smaller provider/server limits.

Drafts, queued prompts, staged files and settings are local. Hermes owns authoritative conversation history, but Wing now also keeps bounded local reading snapshots for recovery and cold reopening. Each connection can retain up to 12 profiles, 10 conversations per profile and 60 recent message rows per conversation, with session/project summaries and a 2 MiB total snapshot cap. Oversized rows and older content can be omitted. Cached reading does not restore live status, approvals or pending writes, and is not a complete offline archive.

Configuration export transfers saved connections, credentials and allowlisted preferences; it is not a full backup of reading snapshots, drafts, queues or app state. Removing Android app storage does not delete server data. See [Privacy](../PRIVACY.md).

## Scope and verification

Bots, Cron/messaging/webhook administration, a general remote filesystem browser and an offline conversation archive are outside the selected scope. Some server administration operations depend on backend readiness or configuration; read the displayed result rather than assuming a control guarantees success.

[Upstream bugs](UPSTREAM_HERMES_BUGS.md) records reproduced server issues. The [testing guide](TESTING.md) distinguishes the recorded live baseline from fixtures. Passing tests on one revision do not certify a later APK or a Play submission.

See [Bug tracker](BUG_TRACKER.md) for the current app and backend issue links.
