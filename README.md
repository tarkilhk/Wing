# Hermes Android

A personal Android client for a remote [Hermes Agent](https://github.com/NousResearch/hermes-agent), focused on finding work, continuing conversations, supervising agents and using their results from a phone.

This is the `tarkilhk/hermes-android` fork. Its current interface and roadmap are independent of the inherited application's UI. Existing code can be reused or replaced according to the selected plan.

## Product plan and research

The [owner-selected product plan](docs/PRODUCT_PLAN.md) is the source of truth for what we intend to build. It records the feature selections, exclusions, incremental work packages and progress. Planned features are not claims about the current app.

The app uses a left hamburger drawer for Chats, Activity, Connections, App settings and Hermes administration. Hermes owns work state; the phone preserves unsent drafts and client-owned follow-up queues, and uses server refresh to recover current history and status. Broader administration is being added in the ranked slices in the [administration roadmap](docs/ADMINISTRATION_ROADMAP.md). Bots, Cron/messaging/webhook administration, offline history and a general filesystem browser remain outside the selected scope.

The [Desktop/Android comparison](docs/HERMES_DESKTOP_ANDROID_FEATURE_ANALYSIS.md) and [source inventories](docs/README.md#research-preserved-for-future-work) preserve the research behind the decisions. The [documentation index](docs/README.md) distinguishes current contracts from historical plans.

## Current implementation

The current connection flow opens `ProfileWorkspaceScreen`, which owns the drawer and the existing chat workspace. Implemented behavior includes:

- Saved connections in the shared app style, password setup, modern dashboard/gateway validation, profile discovery and client-local profile switching.
- Drawer navigation, Activity discovery across profiles, reachable theme/accent/text-size and notification controls, and installed Android version/build in App settings. Hermes administration shows the selected connection/profile, description/SOUL editing, manual access/provider diagnostics, server-recorded profile usage and confirmed one-host backend updates with server progress and outcomes. Activity reports profiles it could not reach. PDF/audio/video outputs can be opened in installed Android viewers using authenticated downloads. Advanced connection settings support custom access-proxy headers stored with secure credentials. The Connections toolbar also opens selected-host backend updates with per-host progress and outcomes.
- Separate profile-owned conversations and running work, with reconnect and server-history refresh.
- Chat-menu supervision of subagents, goal details and background work. Supported controls include targeted subagent Steer/Interrupt, goal Pause/Resume/Clear, loop/heartbeat controls and background-process Stop. Goal criteria can be added, removed or cleared; actions wait for server acknowledgement.
- Projects with creation, rename, server appearance and delete controls. Project creation can explicitly discover repository roots configured on the Hermes host or accept a manual absolute path. Recent and pinned chats, paginated unread filtering, Running/Needs input Activity filters, full-text conversation search, Find within the current chat with recent-first results, Search older messages and View in chat, and an option to include automated chats are also available.
- Rename, pin/unpin, explicit read/unread, archive/unarchive, delete and move-to-project actions with server-side constraints. Successfully opening an unread chat marks it read on Hermes; failed reads and manual unread choices stay protected.
- Streaming conversations, horizontally scrollable tables, selectable fenced code with copy/wrap controls, expandable tool activity, server todo snapshots, collapsed reasoning and Stop. Review summaries open from a memory icon and fold into Activity as the conversation continues. Tapped web images open in a zoomable preview with a browser fallback. Completed Mermaid blocks offer an offline diagram view with zoom and source access.
- A thin context fuse displays server-reported usage, with estimated/unknown states and live updates.
- Per-chat model and reasoning selection, with searchable, expandable technical-provider groups. Server session settings take precedence over former local model overrides.
- Unsent text and staged attachments survive app restart, scoped to their original connection/profile/chat. An uncertain send retains its draft for checking against server history; it is never resent automatically.
- Message actions and a long press on Send/Stop offer follow-up queues with text and attachments, plus text-only steering. Queues run in order while the client is connected, remain separate from the current draft, and pause after failed, stopped or uncertain sends. Queued items can be reviewed and removed.
- Dynamic slash-command discovery, aliases, argument completion, skill dispatch, and dedicated current-session actions including steering and identifiable side-question and background-task cards with the original prompt and result.
- Saved-message Edit/resend with history-replacement confirmation, one-shot idle Fork, Regenerate and Branch. Parent chat navigation uses existing Hermes metadata. Explicit synchronized answer versions remain deferred because their required API has not been verified on unmodified Hermes.
- Per-chat Outputs shows recent file/link references first, with **Load older outputs** for earlier history. Direct Markdown links to result files use the same authenticated viewer. Failed batches keep the files already listed and offer retry. Authenticated file retrieval preserves host/profile/chat ownership, supports formatted Markdown/source, SVG and image previews and shares actual bytes through Android; downloads are capped at 32 MiB. PDFs have page controls and pinch zoom; downloaded audio/video has play/pause and seeking. Web links open a browser preview, and self-contained HTML files up to 1 MiB can open interactively in the app. Back returns to the chat.
- Camera/Photos/Files attachment choices, clipboard image pasting through the Android keyboard or the composer's Paste menu, and reviewed Android sharing into a chosen connection/profile/chat. Pasted JPEG, PNG and WebP images are sanitized and saved as unsent attachments in the originating draft. Camera returns to the originating draft's review when that destination is still valid. Incoming shares survive restart before destination selection, preserve existing drafts and never send automatically. Launcher quick chat, server-advertised approvals and structured clarification remain. Sudo, secret and vault forms keep credentials out of drafts/history, and the jump control identifies their live input requests while the reader is viewing older messages.
- Local completion/input notifications with independent device controls, optional chat titles, a test alert and original host/profile/chat routing, plus configuration restore from the connections screen.
- Profile default model selection with provider groups and server-required confirmation. Administration also includes searchable skills, complete skill instructions, individual skill/toolset toggles, and toolset configuration status.

The shell cleanup removed the unreachable legacy screens and navigation widgets, including the old chat UI, Spaces, Cron, Memory, Files and Skills screens. Shared service and contract code remains available where useful for later work; no stored user data was deleted. The [Android source inventory](docs/research/HERMES_ANDROID_FEATURE_INVENTORY_2026-09-11.md) records the earlier baseline. [Shell delivery notes](docs/APP_SHELL.md) describe this change and its limits.

A command appearing in the gateway catalog does not prove correct support for every client or session. Terminal-only, messaging-only and host-microphone commands have platform restrictions. `/yolo` now uses the session's reported state and the session-scoped configuration RPC, including during a running turn. See the [delivery sequence](docs/DELIVERY_SEQUENCE.md) for verification limits.

Remote work and phone notification delivery are separate. The app refreshes the history and execution state supplied by the existing server. Local notifications require an active connection and currently have limited coverage of unopened chats. Firebase delivery is dropped. Hermes backend modifications are prohibited. The server patches prepared during 2.28-2.30 were an out-of-scope experiment and were never deployed; their deployment plan is withdrawn. Explicit synchronized answer versions and additional sensitive/side-task recovery remain deferred where the unmodified server lacks the required capability. [Emulator verification](docs/EMULATOR_ROADMAP_VERIFICATION.md) records Android behavior against fixtures separately from actual server support.

## Connect to Hermes

The active app requires a modern Hermes dashboard with profile and session APIs and an authenticated Desktop Gateway WebSocket endpoint. It does not fall back to the old unscoped API-only chat flow.

1. Run Hermes on the backend machine and make its dashboard and gateway reachable from the phone, for example on the same LAN or an existing private network.
2. Add a connection with a label and host. The current form defaults to dashboard port `9119`; use the actual port for your deployment.
3. Supply dashboard credentials if required. Advanced fields support a dashboard path prefix, proxy-authenticated access and an explicit Desktop Gateway URL.
4. Save. The app tests profile discovery, gateway connection and session listing before accepting the connection.
5. Select the intended profile and open a chat or project.

Reverse proxies must route both HTTP requests and the WebSocket connection correctly. Gateway authentication is distinct from the model-provider credentials stored on Hermes. If setup fails, check the host/port/path, credentials and server capabilities rather than following the inherited API-key/SSE instructions.

The app's current slash/profile contracts are documented in [slash command support](docs/SLASH_COMMAND_SUPPORT.md) and the [profile design](docs/PROFILE_SWITCHING_DESIGN.md). Do not assume that a newer Android APK supplies a missing server API.

## Version and application identity

Source version on 2026-09-14 is `2.36.2+2219` in [pubspec.yaml](pubspec.yaml). This is the checked-out version, not a claim that a matching public release has been published. Each release is recorded in the [changelog](CHANGELOG.md), with semantic versions and an increasing Android build number.

- Personal release package: `com.tarkilhk.hermes.android`, labelled Hermes Personal.
- Development package: `com.hermesagent.hermes_android.dev`.
- The inherited upstream package is separate and is not this fork's release identity.
- ABI-split codes derive from the base build number; the current ARM64 split uses `22192`.

The [release plan](docs/ANDROID_RELEASE_PLAN.md) and [build configuration](android/app/build.gradle.kts) document identity, signing and version-code rules. App settings displays this client's installed version/build and links to this fork's changelog and published releases, separately from the backend version.

## Development

Use an installed Flutter SDK compatible with [pubspec.yaml](pubspec.yaml), Java 17 and the configured Android SDK. The [local build notes](docs/LOCAL_BUILD_SETUP.md) contain environment-specific setup and dated verification results; use the actual checkout path on your machine.

```sh
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

Device/live gateway checks are separate from the ordinary test suite. Follow the relevant feature's contract document for its opt-in integration tests.

Personal release builds use [scripts/build-personal-release.ps1](scripts/build-personal-release.ps1) and the separate signing identity. Keep signing material outside Git. Complete [CODE_QUALITY_CHECKLIST.md](CODE_QUALITY_CHECKLIST.md) before a release; do not change signing identity or publish an APK as part of unrelated feature work.

## Main implementation paths

| Path | Responsibility |
| --- | --- |
| [lib/main.dart](lib/main.dart) | Saved connections, app wiring, credentials and notification navigation |
| [Profile workspace](lib/core/screens/profile_workspace_screen.dart) | Current conversation UI and composer |
| [Workspace browser](lib/core/screens/profile_workspace_browser.dart) | Profiles, projects, chats, search and Activity entry |
| [Workspace controller](lib/core/services/profile_workspace_controller.dart) | Profile/chat ownership, commands, active work and reconciliation |
| [Profile gateway](lib/core/services/profile_gateway.dart) | Scoped HTTP/RPC operations |
| [Attachment service](lib/core/services/attachment_draft_service.dart) | Staging, validation and upload |
| [Product plan](docs/PRODUCT_PLAN.md) | Selected scope and delivery record |

The older `WorkspaceScreen`, `ChatScreen` and related screens were removed; Git retains their implementation history.

## Provenance and credits

Forked from [rusty4444/hermes-android](https://github.com/rusty4444/hermes-android). The [changelog](CHANGELOG.md), [notice](NOTICE.md) and Git history preserve inherited work and attribution.

Contributors to the inherited application include CarlosReyesPena for the daily-driver workspace edition, CristianGCiocoi for Remote Gateway integration, AI-Guru and grunjol for review/testing and proxy work, louquillio for session-source filters, and sternbergm for password-protected dashboards. This fork's new roadmap does not diminish those contributions.

License: MIT. See the repository's license/provenance material and upstream history.
