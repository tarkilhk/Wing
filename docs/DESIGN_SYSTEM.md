# Wing design system

Studio is the app's selected design language. This charter records the current shared tokens, component rules and behavior-preservation contract, including the September 2026 portrait, theme and menu updates.

The [product plan](PRODUCT_PLAN.md) owns functionality. This document owns the appearance of all new and existing UI. Written owner decisions take precedence over generated images. Existing behavior remains the reference for interactions. Earlier Folio and Instrument proposals are unselected.

## Owner decisions

- Use Studio's restrained sans typography, grouped lists and small rectangular controls.
- Keep search at the top of Chats. Put New chat at the bottom for reach on large phones.
- Preserve the refined Activity and tool-call presentation and interaction. Restyle cautiously without rebuilding its information structure.
- Use the compact context ring beside the model selector, confirmed by the owner after comparing it with the fuse. Do not allocate a row to token-count text or retain the fuse alongside it.
- Keep familiar model/reasoning selection and Queue, Steer and Fork flows.
- Design dark mode fully and use coherent accents throughout.
- Administration uses Profile / Health. Keep the selected connection visible and classify each operation by its actual ownership. See the [administration handoff](design/2026-09-14-administration-handoff.md) for navigation and unsupported memory/MCP writes.
- Provider accounts and keys belong to the selected profile, including `default`. The global menu shows a non-interactive Client version row and a Server version row that opens Versions & updates. Client identity is local only; upstream update checks and the circular-arrows indicator apply only to the server. Manage profiles sits beside the Profile selector. Follow the [administration ownership contract](design/2026-09-14-administration-handoff.md) for credential-source distinctions and pending editor corrections.

## App and notification identity

The app is **Wing** in prose, Android labels and accessibility text. The
approved wordmark reads **wing** in lowercase. The owner selected the compact
feather-accent board on 15 September 2026. See the
[Wing identity specification](design/2026-09-15-wing-identity.md) for the board,
wordmark rules, decorative feather system and application identity decisions.

The owner selected the Playful portrait: a winking woman with a simple dark bob,
mint headphones and a messenger wing on the earcup. Keep the navy, cream and
mint identity colors. The white messenger wing is the notification/status-bar
mark for chat alerts and the optional Android themed launcher mark. The permanent
connection notification uses Hermes' caduceus in white, in its own notification
group. The owner's 16 September 2026 direction is to base this mark on Hermes'
recognizable winged staff and two intertwined snakes. The normal launcher uses
the portrait. These brand colors do not replace Studio's screen tokens or the
user's selected accent family.

The owner approved the final caduceus and wing pairing on 16 September 2026.
The [notification identity board](design/2026-09-15-wing-identity.md#notification-identity-board)
records both exact app vectors and their permanent-connection/chat roles.

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

The owner approved the [Wing arrival screens](design/2026-09-15-wing-arrival.md)
on 15 September 2026. First connection now uses a 144 dp circular portrait,
the scalable lowercase wordmark and the tagline, with Connect your agent,
Restore configuration and an offline Connection guide. This supersedes the
112 dp first-connection placement above. Keep the existing drawer reachable.
Use Studio screen and action tokens in both themes; preserve text scaling and
scrolling on short screens. Native launch uses the portrait on brand navy,
without a timed hold, extra loading route or a network-readiness requirement.

On 16 September 2026, the owner approved implementing the
[connection journey](design/2026-09-16-connection-journey.md), with fewer visible
options and more approved identity artwork. Add and Edit connection now use a
full-screen address, sign-in, check and review flow. Use the 112 dp circular
Playful portrait and the wordmark's original pointed feather cluster on the
address and verified screens; hide the address artwork while the keyboard is
open. Keep the approved 144 dp welcome screen unchanged. Custom authentication,
separate chat routing and access headers live under Sign in / Custom setup.
Use the active Studio accent, tick-free stage statuses, scrollable growing
forms, specific failures and an explicit final save. No network check sends a
chat message or establishes model readiness.

## Layout and controls

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

On 15 September 2026, the owner replaced the full-width New chat shelf with a 56 dp floating button at the bottom right. Show only a plus, with a New chat tooltip and accessibility label. Use the shared action corners and accent colors, subtle elevation and 16 dp edge spacing above the system gesture area. Extend the chat list through the space released by the shelf, with enough trailing scroll padding to move the final row above the button. Respect keyboard and system insets. The same browser control retains its New project action in All projects.

Use 16 dp page gutters, a 4 dp spacing grid, 6 dp action corners, 8 dp group/composer corners, 24-28 sp page titles, 16 sp body text and 12-13 sp metadata. Primary action paint can be about 40 dp high inside a minimum 48 dp touch area. Text scaling must allow rows and controls to grow. Keep established compact activity density; improve touch areas without adding visible card padding.

Use Android's Roboto sans typography explicitly across component themes and monospace for code. Keep the existing compact Activity geometry. Its tabs, badges and disclosures are deliberate density exceptions to the general control dimensions.

## Selection controls

Selection uses the selected background tint throughout Wing. Chips, segmented buttons, dropdown entries, navigation rows, model/provider pickers, project appearance controls, and single/multiple-choice rows keep their original labels and artwork when selected. Do not draw ticks, checkmarks, radio dots, or selected-only borders over these options. This owner decision of 16 September 2026 supersedes the earlier visual selection markers.

Use `StudioRadioTile` inside `RadioGroup` for one choice and `StudioSelectionTile` for multiple choices. Their whole row is the target and selected surface. Preserve checked/selected accessibility semantics, single versus multiple selection behavior, and keyboard navigation. Use `CompactSwitch` for independent on/off settings; its thumb position still expresses on/off. App-authored status and action icons also use tick-free symbols, with status text or accessibility labels retaining their meaning. Authored message and document content remains intact.

Use `CompactSwitch` for standalone switches and `CompactSwitchListTile` for settings where the whole row toggles. The Material switch face draws at 75% size, about 39 × 24 dp, within an unscaled 48 × 48 dp touch and accessibility target. Keep native keyboard, focus and drag behavior. Do not shrink the hit target with the artwork.

Use 16 dp outer page gutters, a 12 dp label-to-control gap, and one shared trailing control column. Do not add another page gutter to rows already inside an inset form. Simple switch rows have a 48 dp minimum height and 4 dp vertical padding; two-line capability disclosures have a 56 dp minimum. Radio-choice rows use a 48 dp minimum and 8 dp vertical padding. These are minimums, not fixed heights. Let wrapped labels, descriptions and enlarged text increase the row height. Keep 16 sp labels and 13 sp muted metadata, with no extra blank line between them.

Selected controls use the active accent family in both themes. Off and disabled controls use neutral track and thumb colors. Expose selection to assistive technology even though its visual indication is the background alone. Retain visible keyboard focus and disable writes while a save is pending. Keep the last confirmed value after a failed save.

A standalone switch needs a label identifying the affected setting. A setting row exposes one merged label, state and toggle action. Where tapping the row opens details, as in Skills and tools or MCP connectors, retain separate disclosure and switch actions. Toggling must not open details, and opening details must not change the setting.

Check light and dark themes, selected and disabled states, long names at 320 dp width and 200% text, touch-target edges, keyboard activation, and screen-reader state before shipping control changes.

The selection audit covers App settings and composer preferences; Activity filters and tabs; drawer and profile navigation; project colors and icons; administration provider filters, tool models and tab navigation; chat intelligence and profile-default models; shared-draft destinations; clarification choices; backup restore mode; backend-update targets; and Markdown task markers. Chips disable `showCheckmark`, segmented buttons disable `showSelectedIcon`, menu entries use selected fills, and row choices use the shared selection tiles. Markdown uses `StudioTaskMarker` for filled/empty task boxes. Status glyphs for completion, readiness and connected providers use flags, dots and links with their existing labels. `test/studio_selection_test.dart` guards app-owned tick icons and automatic control markers and exercises interaction and layout.

## Conversation preservation

The owner approved the [network continuity behavior](design/2026-09-16-network-continuity.md)
on 16 September 2026: a shared LED on the left of each server identity, quiet
bounded recovery, retained conversation state, and immediate notification
navigation with cached reading where available. Use that specification for
connection cues, accessible status targets and the two recovery journeys.

Keep the existing Activity disclosure, tool counts, Tools/Tasks/Agents/Work tabs when available, thinking disclosure, nested tool rows, guide line, selection, expansion state, scroll anchoring and copyable details. Do not add extra outer cards, timeline dots or permanent rows simply because the raster mockup draws them. Use the current component geometry as the baseline and apply color/type/border refinements. Approvals and questions remain outside collapsible tool results.

Keep activity status and queued-message controls above the composer. Preserve the two-row composer: draft first, then attachment/capture controls, the compact model/reasoning selector and Send/Stop. Preserve existing voice states and attachment options.

The model/reasoning selector opens Intelligence. Model selection retains search and collapsible groups by actual technical provider route. Selecting a model returns to Intelligence; Apply confirms the selection for this chat. Keep existing busy/loading/disabled rules and full route identifiers in the picker.

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

Profile / Health is the administration structure; version access lives in the global menu. Profile uses a small
identity brief, two purpose-based groups and observed-value rows. Quiet metadata
supports stronger destination titles; exception states retain their semantic colors.
Administration and Chats share the same directly tappable profile chips; do not
add a separate Change action or administration-only profile picker. Keep search
and the ownership tabs separated by 16 dp, with matching 16 dp page gutters.
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

Growing select-only values, page titles and large-text field labels must remain
readable at 320 dp/200%. Keep 48 dp controls and keyboard-safe editor actions.
Transient changed-value emphasis respects reduced motion. Failed saves reveal their
explanation while preserving the draft. The accepted requirements and evidence are
in [Plan 003](../plans/003-administration-experience.md).

## Verification

Use [Testing](TESTING.md) for render entry points. Review actual widgets with real fonts and native controls; generated design boards are not acceptance evidence.

1. Composer under real constraints: keyboard open, multiline drafts, long model names, attachments, voice capture, queued-message editing and narrow screens. Preserve existing actions while checking room for the ring.
2. Drawer and connection/profile switching: clear active destination and scope, with consistent selection and accent treatment.
3. Dense settings and administration: apply Studio to forms, disclosures, toggles and primary/secondary/destructive actions without wasting vertical space. Include Connections and its repair flow.
4. Attention and recovery states: distinguish approvals, questions, reconnecting, uncertain submission, failure, loading and empty results. Keep the action needed to continue visible.
5. Reading and output details: long Markdown, code, tables, file rows and previews should share readable typography and accents. Preserve existing Activity/tool geometry and behavior.

Use light/dark pairs and enlarged-text examples in verification. Inspect drawer/scope switching, repair/attention states, reading/output details and composer states in the rendered UI. A generated larger-text study does not substitute for layout verification.

Audit every screen, dialog, sheet, menu, form and custom control for legacy styling. Standard widgets must inherit Studio component themes; custom decorations must consume the shared tokens. Keep intentional geometry exceptions for the refined activity/tool presentation and content-specific previews. Record the audit and validation evidence with the implementation. Backend contracts, persistence, state transitions, shortcuts and eligibility rules remain unchanged unless the owner approves a specific behavior change.
