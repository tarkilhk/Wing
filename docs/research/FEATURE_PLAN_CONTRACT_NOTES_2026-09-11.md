# Feature plan contract notes, 2026-09-11

These notes answer the contract questions raised while selecting the Android feature plan. They supplement the [full comparison](../HERMES_DESKTOP_ANDROID_FEATURE_ANALYSIS.md), which remains the historical audit.

Android source inspected at `b8f1d981a272059076cefce179e2de9596dc9e06`. Desktop sources below are pinned to official Hermes commit `d15ed4445207dda418b984e8bda0f68f48b8c6f3`. This was a source check, not a test against the currently deployed gateway. The sparse Desktop checkout omitted backend modules; attempted retrieval of those pinned modules failed. Backend implementation details that could not be checked at that revision are identified below. No application code was changed.

## P08: reuse server project appearance and discovery

Yes, Desktop already reads and writes project appearance through Hermes. Android does not need a separate database of project colors or icons.

| Operation | Existing Desktop contract |
| --- | --- |
| Read declared projects | `projects.list`, with a profile |
| Read project grouping, discovered repositories and their appearance | `projects.tree`, with a profile and preview limit |
| Change a declared project's appearance | `projects.update`, with `id`, `color` and/or `icon`, scoped to the profile |
| Clear color or icon | Send an empty string. Desktop explicitly converts a UI `null` to `""`, because the backend treats omitted/null values as unchanged. |
| Adopt an automatically discovered repository | `projects.create`, using its label, repository root as a folder and primary path, and the chosen appearance |
| Scan remote repository roots | `projects.discover_repos`, with `scan: true` and a profile. The host scans its own filesystem. |

Desktop's `setProjectAppearance` updates an existing project, or creates a declared project when an automatic repository has no stored project row. Adoption changes its ID, so subsequent actions must use the returned/refreshed identity. These are existing client contract details, not proposed Android-only behavior. [Desktop project store][projects]

Android already parses `color` and `icon` in its project models and project tree responses. The implementation work is to show those values consistently and add optional editing/adoption through the existing gateway contract. Start by displaying server appearance. Confirm create/update support against the installed gateway before adding edits. [Android project model](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/models/hermes_project.dart#L42), [Android project tree](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/models/project_sessions_tree.dart#L118)

P08 is about appearance and adopting discovered repositories. If “status” means running/idle work, that belongs to C09/P06 and should likewise come from server session state; it is a separate field from project appearance.

## Q05, Q10, Q12 and R06: what slash support means today

The Android workspace already fetches the server-owned catalog, aliases and metadata through `commands.catalog`, gets arguments through `complete.slash`, and dispatches ordinary commands through `command.dispatch`. It falls back to `slash.exec` only after an explicit refusal saying dispatch does not own the command. There is no fixed client list that excludes newly installed skill commands. [Android command dispatch](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/services/profile_workspace_controller.dart#L1585), [existing slash support notes](../SLASH_COMMAND_SUPPORT.md)

“P1 discoverability” means a visible `/` or Commands entry beside the composer that opens the existing picker. It does not mean rebuilding command support. Currently the composer says “Message Hermes or type /”, and suggestions appear after the user types `/`. [Composer](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/screens/profile_workspace_screen.dart#L470), [suggestions](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/widgets/slash_command_suggestions.dart#L42)

| Command | Current Android behavior | Remaining work |
| --- | --- | --- |
| `/steer <message>` | Calls `session.steer` for the current runtime session. This local handler runs before the generic busy check. | Expose it as a visible one-off send action. |
| `/btw <message>` | Calls `prompt.btw` for the current runtime session, including during an active turn. | Give side questions and their results a clearer presentation. |
| `/bg <message>` and `/background <message>` | Call `prompt.background`, including during an active turn. | Make background work discoverable and link to its progress/results. |
| `/fork` and `/branch` | Use the phone's branching flow and currently reject branching while busy. | A long-press Fork action needs an explicit rule about which completed history it branches from. |
| `/yolo` | Has no dedicated Android handler. It enters generic command dispatch when idle, subject to catalog restrictions and server behavior; generic commands are rejected while busy. | Verify and implement session-scoped semantics. Generic slash access does not establish correct YOLO parity. |

The Send control changes from Stop back to Send when the draft begins with `/`, even while the chat is busy. Thus `/steer`, `/btw` and `/bg` are reachable during a run in the current UI. The earlier audit should not imply they are absent. [Send control](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/screens/profile_workspace_screen.dart#L536), [local command handlers](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/services/profile_workspace_controller.dart#L1836), [steering](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/services/profile_workspace_controller.dart#L1872)

The controller already handles `btw.complete` and `background.complete`; their existence supports improving presentation rather than replacing execution. [Completion handling](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/services/profile_workspace_controller.dart#L2045)

“All slash commands” needs a qualification. Terminal-only, messaging-only and host-microphone commands are deliberately blocked or explained using server metadata. Generic commands are blocked during a run even if another client provides a special active-run action. Command transport, active-run routing, returned-result handling and correct session scope are separate parts of support. [Availability restrictions](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/models/slash_command.dart#L73), [busy check](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/services/profile_workspace_controller.dart#L1650)

For YOLO specifically, current Desktop `/yolo` calls `config.set` with `key: "yolo"`, the live `session_id`, and `value: "1"` or `"0"`. Global YOLO is a separate operation using `scope: "global"`, affecting persistent approval configuration. Android should use the session-scoped operation for R06 and make its current state visible. Do not infer that a generic slash worker changes the active Android chat. [Desktop YOLO helper][yolo], [Desktop slash action][slash]

The requested long press on Enter/Send can offer Queue, Steer and Fork for that submission. Choosing an action must leave the saved/default send behavior alone. The existing button has no long-press menu. Queue availability and branching from an active conversation need a gateway contract check when implemented; current `/fork` expressly waits for the turn to finish.

## Q16: group models by the technical provider route

The current Android picker is a flat searchable list. Each model displays its provider slug as a subtitle. The controller already preserves that slug from each `model/options` provider group, so the requested expandable groups can use server identity directly. The earlier description of the Android picker as “grouped” was too generous. [Options loading](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/services/profile_workspace_controller.dart#L1458), [picker](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/widgets/chat_intelligence_picker.dart#L301)

Keep the pair of provider route and model ID intact. For example, a model reached through OpenCode must stay in that OpenCode route, even if its model ID contains another vendor's name. Desktop source explicitly distinguishes `openai-codex`, `claude-code` and `opencode-go`; its model options tests show a group with display name `OpenCode` and slug `opencode-go`. Use the server's current group name and identity, with a readable fallback for unknown providers. Do not hardcode a model-vendor taxonomy or infer account billing from a model name. [Desktop provider names][providers], [Desktop model group test][model-test]

If the server exposes multiple accounts separately, preserve those IDs too. The inspected Android parsing proves provider-route identity is present, but does not prove that the deployed options API distinguishes every separate credential account. That remains a contract question for implementation.

## T10: server data for the compact context indicator

Desktop's usage model includes `context_used`, `context_max`, `context_percent`, `context_estimated` and `context_source`. Its `session.context_breakdown` response includes those fields, `estimated_total`, categories and optional model identity. A thin “fuse” beside the model/composer can read these fields without calculating a separate phone-owned context estimate. [Desktop usage types][types]

Desktop requests `session.context_breakdown` when the visible session changes and after a turn ends. Its source explains that measured occupancy may be absent after resuming a session until another turn has run in that process; the backend can provide a read-only estimate from the prompt, tools and transcript. During a run, Desktop uses streamed usage rather than repeatedly requesting a breakdown. [Desktop context hook][context]

Show an unknown state when the gateway supplies no usable denominator. Mark an estimate as approximate in the details sheet, and reset the displayed value when changing sessions. Color should accompany a visual fill level and accessible label. Exact availability of these fields on the user's installed gateway has not been tested.

## M01/M08: server authority and temporary phone state

The user's refresh model is the right default. The phone does not need to keep the Hermes agent executing. It needs to reconnect, obtain current state and history, and display the result accurately. Android already reconnects, resumes each relevant server session and refreshes history. It hydrates `running`, `inflight.assistant`, `pending_approval` and `pending_clarify` from the resume response. [Reconnect and hydration](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/services/profile_workspace_controller.dart#L2173)

What remains beyond refreshing a transcript is current run state, requests awaiting input, and uncertainty when a send reaches the server but its acknowledgement is lost. The client must not resend the prompt automatically merely because it did not see a completion event. The current reconnect code already says no prompts were resent after recovery failure. This needs verification and modest hardening, not a second execution system on Android.

Server authority does not preclude temporary copies needed to draw the screen, track an in-flight network request or remember the currently open sheet. Those copies must be disposable and replaced by server reads. Draft/unsent text and staged files need durable local protection because they do not yet exist on the server. Connection credentials also need secure storage so the client can reconnect; they are connection setup, not a second task database.

Current local persistence exceeds the user's intended future boundary in places, including saved chat model overrides and pending-turn journals. Treat that as migration work to review before implementation, not a reason to copy existing behavior into the plan. Saved preferences that change conversation behavior should come from the backend. Any minimal request identity needed to resolve an ambiguous submission should remain transport bookkeeping rather than an authoritative local conversation record. [Saved model overrides](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/services/chat_model_override_store.dart), [pending journal](https://github.com/tarkilhk/hermes-android/blob/b8f1d981a272059076cefce179e2de9596dc9e06/lib/core/services/profile_workspace_controller.dart#L2241)

The inspected client contracts do not establish that every pending request or running session survives a backend process restart. Losing a phone connection and restarting the Hermes backend are different cases. Verify installed-server recovery behavior when working on M01/R features; do not promise durable backend execution based solely on the client's `resume` call.

[projects]: https://github.com/NousResearch/hermes-agent/blob/d15ed4445207dda418b984e8bda0f68f48b8c6f3/apps/desktop/src/store/projects.ts
[yolo]: https://github.com/NousResearch/hermes-agent/blob/d15ed4445207dda418b984e8bda0f68f48b8c6f3/apps/desktop/src/lib/yolo-session.ts
[slash]: https://github.com/NousResearch/hermes-agent/blob/d15ed4445207dda418b984e8bda0f68f48b8c6f3/apps/desktop/src/app/session/hooks/use-prompt-actions/slash.ts#L771
[providers]: https://github.com/NousResearch/hermes-agent/blob/d15ed4445207dda418b984e8bda0f68f48b8c6f3/apps/desktop/src/components/onboarding/providers.tsx
[model-test]: https://github.com/NousResearch/hermes-agent/blob/d15ed4445207dda418b984e8bda0f68f48b8c6f3/apps/desktop/src/app/shell/model-menu-panel.test.tsx#L564
[types]: https://github.com/NousResearch/hermes-agent/blob/d15ed4445207dda418b984e8bda0f68f48b8c6f3/apps/desktop/src/types/hermes.ts#L813
[context]: https://github.com/NousResearch/hermes-agent/blob/d15ed4445207dda418b984e8bda0f68f48b8c6f3/apps/desktop/src/app/shell/hooks/use-context-breakdown.ts
