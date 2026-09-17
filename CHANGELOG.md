# Changelog

## Unreleased

- Replace Administration Runtime with Versions & updates, load backend version and upstream update availability automatically, and show an update indicator. Remove Connection from Server, move server-wide connector reload into MCP connectors, and distinguish update checks, installation progress and update logs.

- Fix speech provider selection confusing Nous Subscription with direct OpenAI. Confirm the saved provider route independently of its speech engine, and keep Nous voice edits in the OpenAI voice settings used by Hermes.
- Combine Hermes speech provider and voice selection in one compact screen, with adjacent Play/Stop and a direct App settings link. Keep the sample sentence hidden and show setup only for the selected provider.

- Add an autosaving profile voice picker with Play/Stop for the Wing sample sentence, Edge suggestions, ElevenLabs account voices and advanced custom IDs, using vanilla Hermes APIs.
- Keep one Administration refresh button in the header. Refresh overview data and runtime identity together while preserving tabs and diagnostic results; remove the duplicate footer action.

- Complete the administration design refinements: composed profile brief, distinct setup/access warnings, concise scheduled-task summaries, retained runtime diagnostic results, capability-first browsing, visible provider expiry and usage tokens, content-first memory, full search paths and targeted overview refresh.

- Give Administration search and tabs consistent spacing and gutters. Select profiles directly with the same profile chips as Chats, replacing the separate Change action and picker sheet.
- Redesign Administration with profile summaries, focused provider and capability inventories, full-screen identity editing, clearer settings conflicts, read-first memory, actionable health findings and contextual search. Keep Profile, Server and Health ownership visible and apply consistent Studio layouts across themes and enlarged text.
- Add independent Local/Hermes dictation and read-aloud choices in App settings, offline Android voice/language controls, and a link to profile-owned Hermes speech settings. Request microphone permission after notifications on first launch; preserve editable drafts and cancel audio when leaving the foreground or changing chats. Live-provider and human speech-quality UAT remain pending.
- Restore the conversation's Unassigned/project selector as a separate action from connection details. Add searchable Studio project selection, refreshed connection status details, accessible header actions and enlarged-text layouts.
- Filter chats in place by tapping a project, with a selected background shade and tap-again clearing. Keep Recents unchanged, hide empty pinned sections, and create new chats in the selected project.
- Show the saved connection icon, then the status light and connection name in Chats and conversation headers, matching the other connection rows.
- Remove the redundant Edit button from the connection address card; use Back to return to the address step.
- Tap a connection icon on Connections or beside the address during setup to choose from 16 Studio-style icons. Save existing connection icons immediately without a server check; keep new choices with the setup draft. Store each choice locally and include it in configuration exports and imports; existing connections and older backups use the standard server icon. Remove the redundant Appearance menu item and keep the status light's details action separate.
- Increase spacing between connection status lights and connection names.

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

The [full development changelog](https://github.com/tarkilhk/wing/blob/main/CHANGELOG.md) retains the detailed intermediate entries. See the [v1.0.0 known limitations](https://github.com/tarkilhk/wing/blob/v1.0.0/docs/KNOWN_LIMITATIONS.md) for recovery, file and backend boundaries.

## [2.36.15+2232] - 2026-09-15

### Fixed

- Stop dashboard HTTP redirects from forwarding session credentials to another endpoint.
- Prevent Queue from taking attachments while a normal send is awaiting acknowledgement.

### Added

- Offline privacy policy accessible from App settings.
- First-connection guide, contributor instructions, known limitations and Play Data safety inventory.

### Changed

- Group Workspace options into visible filter switches, project/archive actions and Refresh; omit actions that do not apply to the current view.
- Anchor project, chat and draft menus beside their ellipsis controls with Studio styling. Replace the project row's compose pencil with New chat inside its menu.
- Shorten the README, move the detailed feature inventory into docs, correct store claims and release instructions, and archive the inherited F-Droid recipe.

## [2.36.14+2231] - 2026-09-15

### Changed
- Replace the full-width New chat shelf with a compact floating plus button.
- Extend the chat list into the freed space, with scroll padding so the final row can clear the button.

## [2.36.13+2230] - 2026-09-15

### Fixed
- Hide internal task-list reminders injected after context compression from the conversation, search and edit controls.
- Preserve ordinary lists, quoted reminders, assistant text and durable history IDs.

## [2.36.12+2229] - 2026-09-15

### Changed
- Deepen the dark-mode Teal accent from pale mint to a richer teal, keeping the existing backgrounds, light theme and other accents.

## [2.36.11+2228] - 2026-09-15

### Changed
- Refine the default accent to Teal with navy-charcoal dark surfaces and a subtly warm light canvas, inspired by Playful.
- Preserve saved Mint selections under the new Teal label and move Glacier toward a cooler blue to distinguish the two accents.
- Keep the existing layouts, portrait artwork and semantic status colors.

## [2.36.10+2227] - 2026-09-15

### Fixed
- Android Back from a conversation returns to the chat list and preserves the draft. Further Back presses open the menu, then exit.
- Correct the navigation regression test to require the chat-list step before opening the menu.

## [2.36.9+2226] - 2026-09-15

### Changed
- Remove profile names from notification headings, including the internal `default` label.
- Use "Finished working" and "Needs your attention", with the chat title underneath when alert previews are enabled.
- Use "Tap to open the chat" when chat titles are hidden.

## [2.36.8+2225] - 2026-09-15

### Changed
- Add the approved Playful portrait to the navigation drawer, empty chat greeting, app settings version card, first connection screen and assistant reply badges.
- Keep the identity colors in light and dark themes, with a shared portrait widget for future changes.
- Keep the empty greeting scrollable on short screens and hide it when messages, history loading, errors or active work appear.

## [2.36.7+2224] - 2026-09-15

### Changed
- Android Back opens the left menu from Chats, Activity, Connections, App settings and Hermes administration. Back with the menu open exits the app.
- Keep normal Back navigation through stacked detail pages, returning to their original screen before opening the menu.
- Remove Connections from the Chats Back sequence while retaining its menu entry and preserving chat drafts.

## [2.36.6+2223] - 2026-09-14

### Changed
- Replace the gold H launcher icon with the selected Playful portrait in navy, cream and mint.
- Use the matching messenger wing for notifications and Android themed icons.
- Record the approved icon identity, source assets and repeatable export process in the design documentation.

## [2.36.5+2222] - 2026-09-14

### Fixed
- Keep administration editor actions accessible above the keyboard and save confirmations.
- Ignore refresh callbacks after leaving an administration page.
- Explain managed provider selections that still need account access, verify composed browser selections, and remove provider switches from setup-only integrations.

### Changed
- Show clearer provider connection and token-expiry status.
- Use compact selection controls and tighter settings rows while retaining full touch targets.
- Add repeatable administration acceptance against an Android emulator and the real local Hermes backend.

## [2.36.4+2221] - 2026-09-14

### Changed
- Make the Intelligence sheet fit its content, with a compact header and two-column reasoning choices.
- Show context usage in a small animated card anchored above the context ring, preserving composer focus and the keyboard.

## [2.36.3+2220] - 2026-09-14

### Fixed
- Render background-process batches as one compact notice with collapsed results. Validate the producer's batch structure and reuse Desktop's process parser, preserving failures without exposing internal response instructions.

## [2.36.2+2219] - 2026-09-14

### Fixed

- Keep table scrollbars below the last row, including on phones with a bottom navigation inset.
- Use a thin, rounded, muted scrollbar with a dedicated gutter beneath Markdown tables.

## [2.36.1+2218] - 2026-09-14

### Changed

- Keep the composer up arrow visible at rest. Animate it into the configured action when held, follow the highlighted choice while sliding, and return to the arrow on release or cancellation.
- Respect reduced-motion settings by switching icons without animation.

## [2.36.0+2217] - 2026-09-14

### Changed

- Use Steer as the default action during active work, with a device preference in Hermes administration.
- Hold the composer button to open a vertical selector, slide to Steer, Stop, Queue or Fork, then release to act. Slide away to cancel.
- Keep unavailable actions visible with an explanation and provide screen reader actions without dragging.

## [2.35.0+2216] - 2026-09-14

### Added

- Tap the conversation title/project header to move the chat to a project, including before its first message.

### Fixed

- Allow idle open chats to move after verifying their profile and runtime ownership. Keep the conversation and unsent draft open.
- Keep move failures visible in the project picker with retry, and block duplicate submissions.

## [2.34.4+2215] - 2026-09-14

### Fixed

- Recover saved chat titles after restarting the app, including pending chats in background profiles.
- Refresh Activity titles from server metadata so recovered chats do not remain labelled "Restored chat".

## [2.34.3+2214] - 2026-09-14

### Fixed

- Open valid forks of compacted conversations without incorrectly reporting that the answer boundary was not copied.
- Validate forks against their complete saved history and clarify when a created fork fails validation but remains available in Chats.

## [2.34.2+2213] - 2026-09-14

### Fixed

- Receive local alerts for observed completion and input requests in unopened chats, including work started by another client in a different Hermes profile, while the app remains connected.
- Avoid duplicate alerts for opened chats and false completion alerts after failed status reads or disappearing sessions.

## [2.34.1+2212] - 2026-09-14

### Fixed

- Show all staged images as matching thumbnails at the left of the composer, with a remove action, regardless of how they were added.
- Validate pasted images from their bytes instead of rejecting generic provider MIME types. Explain when Android no longer grants access to a clipboard image.

## [2.34.0+2211] - 2026-09-14

### Added

- Paste clipboard images through the Android keyboard's image insertion action or the message composer's Paste menu.
- Save pasted JPEG, PNG and WebP images as sanitized, unsent attachments in their originating chat, preserving the existing draft text.

## [2.33.0+2210] - 2026-09-14

### Added

- Change a profile's default model from Hermes administration, with provider groups, search and server-required confirmation.
- Browse and search installed skills, read their instructions, and enable or disable individual skills.
- Inspect toolsets, their setup status and included tools, and change enablement for the selected server profile.

### Changed

- Edit queued instructions directly in the composer. Save them in place, steer them into the running turn, or cancel and restore the separate draft and attachments.
- Confirm queued instruction deletion and pause queue dispatch while an instruction is being edited.

## [2.32.0+2209] - 2026-09-14

### Changed

- Organize activity into slim Tools, Tasks and Agents tabs, with Work available for goals and background processes.
- Use consistent light text, small icons and inline chevrons for tool results and live activity. Keep expanded details close to the left guide with equal insets.
- Keep Thinking below a subtle horizontal divider across tabs. Preserve selected categories, open tool details and transcript position while switching tabs or receiving updates.

## [2.31.23+2208] - 2026-09-14

### Fixed

- Render background-process completions and agent deliveries as compact notices with collapsed details, following Hermes Desktop's exact envelope rules.
- Collapse settled agent replies and reduce expanded skill instructions to the original slash invocation.
- Apply the same display projection to chat search, and prevent internal deliveries from being edited or replayed as human prompts.
- Render system and slash-command status without a full message bubble.

## [2.31.22+2207] - 2026-09-14

### Changed

- Match Tasks, Subagents, current tool activity, Goal and Background work to the compact Activity header, with lighter text, small icons, inline counts and chevrons.
- Reduce spacing in task rows and subagent summaries, while keeping loading indicators, refresh-on-expand and detail controls available.

## [2.31.21+2206] - 2026-09-14

### Fixed

- Keep expandable transcript headers in place while details open or close, including nested tool calls and short conversations.
- Preserve manual scrolling and the Latest action while transcript content changes.
- Show one centered steering acknowledgement without a duplicate queued message.

## [2.31.20+2205] - 2026-09-14

### Changed

- Show Activity and Thought as compact metadata with lighter text, small icons and inline chevrons. Keep tool counts on the same line and remove excess padding between messages.
- Offer Edit and Delete for queued messages. Editing preserves attachments, queue order and the separate composer draft; deleting requires confirmation.

### Fixed

- Reject stale queued-message edits and restore the original message if saving fails.

## [2.31.19+2204] - 2026-09-14

### Fixed

- Use Hermes Desktop's message display types for internal events. Delegation completions show a compact notice with expandable results instead of a user bubble containing agent instructions.
- Keep hidden messages out of the transcript and internal delivery text out of Find in chat. Model changes, resumed turns and personality changes use compact notices.

## [2.31.18+2203] - 2026-09-14

### Changed

- Add a soft moving highlight to live activity text above the composer. The text stays readable, and the animation pauses for idle chats, input requests and reduced-motion settings.

## [2.31.17+2202] - 2026-09-14

### Fixed

- Group adjacent saved tool calls and current work inside one Activity disclosure, with tool details still accessible.
- Load back to the latest user prompt when tool calls fill the first history page after reopening a chat.

## [2.31.16+2201] - 2026-09-14

### Fixed

- Replace the persistent review card with a tappable memory icon that opens review details. Older reviews fold into Activity as the conversation continues.
- Keep received reviews in their conversation position during history refresh without affecting pagination.

### Changed

- Keep live activity at the bottom of the chat, above queued messages and the composer. Show current thinking, writing, tool progress, subagent activity and input waits.
- Keep status fresh across overlapping tools, new turns and reconnections.
- Add an actions menu to saved drafts for opening or discarding a draft and its queued messages while preserving sent messages.

## [2.31.13+2198] - 2026-09-14

### Fixed

- Show queued messages as compact italic rows with return arrows above the composer.
- Confirm accepted steering in the transcript and hide the backend delivery wrapper in saved steering messages.
- Preserve subagents omitted by refresh as unconfirmed, show their recent tool and progress events, and retain previously received live output.

## [2.31.12+2197] - 2026-09-13

### Fixed

- Keep chats visible in Activities and show the menu spinner while their subagents are still working after the main turn ends.

## [2.31.11+2196] - 2026-09-13

### Fixed

- Continue a skill's message after cancelling or timing out its secret setup instead of leaving the chat stuck working.
- Group live tool activity, subagents, thinking, tasks and background work under one aligned Activity section that expands only when tapped.

## [2.31.10+2195] - 2026-09-13

### Fixed

- Refresh subagent controls when opening an existing roster so Steer appears when the server supports it.
- Keep replies from server-started turns separate and refresh their saved history when they finish.

## [2.31.9+2194] - 2026-09-13

### Fixed

- Keep saved attachment prompts readable and prevent file context from multiplying when regenerating or editing a response.
- Show a readable image label instead of encoded image data when reopening saved chats.

## [2.31.8+2193] - 2026-09-13

### Fixed

- Send photos through the image attachment API, with safe retry and removal after a partial upload.
- Place file references before the message text when sending attachments.
- Regenerate answers in the current chat, matching Desktop, while keeping Branch as a separate action.

## [2.31.7+2192] - 2026-09-13

### Fixed

- Find and recover saved unsent drafts from Chats after app restart, including drafts whose original chat is no longer available.

## [2.31.6+2191] - 2026-09-13

### Fixed

- Add and remove attachments for the next draft while Hermes is responding, including queued messages and returning from the file picker during reconnection.

## [2.31.5+2190] - 2026-09-13

### Fixed

- Recover saved draft text, attachments and queued messages when a camera return cannot reopen the original chat after app restart.

## [2.31.4+2189] - 2026-09-13

### Fixed

- Keep captured photos linked to their unsent chat when camera return overlaps reconnection.

## [2.31.3+2188] - 2026-09-13

### Fixed

- Show running tasks only under their verified profile in Activity.
- Open the notified chat on cold start while keeping pending shared content available for review.
- Recover expired, unsent chats while preserving drafts, attachments, queued messages and chat settings.
- Explain rejected regeneration without exposing technical errors or changing the original chat.

## [2.31.2+2187] - 2026-09-13

### Fixed

- Open linked Hermes files from downloaded Markdown previews and return to the source preview.
- Display SVG previews and embedded images in self-contained HTML files.
- Mark directly opened chats as read after history loads, even when they are outside the loaded chat list.
- Keep confirmed subagents and background processes visible when a refresh returns invalid data, with a Retry error.

## [2.31.1+2186] - 2026-09-12

### Fixed

- Explain file-opening failures with specific next steps and offer Retry for temporary failures.
- Apply saved proxy authentication settings to file previews and downloads.
- Keep Find results newest-first when loading older matches.
- Keep View in chat accessible above long expanded search results.

## [2.31.0+2185] - 2026-09-12

### Added

- Choose discovered repository folders when creating a project, with manual path entry available.
- Open linked files directly from conversation messages using the existing file viewers.
- Display Hermes review summaries separately from ordinary replies.

### Fixed

- Show Input needed for password and verification requests while reading older messages.

## [2.30.1+2184] - 2026-09-12

### Fixed

- Keep active password requests and background-task cards visible across reconnections to the same session.
- Remove unavailable answer-version controls while preserving Branch and Regenerate.

## [2.30.0+2183] - 2026-09-12

### Added

- What's new and Releases links in App settings.

### Fixed

- HTML and SVG previews announce the correct format to accessibility services.

## [2.28.0+2181] - 2026-09-12

### Added

- Show background notification availability in App settings.

## [2.27.2+2180] - 2026-09-12

### Fixed

- Notification taps reuse the correct chat screen instead of opening duplicates.
- The latest notification tap takes priority when switching quickly between chats.
- Failed notification opens can be retried.

## [2.27.1+2179] - 2026-09-12

### Fixed

- Notifications recover after a temporary startup failure.
- Alerts for the same chat replace one another consistently across app restarts.

## [2.27.0+2178] - 2026-09-12

### Added

- Queue messages with attachments, including attachment-only drafts, and restore them after interruption.

### Fixed

- Preserve newer composer edits while saving or removing queued messages.
- Keep failed or uncertain sends paused for review.
- Remove queued attachment copies when their chat is deleted.

## [2.26.0+2177] - 2026-09-12

### Added

- Open Find matches in their conversation with nearby messages and Back to latest.
- Automatically expand matching tool results.

## [2.25.1+2176] - 2026-09-12

### Fixed

- Mark an unread chat read on Hermes after its history opens successfully.
- Preserve unread status after failed loads and provide a retry when the read update fails.

## [2.25.0+2175] - 2026-09-12

### Added

- Show prompts, running status and results for `/bg` and `/background` tasks.

### Fixed

- Keep task results attached to the correct chat when events arrive out of order.
- Explain completed tasks that return no text.

## [2.24.1+2174] - 2026-09-12

### Fixed

- Find searches recent history first and can load older messages without losing the query or results.
- Remove the 100-result display limit and duplicate matches from overlapping pages.
- Keep Find and Outputs working after server history compression.

## [2.24.0+2173] - 2026-09-12

### Added

- Open downloaded, self-contained HTML files with interactive preview, source access and Save or share.

### Fixed

- Large chats open Outputs without loading the entire conversation.
- Load older outputs adds earlier files; failed batches retain existing results and offer retry.

## [2.23.0+2172] - 2026-09-12

### Added

- Preview SVG code blocks and output files with zoom, source access and copying.
- Keep source available for incomplete or oversized SVG content.

## [2.22.0+2171] - 2026-09-12

### Added

- Play downloaded audio and video inside Hermes with play, pause and seeking.
- Offer external playback and Save or share when a format cannot be played in the app.

## [2.21.0+2170] - 2026-09-12

### Added

- Read formatted Markdown output files and switch to their source.
- Open web links in a browser preview and return to the original chat.

## [2.20.0+2169] - 2026-09-12

### Added

- Read PDFs inside Hermes with page navigation, pinch zoom and retry.

## [2.19.0+2168] - 2026-09-12

### Added

- Open Mermaid diagrams in a zoomable viewer with source access and copying.
- Keep source readable when a diagram cannot be rendered.

## [2.18.0+2167] - 2026-09-12

### Added

- Open a parent chat when Hermes supplies its relationship.

### Changed

- Remove locally stored answer-version links while retaining Regenerate, Branch, Edit and Fork.

## [2.17.0+2166] - 2026-09-12

### Added

- Open PDF, audio and video outputs in compatible installed apps.

### Changed

- Add thousands separators to usage counts, token counts and costs.

## [2.16.0+2165] - 2026-09-12

### Added

- Check and update selected Hermes connections with separate progress and results for each host.

## [2.15.0+2164] - 2026-09-12

### Added

- Configure securely stored custom access-proxy headers for dashboard and chat connections.

## [2.14.0+2163] - 2026-09-12

### Added

- Add, remove and clear goal criteria, preserving unsaved additions after failures.

## [2.13.0+2162] - 2026-09-12

### Added

- View the selected profile's last 30 days of sessions, API calls, tokens and costs, including per-model usage where available.
- Show estimated and reported costs separately.

## [2.12.0+2161] - 2026-09-12

### Added

- Start an eligible backend update after confirmation and follow its progress and outcome.

## [2.11.0+2160] - 2026-09-12

### Added

- Edit profile descriptions and SOUL content, retain unapplied changes after partial saves, and confirm before discarding edits.

## [2.10.0+2159] - 2026-09-12

### Added

- Run connection, authentication and provider diagnostics from Hermes administration.
- View the installed Android version and check backend version and update availability.

## [2.9.0+2158] - 2026-09-12

### Added

- Inspect session loop and heartbeat status with supported controls.
- View background processes, recent output and exit status; stop a process or dismiss a finished one.

## [2.8.0+2157] - 2026-09-12

### Added

- View goal status, criteria, verification details, turn limits and waiting reasons.
- Pause, resume or clear goals without losing unsent drafts or queued messages.

## [2.7.0+2156] - 2026-09-12

### Added

- View active subagents and their live output.
- Steer or interrupt a selected subagent; retain guidance when steering fails.

## [2.6.0+2155] - 2026-09-12

### Added

- Capture a photo from the attachment menu and review it in the originating chat's draft.
- Preserve the photo if another destination must be chosen; cancellation leaves the draft unchanged.

## [2.5.2+2154] - 2026-09-12

### Fixed

- Delete chats whose existing server session is still open but idle.

## [2.5.1+2153] - 2026-09-12

### Fixed

- Close idle sessions before deleting their history, while protecting chats that are working or awaiting input.

## [2.5.0+2152] - 2026-09-12

### Added

- Preserve incoming shares across app restarts until added to a draft or discarded.

### Fixed

- Report unreadable or oversized shared files without silently omitting them.
- Keep shared content available when adding or discarding it fails.
- Load context fullness when reopening a chat without requiring a new message.

## [2.4.0+2151] - 2026-09-12

### Added

- Review incoming shares and choose a connection, profile and new or existing chat.
- Add photos and files through the attachment menu.

### Fixed

- Validate all shared files before changing the destination draft.
- Keep later shares from replacing content already under review.

## [2.3.0+2150] - 2026-09-12

### Added

- Running and Needs input filters in Activity, plus Unread only in Chats.
- Project rename, icon, color and delete actions.

### Changed

- Integrate the context fuse into the composer border with a dot marking current usage.

## [2.2.0+2149] - 2026-09-12

### Added

- Expandable tool details, server todos and available reasoning and timing.
- Find within a chat and per-chat Outputs for files, images and links.
- Image zoom, text and code previews, and file downloads with Android save/share.

### Changed

- Load saved history in pages and report incomplete history clearly.
- Limit downloads to 32 MiB.

## [2.1.5+2148] - 2026-09-12

### Added

- Edit and resend saved messages with confirmation before replacing history.
- Fork from a saved answer and display separate `/btw` result cards.
- Improve narrow-screen tables, code blocks and image previews.
- Display server-reported context usage near the composer.

### Fixed

- Preserve unrelated drafts and attachments during Edit and Fork.

## [2.1.4+2147] - 2026-09-12

### Added

- Discover ongoing work across profiles in Activity.
- Respond to sudo, secret and vault requests without saving sensitive answers.
- Configure completion and attention alerts, optional chat titles and sample notifications.
- Queue, review, remove, pause and resume follow-up messages; steer a running turn.

### Changed

- Send queued messages in order and pause after stop, failure or uncertain delivery.

## [2.1.3+2146] - 2026-09-11

### Added

- Restore unsent drafts and staged attachments by connection, profile and chat.
- Choose models grouped by technical provider and control session-specific `/yolo`.
- Use server-supported approval scopes and independent notification preferences.

### Fixed

- Refresh execution and pending-input state when reopening a chat.
- Preserve newly typed text and prevent duplicate sends after uncertain acknowledgements.

## [2.1.2+2145] - 2026-09-11

### Changed

- Add a shared left drawer for Chats, Activity, Connections, App settings and Hermes administration.
- Apply a consistent style to connection setup and device settings.
- Add an administration entry for connection and profile information.
- Remove unused legacy screens and navigation.

## [2.1.1+2142] - 2026-09-08

### Fixed

- Fork conversations correctly when hidden notices precede the selected answer.

## [2.1.1] - 2026-09-06

### Fixed

- Handle clarification requests containing multiple questions.

## [2.1.0] - 2026-09-03

### Added

- Workspace navigation, attention summaries and Activity.
- Project browsing, chat assignment, project search and deletion.
- Chat filters, date grouping and session search with matching excerpts.
- Encrypted configuration export and import.
- Quick-chat shortcuts and reviewed sharing into chats.
- Android notification permission controls.
- Context display, message actions, code copying and expanded tool output.

### Fixed

- Recover from stalled connections and unresponsive navigation controls.

## [1.0.14-hermesapk.14] - 2026-07-30

### Added

- Show document-intake status for uploaded attachments.

### Fixed

- Keep uploads usable when document catalog registration is temporarily unavailable.

## [1.0.13-hermesapk.13] - 2026-07-30

### Added

- Resumable streaming chats with interruption and reconnect support.
- Per-chat model and thinking-effort selection.
- Up to ten attachments per message with upload progress, removal and retry.
- Markdown, copying, read-aloud, editing, regeneration, chat export, search and branching.
- Approval, clarification, sensitive-request, tool, background-task and subagent displays.
- A separate debug app that can coexist with the release app.

### Changed

- Keep text and attachments in the same conversation.
- Scope model and thinking preferences to individual chats.

### Fixed

- Prevent crashes while opening Branch and dashboard dialogs.
- Reconcile successful branches after a late server error.
- Request microphone permission only when starting a microphone action.
- Handle delayed and duplicate chat events consistently.

## [1.0.13]

### Fixed

- Display the correct installed application version.

## [1.0.12]

### Added

- Filter chats by session source, with separate preferences for each connection.

## [1.0.8]

### Added

- Configure reverse-proxy path prefixes and proxy-managed dashboard authentication.
- Edit dashboard and proxy settings for saved connections.

### Fixed

- Apply configured path prefixes consistently to history, streaming and connection checks.

## [1.0.7]

### Added

- Connect to password-protected dashboards.
- Configure and validate dashboard ports and credentials per connection.

### Fixed

- Avoid duplicate simultaneous dashboard logins.
- Preserve dashboard settings when changing a connection's API key.
