# Wing design system

Studio is the app's selected design language. This charter records the current shared tokens, component rules and behavior-preservation contract, including the September 2026 portrait, theme and menu updates.

This charter owns the appearance of new and existing UI. [Feature guides](FEATURES.md) and current behavior describe functionality. Written owner decisions take precedence over generated images.

## Owner decisions

- Use Studio's restrained sans typography, grouped lists and small rectangular controls.
- Keep search at the top of Chats. Put New chat at the bottom for reach on large phones.
- Preserve the refined Activity and tool-call presentation and interaction. Restyle cautiously without rebuilding its information structure.
- Use the compact context ring beside the model selector, confirmed by the owner after comparing it with the fuse. Do not allocate a row to token-count text or retain the fuse alongside it.
- Keep familiar model/reasoning selection and Queue, Steer and Fork flows.
- Design dark mode fully and use coherent accents throughout.
- Administration opens directly on Profile without tabs. A pharmacy-cross action in the top bar opens the dedicated Health route. Keep the selected connection visible and classify each operation by its actual ownership. See the [administration handoff](design/2026-09-14-administration-handoff.md) for navigation and unsupported memory/MCP writes.
- Provider accounts and keys belong to the selected profile, including `default`. The global menu has a larger portrait aligned with Wing and a low, borderless split footer: saved connection icon, name and status LED on the left; server version and conditional update icon on the right. Connection identity opens details; server version opens Versions & updates. Client identity stays in App settings; upstream update checks and the circular-arrows indicator apply only to the server. Manage profiles is its own pill after the last profile in the horizontally scrolling selector. Follow the [administration ownership contract](design/2026-09-14-administration-handoff.md) for credential-source distinctions and pending editor corrections.

## Chats Target, 19 September 2026

The chat list follows these rules.
This supersedes earlier Chats-specific instructions for profile chips, a separate
Projects section, Recents, separators, and the header's duplicated filters.
Use the compact Status / Profile / Project row, five colored status dots and
a continuous grouped list with three-chat previews. The owner’s 20 September
update uses “Show more” to reveal ten additional chats in that group per tap;
the action disappears when every matching chat in the group is visible.
The owner’s 20 September
refinement places Group by, Sort by and Show details directly in the header
overflow menu, each opening an anchored menu at the ellipsis. There is no
permanent grouping/sorting row or bottom sheet. Choices apply immediately and
are remembered per connection on the device. Show details stays open for
multiple selections, with Done reachable while the choices scroll. Tokens, when
shown, include group totals. Preserve the conversation, Activity, tool
presentation and composer; the list has its own dot component.
The approved token refinement truncates titles to keep counts and updated ages
in aligned columns on the same row. Use compact counts at existing precision
and tabular numerals without a Tokens / Age legend. At enlarged text sizes,
let titles and metadata wrap; keep full titles and labelled counts accessible.
Groups of chats without an assigned project use the profile name in angle brackets
and italics, with spaces inside the brackets (for example, `< default >`)
and an outlined mixed-shapes icon (`category_outlined`) in headings and Project
filter choices. Do not prefix these labels with Home.
The owner's subsequent profile-bar refinement places a fixed viewport beside
the connection label, with horizontally scrolling profile-initial squares.
Pack short profile lists against the viewport's right edge beside the menu,
leaving breathing room after the connection identity.
Use desktop's deterministic profile hues and a neutral default; selected fill
indicates the shared list filter. Tap to select one profile, tap again to clear.
The subsequent density refinement matches desktop's 20 dp squares, 4 dp gaps,
3 dp corners, 9 sp colored initials and soft profile-color fills. The bar's
24-by-48 dp targets are an owner-requested exception to standard control width.
The owner also requested a 1.5 dp outside border around selected profile squares
for visibility, using their profile color (neutral for default). This is an
explicit exception to the selection-border rule; square size and spacing stay fixed.

Working chat rows show desktop's travelling rectangular arc: a flush 1.25 dp
border, 160-degree gradient with a fading tail, and a 2.23-second linear loop.
Use Studio control corners and neutral theme colors, retaining the colored status
dot. The border overlays the existing row without changing its size or gestures;
only its paint layer animates. Reduced motion freezes the arc. Needs-input and
idle rows have no arc. This reflects live working status, not recent REST activity.
Verified against upstream main `80154cf3cfee087fbc72bf1dd58f9906b8a2f66e`
on 20 September 2026: desktop `src/app/chat/sidebar/session-row.tsx`,
`src/store/session-dot-state.ts`, and `src/styles.css` (`arc-border arc-row`).
Stock `tui_gateway/methods_session.py` still exposes `session.active_list`;
the client uses its existing activity projection with no protocol changes.

## App and notification identity

The official app name and wordmark are **Wing**, with a capital **W** and
lowercase **ing**, in artwork, prose, Android labels and accessibility text.
The owner requested this capitalization across the design language on
17 September 2026, superseding the lowercase wordmark selected on
15 September. Keep the compact feather accents and lowercase technical
identifiers, including `com.tarkilhk.wing` and the Dart package `wing`. See the
[Wing identity specification](design/2026-09-15-wing-identity.md) for the board,
wordmark rules, decorative feather system and application identity decisions.

The owner's final 17 September selection uses a modest capital W with slimmer
diagonals to match the optical weight of ing. Follow the approved README banner;
uppercase must not make the initial heavier, fatter or disproportionately tall.
In the Flutter wordmark, use the same stroke width for W and ing. The owner
rejected the thinner W in the welcome screenshots; the banner remains selected.
After reviewing the drawer, the owner requested a lighter overall weight: use
32-unit strokes for every letter, reduced from 36, with the same geometry and size.

The owner selected the Playful portrait: a winking woman with a simple dark bob,
mint headphones and a messenger wing on the earcup. Keep the navy, cream and
mint identity colors. The white messenger wing is the notification/status-bar
mark for chat alerts and the optional Android themed launcher mark. The permanent
monitoring notification uses the same full-size wing with a softer circular-arrow
ring behind it, centered on the wing's visual center. This 20 September decision
supersedes the earlier caduceus. Replies use the plain wing; input and stopped-work
variants add small type cues. The normal launcher keeps the portrait. Brand colors do not replace
Studio's screen tokens or the user's selected accent family.

See the [icon assets and production record](design/2026-09-14-app-icon.md) for
source assets, approved placements and the export command.
Preserve the wink, simple hair masses and wing when making future exports.

On 15 September 2026, the owner approved all five
[in-app Playful placements](design/2026-09-14-app-icon.md#in-app-placements): 48 dp in
the drawer header and installed-app version card, 104 dp above the empty chat
greeting, 112 dp on first connection, and 24 dp replacing the assistant's H
badge. Use the shared `PlayfulPortrait` widget and original palette in both
themes. Treat the portrait as decorative beside existing labels. Preserve
the author row and message width. The empty greeting yields to messages,
history loading or errors, and active work; keep it scrollable on short screens.

First connection uses a 144 dp circular portrait,
the scalable title-case Wing wordmark and the tagline, with Connect your agent,
Restore configuration and an offline Connection guide. This supersedes the
112 dp first-connection placement above. Keep the existing drawer reachable.
Use Studio screen and action tokens in both themes; preserve text scaling and
scrolling on short screens. Native launch uses the portrait on brand navy,
without a timed hold, extra loading route or a network-readiness requirement.

Add and Edit connection use a
full-screen address, sign-in, check and review flow. Use the 112 dp circular
Playful portrait and the wordmark's original pointed feather cluster on the
address and verified screens; hide the address artwork while the keyboard is
open. Keep the approved 144 dp welcome screen unchanged. Custom authentication,
separate chat routing and access headers live under Sign in / Custom setup.
Use the active Studio accent, clearly labelled stage statuses, scrollable growing
forms, specific failures and an explicit final save. No network check sends a
chat message or establishes model readiness.

The owner selected a portrait-led menu header on 17 September 2026: 96 dp artwork
beside the shared Wing wordmark, adapting to 64 dp at enlarged text to retain
horizontal alignment. Use the approved drawn lettering and feather accent in
the header, rather than a plain text substitute.
This supersedes the earlier 48 dp drawer placement. Keep only the app identity
in this header. The low footer uses icon → connection name → LED on the left and
version → update indicator on the right.

Offer equally
weighted Hermes Cloud and Use an address routes. Both destination screens use the
same 112 dp portrait, feather cluster, “Where’s your Hermes?” heading and bottom
Continue action. Preserve the complete address journey. Cloud instance selection
uses Studio tint and joins the existing checks and explicit final save.

## Layout and controls

The owner-approved menu groups Chats and Activity, then Hermes instances and
App settings, then Hermes administration, Hermes health and Hermes analytics.
Use quiet separators before Hermes instances and Hermes administration, without
section headings. Hermes instances is the saved-server collection; use Add
instance, Edit instance and Instance name in its setup flow. Removing an instance
removes its saved connection, not the deployed server. Hermes analytics opens the
existing usage dashboard directly, with a profile-only scope picker. Health ends
with its Server and Profile checks and has no Usage row.

Keep hamburger navigation and projects scoped inside Chats. Use compact connection/profile text below the page title. Search stays below this scope. Projects, pins and recents use full-width rows, grouped where helpful, with thin separators.

On 15 September 2026, the owner requested compact row menus attached to their
ellipsis controls. Project rows use one ellipsis with New chat, Rename,
Appearance and Delete; remove the ambiguous compose pencil. Project, chat and
saved-draft actions use a shared opaque popup with an 8 dp border radius, thin
border and subtle elevation. Anchor it below the invoking button with a 4 dp
gap and keep it within the viewport. Preserve long-press access, 48 dp action
targets, keyboard navigation, outside-tap dismissal and deletion confirmations.

The Chats header menu uses the same anchored panel treatment. Align icons and
labels, show independent filters with compact trailing switches, and separate
filters, navigation/creation and Refresh. Hide chat filters and duplicate New
project in All projects, where the floating button already creates a project.
Hide Archived chats inside the archive. Keep New chat on the floating button
and item-specific mutations in the row menus. Filter selection dismisses the
menu and applies to the list; preserve existing scope, persistence and paging.

On 15 September 2026, the owner replaced the full-width New chat shelf with a 56 dp floating button at the bottom right. Use the outlined pen-on-a-square icon (`WingIcons.newChat`, Lucide `square-pen`), with a New chat tooltip and accessibility label. The owner's 18 September selection supersedes the earlier plus and standalone pencil: every New chat action, including project menus and the Android New Quick Chat shortcut, uses this same icon. Use the shared action corners and accent colors, subtle elevation and 16 dp edge spacing above the system gesture area. Extend the chat list through the space released by the shelf, with enough trailing scroll padding to move the final row above the button. Respect keyboard and system insets. The same browser control retains its New project action and plus icon in All projects.

Use 16 dp page gutters, a 4 dp spacing grid, 6 dp action corners, 8 dp group/composer corners, 24-28 sp page titles, 16 sp body text and 12-13 sp metadata. Primary action paint can be about 40 dp high inside a minimum 48 dp touch area. Text scaling must allow rows and controls to grow. Keep established compact activity density; improve touch areas without adding visible card padding.

On 18 September 2026, the owner split the shared screen header into two targets:
the connection icon and LED open the existing status/retry sheet, while the name
opens an anchored dropdown matching its displayed scope: connection-only headers
(including Chats, conversations and Activity) offer connections only; headers
showing a profile offer connections and profiles, except Analytics, whose dropdown
offers only profiles following the owner’s 19 September refinement. Each target is at least 48 dp.
Use the standard Studio popup surface and selected background tint. This applies
to Chats, conversations, Activity, Administration, Health and administration
drill-downs.

Use Android's Roboto sans typography explicitly across component themes and monospace for code. Keep the existing compact Activity geometry. Its tabs, badges and disclosures are deliberate density exceptions to the general control dimensions.

## Selection controls

Selection uses the selected background tint throughout Wing. Chips, segmented buttons, dropdown entries, navigation rows, model/provider pickers, project appearance controls, and single/multiple-choice rows keep their original labels and artwork when selected. Do not add ticks, radio dots or selected-only borders to indicate the selected option; use the background tint. This rule concerns option selection, including dropdown lists. It does not restrict tick icons in other visual components, such as task completion, test results, status indicators, actions or Markdown task content.

Use `StudioRadioTile` inside `RadioGroup` for one choice and `StudioSelectionTile` for multiple choices. Their whole row is the target and selected surface. Preserve checked/selected accessibility semantics, single versus multiple selection behavior, and keyboard navigation. Use `CompactSwitch` for independent on/off settings; its thumb position still expresses on/off. Status and action icons should communicate their meaning, supported by status text or accessibility labels. Authored message and document content remains intact. MCP test results use a green tick for passed tests and a red cross for failed tests, distinguishing the explicit test result from the connection-status LED.

Use `CompactSwitch` for standalone switches and `CompactSwitchListTile` for settings where the whole row toggles. The Material switch face draws at 75% size, about 39 × 24 dp, within an unscaled 48 × 48 dp touch and accessibility target. Keep native keyboard, focus and drag behavior. Do not shrink the hit target with the artwork.

Use 16 dp outer page gutters, a 12 dp label-to-control gap, and one shared trailing control column. Do not add another page gutter to rows already inside an inset form. Simple switch rows have a 48 dp minimum height and 4 dp vertical padding; two-line capability disclosures have a 56 dp minimum. Radio-choice rows use a 48 dp minimum and 8 dp vertical padding. These are minimums, not fixed heights. Let wrapped labels, descriptions and enlarged text increase the row height. Keep 16 sp labels and 13 sp muted metadata, with no extra blank line between them.

Selected controls use the active accent family in both themes. Off and disabled controls use neutral track and thumb colors. Expose selection to assistive technology even though its visual indication is the background alone. Retain visible keyboard focus and disable writes while a save is pending. Keep the last confirmed value after a failed save.

A standalone switch needs a label identifying the affected setting. A setting row exposes one merged label, state and toggle action. Where tapping the row opens details, as in Skills and tools or MCP connectors, retain separate disclosure and switch actions. Toggling must not open details, and opening details must not change the setting.

Check light and dark themes, selected and disabled states, long names at 320 dp width and 200% text, touch-target edges, keyboard activation, and screen-reader state before shipping control changes.

The selection audit covers App settings and composer preferences; Activity filters and tabs; drawer and profile navigation; project colors and icons; administration provider filters, tool models and tab navigation; chat intelligence and profile-default models; shared-draft destinations; clarification choices; backup restore mode; backend-update targets; and Markdown task markers. Chips disable `showCheckmark`, segmented buttons disable `showSelectedIcon`, menu entries use selected fills, and row choices use the shared selection tiles. `test/studio_selection_test.dart` checks these selection controls, selection semantics, keyboard interaction, task state and layout; it must not ban status or action icons across the app.

## Conversation preservation

Network continuity uses a shared LED on the left of each server identity, quiet
bounded recovery, retained conversation state, and immediate notification
navigation with cached reading where available. Use these rules for
connection cues, accessible status targets and recovery journeys.

Keep the existing Activity disclosure, tool counts, Tools/Tasks/Agents/Work tabs when available, thinking disclosure, nested tool rows, guide line, selection, expansion state, scroll anchoring and copyable details. Do not add extra outer cards, timeline dots or permanent rows simply because the raster mockup draws them. Use the current component geometry as the baseline and apply color/type/border refinements. Approvals and questions remain outside collapsible tool results.

Task status icons follow upstream desktop: a green filled-circle tick for
completed, a spinner for in progress, a muted dashed circle for pending and a
muted slashed circle for cancelled. Keep the existing 16 dp icon slot and use
Wing's semantic success and muted colors in both themes. The native spinner
becomes a static arc with reduced motion; each state has an accessibility label.
This is task status, not option selection. Verified against upstream Hermes
commit `603007ead347608c81bf95fd7b40c3fff9e4bed5`, desktop
`apps/desktop/src/app/chat/composer/status-stack/status-row.tsx`, on 19 September
2026. The change uses the existing client task states and requires no API changes.

Keep activity status and queued-message controls above the composer. Preserve the two-row composer: draft first, then attachment/capture controls, the compact model/reasoning selector and Send/Stop. Preserve existing voice states and attachment options.

The activity summary occupies no space while idle, after completion or after
cancellation. Keep notices for ongoing work, active subagents, input requests,
loading, recovery and errors. Both this summary and the connection notice below
the header expand/fade in and collapse/fade out using the shared 200 ms motion.
Update visible status text in place; omit transitions when reduced motion is
enabled. Neither notice reserves an empty row. Brief connection interruptions
retain the existing two-second grace period before showing a notice.

The model/reasoning selector opens Intelligence. Model selection retains search and collapsible groups by actual technical provider route. Selecting a model returns to Intelligence; Apply confirms the selection for this chat. Keep existing busy/loading/disabled rules and full route identifiers in the picker.

Model catalog choices use the shared chooser in Chat, profile defaults, helper and fallback settings, scheduled tasks, and image/video tool settings. Search stays above the list and opens matching provider groups. The selected row is tinted, and provider plus model form its identity. Refresh keeps the pending choice and search text; a saved choice missing from the current catalog remains visible with an availability note. Automatic helper routing and a scheduled task's Profile default are separate named choices. Each editor has one labelled action: Chat Apply, profile Save default, helper Set helper model, fallback Add/Save fallback, tool Use model, or task Use in task. Task Save performs the server write for the entire task. A failed save keeps the pending choice visible. The catalog filter policy stays specific to each setting. Speech model IDs remain editable fields because the server does not expose a speech model catalog through this route.

Preserve the current Send/Steer/Queue/Stop and Enter behavior. Preserve the message-actions entry points present in the implementation baseline, including long-press. Do not restore controls removed by later approved UX work. Fork, Steer and Queue remain one-shot choices with current eligibility rules, never persistent composer modes. Preserve queued-message review, edit, delete and pause/resume behavior. Do not show unavailable actions as usable in a running chat.

The later owner-approved [held-slide composer actions](COMPOSER_ACTION_GESTURE.md) supersede the earlier busy-button interaction. Preserve the resting arrow, held-action animation, vertical selector, cancellation and accessibility behavior, and device default-action preference. Its existing geometry is an explicit exception to the general control-corner tokens. Preserve the Markdown scrollbar gutters and subtle thumb styling added alongside this work.

## Context indicator, selected ring

The owner selected the ring after reviewing the tradeoff. It keeps context usage localized beside the model selector and leaves the composer border clear. The fuse uses less literal space, but the ring separates capacity from task progress more clearly.

Use a 16-18 dp ring with a thin muted full track and a thicker accent arc proportional to actual occupancy. Keep the center empty in the normal known state. Avoid glow, rotation and continuous animation. Tap opens compact usage details with used/max, percentage and estimate qualification. Preserve an accessible usage description. The ring needs an independent accessible touch target and must not intercept model selection or shrink Send/Stop targets. Check narrow phones and long model names before fixing the exact geometry.

Keep current warning thresholds unless separately changed: warning at 65%, danger at 85%. For unknown occupancy, show a neutral broken track without a usage arc and label details and accessibility state as unknown, never 0%. The percentage remains server-derived. Do not display the retired fuse alongside the ring.

## Light and dark tokens

On 15 September 2026, the owner approved refining the default around Playful
and expressed a preference for teal. Teal replaces the displayed Mint option,
with a deep teal light accent, richer teal dark accent, navy-charcoal dark
surfaces and a subtly warm light canvas. Keep the stored `mint` value so saved
choices carry over. Glacier uses a cooler blue, `#285F9B` in light mode and
`#ABC9FF` in dark mode, to distinguish it from Teal. Iris, Coral and Gold
retain their accent colors.
The portrait keeps its original navy, cream and mint artwork.


| Role | Light | Dark |
| --- | --- | --- |
| Canvas | `#F7F7F4` | `#101B24` |
| Panel / sheet / menu | `#FFFFFF` | `#192934` |
| Primary text | `#1B2D36` | `#EBF1F2` |
| Secondary text | `#586970` | `#ADBDC4` |
| Accent | `#126D70` | `#65C7BC` |
| Text on accent | `#FFFFFF` | `#102C32` |
| Border / divider | `#D6E0E1` | `#344C58` |
| Selected tint | `#E2F1EE` | `#20454A` |

Dark uses charcoal with a restrained navy undertone, elevated opaque panels and readable secondary text. Avoid washed-out disabled text, translucent stacked cards and saturated page backgrounds. Menus, sheets, keyboard-adjacent chrome, previews and system bars must receive the same theme treatment.

The owner found the initial dark teal too pale and approved deepening it to
`#65C7BC` in 2.36.12. Keep the existing light accent and navy-charcoal surfaces.

Calculated sRGB contrast for these exact token pairs: light body/canvas 13.26:1, light secondary/canvas 5.33:1, light button text/accent 6.09:1, dark body/canvas 15.28:1, dark secondary/panel 7.71:1 and dark button text/accent 7.32:1. These calculations cover those pairs only, not generated-image pixels, every state or a rendered app.

Use the chosen accent for primary actions, links, selected controls, model icon, switches and focus outlines. Stable project colors stay tied to existing project metadata. Keep Teal, Iris, Glacier, Coral and Gold as coherent paired light/dark accent families, with darker foreground accents in light mode and lighter foreground accents in dark mode. User accent choice must not recolor warning/error semantics or rewrite project identity.

Pressed actions use a modest tonal shift, selected rows use the shared background tint, keyboard focus uses a clear outline, and disabled controls use neutral surfaces with readable labels. Loading states keep their label and control width. Errors use a distinct semantic color plus icon and text; empty states use plain explanations and one relevant action. Validate these states in the rendered app. No accessibility claim is made from images alone.

Use `StudioSelect` for select-only form menus, `StudioActionLabel` for actions
that can become pending, and `StudioError` (or `AdminNotice.error`) for failures.
Keep uncertain observations distinct from confirmed failures. Device preference
editors retain a confirmed value and disable writes until persistence finishes;
a failed write must not become the displayed value when the editor is reopened.
Native preview chrome receives the active Studio palette from Flutter. Authored
HTML, diagrams, images and video retain their content-specific appearance.

## Administration refinement, 17 September 2026

Administration opens on the profile overview without ownership tabs. The top-bar
pharmacy cross opens Health; version access stays in the global menu. Profile uses
a small identity brief, two purpose-based groups and observed-value rows. Quiet metadata
supports stronger destination titles; exception states retain their semantic colors.
Administration and Chats share the same directly tappable profile chips; do not
add a separate Change action or administration-only profile picker. Keep search
and the profile brief within the shared 16 dp page gutters.
Group profile choices and the purpose/description in one compact panel, with a
direct Identity edit or Describe this agent action. Keep configuration in the
rows below and setup/access exceptions on distinct semantic status lines.
Providers use comparable rows with disclosure to account detail, and capabilities
open to capabilities grouped by setup need and enablement; installed skills and
secondary management remain accessible. Health leads with retained findings,
observation times and explicit check coverage; reviewing output does not rerun a
diagnostic. Identity is a full-screen editor; settings show dirty counts, sparse-save
feedback and deliberate field conflict resolution. Percent diagrams describe
configuration and usage bars describe reported costs, never inferred activity.

The owner-approved 18 September Health revision replaces the combined verdict
with Server and Profile groups on the standalone Hermes health destination.
Server rows own Doctor, audit and Logs. The owner-approved 19 September update
removes the runtime-profile label. The Server refresh icon is labelled
Run all diagnostics and shows the same progress spinner as Profile while running.
It starts both diagnostics directly and disables repeat starts until both have
known completion. Doctor and audit details use a top-bar play action to rerun,
with automatic result polling and no bottom rerun button. Profile
uses the shared header for profile selection, a refresh icon beside its heading,
four stable observation rows. Analytics has its own drawer destination. The refresh icon explicitly checks the
selected profile and shows progress while the check runs.
Only actual issues carry warning/error emphasis. Healthy Tool setup, Connectors and
Scheduled tasks rows use green success icons, with no chevron or tap action.
Non-healthy rows retain detail navigation and recovery links; unknown checks use
neutral icons.
Unknown checks are local to their row. Do not invalidate configuration after a
fixed five-minute timer or imply successful inference from configuration.
Detail pages use the same gutters, grouped rows and quiet timestamps, with
specific recovery links to the owning editors. The owner-approved 19 September
correction removes the Model & provider detail screen and places Model access
status directly in Health's Profile group. The row is passive: label, credential
result and subordinate model/provider. Its key icon uses the
success green only after credentials are confirmed. It has no chevron, row tap,
model picker, or routine management link. Profile refresh owns checking; a problem
alone reveals Fix access, Review access, Retry or Review connection as appropriate.
Keep these actions compact and preserve the selected profile when entering its
existing recovery editor. Use the compact What’s checked? information action below
the group for the four plain-language explanations and their limits.
Show concrete counts: enabled tool groups and setup gaps, passed/failed/incomplete
connector checks, and listed tasks with reported errors. Empty inventories are
explicit. Model access success says Access is set up; it does not imply a test reply.
Each Server and Profile heading owns one check time. Use Last checked after a
completed section refresh, Checking… during work, and Check incomplete when a
result could not be established. Findings are completed checks, not incomplete
checks. Remove timestamps from overview rows; a single diagnostic rerun must not
advance the Server section’s shared completion time. Older dates include their date.
Name any different resolved model/provider without validating the selected route.
Health retains server results and separate profile checks across navigation and app
restarts. Opening it reuses results for 24 hours; expired completed diagnostics
and expired profile checks refresh automatically. Missing server results trigger an initial diagnostic run. Model selection stays in Administration.

Growing select-only values, page titles and large-text field labels must remain
readable at 320 dp/200%. Keep 48 dp controls and keyboard-safe editor actions.
Transient changed-value emphasis respects reduced motion. Failed saves reveal their
explanation while preserving the draft.

## Verification

Use [Testing](TESTING.md) for render entry points. Review actual widgets with real fonts and native controls; generated design boards are not acceptance evidence.

1. Composer under real constraints: keyboard open, multiline drafts, long model names, attachments, voice capture, queued-message editing and narrow screens. Preserve existing actions while checking room for the ring.
2. Drawer and connection/profile switching: clear active destination and scope, with consistent selection and accent treatment.
3. Dense settings and administration: apply Studio to forms, disclosures, toggles and primary/secondary/destructive actions without wasting vertical space. Include Connections and its repair flow.
4. Attention and recovery states: distinguish approvals, questions, reconnecting, uncertain submission, failure, loading and empty results. Keep the action needed to continue visible.
5. Reading and output details: long Markdown, code, tables, file rows and previews should share readable typography and accents. Preserve existing Activity/tool geometry and behavior.

Use light/dark pairs and enlarged-text examples in verification. Inspect drawer/scope switching, repair/attention states, reading/output details and composer states in the rendered UI. A generated larger-text study does not substitute for layout verification.

Audit every screen, dialog, sheet, menu, form and custom control for legacy styling. Standard widgets must inherit Studio component themes; custom decorations must consume the shared tokens. Keep intentional geometry exceptions for the refined activity/tool presentation and content-specific previews. Record the audit and validation evidence with the implementation. Backend contracts, persistence, state transitions, shortcuts and eligibility rules remain unchanged unless the owner approves a specific behavior change.
