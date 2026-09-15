# Feature guide

Start with [Getting started](GETTING_STARTED.md) to install and connect. The controls below are reachable in the current profile workspace; individual operations depend on the connected server. Read [Known limitations](KNOWN_LIMITATIONS.md) before relying on recovery or background alerts.

## Find your work

Use the drawer for Chats, Activity, Connections, App settings and Hermes administration. Select a connection and profile without changing another client's selection. Chats includes recent projects, pins, search and paginated history. Filters cover unread and automated chats; Activity can filter Running and Needs input and reports unreachable profiles.

The floating plus creates a chat, or a project in All projects. Row ellipsis menus keep actions beside their item. Projects support host-folder discovery, creation, rename, appearance and deletion. Chats support rename, pin, read/unread, archive, delete and move to project, subject to server/runtime checks. Opening a chat successfully marks it read on Hermes.

See [Navigation and projects](APP_SHELL.md) for search limits and ownership rules.

## Write and control a conversation

Replies stream into a readable transcript with selectable code, copying, tables, expandable tools, reasoning and server todo progress. A context ring beside the model selector shows server-reported or estimated usage. Model selection has search and collapsible technical-provider groups, with supported reasoning choices.

Internal task snapshots and compaction continuation reminders are filtered out of chat and Find in chat. Saved history stays intact, and quoted technical messages remain visible.

Unsent text and staged files survive navigation and restart. Tap Send while idle. During work, the normal action defaults to Steer and can be changed to Queue or Stop in App settings. Hold the arrow, slide to an available action and release for a one-time alternative. Queue supports text/files; Steer is text-only. Hold a queued row to edit it. Queues remain separate from the draft and pause after stopped, failed or uncertain work.

Type `/` for commands, skills and argument completion. Current-session YOLO reports the server's state. Side questions and background commands display their original question and received result. Saved-message Edit confirms history replacement; Regenerate replaces an answer in place, while Branch/Fork creates a separate chat. Parent chat uses server metadata. Shared older answer alternatives remain unavailable.

See [Conversation actions](CONVERSATION_ACTIONS_AND_READING.md), [composer gesture](COMPOSER_ACTION_GESTURE.md) and [queues](SUPERVISION_AND_QUEUES.md).

## Send attachments and use results

Add Camera, Photos or Files, paste a supported clipboard image, or share content into Hermes from Android. A photo taken with Camera inside a chat attaches directly to that chat's draft. External shares open a review to choose their destination and content; Send is separate. Dictation uses the device's speech-recognition service to produce text for review.

Sent images appear below your message on your side of the chat. Previews are capped at 240 × 320 dp; long screenshots show a crop from the top. Tap to view and zoom the full image. Other attachments appear as file cards with their name and extension. Saved history retains previews when its image content or server file remains available. An unavailable image shows a retry control.

Find in chat starts with recent messages and can search older history. View in chat shows a result with nearby context; Back to latest returns to the conversation. Outputs lists recent file references and can load older ones.

Authenticated viewers support Markdown/source, images, SVG, PDF pages/zoom and common audio/video playback. Completed Mermaid blocks open an offline diagram viewer. Web links use browser previews; self-contained HTML up to 1 MiB can open interactively. Downloads are capped at 32 MiB, and Save or share delivers actual bytes through Android. Old server references may no longer resolve.

See [Sharing and capture](SHARING_AND_CAPTURE.md), [Find and Outputs](EXECUTION_FIND_AND_OUTPUTS.md) and [output viewers](OPENING_OUTPUT_FILES.md).

## Supervise and administer

Respond to supported approval scopes and structured clarification. Dedicated sudo, secret and vault forms keep sensitive values outside ordinary drafts/history. Inspect subagents and use supported targeted Steer/Interrupt. Goals expose details and Pause/Resume/Clear, criteria editing and Resume now; background work exposes supported loop, heartbeat and process controls.

Administration separates Profile, Server and Health. It includes supported model defaults, SOUL/description, skills/toolsets, shared provider accounts and explicit overrides, MCP controls, profile lifecycle, settings, diagnostics, logs and usage. Unsupported writes are labelled, including individual memory edits and per-tool MCP changes. Eligible backend updates support deliberate single-host or selected-host actions with separate outcomes.

App settings groups device preferences into Appearance, Chat, Notifications and About. Appearance includes a live chat preview, paired light/dark themes, accent colors and text size. Chat explains the default action during work; Notifications groups alert preferences and delivery recovery. About contains the installed version, release links and offline privacy policy. Configuration export/import transfers connections, credentials and allowlisted preferences; it is not a full draft/app backup.

The Connections toolbar provides Backup configuration and Restore configuration, in that order. Backup offers an optional passphrase before sharing the file. Leave it blank for a plain JSON backup, including readable credentials, or enter and confirm a passphrase to encrypt it. Restore accepts either format and only needs a passphrase for encrypted files. Restore is also available before adding a first connection.

See [Administration](ADMINISTRATION.md), [session controls](SESSION_CONTROLS.md), [subagents](SUBAGENT_SUPERVISION.md) and [notifications](BACKGROUND_NOTIFICATIONS.md).

Accepted work continues on Hermes when the phone leaves. Background monitoring retains the connected client while chats are working, with an ongoing notification and an optional battery exemption for screen-off delivery. When every chat is finished or waiting for input, monitoring stops and the chat notifications remain. Local queues and alerts still stop if Android terminates the process. Firebase delivery, cold sensitive/side-task recovery and synchronized answer versions are not current features. The [product plan](PRODUCT_PLAN.md) separates selected work from exclusions.
