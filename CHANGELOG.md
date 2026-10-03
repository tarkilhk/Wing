# Changelog

User-facing changes for Wing. Download published APKs from [GitHub Releases](https://github.com/tarkilhk/Wing/releases/latest); upcoming changes stay under **Unreleased**.

## Unreleased

- Apply Once, Session and Deny directly from command notifications without a
  second approval prompt. Keep Always behind review, and show Review and Deny
  when the command is truncated. Reload cold or cached chats before deciding,
  and require review if the command has changed.

- Keep Chats interactive after chat and project changes are confirmed. Refresh
  the list in the background with fixed progress and retry feedback, preserving
  token totals, search results and scroll position. Dismissing an action menu
  no longer reloads the list.

- Fix chat action menus turning the screen pale when a live chat-list update
  replaces the row while its menu is opening or repositioning.

## [1.2.0] - 2026-10-02

Inline reply images, less Markdown work during streaming, and stronger handling
of drafts, outgoing messages and connection recovery.

### Conversations and files

- Display reply images inline, following desktop's tap-to-zoom convention, with
  bounded mobile previews and a compact download control. Keep failed previews
  retryable and use the original image when zooming or downloading.
- Reduce repeated Markdown work on the UI thread while replies stream, including
  code-fence scanning, so typing and scrolling have less parsing work to compete with.
- Preserve valid text selections, code controls and reading position as streamed
  answers grow, finish and refresh from saved history. Restore reading position
  when reopening long chats while their formatting is prepared.
- Keep one saved draft per conversation and save only the conversation being
  edited. Save outgoing messages before submission, preserve new composer edits
  after acknowledgement, and pause uncertain deliveries for review.
- Move recent-chat snapshot filtering and size preparation off the UI thread.
- Show command confirmations in the conversation so later messages push them up;
  use a temporary YOLO notification in empty new chats.
- Fix argument suggestions after selecting slash commands such as `/approvals`.
- Open `.html` and `.htm` file paths from chat in the HTML viewer, with the full
  document, source and download actions. Support HTML reports throughout the
  supported 32 MiB download range.

### Reliability and privacy

- Keep chat-local `/stop` scoped to the selected conversation and its verified
  processes instead of stopping unrelated server work.
- Require review when notification previews are disabled, including actions on
  previously posted approval notifications.
- Validate external shared-file permissions before reading or copying content.
- Make configuration restore validate input and recover interrupted writes without
  leaving a partially restored connection. Keep connector setup edits attached to
  their profile and confirm before discarding them.
- Show scheduled script-run results separately from chat runs, and correct usage
  date handling to preserve the dates returned by Hermes.

### Before updating

- Saved drafts and queues use a new per-conversation format. Earlier saved drafts
  and queues are not imported; send them or copy their text and files before updating.
- Configuration backups now use version 2, with or without passphrase protection.
  Older backups cannot be imported; export a fresh backup after updating.
  [Current backup format and limits](https://github.com/tarkilhk/Wing/blob/v1.2.0/docs/CONFIGURATION_BACKUPS.md).

### Build and testing tools

- Make custom performance timing, counters and traces an explicit QA build option.
  Production release builds disable them and always use the production renderer.

## [1.1.3] - 2026-09-28

- Fix the black screen caused by competing Android activities sharing one
  rendering engine. Launcher, shortcut and notification opens reuse the existing
  Wing activity, with native resources cleaned up by their owning lifecycle.
- Replace Activity with Recents: show chats with messages in the last 24 hours
  alongside ongoing work, retaining All, Running and Needs input filters.
- Give Recents a compact Ongoing panel, quieter history rows, filter counts and
  aligned activity ages. Show profile icons beside ongoing chats, with profile
  name and status below the title.
- Hide internal technical sessions from saved, loaded and ongoing Recents results
  while keeping ordinary chats with background work visible.
- Return to Recents with the selected filter when leaving a chat opened there,
  using either the toolbar or Android Back button.
- Clearly label unknown backend update commit counts and explain when Hermes
  has not provided change details.

## [1.1.2] - 2026-09-27

- Open inline file paths directly from chat. Resolve Markdown document links
  and linked images from the open file's directory, and follow heading anchors
  within the current document or a linked file.
- Recover connections when returning to Wing or entering workspace screens,
  retry failed notification opens, and reopen chats whose stock Hermes session
  has not yet initialized its agent.
- Release the composer promptly when a reply finishes and reconcile stale working
  state so finished chats do not remain busy.
- Show watched chat titles in the background monitoring notification when
  notification titles are enabled.
- Hide background-process heartbeat messages from chat and search.
- Keep the Chats list order and scroll position steady during live updates,
  updating affected rows without repeatedly rebuilding or sorting the list.
- Process large offline reading snapshots away from the UI thread and avoid
  repeatedly encoding history while trimming the cache.
- Keep draft typing and queued-message edits from rebuilding unchanged chat
  history or waking workspace-wide notification observers.
- Reuse unchanged Markdown rendering while replies stream, reducing repeated
  parsing of earlier answers without delaying live updates.
- Show a home icon for the backend's default profile in Chats. Limit the
  profile strip to five visible squares, with horizontal scrolling for more.
- Simplify the add-instance button and align connection status spacing in
  screen headers.

## [1.1.1] - 2026-09-25

- Long-press an Administration profile pill to choose from Desktop's profile
  color palette or restore its automatic color. The device-saved choice also
  colors that profile in Chats.
- Choose models through a consistent search and selection flow in Chat, profile
  defaults, helper and fallback settings, scheduled tasks, and image and video
  tools. Keep pending choices visible through refresh or save errors, and use
  one clearly labelled confirmation for each setting. Remove the misleading
  speech Models entry where Hermes has no model catalogue.
- Refresh the chat model catalogue, reveal matching provider groups during
  search, and link to provider access when a model is missing.
- Put selected tool providers and models first. Outline the selected provider
  card, label saved and pending model choices, and distinguish Web search and
  extraction providers.
- Offer Android autofill in provider keys, connector credentials, connection
  headers, sensitive prompts, and backup password fields.
- Recover stalled profile connections without leaving a stale warning, and
  open the intended chat when a notification is tapped from Administration.
- Update Android secure storage, Gradle and GitHub Actions dependencies;
  refresh public guides and remove outdated planning documents.

## [1.1.0] - 2026-09-24

A more capable mobile workspace, clearer Hermes administration, and better
recovery while your agent works in the background. These changes follow `v1.0.1`.

### Chats, files and voice

- Filter chats by profile and project, create chats in the selected project, and
  browse longer lists with Show more. Grouping, sorting and visible details move
  into the chat menu.
- Show working-state animation and quieter status transitions with reduced-motion
  support. Keep fork, retry and background-agent results close to their answers.
- Open assistant deliverables from Download and Open preview cards. Read Markdown
  in Rendered or Source mode and save files through Android.
- Dictate into editable drafts and read replies aloud, with independent Local or
  Hermes choices. Add offline Android voice/language controls and profile-owned
  Hermes voice settings with sample playback. Live speech-provider and human
  speech-quality acceptance checks remain pending.
- Confirm Hermes warnings before switching a chat model, including large-context
  cost warnings.

### Administration and analytics

- Reorganize Administration around profile summaries, focused settings, provider
  access and capabilities. Edit identity and memory, search settings, and manage
  scheduled tasks without losing profile context.
- Add profile-scoped MCP setup and sign-in, clearer connection tests and failure
  details, and a confirmed server-wide Reconnect MCP tools action.
- Add provider credential renewal, sign-in recovery and reviewed credential removal.
- Separate Server and Profile health, with retained results, clearer findings and
  recovery links. Run Doctor and Security audit from Health; use Ask Hermes to
  turn a Doctor finding into an editable chat draft.
- Move usage into Hermes analytics with selectable periods, a scrollable year of
  daily activity, model/token breakdowns and token trends. Label API-equivalent
  cost estimates, pricing sources and unavailable dimensions explicitly.
- Show backend version and update availability under Versions & updates, including
  commit summaries supplied by Hermes and separate installation progress/logs.

### Connection recovery and Android

- Retry interrupted chats on return or reopening, preserve drafts and recover
  missed replies without automatically resending uncertain work.
- Improve reply, approval and structured-question notifications after restart and
  reconnect. Keep approval scope visible, show offline/retry states, and avoid
  replaying unconfirmed decisions.
- Restore unread notifications silently on relaunch while respecting read and
  dismissed alerts. Background delivery still requires a connected client and
  remains subject to Android restrictions.
- Add Hermes Cloud discovery through Nous Portal. Live hosted-instance connection
  acceptance testing remains pending.
- Add launcher shortcuts for Quick Chat, Activity and Search chats, and optional
  support links for GitHub Sponsors and Ko-fi.
- Move configuration backup/restore into App settings, including accent color,
  notification preferences, composer defaults and saved connection icons.
- Clarify connection/profile header actions and project selection; retain the
  current workspace and drafts while switching.

## [1.0.1] - 2026-09-16

Wing 1.0.1 refines the first-run experience, reorganizes device settings, improves attachments and chat alerts, and keeps notification monitoring active only while chats are working. This changelog covers all changes since the `v1.0.0` source tag.

### Connection setup and offline guide

- Replace the Add/Edit connection dialog with a full-screen Studio journey: dashboard address, sign-in, connection checks, then name and save.
- Bring the approved Wing portrait and pointed feather artwork into address and verification screens. Hide the address artwork when the keyboard opens to leave room for the form.
- Accept one complete HTTP or HTTPS dashboard URL, including its custom port and path. Honor standard HTTP/HTTPS ports, support IPv6, and reject ambiguous endpoint URLs, embedded credentials, query strings, fragments and phone-local loopback addresses.
- Explain that dashboard credentials sign in to Hermes and that model-provider keys stay on the Hermes host.
- Keep proxy authentication, separate chat routing and access headers under Sign in / Custom setup, with access headers behind a further disclosure.
- Check profiles, live chat and saved history separately before saving. Report which stage needs attention and provide connection details and retry actions. Checks do not send a chat message or establish that a model is ready.
- Require a complete username/password pair for password sign-in, preserve intentional password whitespace, and show safe errors without exposing server response bodies or credentials.
- Apply a deadline to each check, cancel provisional network work when leaving, close sockets still opening, and ignore late results after cancellation.
- Preserve the verified connection draft after a failed save so storage can be retried without repeating successful checks. Save explicitly, then open the saved workspace.
- Keep incoming-share and quick-chat routing from interrupting connection setup.
- Restyle the offline Connection guide with numbered headings, shorter paragraphs, bold action names, selectable monospace address examples and an optional Custom setup explanation.
- Improve guide reading width, spacing, safe-area handling and enlarged-text layouts in both themes. Retain the backup instructions and full setup link.

### App settings and visual consistency

- Organize App settings into Appearance, Chat, Notifications and About.
- Add a live chat preview beside appearance choices so theme, accent and text-size changes are easier to assess.
- Use compact text-size controls and clearer descriptions of default composer actions during work.
- Group notification preferences and delivery-recovery actions together. Put installed version, release links and the offline privacy policy under About.
- Express selection through the active accent background across chips, segmented controls, dropdowns, navigation, tabs and choice rows. Remove selection ticks, radio dots and selected-only borders while retaining labels and artwork.
- Apply shared selection rows to device preferences, profile/model choices, project appearance, clarification, backup restore and update targets, retaining single/multiple-choice behavior, accessibility state and keyboard interaction.
- Use tick-free status symbols and filled/empty Markdown task markers consistently across app-authored UI.

### Background monitoring and chat notifications

- Replace Firebase/server push registration with Android foreground monitoring of authenticated Hermes connections already opened in Wing.
- Start monitoring automatically when a chat begins work and alerts are enabled. Remove the separate monitoring toggle and show settings actions when permission or battery restrictions need attention.
- Retain the Flutter engine, live clients and notification routing across activity destruction and recreation while work continues.
- Run the service only while chats are working. Keep it active for concurrent chats, queued submissions and live child work; do not treat a temporary disconnect or uncertain read as completion.
- Stop monitoring after the last working chat finishes or asks for input, posting the final alert before releasing the engine and wake lock. Keep delivered reply/question notifications visible and restart monitoring when work resumes.
- Request Android notification permission after the first screen appears. Remember acceptance or denial, avoid repeated prompts, and allow a failed platform request to be retried on a later launch.
- Use Hermes’ approved caduceus for monitoring and Wing’s wing for chat alerts. Keep monitoring in its own notification group so it does not absorb chat alerts.
- Show each alert’s chat name and connection/profile context. Use expandable message previews and clear Reply ready, Input needed, Failed, Stopped and Chat updated wording.
- Take notification names and previews from the owning event, including side/background answers, and retain stable destinations when opening alerts.
- Add Show message previews, enabled by default. When disabled, retain the chat name and short status. Let Android settings control private lock-screen visibility.
- Retain separate completion and attention preferences, notification testing and delivery-recovery controls; stop monitoring when both alert categories are disabled or permission is revoked.

### Camera and sent attachments

- Attach a successful camera capture directly to its verified originating chat draft instead of opening share review. Preserve existing draft text and attachments, and keep Send explicit.
- Acknowledge camera intake only after the destination draft is saved. Keep the photo pending on preparation/save failure and retain destination review when the original chat cannot be verified or reopened.
- Render sent images as bounded, cropped previews with full-image zoom rather than unbounded transcript images.
- Present other sent attachments as file cards with recognizable names and extensions, retaining their existing open behavior.

### Documentation, maintenance and release reliability

- Refresh the repository introduction and app previews, use Wing identity throughout public documentation, and correct setup, issue-reporting and release guidance.
- Expand the historical 1.0.0 notes to describe the accumulated work in the first Wing release; those older features remain documented under 1.0.0.
- Update connection, settings, attachment, notification and design documentation to describe the delivered behavior and its validation boundaries.
- Remove obsolete generated repository maps and archived server-patch artifacts, and consolidate the release checklist under the maintained documentation.
- Allow internal Android build numbers to advance independently of the displayed release version, while enforcing valid progression for new release tags.
- Pin APK verification to Android build-tools 36.0.0 so newer `apksigner` output formats do not reject correctly signed APKs. Locate `sdkmanager` through the Android SDK root.
- Store the non-secret signing alias as an Actions variable while retaining private signing credentials as secrets.
- Support retries of an unpublished immutable version tag using current workflow tooling and the original tagged application source. Record both revisions in release metadata and refuse to overwrite published release assets.
- Wait for asynchronous attachment removal before clipboard-test cache cleanup, avoiding an intermittent teardown race.
- Extend regression coverage for connection parsing and transport, cancellation and save recovery, settings and selection layouts, camera intake, startup permissions, notification content/routing, monitoring lifecycle and release verification.

### Update and operational notes

- This release updates the existing `com.tarkilhk.wing` application with the same Wing signing identity. An in-place update preserves local app data; uninstalling is unnecessary.
- Background monitoring is a live connection, not a wake-up push service. Android force-stop, process termination, reboot, lost connectivity and manufacturer restrictions can interrupt delivery. Reopen Wing to reconnect; work started from another client while Wing is idle cannot wake it.
- Notification delivery still depends on events supplied by the Hermes server. A local test notification checks Android posting, not every server event or model workflow.

## [1.0.0] - 2026-09-16

Wing 1.0.0 is the first release under the Wing name: an independent Android client for a self-hosted Hermes server. It brings together the accumulated workspace, conversation, supervision, file-viewing, administration and Android reliability work recorded throughout the development changelog.

### A redesigned Android workspace

- Navigate through a shared drawer for Chats, Activity, Connections, App settings and Hermes administration.
- Work across saved connections and server profiles, with profile-scoped chats, projects, drafts and ongoing work.
- Browse paginated chat history, search chats and projects, and filter unread or automated conversations. Activity offers Running and Needs input filters.
- Create projects from discovered host folders or a manually entered path. Rename projects, choose their icons and colors, and delete them through the project controls.
- Rename, pin, archive, mark read/unread, delete and move chats with server/runtime checks. Move an idle conversation directly from its header, including before its first message.
- Use compact, anchored project and chat menus and a floating New chat button that leaves more room for the chat list.
- Return from a conversation to the chat list with Android Back while preserving the draft; top-level destinations share consistent drawer navigation.

### Conversation controls and a more capable composer

- Select a model per conversation from searchable provider groups and choose supported reasoning settings. Inspect context usage without dismissing the keyboard.
- Use gateway slash commands, profile skills and command completion, including supported session-specific YOLO and approval controls.
- Steer a running turn or queue a follow-up. Hold the composer arrow, slide to Steer, Stop, Queue or Fork, and release to act; slide away to cancel. The default action during work is configurable.
- Queue text, files or attachment-only messages. Review, pause, resume, edit or delete queued instructions while keeping the separate composer draft and attachments intact.
- Edit queued instructions directly in the composer, save them in place or steer them into the running turn. Queue dispatch pauses during editing and after stopped, failed or uncertain work.
- Edit and resend saved messages with confirmation before replacing history. Regenerate an answer in the current chat or branch from a saved answer into a separate conversation.
- Open a parent chat when Hermes supplies the relationship. Fork validation handles hidden notices and compacted history without rejecting valid branches.
- Answer structured clarifications and supported approval requests. Dedicated sudo, secret and vault forms keep sensitive answers out of ordinary drafts and conversation history.
- Read side-question and background-task results separately from ordinary replies, with the original question, running status and returned result kept together.

### A cleaner transcript and visibility into running work

- Read streamed replies with selectable code, copying, narrow-screen Markdown tables, image previews, reasoning, timing and server todo progress.
- Inspect expandable tool calls and results in compact Activity panels. Tools, Tasks and Agents have their own tabs, with goals and background processes under Work.
- Follow thinking, writing, tool progress, input waits and subagent work above the composer. A subtle live highlight respects reduced-motion settings.
- Keep the selected activity tab, expanded details and transcript position as updates arrive or panels open and close.
- Group historical tools and live work, collapse completed agent deliveries and background-process batches, and present server status as compact notices.
- Hide internal task snapshots, compaction continuation reminders and delivery wrappers from the transcript and chat search while preserving saved history and ordinary quoted text.
- Keep memory-review summaries accessible without a persistent oversized card, and show discreet message timestamps.
- Reopen long conversations near the latest user prompt even when tool activity fills the first history page, with manual scrolling and Back to latest preserved.

### Attachments, search and output viewers

- Add photos, camera captures and files, or paste supported clipboard images. Staged images show thumbnails and individual remove controls.
- Review Android shares and choose a connection, profile and destination chat before adding them to a draft. Sending remains a separate action.
- Preserve pending shares, captured photos, draft text and staged attachments across navigation, reconnection and app restart, including camera-return recovery.
- Prepare attachments while a reply is running. Upload photos through the image API, retry or remove partial uploads, and keep saved attachment prompts readable during editing and regeneration.
- Find text within recent messages, load older matches and jump to a result with nearby conversation context. Matching tool results expand automatically.
- Browse per-chat Outputs without loading the whole conversation; load older file references and keep existing results available after a failed page request.
- Open images, text, source and formatted Markdown inside the app, including linked Hermes files from Markdown previews.
- Read PDFs with page navigation and zoom; inspect SVG blocks and files with source access; open completed Mermaid diagrams in an offline viewer.
- Play supported audio and video with seeking, preview web links and self-contained interactive HTML, and save or share downloaded file bytes through Android.
- Show clearer file-opening failures and retry options, apply saved proxy authentication to previews/downloads, and keep search navigation accessible beside long results.

### Supervision, goals and background work

- Discover ongoing work across profiles, including chats whose delegated agents are still running after the main turn ends.
- Inspect subagents, their recent activity and live output, and use supported targeted Steer or Interrupt controls. Failed steering preserves the guidance for retry.
- View goal status, criteria, verification details, turn limits and waiting reasons; pause, resume or clear goals without losing drafts or queues.
- Add, remove and clear goal criteria, retaining unsaved additions when a request fails.
- Inspect supported session loops, heartbeats and background processes, including recent output and exit status; stop processes or dismiss finished work.
- Keep background-task results attached to the correct chat when events arrive out of order, and retain previously confirmed work when a refresh fails.
- Configure local completion and attention alerts, optional chat-title previews and sample notifications. Observed transitions in unopened chats can also alert while the app remains connected.
- Recover notification setup after temporary startup failures, avoid duplicate chat screens on notification taps, and prioritize the latest tapped destination.

### Profile, server and health administration

- Use separate Profile, Server and Health tabs, keeping profile defaults, shared server configuration and runtime observations in their owning scopes.
- Change supported model defaults, reasoning and speed settings; manage auxiliary model assignments and ordered fallback models.
- Edit profile descriptions and SOUL content. Browse retained memory and configure supported memory and context-compression settings.
- Browse and search installed skills, read their full instructions, toggle skills and toolsets, inspect setup readiness and manage supported skill installation and updates.
- Manage supported shared provider accounts and profile overrides with clearer connection, authentication and token-expiry status.
- Inspect MCP connections, test their status and use supported enablement, authentication and removal controls. Browse agent-plugin status and enablement.
- Create, clone configuration, rename and delete supported server profiles, checking the resulting server state.
- Configure supported approval, security and speech settings, with settings search and clear unavailable states for unsupported operations.
- Run connection and profile diagnostics, inspect bounded runtime logs and supported Doctor/security-audit actions, and check backend versions.
- Check and update eligible selected Hermes hosts with explicit confirmation, separate progress and an outcome for each host.
- View server-recorded sessions, API calls, tokens and estimated costs, with supported date ranges and per-model breakdowns.
- Preserve edits after rejected or partial saves, guard duplicate submissions, and keep editor actions reachable above the keyboard.

### Wing identity and Android presentation

- Adopt the Wing name, lowercase wordmark, portrait artwork, feather accents and matching launcher and notification icons.
- Introduce the navy splash screen and light/dark first-connection welcome, with an offline connection guide and restore access before setup.
- Apply the Studio design across the app: paired light/dark themes, refined Teal accents, compact controls, consistent feedback and improved native previews.
- Bring the portrait identity into the drawer, empty-chat greeting, settings and assistant badges while keeping short screens scrollable.
- Simplify alert headings to “Finished working” and “Needs your attention,” with optional chat titles underneath.
- Display the public version as `1.0.0`, and update repository, support, store and release links for Wing.
- Use the independent `com.tarkilhk.wing` application identity, with Wing Dev for development builds. Wing starts with separate local data from the inherited Hermes application.

### Recovery, privacy and release delivery

- Restore unsent drafts, attachments and queues to their originating connection, profile and chat, including recovery from Chats after a cold restart.
- Refresh execution and pending-input state when reopening a chat; preserve newer composer edits and pause uncertain queued sends for review.
- Mark chats read on Hermes only after successful history loading, and recover saved chat titles in Activity after restart.
- Fix clarification and secure-input forms rejected or omitted under strict gateway request validation, and prevent cancelled skill secret setup from leaving work stuck.
- Prevent Queue from taking attachments while an ordinary send awaits acknowledgement, and stop dashboard redirects from forwarding session credentials to another endpoint.
- Export and restore connection configuration and allowlisted preferences. Backup protection is optional: a passphrase encrypts the export; an unencrypted export contains readable credentials.
- Access the privacy policy offline in App settings, along with first-connection guidance, public feature documentation and known limitations.
- Install signed ARM64, ARMv7 or x86_64 APKs from GitHub Releases, with checksums, archived debug symbols and source/signing metadata.
- Prepare future releases with major, minor or patch version bumps and dated changelog notes. Release automation runs analysis and tests, verifies every APK, and checks uploaded assets before publication.

### Scope of this first release

Wing requires a compatible modern Hermes dashboard and gateway; individual controls depend on the server's capabilities. Accepted work continues on Hermes when the phone leaves, but local queues and alerts need a running, connected client. Firebase push delivery and synchronized older answer alternatives are not part of this release. Configuration exports do not back up drafts or the full app state.

The [earlier development history](docs/DEVELOPMENT_CHANGELOG.md) retains the intermediate entries from before Wing 1.0.0. See the [v1.0.0 known limitations](https://github.com/tarkilhk/Wing/blob/v1.0.0/docs/KNOWN_LIMITATIONS.md) for recovery, file and backend boundaries.
