# Hermes Android product plan

Owner-selected scope recorded on 2026-09-11. This is the working product plan for this fork. Maintain it as work proceeds over the coming days and weeks.

The initial research and scope decisions are recorded below. The app shell is deployed and feature implementation is underway; see the delivery sequence for current progress. A selected feature remains planned until its behavior is implemented and verified.

## Authority and references

- This plan records the owner's selections from the [Desktop/Android analysis](HERMES_DESKTOP_ANDROID_FEATURE_ANALYSIS.md). Feature IDs retain their meaning from that research.
- The research is an evidence snapshot and a menu of possibilities. Its original priorities and suggested architecture are not the approved backlog. This plan narrows and changes them.
- Earlier inherited roadmaps and UI specifications are historical. They must not add requirements or dictate the appearance of this fork.
- The owner does not require preservation of the old app's UI or unselected functionality. Remove or replace that code when relevant to selected work, while preserving user data and current selected behaviors. The owner subsequently authorized removal of obsolete UI as part of the app-shell work.
- The owner authorized continuing through the milestones, with regular progress reports and a commit/push after each milestone. Use cheaper agents for bounded work, keep implementations small, and reuse existing code. No backward compatibility is required. No calendar schedule or unattended automation has been created.

Supporting evidence is indexed in [docs/README.md](README.md), including all three source inventories and [follow-up contract notes](research/FEATURE_PLAN_CONTRACT_NOTES_2026-09-11.md).

## Product decisions

Owner correction, 2026-09-12: **No Hermes backend modifications.** This project
builds the Android client against existing Hermes APIs. Do not develop or deploy
Hermes patches, add a server sender, or build a restart supervisor to complete
a client feature. Earlier backend-patch deployment plans were an agent scope
error and are withdrawn. Missing capabilities remain deferred unless the
unmodified backend already supplies a usable contract. Test fixtures and rejected
patch experiments are not evidence of support in the installed backend.

1. Build a productive general Hermes client. Pure coding workflows are not the primary optimization target. Useful command/tool output still belongs in scope.
2. Hermes owns conversations, projects, status, configuration, appearance metadata where supported, and execution. Read current state from the server and write changes back there. Do not introduce a competing phone database of tasks or organization.
3. Persist unsent text and staged attachments on the phone so they survive interruption. The owner subsequently approved Desktop-style client-owned queues: queued follow-ups are unsent client work until submitted to Hermes. Reuse draft storage and the send path. Other temporary render/network state must remain disposable and refreshed. Connection credentials and device settings are separate from Hermes work state; see the storage boundary below.
4. Start with simple resume/refresh and honest network errors. Reliable background notifications are a committed later milestone, even if the first release ships without them. Server execution and delivery of a phone notification are different concerns.
5. Keep existing tap/Enter behavior. Alternative send actions must be one-shot choices and must not silently change the default.
6. Show the backend's actual technical provider route when choosing a model. Group by routes such as OpenCode, OpenAI subscription and Anthropic subscription, not merely by the company that trained the model.
7. Use a left hamburger drawer for the agreed destinations. Do not build permanent bottom navigation from the previous proposal.
8. Use the owner-selected [Studio design charter](DESIGN_SYSTEM.md) throughout, including saved connections and future settings. Apply its compact controls, paired light/dark themes and behavior-preservation rules to existing and new UI. Existing functionality is reusable code, not a requirement to retain old styling.

## Navigation and initial administration flow

The primary drawer has Chats and Activity, followed by Connections, App settings and Hermes administration below a divider. These secondary destinations are directly accessible without an extra More page. Projects remain a scope inside Chats.

| Entry | Initial flow |
| --- | --- |
| Chats | Current connection/profile, search, projects, pins and recents. Conversation actions expose archives and selected work filters. |
| Activity | Ongoing work across profiles, including running, queued and awaiting input where the server exposes those states. Open an item in its original host/profile/chat. Refresh from the server. |
| Conversation | Transcript and composer; compact model/provider/context display; per-chat Outputs and task details. Leaving a preview returns to this chat. |
| Connections | A redesigned connection list and add/edit/test flow using this fork's current visual language. |
| App settings | Theme/text size, simple notification controls, selected reading preferences, Android version/build and update information. |
| Hermes administration | A small, functional backend administration entry. Explicit connection/profile header, then the seed features below. Broader K features are later additions. |

The administration screen has the selected seed functions below. They remain deliberately small:

- Connection health and backend version, with Refresh and access to the connection repair flow. Restart/update belong to the selected B11 work when that contract is implemented, not to an invented local process manager.
- Selected profile details and SOUL/persona viewing/editing, covering B14 and B15.
- Current default model/provider information and capability readiness, initially read-only. Link to existing chat model selection; do not silently add a full provider credential editor or make per-chat choices change profile defaults.

Those were the initial K-adjacent functions. On 2026-09-14, broader mobile administration was selected: the [administration roadmap](ADMINISTRATION_ROADMAP.md) ranks A01–A56 and defines the next small slices, starting with profile default models, skills and tools. Cron, messaging, webhooks and Kanban remain outside this phase.

Settings writes must show their scope. For example, "Prestige / Work profile" identifies a profile setting; "Prestige / Entire backend" identifies a restart or update. A profile selector cannot make a server-wide operation profile-local.

The owner clarified B15: selecting or activating profile A changes only that client's active view. It must not switch another client to profile A or change a global active-profile setting. Each request carries the intended host/profile/session independently of other clients' selections. Editing actual server options changes them centrally, and every client reading those options sees the change. Device appearance and notification preferences remain specific to the installation. There is no requirement for phone-only overrides of server configuration.

## Work packages and progress

Changelog correction, 2026-09-12: keep `CHANGELOG.md` limited to added, changed
and fixed product features. Remove personal information, work logs, test counts,
deployment details and instructions from existing entries as well as new ones.
Keep version/date labels for recorded feature changes. Omit releases with no
independent user-facing change rather than inventing one. Verification belongs
in the separate technical docs.
The existing changelog has been rewritten accordingly in the 2.31 milestone.

Continue implementation, verification and regular commits/pushes when wireless
debugging is unavailable. Phone availability does not block emulator testing
or other selected client work.

The owner subsequently requested continuous work through the agreed roadmap,
without requiring a new "continue" message after each milestone, followed by
full emulator testing with direct UI interaction. Milestone commits are progress
points, not stopping points. Complete client work using the unmodified backend;
record unavailable capabilities without adding backend work to the roadmap.
Emulator fixtures verify Android behavior; they do not establish production
backend support or real Firebase delivery.

The approved [delivery sequence](DELIVERY_SEQUENCE.md) breaks these themes into small implementation slices, with priority order, acceptance outcomes and verification status.

Use these packages to avoid building the same requirement twice. Their order is a suggested dependency sequence, not a fixed schedule. The shell is tracked separately from the feature packages. Some underlying features already exist; Planned does not mean all code is missing.

| Package | Selected IDs | Intended outcome | Status |
| --- | --- | --- | --- |
| W00 App shell | Left drawer, B01 presentation, W09/W11 entry points, legacy UI retirement | Shared navigation and styling around existing behavior; read-only administration entry. No new backend features. See [shell delivery notes](APP_SHELL.md). | Done, deployed to the owner's phone as Personal 2.1.2 / 21452 on 2026-09-11 |
| W01 Find and resume work | C02, C03, C07, C08 P1, C09 ongoing only, T11, T12, R02, R03, M01, M02, M04 | Authoritative history/status, useful search and filters, simple refresh/recovery and cross-profile Activity. | Implemented. Live history/Find, cross-client read state, main-work Activity and draft recovery pass; unopened child-only activity remains limited by the stock server contract. |
| W02 Protect drafts and control submission | Q02, Q03, Q07, Q09, Q10, Q11, Q12, M03 | Unsent work survives interruption; correct, branch, steer and queue without changing default send behavior. | Drafts, Queue/Steer, Edit/Fork and live side questions implemented; synchronized answer versions and cold side-task recovery are deferred without existing server APIs |
| W03 Commands, model choice and context | Q16, T10, R06 | Correct session-scoped `/yolo`, real provider grouping with collapsible sections, minimal context indicator. Keep typing `/` as the command entry point. | D03/D04/D15 implemented. The reported existing-chat context regression passed live on 2.31.1; other provider/server combinations remain bounded by server data |
| W04 Projects | P03, P04, P06, P08 | Useful project creation/admin/context with server-owned metadata. | Implemented and verified against real Hermes: repository discovery/selection, owned project creation, rename, appearance changes, deletion and independent readback/cleanup pass. |
| W05 Read and use results | T03 common content, T04, T05, T06, T07, T08, T09, T14, F03, F04, F05 per-chat only, F06, F07, G07 | Read media and tool progress; open, download and use generated results without a general filesystem browser. | Implemented. Real-backend native PDF/image/SVG zoom, common audio/video controls, linked media and invalid-format recovery pass, alongside recorded large-chat Outputs and Find checks. Old server references returning HTTP 404 remain unresolved. |
| W06 Unblock and supervise work | R04, R05, R07, R08, R09, R10, R11, R12, R13, R14, R15, R18 | Answer requests and inspect/control active agent work through supported server contracts. | Implemented. Live clarification, sudo/secret cancellation and stock expiry, subagent controls, goals and default-profile background controls pass. Real manual approval Deny and Allow once also pass. Vault acceptance is blocked by the stock browser failing before a request is emitted. Cold sensitive recovery and non-default loop scope retain documented server limits. |
| W07 Notifications | R16, R17, S12, M01, M09 | Useful local notices and correct task opening. Firebase delivery is dropped. | Local controls, startup retry and tap routing implemented. Sparse alerts remain under investigation; OS permission works, but loaded-chat event coverage is limited. See the administration roadmap findings. |
| W08 Connections and operations | B01, B02, B04, B10, B11 all proposed, B14, B15, S01, S02 | Current-looking password setup and repair, understandable health/usage, scoped profile/admin actions and backend updates. | Diagnostics, profile editing, usage, custom access headers and one-host/selected-host updates implemented. Remote TUI restart is deferred because existing Hermes exposes no authenticated restart API |
| W09 App navigation and preferences | S08, S10, left drawer | Consistent navigation, version/build visibility and readable preferences. Server session restoration belongs to W01. | Navigation, preferences and version visibility implemented. Android/backend identity, Releases and Changelog links passed live checks. |
| W10 Phone capture | M06 plus Q03 | Share text, links, images or files into a reviewed draft; add camera/photo capture in the same flow. | Samsung Camera, Photos, Files, share review/routing and interruption/recovery checks pass. Local Hermes image/text contents were verified. Remote text contents and saved reopen also pass; automatic @file expansion retains a confirmed backend workspace restriction, matching Desktop. See the final real-backend acceptance record. |
| W11 Administration | Initial K-family seed, integrated with B11/B14/B15; broader scope selected 2026-09-14 | Grow the existing administration screen in ranked, small slices using existing Hermes APIs. | Initial description/SOUL, diagnostics, usage and update controls implemented. Broader scope and validation are tracked in the administration roadmap. |

When beginning a slice, record its package and precise IDs here, inspect the current app and deployed backend, and specify the observable change. When finishing, record the code/PR reference, relevant checks, remaining limits, and date. Use **In progress**, **Done**, **Blocked on server**, or **Deferred** as needed. Mark a slice done only when its UI and server behavior are complete; existing source or a mock alone is not completion evidence.

Do not infer that a selected existing feature needs a rewrite. C02 and several approval/history actions may require preservation, a focused improvement or verification rather than new implementation. Q05 needs no new work.

## Selected feature ledger

Rows record selected work and explicit decisions to discard or merge a proposal. Follow each row's decision rather than treating every ID as implementation work. Unlisted research features are not new work for this plan. Existing behaviors supporting selected workflows remain available until deliberately changed.

### Conversations

| ID | Selected scope and owner qualification |
| --- | --- |
| C02 | Paginated conversation/history browsing. Preserve working behavior and improve actual limits/usability as needed. |
| C03 | Conversation search, including older server history and useful result navigation. |
| C07 | Read/unread behavior sourced from Hermes, including consistency when reopening work or using another client. |
| C08 | Only the P1 task-state filters, such as Needs input, Running and Unread. Exclude cost/manual-order/PR filter expansion. |
| C09 | See all ongoing work across profiles. Merge with R03/M02 into Activity; no separate merged archive/search project. |

### Projects

| ID | Selected scope and owner qualification |
| --- | --- |
| P03 | Create a project and choose its host working folder through a phone-appropriate flow. The 2.31 release offers an explicit `projects.discover_repos` scan plus manual absolute-path entry; unit/widget and emulator checks pass; live server acceptance remains. |
| P04 | Rename and delete projects. Do not import unselected legacy project administration. |
| P06 | Clear selected project and destination for new work. Distinguish UI selection from server defaults. |
| P08 | Approved after the backend contract check. Read/write supported project icon/color metadata through Hermes; no phone-only appearance override database. Verify the deployed server supports the researched contract. Backend status is separate and remains server-owned too. |

### Composer, commands and models

| ID | Selected scope and owner qualification |
| --- | --- |
| Q02 | Persist drafts and staged attachments across navigation/restart. Merge with M03. |
| Q03 | Better file/image/link intake and draft feedback; reuse the same pipeline for M06. |
| Q05 | No new work. Typing `/` is the intended shortcut for the existing command picker. Discard the proposed discoverability button/toolbar change. Preserve the working catalog. |
| Q07 | Edit a prior user message and resend with clear history consequences. |
| Q09 | Preserve/improve regeneration and answer versions using server-owned relationships. 2.18.0 removes the phone-only index and offers Parent chat from backend metadata. Regenerate/Branch/Edit/Fork remain available. A synchronized answer carousel still needs an origin-row/relationship/order contract; see [relationship notes](SERVER_CHAT_RELATIONSHIPS.md). |
| Q10 | Existing steering should be made usable during a running turn. Candidate: long-press Send/Enter to choose Queue, Steer or Fork for this submission. Preserve ordinary tap/Enter behavior and never make the choice a new default. |
| Q11 | Queue follow-up prompts locally, following Desktop's client-owned composer queue. The owner explicitly approved this on 2026-09-11 after the source audit. Queue per chat, allow review/removal, and drain after the active turn finishes. Reuse draft storage and submission. An uncertain submission must not be silently retried. |
| Q12 | Important: side/background questions and their visible results/status. Commands already exist in part; improve the interaction and verify busy-turn submission rather than claiming this is entirely new. |
| Q16 | Collapsible model groups by the Hermes technical provider/account route, including OpenCode, OpenAI subscription and Anthropic subscription as examples. Preserve exact route IDs; do not group solely by model vendor or infer a route from the model name. |

The long-press proposal needs a small interaction specification when W02 starts. Queue means after the current work, Steer means correction to the current run, and Fork means a separate conversation with an explicit history boundary. Availability must reflect current state. For example, do not claim a busy chat can fork at an unsaved answer. Keep Stop usable. An ordinary accessible menu should expose the same alternatives so long press is not the only way to reach them.

The original source check found active-turn paths for `/steer`, `/btw`, `/bg` and `/background`. Typing a slash draft changes the busy composer button from Stop to Send. D04 subsequently added the dedicated current-session `/yolo` handler. D11 added correlated `/btw` cards and extends the same flow to `/bg` and `/background` in 2.25.0. Task recovery after reconnect remains a separate missing server contract. The [contract notes](research/FEATURE_PLAN_CONTRACT_NOTES_2026-09-11.md) preserve the original findings.

### Transcript and output presentation

| ID | Selected scope and owner qualification |
| --- | --- |
| T03 | P1 common content only: readable Markdown, code, tables and large content. A separate advanced math project is not selected here. |
| T04 | Readable diagrams and supported visual blocks with a useful fallback. On-demand Mermaid rendering is implemented in 2.19.0, with SVG blocks/files added in 2.23.0; other formats retain copyable source. See [diagram notes](DIAGRAM_PREVIEWS.md) for supported scope and verification. |
| T05 | Images and other media, not images alone. |
| T06 | Useful link/media previews and opening in the appropriate app/browser. The 2.31 release recognizes direct Markdown links to result files and routes them through the existing authenticated output viewer; unit/widget and emulator checks pass; live server acceptance remains. |
| T07 | Structured, expandable tool status and results. |
| T08 | Optional readable reasoning/time information where Hermes supplies it. |
| T09 | Server-provided todo/progress summary. |
| T10 | A very thin context-usage fuse integrated into an existing composer edge, with a mini dot at the current usage position. Owner screenshot feedback on 2026-09-12 accepts the message box top edge or model selector top edge; use the message box edge and remove the separate row. It changes color as context fills. Use server used/max values or a labelled server estimate; show unknown when absent. No large panel or decorative continuous animation. |
| T11 | Find within a conversation. |
| T12 | Stable reading position, older history and return/jump to latest. Do not treat a local scroll position as authoritative conversation state. |
| T14 | Distinguish system/control notices, agent deliveries and linked task references. The 2.31 release renders existing `review.summary` events as transient review notices; unit/widget and emulator checks pass; live server acceptance remains. |

### Running work and attention

| ID | Selected scope and owner qualification |
| --- | --- |
| R02 | Simple reconnect/resume and server refresh. Preserve uncertain-send protection without building a separate turn ledger. |
| R03 | Authoritative Activity across profiles, merged with C09/M02. |
| R04 | Allow once/reject, preserving request details and acknowledged outcome. |
| R05 | Other server-supported approval scopes and visible effective policy. |
| R06 | Confirmed fix required. Make `/yolo` work through the correct current-session contract and display the server's effective state, including during a running turn where supported. Do not change global defaults or assume generic dispatch works. |
| R07 | Structured clarification and multiple questions. |
| R08 | Supported sudo/password/environment-secret requests through dedicated responses. The 2.31 release labels their jump-to-latest state as **Input needed** while reading older history; unit/widget and emulator checks pass; live server acceptance remains. |
| R09 | Supported vault/login/verification-code requests, with the same 2.31 jump-label behavior. |
| R10 | Subagent roster and progress. |
| R11 | Subagent details/transcript and targeted steer/interrupt. |
| R12 | Goal status and pause/resume/clear controls. |
| R13 | Goal criteria and details/verification information. |
| R14 | Session heartbeat/loop state and controls. This remains selected even though the separate Cron/messaging/webhook section is deferred. |
| R15 | Background process status and controls. |
| R16 | Attention/completion notifications. Start with available local delivery; committed later push delivery covers the app being absent, as specified in M01/W07. |
| R17 | Correct task opening and simple notices/actions. Start with taps opening the task; inline reply/approval complexity is not required initially. |
| R18 | Clear cause and next action for errors: retry/reconnect, credentials, model/provider or server capability as appropriate. |

### Files and command output

| ID | Selected scope and owner qualification |
| --- | --- |
| F03 | Open and read the result file from a conversation. |
| F04 | Download a result from the backend to the phone. |
| F05 | P1 per-chat Outputs only. No global artifact library for now. |
| F06 | Common file previews/viewers such as image, PDF, Markdown and code. Formatted Markdown/source previews join image, PDF and code in 2.21.0; see [preview notes](MARKDOWN_AND_WEB_PREVIEWS.md). |
| F07 | Open an interactive HTML/web preview and return to the chat. Hosted web page previews are implemented in 2.21.0; 2.24.0 adds downloaded self-contained HTML up to 1 MiB, with source and Save or share. External-resource-dependent pages remain outside the embedded preview. See [web preview scope](MARKDOWN_AND_WEB_PREVIEWS.md). |
| G07 | Read command/tool output and relevant log details. No implied full terminal, Git or coding-client scope. |

### Connections and backend operations

| ID | Selected scope and owner qualification |
| --- | --- |
| B01 | Redesign saved connections and their management in this fork's current look and feel. The old screen is not a design reference. |
| B02 | Tested modern gateway authentication/connection flow. |
| B03 | Discarded. The owner uses the password authentication flow; no browser/OAuth sign-in work is selected. |
| B04 | Advanced proxy/header access where needed. |
| B10 | Repair a connection from an unavailable/error state. |
| B11 | All proposed operations, including triggering backend update. Show backend version/health/restart/update progress and results. Eligible multi-connection update support remains in selected scope, with a deliberate target list and per-host outcomes. Implement one-host behavior first. |
| B14 | Profile details and SOUL/persona editing. |
| B15 | Client-local active-profile selection. Selecting profile A in one client must not switch another client's active profile or mutate a global selection. Actual server-setting edits remain central and visible to every client using the affected scope. Requests must target the intended host/profile/session. |

B16, B17, B18, B19 and B20 are deferred. The owner wants profiles rather than a separate bot product model for now. This does not defer R10/R11 subagent supervision.

### App settings and operation

| ID | Selected scope and owner qualification |
| --- | --- |
| S01 | Useful connection/backend health and diagnostic details. |
| S02 | Server usage/cost information. Do not compute a competing authoritative account ledger locally. |
| S08 | Android client version/build, release/update information, and distinction from backend version. Include the identity/version of this fork, not the upstream app's release label. |
| S10 | Reachable theme/readability/text-size controls. |
| S12 | Simple notification enablement/categories and a test; no complex policy engine. |
| S14 | No standalone client restoration or extra preference project. On opening a session, display its latest server-owned history, run state and pending requests. This is existing R02/T12 work in W01. If restoring a last-read location or last-opened session across devices needs a missing server field, record that backend dependency; do not create durable local substitutes. |

### Mobile additions and deduplication

| ID | Owner decision | Canonical work |
| --- | --- | --- |
| M01 | Approved in two phases. First, server execution, auto-refresh on reopen/resume, manual Refresh and available local notifications. Later, reliable server-triggered background notifications even when Android has terminated the app normally. Push is committed roadmap work, although the initial release may ship without it. | R02/R16, W01/W07 |
| M02 | Accepted; same cross-profile attention/activity requirement already selected. | C09/R03 |
| M03 | Accepted; same persistent unsent-draft requirement already selected. | Q02 |
| M04 | Accepted, keep simple. Show disconnected/sending/accepted/uncertain as needed, preserve drafts, do not blindly resend. No elaborate offline outbox. | R02/Q02 |
| M05 | Not separately selected. F03/F04/F05 cover usable output access; do not silently broaden into full transcript sharing/export. | No separate work item |
| M06 | Accepted. Android Share or composer attachment/camera/photo choice creates a reviewable draft in an explicit destination; never send invisibly. | Q03/W10 |
| M07 | Future possibility. No near-term voice/dictation implementation from the previous recommendation. | Deferred |
| M08 | Server-authoritative state requirement replaces the proposed local handoff feature. No independent deep-link/cross-device feature project yet. Avoid durable phone-only chat relationships. | Applies to all packages, especially Q09 |
| M09 | Accepted, start simple: permission, completion/input controls and correct task opening; basic private preview if exposed. Quiet hours and elaborate rules are not initial work. | R16/R17/S12 |
| M10 | No offline conversation/result library. Temporary viewing or explicitly downloading a file is not a separate offline-history feature. | Excluded |
| M11 | No favorites/popularity feature or local ranking. If the server already supplies skill order, preserve it. Do not build a ranking store. | Excluded |
| M12 | Maybe later as a dedicated accessibility/tablet expansion. Selected S10/readability improvements and basic accessible controls still apply now. | Deferred expansion |
| M13 | Maybe later; no widget project now. | Deferred |

## Storage and recovery boundary

Hermes must remain the authority for submitted task and conversation data. Server-owned relationships include history, read/unread, project membership, answer-version relationships where supported, model/provider configuration, goals, status and results. The client may render cached values during a request, but it must not manufacture a success or preserve a conflicting local truth. The owner explicitly approved a client-owned queue matching Desktop: these entries remain unsent drafts until Hermes accepts each submission. A queue cannot continue draining while Android is not running; reopening refreshes server status before continuing.

The owner explicitly allows durable drafts/unsent messages, now including the client-owned composer queue. Staged attachments are part of that draft. Unsure submission is different from unsent: after a lost acknowledgement, reconcile with the server before retrying automatically. If the server cannot disambiguate, show that uncertainty and preserve the user's text.

Some local data is needed for the other selected features: saved connection addresses and securely stored credentials for B01, device appearance/notification settings for S10/S12, and transient navigation/render state, including this client's active profile under B15. These are device configuration and navigation, not replicated Hermes work. The owner's "only drafts locally" requirement is interpreted as prohibiting an independent durable work database. Confirm any broader persistence proposal before adding it. S14 adds no local restoration store. The server supplies wherever the session last stood; any missing server contract is a backend dependency. Client-local profile selection does not authorize a new durable local session history.

Current deviations to address as selected work reaches them:

- Obsolete phone-only answer-version links are removed in 2.18.0. Parent navigation uses server metadata; Q09's synchronized answer carousel remains a backend dependency.
- Chat model overrides were removed in the conversation-foundations delivery. Server session configuration is authoritative.
- Activity now discovers ongoing sessions from each profile on the server. Deployed-gateway coverage still needs live verification.
- Draft text and staged attachments now persist per connection/profile/chat. Q11 now reuses that storage for the approved client-owned text queue.
- Pending identity journaling exists. Keep only the minimal references needed to reconcile uncertain work; do not expand it into a shadow transcript or task database.

Server work can finish while Android is closed. Refresh on reopening retrieves the result but cannot deliver an alert before reopening. Local alerts depend on the app process and event connection. Activity discovery remains selected for finding work across profiles.

### W07 current scope — updated 2026-09-14

Keep local completion/input alerts, device controls and taps that open the correct server/profile/chat. **Firebase background delivery (D26/D27) is dropped**, because unmodified Hermes has no verified compatible sender/registration contract. It is not an unfinished implementation milestone. No backend changes are authorized.

Missing local alerts remain a defect to investigate. Some alerts arrive, and Android permission/channel checks passed. Source inspection shows limited coverage for chats loaded by the current app process; this is not proof of the cause of any particular missed alert. See [current findings and the next real-event check](ADMINISTRATION_ROADMAP.md#notification-findings). A test notification establishes native posting, not complete event coverage.

For M06, Android's [sharing contract](https://developer.android.com/develop/ui/compose/sharing/receive) provides the OS entry point. Proposed flow: Share from a browser/gallery/document app, choose Hermes, review the text/files, choose the connection/profile and new or existing conversation, then explicitly Send. An attachment menu inside chat can add Camera, Photos and Files to the same staging flow. This is a product flow to implement on the current Flutter/native bridge, not a request to switch UI frameworks.

## Explicitly outside the current scope

- Q05 command-discoverability UI, B03 browser/OAuth gateway sign-in, and a separate S14 client-side restoration/preferences project. Existing slash entry and server refresh remain part of the app.
- The full section 11: Cron authoring/management, messaging-channel administration, pairing, webhooks and Kanban. Session heartbeat/loop controls R14 remain selected.
- Bot Mode/canonical bot chats and group-bot features B16 through B20. Selected subagent supervision remains in scope.
- The separate candidates and desktop-only features excluded in the administration roadmap. Broader administration is now selected, in the ranked slices recorded there.
- Offline transcript library, local skill popularity/favorites, widgets, continuous voice and a full tablet layout effort.
- General remote filesystem browsing, a full terminal, Git/PR administration, and a global artifact library. G07 and per-chat output access remain selected.
- Inherited app functionality solely to preserve compatibility with the old UI. Reuse code only when it helps selected outcomes.
- Research items not selected above. Omission does not authorize deleting user data or removing existing behavior without examining dependencies.

## Acceptance baseline for each slice

- Verify backend support before presenting a capability as available. Prefer a short explanation to silently routing a command into an unrelated session or profile.
- Reads and writes retain their actual host/profile/chat owner after navigation, refresh and late responses.
- With two clients connected, switching one from profile A to B leaves the other's selected profile unchanged. Editing a server option is visible to both clients when they read that option's scope.
- A task started elsewhere can be discovered when the relevant server endpoint supports it; show bounded/incomplete results honestly.
- Drafts and attachments survive interruption without duplicate submission or silent destination changes.
- Show refresh/error/pending states clearly. Notifications supplement server state rather than becoming the only record of an input request or result.
- Outputs resolve on the correct host and open on Android with their real contents. A printed backend path is not a completed download.
- A backend restart/update reports progress, interruption/failure and reconnect outcome. Showing "requested" is not the same as a verified new version.
- Update this plan and the current-behavior docs when a slice actually ships. Keep historical research dated.

## Decision log

| Date | Decision/change | Delivery evidence |
| --- | --- | --- |
| 2026-09-11 | Recorded owner selections and exclusions, left drawer, minimal local work state, simple refresh/notifications, technical-provider model grouping, optional one-shot long-press submit actions, context fuse, redesigned connections, backend update support and a small later administration screen. | Documentation only. No app features implemented in this update. |
| 2026-09-11 | Follow-up approved P08, declined Q05 discoverability work and B03 OAuth, confirmed the R06 fix, merged S14 into server refresh, and committed later background notifications under M01/W07. B15 clarified: active-profile selection affects only that client; actual server-option edits are central and affect all clients using those options. | Documentation only. No application code or push infrastructure changed. |
| 2026-09-11 | Selected Firebase Cloud Messaging as the transport for the later M01/W07 background-notification milestone. | Superseded: Firebase delivery was dropped, reconfirmed on 2026-09-14. Existing local alerts remain selected. |
| 2026-09-11 | Approved continuing through the delivery sequence using cheaper agents, regular progress reports and milestone commits/pushes. Prefer the smallest implementation and reuse; no backward compatibility required. | Shell `87ddb44`; conversation foundations `1d00123`, built and installed as Personal 2.1.3 / 21462. |
| 2026-09-11 | After learning Desktop's composer queue is client-owned, explicitly approved implementing the same approach on Android and following Desktop's design in general. This supersedes Q11's prior server-queue prerequisite. | D09 was in progress at this decision point and is now implemented. Local queue entries are unsent drafts; submitted execution/history remain on Hermes. |
| 2026-09-12 | Delivered cross-profile Activity discovery, sensitive-response forms, notification controls and client-owned Queue/Steer. | Personal 2.1.4 / 21472 installed in place; 921 tests passed, four opt-in skips; analyzer clean. See [delivery notes](SUPERVISION_AND_QUEUES.md) for remaining live checks. |
| 2026-09-12 | Delivered saved-message Edit/Fork, identifiable side questions, phone table/code reading, tapped image previews and the context fuse. | Personal 2.1.5 / 21482 installed in place; 944 tests passed, four opt-in skips; analyzer clean. [Delivery notes](CONVERSATION_ACTIONS_AND_READING.md) retain incomplete diagram/media/version/background portions. |
| 2026-09-12 | Delivered execution details, Find in chat and initial per-chat Outputs with authenticated previews and save/share. Adopted minor version bumps for features, patch bumps for fixes and major bumps for breaking changes; maintain the changelog and commit/push each milestone to main. | Personal 2.2.0 / 21492 installed and launched; 970 tests passed, four opt-in skips; analyzer and release-identity checks clean. [Delivery notes](EXECUTION_FIND_AND_OUTPUTS.md) retain live gateway and richer-media limitations. |
| 2026-09-12 | Delivered paginated Unread only, Activity status filters and server project actions. Applied screenshot feedback to move the context fuse onto the message box top edge with a mini endpoint dot and no extra row. | Personal 2.3.0 / 21502 installed and launched; 984 tests passed, four opt-in skips; analyzer clean. See [filters and projects](FILTERS_AND_PROJECTS.md) and the [changelog](../CHANGELOG.md). |
| 2026-09-12 | Delivered share review with explicit destinations, safe merge into existing drafts, exact pending acknowledgement and Photos/Files selection. | Personal 2.4.0 / 21512 installed and launched; 995 tests passed, four opt-in skips; analyzer clean. [Sharing notes](SHARING_AND_CAPTURE.md) retain Camera/intake interruption limits. The D15 loading bug noted at this point was fixed in 2.5.0. |

## Active owner feedback

Personal 2.30.1 / 21842 was the preceding verified baseline. It removed the
unsupported answer-version requests and preserves live sensitive forms and
side-task cards across same-runtime reconnects when optional fields are absent.
All 53 focused checks and 1,257 full-suite tests pass, with four opt-in skips;
analysis is clean. Detailed verification remains in the linked technical records,
not the product changelog.

The 2.31 release added four client-only improvements through existing Hermes
data and APIs: discovered repository roots during project creation, direct
Markdown file links, transient `review.summary` notices, and an **Input needed**
jump label for sensitive requests while reading older history. The 2.31.1
correction adds safe actionable file HTTP errors, transient Retry, saved
proxied-auth forwarding, stable recent-first Find loading and action-first long
results. All 1,288 tests pass with four opt-in skips, analysis is clean, and all
four emulator scenarios pass. Personal 2.31.1 / 21862 is installed and launches.
See the [live phone record](LIVE_PHONE_ACCEPTANCE_2026-09-12.md) and
[emulator record](EMULATOR_ROADMAP_VERIFICATION.md) for evidence and limits.

No Hermes patches were deployed. The 2.28-2.30 server-contract experiments are
rejected history, not open deployment work. Background push, synchronized answer
versions, cold sensitive/side-task recovery and remote TUI restart remain deferred
because unmodified Hermes does not expose the required capabilities.

Live 2.31.1 closes the reported existing-chat context, large-chat Outputs and
older Find regressions, and verifies one current Markdown file. Two older
generated references return HTTP 404 and were not restored. Draft survival,
provider grouping and a basic prompt round trip also passed live checks. The
temporary test chat was deleted. Project creation, Activity with real work,
cross-client read state, queue/upload behavior, sensitive response delivery and
Samsung-specific media and capture behavior remain open.
The 2026-09-13 Samsung follow-up verified the local test alert and app-opening
tap, Camera/Photos/Files cancellation, and incoming text recovery and discard
across real Hermes process restarts. Successful capture, media intake and
chat-specific alert routing still need live checks.
The [delivery sequence](DELIVERY_SEQUENCE.md) and technical feature notes record
the precise limits and completed verification.

## Questions resolved now and details left for implementation

The [contract notes](research/FEATURE_PLAN_CONTRACT_NOTES_2026-09-11.md) preserve source evidence for project metadata, slash command routing and provider/context data. P08 is approved. Q05 needs no extra entry point and B03 is discarded. The fuse concept is sufficiently clear to record without a mockup now.

B03 concerned gateway browser/identity-provider sign-in, separate from model-provider subscriptions. The owner confirmed password authentication, so this proposal is removed from planned work.

B15 is settled. Profile selection is navigation local to each client. Client 1 selecting Work must not switch client 2 away from Personal. Changing Work's persona edits Work centrally, so any client reading Work sees the new persona. A backend update affects the whole backend even if reached from Work. Keep selections independent, route requests to their actual scope, and display shared server configuration faithfully.

S14 originally bundled return-to-last-chat and transcript display preferences too broadly. It adds no separate feature now. Reopening a session loads what Hermes knows about that session, including where its execution stood and any pending interaction. Any cross-device remembered reading location must also come from Hermes if supported. Temporary scroll/render state is disposable and does not become a local session record.

The Fork boundary, active-turn submission and `/yolo` target routing have been implemented through existing contracts. Unmodified Hermes has no verified synchronized answer-version relationship API, so that portion of Q09 is deferred. Before expanding local persistence, check it against the explicit storage boundary.

### App shell implementation, 2026-09-11

This is a historical shell milestone. The owner requested the shell before new roadmap features, then requested phone deployment. The slice replaced primary navigation, exposed existing device settings, added an administration entry using discovered profile metadata, and removed unreachable legacy screens/widgets. At that milestone Activity covered only controller-observed chats; D05 later added server discovery across profiles. See [delivery notes](APP_SHELL.md) for its checks and limits.

Delivery completed as Personal `2.1.2+2145`, ARM64 code `21452`, installed in place on the owner's phone. Static analysis and 873 tests passed, with four environment-dependent skips. The signed APK passed identity/certificate checks. Phone verification used installed version and process metadata; a live screenshot was blocked by automatic approval review. The shell implementation remains separate from the earlier research commit `acd8c40`.
