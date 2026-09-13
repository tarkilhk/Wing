# Delivery sequence

Approved on 2026-09-11 after the owner tried the new shell. This breaks the [product plan](PRODUCT_PLAN.md) into increments for implementation and phone use. It does not add features, change exclusions or set calendar deadlines. Owner feedback can move a slice forward.

W00, the shell, is deployed. The W packages remain feature themes and coverage records. D01 through D30 below are delivery slices within those themes, not new feature IDs. Implementation is underway; the tracking table records what has actually been verified.

## How we deliver

As of 2026-09-13, pause new feature work and complete the
[implemented-feature QA sweep](QA_SWEEP_2026-09-13.md). Check every delivered
feature, record failures, fix them and rerun the failed checks before proceeding.

Owner correction, 2026-09-12: **No Hermes backend modifications.** Earlier
instructions to deploy `server-patches` or add a sender/supervisor are withdrawn.
The experiments were never deployed. Use existing Hermes APIs and defer unsupported
capabilities. Any patch test results retained in historical technical records are
not completed product acceptance or authorization for server work.

The 2.30.1 correction is installed on the owner's phone as Personal 21842.
It removes invented answer-version requests and branch metadata, and fixes
same-runtime reconnects clearing live prompts/cards when optional fields are
absent. All 53 focused checks and 1,257 full-suite tests pass, with four opt-in
skips; analysis is clean. The prior patch-dependent version/recovery claims are
withdrawn. No server deployment is requested or planned.

Start a slice by checking its existing behavior and the relevant deployed backend contract. Preserve working implementations and define the specific remaining change. Keep this check inside the slice; do not make a complete backend audit a prerequisite for all development.

Implement one useful outcome at a time. Prefer one focused commit and a short set of acceptance checks. If a slice becomes too large, split it at a usable intermediate outcome, such as displaying server project appearance before adding its editor. Do not bundle unrelated work to fill a release.

Use the emulator for routine implementation and acceptance checks. Reserve the
phone for final deployment, Samsung-specific behavior and reproducing reported
live-connection problems. Synthetic gateway scenarios must remain isolated from
real Hermes servers and must not be reported as live-server verification.

For each phone build, keep the [changelog](../CHANGELOG.md) limited to added, changed and fixed product behavior. Record checks, deployment details and remaining limits in the relevant technical feature note or verification record. Use semantic versions: minor for added features, patch for fixes, major for breaking changes. Increase the Android build number for each release and preserve published version history. Update the changelog with each milestone commit and push to `main`. The owner tries the change during normal use; correct problems before adding another layer to that workflow. Closely related small slices can share a build. One slice is not a promise of one day or one conversation of development.

Research is on `main` as `acd8c40`; the accepted shell baseline is committed and pushed as `87ddb44`. Commit and push after each verified milestone. Use smaller, cheaper agents for bounded tasks, integrate their changes, and report progress regularly. Reuse working code and remove obsolete implementations. This is a new product: do not add backward-compatibility layers.

## 1. Make everyday conversation dependable

These are the first proposed deliveries. Draft protection has immediate value because unsent work has no server copy. Provider grouping and the known `/yolo` gap are bounded improvements that should follow without a large redesign.

| Slice | Scope | Observable completion |
| --- | --- | --- |
| D01 Protect unsent work | Q02, M03; draft portion of Q03 | Unsent text and staged attachment references survive navigation and app restart, retain their intended host/profile/chat, and clear only when appropriate. A missing staged file is reported without losing the text. No transcript database or accepted-work outbox. |
| D02 Resume from Hermes | R02, R18, M01 refresh portion, M04; merged S14 | Reopening a chat displays the server's latest history, execution state and pending input. Lost acknowledgements do not cause duplicate submissions. Preserve and verify current behavior; fix only demonstrated gaps. |
| D03 Choose the right provider and model | Q16 | Expandable technical-provider groups preserve the exact server route/model identity. Reopening reflects server session configuration; old local overrides do not overwrite changes made elsewhere. |
| D04 Fix current-session YOLO | R06 | `/yolo` changes the intended session, shows its effective server state and leaves global defaults alone. Check behavior during a running turn against the deployed contract. Typing `/` remains the command entry point. |

D02 and D03 may reveal a missing server field or API. Record the precise dependency and continue independent slices instead of introducing durable client-owned substitutes.

## 2. Find work that needs attention and unblock it

This makes the phone useful for work started on Desktop or another profile. It also establishes the task targets and pending-input behavior that later push notifications need.

| Slice | Scope | Observable completion |
| --- | --- | --- |
| D05 Discover ongoing work | C09, R03, M02; Running/Needs input portion of C08 | Activity discovers ongoing sessions across profiles from the server, including work never opened on this phone. Opening a result retains its original owner. Test discovery limits before claiming full coverage. |
| D06 Answer approvals and questions | R04, R05, R07 | Existing allow/reject and clarification work is retained and completed where needed. Supported approval scopes, multiple questions and acknowledged outcomes are understandable and target the correct request. |
| D07 Answer sensitive requests | R08, R09 | Supported password, sudo, environment-secret and login/verification requests have dedicated responses and accurate completion/error handling. Implement each request family separately if the contracts differ. |
| D08 Make current notifications useful | R16, R17, S12, M09; local portion of M01 | Local completion/input notices, simple controls and notification taps work together. Tapping loads the right server session. The app accurately describes the limits before D27 adds background push. |

The first backend discovery check belongs at the start of D05. If the server cannot enumerate live sessions and pending requests across profiles, record the client capability as unavailable; do not add backend work. The current controller-only Activity list cannot satisfy this slice.

## 3. Direct a conversation while Hermes works

Keep the interaction small. Existing slash commands and ordinary Send behavior remain the starting point.

| Slice | Scope | Observable completion |
| --- | --- | --- |
| D09 Queue or steer this submission | Q11; Queue/Steer portion of Q10 | One-shot Queue/Steer through long press and an accessible menu. The owner approved Desktop-style client-owned queues on 2026-09-11: keep queued follow-ups with their chat, review/remove them and submit in order after active work finishes. Reuse draft storage/send; pause on uncertainty. Steer uses the backend's acknowledged outcome. Normal Send stays unchanged and Stop remains available. |
| D10 Correct and branch saved work | Q07, Q09; Fork portion of Q10 | Edit/resend, regeneration and answer-version navigation reflect server-owned history relationships. Complete the one-shot Fork action after defining its saved-history boundary. |
| D11 Ask alongside ongoing work | Q12, T14 | Side/background questions have identifiable results and links back to their work. Control notices and agent deliveries remain distinct from ordinary assistant answers. |

Do not delay useful Queue/Steer controls while resolving answer-version persistence. D10 begins by checking whether the server represents branch/version relationships; a local-only grouping database is not an acceptable completion.

## 4. Read and use the results

Deliver the path from an answer to a usable result on the phone. Keep the general remote file browser excluded.

| Slice | Scope | Observable completion |
| --- | --- | --- |
| D12 Read common answer content | T03 P1, T04 | Common Markdown, code, tables and supported diagrams are readable on a narrow phone, including large text and long content. Advanced math remains outside this slice. |
| D13 Read media and links | T05, T06 | Images and other supported media display or open sensibly, and links/previews return cleanly to the conversation. |
| D14 Understand execution output | T07, T08, T09, G07 | Tool output, server-provided todos and optional reasoning/time information are readable and expandable. No terminal or Git client is implied. |
| D15 Show the context fuse | T10 | A thin line integrated into the composer border shows server-reported context occupancy, with a mini dot at the current position, an accessible value and clear unknown/estimated states. Owner screenshot feedback on 2026-09-12 removes the separate row. |
| D16 Retrieve chat outputs | F03, F04, F05 P1 | A per-chat Outputs entry opens and downloads actual backend results from the right host. No global artifact library. |
| D17 Preview results | F06, F07 | Common file previews and interactive web output open from D16 and return to the originating chat. Reuse the media/link handling from D13. |

D15 is independent and can move earlier if the owner wants the fuse sooner. D16 can likewise move ahead of transcript polish when downloading results is the more pressing need.

## 5. Find, organize and start work from the phone

| Slice | Scope | Observable completion |
| --- | --- | --- |
| D18 Search and read older work | C02, C03, T11, T12 | Existing pagination/search is verified and completed for older server history, find-in-chat, stable reading during loading and jumping to the latest message. No durable local session-restoration store. |
| D19 Read state and remaining filters | C07; remaining P1 scope of C08 | Read/unread comes from Hermes and remains consistent across clients. Complete the agreed filters, reusing D05's task states. |
| D20 Manage projects | P03, P04, P06, P08 | Project creation, rename/delete, destination selection and server-owned icon/color metadata work together. Start with display and one-host operations; split individual write actions into separate commits if needed. |
| D21 Share into a reviewed draft | Q03, M06 | Android Share for text, links, images and files reaches the existing staging pipeline, with an explicit destination and review before Send. Reuse D01's durable drafts. |
| D22 Capture into that draft | Camera/photo portion of M06 and Q03 | Camera/photo choices feed the same draft and attachment flow, including cancellation and unavailable-file handling. No separate capture application. |

Capture can move forward once D01 is complete. It does not depend on finishing all search/project improvements.

## 6. Supervise longer work

These screens depend on the same server status and interaction contracts used by Activity and approvals. Keep each control close to the work it affects.

| Slice | Scope | Observable completion |
| --- | --- | --- |
| D23 Supervise subagents | R10, R11 | View a roster and progress, open details/transcripts, and target supported steer/interrupt actions at the correct subagent. |
| D24 Follow goals | R12, R13 | Display server goal state, criteria and verification details; provide supported pause/resume/clear operations with acknowledged outcomes. |
| D25 Inspect session background work | R14, R15 | Inspect and control session heartbeat/loop and background processes where supported. This does not reopen the deferred Cron/messaging/webhook administration section. |

## 7. Add reliable background notifications

Background notifications remain a desired later outcome, subject to the no-backend-modifications constraint. They are deferred because an existing registration/sender integration has not been verified. Client SDK code alone does not complete delivery.

| Slice | Scope | Observable completion |
| --- | --- | --- |
| D26 Connect backend events to FCM | M01, R16, W07 | Use an existing authenticated registration and delivery integration if Hermes supplies one. Otherwise defer; do not implement a Hermes sender or registration API. |
| D27 Receive and open background alerts | M01, R16, R17, S12, M09, W07 | Complete Android delivery, registration lifecycle, duplicate handling and taps that refresh the authoritative session. Verify phone-locked and normally terminated-app cases. Respect Android permission, offline and force-stop limits. |

Push carries minimal notification/routing information. Conversations, pending requests and execution remain on Hermes. Do not turn this into a Firebase database migration.

## 8. Complete connection maintenance and the small admin screen

Keep broad K-family administration low priority. The shell already supplies navigation, device appearance controls and a read-only admin entry; finish their selected gaps rather than rebuilding those screens.

| Slice | Scope | Observable completion |
| --- | --- | --- |
| D28 Repair and inspect connections | Remaining B01/B02, B04, B10, S01, S02 | Setup, advanced access, connection repair, useful health diagnostics and server usage information are complete. Separate diagnostics/usage from access changes if the slice grows. |
| D29 Edit the selected profile | B14, B15; limited K seed | Add the selected profile/SOUL operations with explicit server scope. Preserve client-local profile navigation and centrally shared server settings. Broad provider/tool/plugin administration remains deferred. |
| D30 Expose versions and perform updates | S08, B11; verify remaining S10 | Expose Android/backend version identity and selected update information. Implement backend health/restart/update for one host first, then the selected multi-connection operations with per-host outcomes. Validate each operation separately. Retain the existing device appearance controls. |

D30 is a milestone with explicit subdeliveries: version visibility, one-host restart/update, and multi-host updates. Showing version information must not wait for multi-host operations. Restart and update require verified backend contracts and recovery outcomes.

## Tracking and completion

### Current work, 2026-09-13

The 2.31.11 fixes pass focused checks and available live emulator acceptance,
including the unified collapsed Activity section against a real sudo request.
The shared-checkout final run was invalidated by unrelated concurrent task edits,
which are excluded from this release and are not product failures. The isolated
`build/camera-release` snapshot passes 1,343 tests with four opt-in skips in
1 minute 52 seconds; its package config and test inventory confirm isolation.
Evidence is `build/2.31.11-isolated-full-tests.log`. Analyzer verification is
clean after 11.5 seconds in `build/2.31.11-isolated-analysis-final.log`. The only
intervening edit added analyzer-required braces around one test-cleanup `if`;
product code and behavior were unchanged. Signing and the phone update to 2.31.11
are pending; the installed phone version is confirmed as 2.31.8.

Remaining acceptance includes signing and phone verification, plus checks needing
external conditions, physical hardware or an upstream contract.
Broad K administration, background push,
synchronized answer versions, cold sensitive/side-task recovery and remote TUI
restart remain deferred. No backend changes are authorized by this queue.

### Previous continuation queue, 2026-09-12

These are remaining portions of selected slices, not additional product scope.
Deliver and verify each before adding the next layer.

The 2.31 release contains four bounded client changes:

1. D20 / P03 offers repository roots from an explicit stock
   `projects.discover_repos` scan while retaining manual absolute-path entry.
2. D13/D16/D17 / T06, F03 and F06 route direct Markdown file links through the
   existing authenticated output viewer.
3. D11 / T14 renders existing `review.summary` events as transient review notices.
4. D07/D18 / R08, R09 and T12 labels the jump action **Input needed** when a
   sensitive request arrives while the reader is in older history.

The 2.31.1 correction adds actionable file HTTP errors, transient Retry, saved
proxied-auth forwarding, stable recent-first Find loading and action-first long
results. All 1,288 tests pass with four opt-in skips, analysis is clean, and all
four emulator scenarios pass. Personal 2.31.1 / 21862 is installed and launches.
No server changes are part of this release. See the
[live phone record](LIVE_PHONE_ACCEPTANCE_2026-09-12.md) and
[emulator record](EMULATOR_ROADMAP_VERIFICATION.md).

### Work after the current continuation queue

The 2026-09-12 coverage check found the following remaining dependencies. These
items remain selected; completing the client slices above does not complete
their live verification or authorize broader administration features.

| Selected work | Next required step |
| --- | --- |
| Phone and live-server QA across delivered slices | Personal 2.31.1 / 21862 is installed. Existing-chat context, large-chat Outputs, older Find, project discovery selection, draft survival, provider grouping and a basic prompt round trip passed their recorded live checks. Project creation, Activity with live work, cross-client read state, attachment queues and Samsung media/capture behavior remain. |
| D26-D27 / M01, R16, R17, S12, M09 | Background push stays deferred. Reassess only if unmodified Hermes exposes a compatible delivery integration. The earlier sender/registration experiment is rejected; existing local alerts remain supported. |
| D10 / Q09 synchronized answer versions | Deferred: no existing explicit version-group API was verified. Keep normal Branch/Regenerate and parent navigation. The rejected version experiment is not product support. |
| D07 sensitive request recovery | Live sensitive forms remain supported. Cold or cross-client recovery is deferred because unmodified Hermes exposes no verified pending-sensitive snapshot. |
| D11 side/background task recovery | Existing live side/background events remain supported. Cold snapshot recovery and unopened-chat background counts are deferred because the required fields are not verified on unmodified Hermes. |
| D30 / B11 remote TUI restart | Deferred: no existing authenticated remote TUI restart API was verified. Do not build a supervisor or modify Hermes. Existing backend update APIs remain a separate approved client flow. |

Device-dependent acceptance stays open until it is exercised on the phone and
live server. Fixture coverage cannot close that gap. The 2.31.1 full suite,
analysis and emulator scenarios pass, and its installed live results are recorded
separately from remaining checks in
[live phone acceptance](LIVE_PHONE_ACCEPTANCE_2026-09-12.md).

| Slice | Status | Delivered change | Verification and phone build | Remaining dependency |
| --- | --- | --- | --- | --- |
| W00 | Done | Shared shell and legacy UI cleanup | Personal 2.1.2 / 21452; see [shell notes](APP_SHELL.md) | No new feature coverage implied |
| D01-D04 | Implemented; available native/live QA passed | Durable drafts, server refresh on cached reopen, technical-provider groups, session YOLO; removed local model overrides. See [delivery notes](CONVERSATION_FOUNDATIONS.md) | Samsung verified draft restart, reopen, provider grouping, reasoning and `/yolo`. Emulator clarification recovery, cross-client model/reasoning adoption and lost-ack protection passed. The final native suite proved missing-file recovery retained the draft/error/removal action and sent no prompt | Remaining variants require external server/device conditions recorded in the QA sweep |
| D05 | Live ownership and Activity filters passed | Read the global active list once and show tasks only after verifying their profile owner from local identity or profile-scoped saved metadata | Samsung showed one correctly owned running task. Local Hermes All and Needs input showed the one owned request, Running correctly showed none, and opening the filtered row restored the exact question | Child-only discovery is unavailable because `session.active_list` omits the idle parent and has no `side_tasks_running` field; see the [QA sweep](QA_SWEEP_2026-09-13.md) |
| D06 | Clarification live QA passed; manual approval variant pending | Existing clarification handling retained; server-advertised approval scopes and request targeting | Single-question force-stop recovery and a two-question BLUE/DOG response passed against local Hermes. A safe live `-WhatIf` approval probe auto-resolved on Hermes and its terminal result persisted | No manual approval card was produced, so advertised manual approval-scope variants remain unverified |
| D07 | Live sudo and QA-034 secret Cancel/expiry passed; cold recovery deferred | Dedicated sudo/secret/vault forms handle existing live requests and expiry events. Same-runtime reconnect preserves received requests; credentials remain unsaved. The 2.31 release improves the older-history jump label | A real sudo request cancelled with an empty response and persisted its tool result. Default `/gif-search` produced a real `TENOR_API_KEY` request. Corrected Cancel and the untouched stock 300 s expiry both completed; all seven live-backend scenarios passed with driver exit 0 | No vault backend is configured. Unmodified Hermes exposes no verified pending-sensitive snapshot; see [limits](SENSITIVE_REQUEST_RECOVERY.md) |
| D08 | Local and real chat routing passed; background push deferred | Independent completion/attention switches, optional chat titles, permission/test alert and existing notification routing; 2.27.1 adds startup retry and stable chat alert IDs | Samsung verified the local test alert plus warm and process-cold routing for a real chat, including retained pending camera intake; see the [QA sweep](QA_SWEEP_2026-09-13.md) | Locked or normally terminated background delivery remains D26/D27 and requires a supported unmodified-Hermes push contract |
| D09 | Samsung queues, Steer and lost-ack recovery passed | Desktop-style text/file queues with filename review and removal; next-draft attachment preparation survives active responses and picker reconnection | Samsung 2.31.6 verified ordered drain and acknowledged Steer. Local Hermes proved attachment contents. The 2.31.9 transparent-proxy test dropped a successful acknowledgement, then reconnect proved exactly one server row and one matching submission while the uncertain queue item remained for explicit removal. See the [QA sweep](QA_SWEEP_2026-09-13.md) | The app deliberately does not remove an uncertain item automatically. The original outside-workspace QA018 failure remains unproven on the other deployment |
| D10 | Ordinary text actions passed; synchronized versions deferred | Edit/resend, Regenerate, Branch, Fork and existing parent-chat navigation. Unsupported version-group UI and requests are removed. See [answer versions](ANSWER_VERSIONS.md) | Emulator controls passed with exact scoped requests, retained unrelated draft, parent navigation and one-shot Fork. QA029 fixed repeated attachment-context expansion in 2.31.9; QA030 then passed focused and normal-build live image reopen with draft/context preservation. See the [QA sweep](QA_SWEEP_2026-09-13.md) | Explicit synchronized versions are not verified on unmodified Hermes |
| D11 | Live handling passed for `/btw`; cold recovery deferred | Existing live events display correlated side/background questions and results. Same-runtime reconnect retains already received cards. The 2.31 release adds transient `review.summary` notices. See [recovery](SIDE_TASK_RECOVERY.md) | Local Hermes `/btw` completed with its correlated `BTW_OK` result; fixture and widget coverage remains recorded in the QA sweep | Cold recovery is not available through a verified unmodified-Hermes snapshot; other live event variants depend on server availability |
| D12 | Common content, Mermaid and SVG implemented; live QA pending | Wide tables, selectable streamed/nested fenced code and copy/wrap controls; on-demand Mermaid/SVG previews with zoom and source access. See [diagram notes](DIAGRAM_PREVIEWS.md) | 2.23.0: 1,169 tests passed, four opt-in skips; analyzer clean; browser fixtures passed; signed Personal 21722 installed and launched | Other diagram formats retain source fallback; live device preview/zoom QA remains |
| D13 | Common media implemented; live QA pending | Zoomable images, hosted web page previews and downloaded audio/video playback with native controls. The 2.31 release adds direct Markdown file links through the existing output viewer. See [opening files](OPENING_OUTPUT_FILES.md) | 2.31.1: 1,288 tests pass/four skips; clean analysis; all four emulator scenarios pass; one current Markdown file passed live preview | Samsung codec/playback QA remains; unsupported files keep external-open/save-share fallback |
| D14 | Live tool detail, timing, todos and reasoning passed | Expandable live tools with args/results/server duration, revisioned server todos, live/historical reasoning | Real clarification details expanded, a completed live tool reported 211 s, server-provided loop reasoning displayed as Thought, and a real clarification-driven task advanced from Tasks 0/2 to Tasks 2/2 with the correct item names | Todos and reasoning remain bounded by fields the server exposes |
| D15 | Reopen fix implemented; reported live regression closed | Border fuse and endpoint dot; ready-event refresh after deferred agent construction, with stale-response protection | Live 2.31.1 immediately showed 57% on the affected existing chat with an empty composer and no prompt; see [fix notes](CONTEXT_REOPEN_FIX.md) | Other provider/server variants remain bounded by available context data |
| D16 | Paged large-chat fix implemented; path limits remain | Recent outputs first, Load older outputs, retained results and actionable retry; original scoped authenticated downloads retained. See [owner-reported fix](EXECUTION_FIND_AND_OUTPUTS.md) | Live 2.31.1 opened the formerly failing list and loaded an older batch without losing it | Two older generated references return HTTP 404; heuristic/stale relative paths remain unresolved rather than restored |
| D17 | Selected previews implemented; Samsung QA pending | Authenticated image/SVG/text and Markdown/source, hosted web pages, downloaded self-contained HTML, binary save/share, external media handoff, in-app audio/video and PDF pages with zoom; see [opening files](OPENING_OUTPUT_FILES.md), [PDF reading](PDF_READING.md) and [HTML scope](MARKDOWN_AND_WEB_PREVIEWS.md) | Live 2.31.1 opened one current repository README as formatted Markdown and returned correctly | Two older generated paths return HTTP 404. HTML remains limited to 1 MiB and self-contained content; Samsung media QA remains |
| D18 | Paged Find and result navigation implemented; live regression closed | Recent-first Find, Search older messages, retained results/retry and View in chat with highlighted nearby content; Back to latest, original ownership and stale-selection guards. See [Find notes](EXECUTION_FIND_AND_OUTPUTS.md) | Live 2.31.1 grew 121 matches to 132 while keeping the first result, kept View in chat above long text, opened nearby messages and returned to latest | Broader search terms and server histories remain subject to normal live use |
| D19 | Direct-open and cross-client read state passed | Paginated Unread only in Chats; Activity filters; successful explicit chat opens acknowledge server read state, with stale-response and manual-retry handling. See [read state](FILTERS_AND_PROJECTS.md) | QA004 regressions pass. The 2.31.9 two-client live test observed unread through client 2, opened it there, then observed read through client 1 | Unread has no server query filter, so older pages must be loaded |
| D20 | Native and live project lifecycle passed | Project create/rename/appearance/delete and membership. The release adds explicit repository-root discovery through stock `projects.discover_repos`, with manual absolute-path fallback | The final native scenario passed. The real Hermes test created a nonce-owned project, renamed it, changed appearance, independently verified persistence, deleted it, and verified exact owned cleanup | Other deployment variants remain subject to their server data and paths |
| D21 | Samsung text/file/image review and routing passed | Connection/profile/new-or-existing chat choice, draft staging, durable pending intake and acknowledgement/discard | Emulator merge/restart, Samsung text review/discard restart, and Samsung My Files share-sheet selection through Hermes Personal for text and PNG files passed. See the [QA sweep](QA_SWEEP_2026-09-13.md) | An interruption between draft save and intake acknowledgement can reoffer a share; no automatic sending |
| D22 | Samsung Camera, Photos and Files passed | Camera/Photos/Files feed existing draft preparation; camera retains its verified destination or offers explicit recovery | Saved/new-chat capture, expiry and process-removal recovery, Files selection and Photos selection through Gallery passed. Local Hermes proved image and text attachment contents, and QA030 passed normal-build image reopen without exposing encoded data while preserving the draft. See the [QA sweep](QA_SWEEP_2026-09-13.md) | The original outside-workspace QA018 failure remains specific to the other deployment |
| D23 | Live initial roster, Steer and Interrupt passed | Scoped subagent roster, live details and acknowledged Steer/Interrupt. See [subagent notes](SUBAGENT_SUPERVISION.md) | Normal 2.31.10 showed a Running child and Steer on first open without Refresh. Earlier live control checks acknowledged Steer and reached final Interrupted state | Active-only roster and transient tails remain; child-only Activity discovery retains the server limitation recorded under D05 |
| D24 | Goal and criteria controls passed live | Server goal/verification details, Pause/Resume/Unwait/Clear and criteria Add/Remove/Clear. See [session controls](SESSION_CONTROLS.md) | Local Hermes passed Pause/Resume, Goal Unwait with a real owned-process PID barrier, goal Clear, and criteria Add/Remove/Clear with exact retained/cleared counts. Unwait verified **Resume now**, barrier removal, and goal/process cleanup. The earlier busy Resume partial failure remains recorded | Goal contracts and gates remain read-only |
| D25 | Live process and default-loop controls passed; profile limit remains | Session heartbeat/loop state, supported controls and targeted process Stop/Dismiss | Process details, Stop and Dismiss passed. Default-profile loop Pause, Resume, separate automatic replies, durable reopen and Stop with one tick remaining passed on normal 2.31.10 after QA033. Read-only history more than five minutes after Stop still contained exactly two replies and no later automatic turn. See the [QA sweep](QA_SWEEP_2026-09-13.md) | QA031 limits non-default-profile control upstream |
| D26-D27 | Local alerts implemented; background push deferred | Local completion/input alerts and scoped notification taps. Optional receiver code is dormant; no supported sender/registration integration is configured | Notification client checks are included in the 2.30.1 baseline. See [setup and limits](BACKGROUND_NOTIFICATIONS.md) | Unmodified Hermes has no verified compatible sender/registration contract. Existing local alerts stay available |
| D28 | Diagnostics, session usage and custom headers implemented; live QA pending | Dashboard/provider checks, connection repair, server-recorded profile usage and secure proxy headers | 2.15.0: 1,124 tests passed, four opt-in skips; clean analyzer | Live proxy/provider QA remains; no local usage ledger |
| D29 | Profile editor passed live | Selected-profile description/SOUL editor with acknowledged and partial-save handling | The real editor saved nonce description/SOUL values, an independent gateway read both exact values, and cleanup restored and verified both originals | No global profile activation or broad admin |
| D30 | Versions, read-only update status and release links passed | Installed Android identity, this fork's changelog and release page; backend update eligibility, confirmation, progress and correlated per-host outcomes | Live UI showed backend 0.21.2 and eligibility 88 behind without running an update. Releases and Changelog opened their correct repository pages in Chrome and Close returned to Settings | TUI restart is deferred without an existing remote API. No actual backend update was performed |

The feature ledger in PRODUCT_PLAN.md remains the coverage checklist. Mark a feature Done only after all of its selected portions are delivered; Q10, Q03, C08 and notifications deliberately span multiple slices. R18 error clarity, B15 ownership and M08 server authority apply throughout.

Q05 discoverability, B03 OAuth, B16-B20 bots, broad K administration, section 11, M10 offline history and M11 local ranking remain excluded or deferred exactly as recorded in the product plan. M07, M12 and M13 remain future possibilities. M05 adds no separate work. M08 and S14 add no independent client-state feature.
