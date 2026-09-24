# Product scope

This is the owner's selected scope for Wing. [Features](FEATURES.md) describes the current app; [known limitations](KNOWN_LIMITATIONS.md) records incomplete behavior. Scope decisions were made on 11–14 September 2026. Earlier research and delivery journals are available in Git history.

## Product boundaries

Build a general Hermes client for working from a phone. Use existing authenticated Hermes APIs. A missing backend contract is a dependency, not permission to patch or deploy the backend.

Hermes owns submitted conversations, execution, projects, read state, model configuration and supported relationships. The phone stores unsent drafts, staged attachments and follow-up queues, plus connection credentials and device preferences. It must not maintain a competing durable transcript or task database.

Selecting a profile changes this client's view. Every request retains its actual connection/profile/chat owner; switching profiles must not switch another client. Editing a server setting changes that setting centrally for every client using its scope.

Use the drawer and the [Studio design system](DESIGN_SYSTEM.md). Reuse working behavior without restoring the retired navigation or adding legacy transport compatibility. Models are grouped by technical provider route, preserving the route's exact identity.

## Selected work

These IDs preserve the original scope references. They describe outcomes, not instructions to rebuild features already present.

| Area | Selected IDs | Scope and current boundary |
| --- | --- | --- |
| Find and resume work | C02, C03, C07, C08, C09; R02, R03; T11, T12; M01–M04 | Paginated chats/history, search, server read state, task filters, cross-profile Activity and simple reconnect. Activity cannot discover every child-only task with the current server response. |
| Projects | P03, P04, P06, P08 | Create with discovered or explicit host folder, rename/delete, clear destination and server-owned appearance. No phone-only metadata database. |
| Drafts and submission | Q02, Q03, Q07, Q09–Q12; M03, M06 | Persistent text/files, reviewed Android intake, Edit/Regenerate/Branch/Fork, Steer, editable local queues and live side questions. Synchronized answer alternatives and cold side-task recovery require server support. |
| Commands, models and context | Q16, R06, T10 | Existing slash entry, current-session YOLO, provider-grouped models and a server-fed context ring beside the model selector. The ring supersedes the earlier composer-edge fuse. |
| Reading and outputs | T03–T09, T14; F03–F07; G07 | Common Markdown/code/tables, supported diagrams and media, tool/reasoning/todo disclosures, per-chat output discovery, authenticated viewing and explicit download/share. |
| Supervision | R04, R05, R07–R15, R18 | Supported approval scopes, clarification, sensitive forms, subagents, goals, heartbeat/loop and process controls, with actionable errors. Backend gaps remain visible. |
| Notifications | R16, R17, S12, M09 | Foreground-service monitoring, local completion/input alerts, device and battery controls, and correctly scoped taps. No Firebase or server sender is required. |
| Connections and operations | B01, B02, B04, B10, B11, B14, B15; S01, S02 | Address and Hermes Cloud connection setup, repair, custom headers, diagnostics, usage, profile editing and deliberate one-host or selected-host updates. Remote TUI restart lacks a supported API. |
| Device preferences | S08, S10 | Installed app identity/version, update links, theme, text size and reading preferences. |
| Administration | A01–A45, A48–A49, A56 as qualified in the [administration roadmap](ADMINISTRATION_ROADMAP.md) | Profile, Server, Health and scheduled tasks, with explicit account/configuration ownership. Mixed P1/P2 items do not make every advanced operation an immediate commitment. |

Queue entries are unsent local work, matching Desktop's composer queue. Drain them only while the client is running and connected, after refreshing server status. Pause on stop, failure or an uncertain acknowledgement. Do not silently replay a potentially accepted prompt. The normal-send process-death gap is tracked in issue #3, linked from the limitations guide.

The busy composer defaults to Steer; the device setting can choose Queue or Stop. Holding and sliding selects a one-time alternative. Idle chats and slash drafts use Send. See [composer actions](COMPOSER_ACTION_GESTURE.md).

## Excluded or deferred

| Decision | Boundary |
| --- | --- |
| Q05, S14 | No extra slash-discoverability toolbar or separate client restoration project. Hermes Cloud sign-in and address setup are available; model-provider sign-in is a separate administration feature. |
| B16–B20; A46–A52 | Bot/group-chat, messaging, pairing, webhooks and Kanban administration remain separate candidates. Scheduled tasks, session loops/heartbeats and subagents are available. |
| M05, M08 | No separate full transcript export or cross-device handoff database. Use per-chat outputs and server-owned relationships. |
| M07, M12, M13 | No new continuous-voice, dedicated tablet expansion or widget project. Existing dictation, readable layouts and accessible controls remain supported. |
| M10, M11 | No offline conversation library or locally ranked skill favorites/popularity store. |
| Desktop-only work | No general remote filesystem browser, full terminal, Git/PR administration, global artifact library or local backend installer. Advanced math and other unselected research ideas are not implied. |
| Missing contracts | Shared answer alternatives, cold side-task recovery and remote TUI restart remain deferred. Pending sensitive forms can resume when Hermes supplies them. Firebase delivery is dropped. |

## Acceptance

Verify backend support before presenting an operation as available. Fixture tests establish client behavior; live acceptance must record the backend revision and actual result.

Reads, writes and late responses must retain their captured owner across two profiles and two connections. Preserve newer draft text/files during asynchronous work. An update request, upload receipt or process exit is not proof that the requested final result succeeded.

Use [Testing](TESTING.md) and the [release checklist](CODE_QUALITY_CHECKLIST.md). Update current guides when behavior changes. Keep the changelog about product changes, with version/date labels; omit personal deployment journals, test counts and releases with no independent user-facing change.
