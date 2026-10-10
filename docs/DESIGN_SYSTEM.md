# Wing design system

Studio is the app's selected design language. This charter records the current shared tokens, component rules and behavior-preservation contract, including the September 2026 portrait, theme and menu updates.

This charter owns the appearance of new and existing UI. [Feature guides](FEATURES.md) and current behavior describe functionality. Written owner decisions take precedence over generated images.

## Owner decisions

- Use Studio's restrained sans typography, grouped lists and small rectangular controls.
- Keep search at the top of Chats. Put New chat at the bottom for reach on large phones. While a saved profile needs repair, put its notices and profile choices in the list scroll area below search and filters so the full repair action remains reachable at 320 dp/200% text. Preserve the ordinary fixed progress and retry presentation once a profile is admitted. `test/profile_selection_repair_view_test.dart` exercises direct choice reachability, 48 dp targets, held saves and failed-save recovery in both themes and text sizes; rendered reachability needs behavioral verification.
- Activity information follows [USER-VALUE-FIRST](#user-value-first-activity): curate the requested intent, reported achievement and useful payloads within Studio framing.
- Activity details follow the [accepted activity family](#accepted-activity-detail-family). Extend its shared components and verify the family together.
- Use the compact context ring beside the model selector, confirmed by the owner after comparing it with the fuse. Do not allocate a row to token-count text or retain the fuse alongside it. The owner's 7 October refinement selects option A: show the percentage inside a 32 dp ring (up to 40 dp at enlarged text), in a 48 dp target, and open a 320 dp anchored popover above it. Center the digits and percent sign together using Roboto's cap-height baseline on the ring's canvas. Keep used/max tokens, percentage full, a 6 dp composition bar, aligned estimated category counts and supplied compression count compact. The bar represents category estimates; it never replaces measured occupancy. At enlarged text, put each category count below its full-width label and scroll the panel when needed. Preserve composer focus/keyboard, outside-tap dismissal and keyboard access; a chat change retires its open panel. Unknown occupancy uses a centered dash and broken neutral ring. The design exploration and owner selection are archived on local branch `prototype/context-window-studio` at `c655aa4`, under `plans/prototypes/context-window-studio`. Do not repeat the model or introduce a large duplicate gauge/account-limit card.
- Keep familiar model/reasoning selection and Queue/Steer flows. Fork belongs to the selected answer, never the composer.
- Canonical bot conversations stay in Chats. Replace the generic Bot Chat heading
  with the bot's name in the existing title position. Conversation replies omit
  repeated author names and avatars; bot identity stays in chat chrome. Keep
  project controls in the context row and preserve Back to the Bots roster.
  Ordinary conversations retain their titles.
- Design dark mode fully and use coherent accents throughout.
- Administration opens directly on Profile without tabs. A pharmacy-cross action in the top bar opens the dedicated Health route. Keep the selected connection visible and classify each operation by its actual ownership. See the [administration handoff](design/2026-09-14-administration-handoff.md) for navigation and unsupported memory/MCP writes.
- Provider accounts and keys belong to the selected profile, including `default`. The global menu has a larger portrait aligned with Wing and a low, borderless split footer: saved connection icon, name and status LED on the left; server version and conditional update icon on the right. Connection identity opens details; server version opens Versions & updates. Client identity stays in App settings; upstream update checks and the circular-arrows indicator apply only to the server. Manage profiles is its own pill after the last profile in the horizontally scrolling selector. Follow the [administration ownership contract](design/2026-09-14-administration-handoff.md) for credential-source distinctions and pending editor corrections.

## Chats Target, 19 September 2026

The chat list follows these rules.
This supersedes earlier Chats-specific instructions for profile chips, a separate
Projects section, Recents, separators, and the header's duplicated filters.
Use the compact Status / Profile / Project row, five colored status dots and
a continuous grouped list with three-chat previews.
Selected filters use a rounded accent inset from the bar, with padding inside
the tint. Distribute Status / Profile / Project in equal-width slots between
equal-width icon slots at both ends, centering each label in its slot. Keep
Clear all filters fixed at the right gutter. On narrow screens and at enlarged
text sizes, stack the filters with equal full-width targets and centered labels.
Project filter choices use the same saved project icon and color as their list
headings. The conversation context shows that same 20 dp project avatar before the assigned project name, with a 6 dp gap inside the existing project-picker target. Unassigned or unavailable projects have no borrowed project avatar. Profile home groups retain their outlined mixed-shapes icon.
The owner’s 20 September
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
The owner's 26 September refinement replaces the initial with a 14 dp outlined
home icon when the backend profile has `is_default: true`. Use the backend flag,
including after display-name changes; selection does not change the glyph.
Other profiles retain their initials. This is independent of the desktop's local
“Set as default” preference; see [the verified contract](DEFAULT_PROFILE.md).
The Chats profile viewport is right-aligned and capped at five 24 dp tap targets
(120 dp). Additional profiles remain available by horizontal scrolling; narrower
headers can show fewer than five at once.
Inset the viewport by an additional 16 dp from the context row's right edge so
the profile squares balance the connection icon's visible left inset.

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

The owner's 3 October refinement separates confirmed browser actions from
follow-up reads. Apply acknowledged chat and project changes immediately and
release the action controls while the list refreshes in the background. Keep
the retained list, token totals, active search, grouping and scroll position
available. Progress and refresh failures stay above the scrolling list; use
the existing thin linear bar with a quiet status label. Retry only rereads data.
At enlarged text, put Retry below the failure message. Reduced motion uses a
static bar. Dismissing menus and copying IDs do not request a list refresh.
See the [browser refresh contract](CHAT_BROWSER_REFRESH.md) for the verified
stock responses and client reconciliation rules.

## Recents, 27 September 2026

The former Activity destination is now Recents, including its drawer and launcher
labels. Preserve the existing top All / Running / Needs input filters and compact
row density. All includes chats with messages in the last 24 hours plus ongoing work.
Read-only opens and unsent drafts do not affect recency. Completed chats stay visible in All; do not label them Running.
Back from a chat opened here returns to Recents with the selected filter retained.
This rename concerns the destination, not the conversation's Activity presentation.

On 28 September, the owner selected **Work & history**, option C from the Studio
prototypes preserved on `prototype/recents-studio` at `7eae605`. Place ongoing
work in one compact bordered panel, followed by unboxed Last 24 hours rows with
thin separators. Each chat appears in one section only. Keep newest-first order
within each section, the three top filters with counts, and a quiet scope line.
Use the profile icon as the leading icon on ongoing rows, with profile name and
status beneath the title and aligned relative ages. Do not repeat the profile
icon beside that subtitle or add a separate status icon. History rows keep the
profile icon beside their profile name.
Idle history needs no repeated Recent label or chevron.
At enlarged text, wrap titles and metadata and move ages below titles. Continue
showing background-task details, partial-profile failures and loading feedback.

### Switching recent conversations

A chat opened from Recents retains the exact displayed filter, membership and
ongoing-before-history order for that visit. Last and first link circularly.
The normal chat, Activity, message actions and composer remain the resting screen.
No permanent carousel controls or status strip are added. The chat header has the
hamburger on the left and overflow on the right, with no back arrow; Android Back
retains stack and Recents navigation.

- Two fingers swiping horizontally on the transcript pull the chat into
  a card and commit the adjacent conversation on release. A short drag returns.
  Once recognized, a swipe stays a swipe until lift, including uneven finger drift.
- Pinch inward with two fingers to zoom into a persistent card stack. Lifting
  fingers leaves it open. Admission requires more than 24% and 32 logical pixels
  of finger-spacing reduction, exceeding twice the midpoint's travel, so an
  ordinary two-finger swipe does not open the stack. One-finger swipes coast
  through multiple circular cards according to their release velocity. A new
  touch catches the stack immediately; tapping the center or a visible
  neighboring card commits and expands that conversation. Back returns to the
  committed conversation before a second Back returns to the preserved Recents
  filter. Returning from cards restores an originally visible keyboard; a keyboard
  already hidden with Android Back stays hidden. The obscured chat cannot receive
  focus, including when a menu restores its previous focus target.

Moving cards use cached viewport images or static title-only placeholders.
Place placeholder titles at the top with the shared chat-title typography and
safe-area spacing. Omit the profile label. On an uncaptured chat's opening cover,
keep the temporary opening status separate in the center, below the title.
At zoom-out admission, capture the actual chat's completed paint before hiding
it offstage with its tickers and focus paused. Keep its latest image and reuse
valid images on later stack openings; there is no recurring capture timer.
Show one spinner while the initial batch settles. After motion stops, prepare
up to ten unique cards in center, left neighbor, right neighbor, then outward
order. Each ready image replaces only its own placeholder. New visible demand
gets priority after browsing; other ring members remain available on demand.

Use one rendering/readback lane and at most three physical history reads.
Pausing admission during motion does not pretend an outstanding readback or
network request has been canceled. Passive pages use the normal ProfileMessage
and background Markdown renderer, shared header chrome and composer framing.
They render saved dialogue without external image loading, live activity trees,
resume or read acknowledgement. Await completed Markdown and paint before
capture. The loading spinner cannot starve preparation through Priority.idle.

The decoded-pixel cache is bounded to 32 MiB, including reserved readback pixels.
Capture resolution is capped at a 1280-pixel long edge and adapts to the pixel
budget for ten retained cards plus a readback. Genuine and prepared images
survive neighborhood changes within that budget. Replace invalid versions and
dispose evicted or late pixels. Conversation identity, observed reading/draft
revision, theme appearance values, text scale and viewport determine validity; captured metadata
holds an opaque reading token rather than retaining a transcript copy. Recreated
workspace theme objects with equal appearance preserve valid images. Cache
hits publish immediately; image display does not wait for PNG encoding.

History and render jobs have five-second preparation deadlines. Initial-batch
progress settles after success, failure or a fifteen-second batch deadline, even
if physical I/O remains held. Browsing and selection stay available. Exit,
retirement, superseding work and layout changes fence late results. Selection starts server work alongside a 240 ms
expansion. Retain the original mounted view throughout that motion; admitting
cached reading must not build or lay out the selected transcript on animation
frames. After expansion, two completed paint frames let the selected chat and its deferred
reading-layout corrections finish beneath the opaque cover before a 100 ms
reveal. Cancellation releases the retained view and any paint wait. For a
previously loaded conversation, reveal the canonical retained
transcript, draft and reading position without waiting for session resume or
history refresh. Retained loaded profiles can be selected without rereading
discovery, chat lists or projects. Keep the thin loading bar at the top while
the selected conversation refreshes; fresh server messages publish through the
existing transcript reader. Runtime-dependent actions wait for the refresh.
Genuine snapshots keep their exact viewport throughout; an uncaptured
prepared page fades into an opening frame rather than becoming a false full-screen
transcript. Reduced motion reveals directly after the completed paint frame.
Cards keep stable physical identities as paint order changes. They round and gain shadows only during
motion; scale is about .86 during a switch
and .72 in the stack. Friction carries a quick swipe through the ring, then a
small spring snaps to the projected card. Touch stops coasting at its current position; independent
numerical springs retain positions and velocities when retargeted; reduced motion
settles directly. Input uses native
pointer timestamps for velocity. A new gesture can interrupt a returning card
once selection has settled. Two-finger gestures admit unselected transcript prose
and exclude Android's 24 dp edge zones. Active text
selection, code, message actions, Activity controls, pending-input panels, composer,
voice and queued-prompt editing keep their input. Chat actions omits recent
conversation navigation; use the two-finger swipe and inward pinch instead.
Accessible navigation within the stack uses explicit icon-only controls with
labels and tooltips. An enabled accessibility service alone does not disable expert
gestures; Android retains ownership of any gestures its accessibility service consumes. A failed stack
selection without retained reading keeps the committed chat and reports one
error beside the stack controls, leaving the cards available for retry or Back.
If refresh fails after retained reading was revealed, keep that conversation
visible, stop the loading bar and show the existing retry banner above its
messages. Retry rereads the server; it does not discard the retained transcript.

Passive edge cues point along the shortest circular path, with an equal-distance
tie pointing right. Neutral reply cues are white in dark mode and charcoal in
light mode; confirmed pending input uses amber. A coalesced cue fades over 650 ms
and grants no selection or read authority. Suppress cues during manipulation,
settling, text editing, voice, obscured/inactive routes and reduced motion. In a
settled stack, direction follows the focused card. Do not infer pending input
from ordinary prose questions.

Browsing never resumes, marks read or dispatches a chat. Keep at most three
physical preview reads in flight; evicted or retired previews cannot publish.
Selection uses the existing captured workspace command and its lifetime fences.
Drafts, attachments and scroll anchors keep their existing owners. Raster captures
retain outward-prepared and visited cards within the decoded byte budget and are disposed
when evicted or the route leaves. Failed preview reads leave the title placeholder
and settle that card's initial-batch progress. Selection and refresh have separate completion boundaries; an older
refresh cannot clear a newer refresh's progress or change the selected chat.

Client-only integration inspected upstream Hermes main
`14ec243c1797412d93e6b52c41f29f41e75b0cef` (9 October 2026): stock saved-message
history, session selection and correlated input/completion observations. No new
server endpoint or backend modification is required.

Retained-reading refresh inspected upstream main
`32b77f51c12e6093074b2c8076fc0a3229a7ff76` (10 October 2026):
`tui_gateway/methods_session.py` supports `session.resume` with `omit_messages`;
`hermes_cli/web_routers/sessions.py` provides paginated saved messages through
`GET /api/sessions/{session_id}/messages`. This change uses those stock operations
and adds no server contract.

Snapshot preparation inspected stock Hermes main
`26610b09a5c4aead8d8dfb276ea33decf0d7fa46` (10 October 2026): the saved-message
endpoint supports bounded latest-page reads and `inline_images=false`. Passive
Recents requests retain the existing six-row limit and omit inline image
payloads. This remains a client-only change. The chosen scheduling and cache
patterns follow [the snapshot research](../plans/recents-snapshot-research-2026-10-10.md).

## Bots, 9 October 2026

Use the selected **Compact roster** arrangement from `prototype/bots-studio`
(`c85eabbb11a19eea84dc00b2c41acc205f6dd4c1`). Bots and Groups are peer tabs.
Use one continuous grouped list per tab: pins sort first and carry a small pin
glyph; there is no separate pinned heading. Every bot row shows the truncated
last message from the same continuing Bot Chat it opens. Instance/status stays
secondary to the bot's name. Use native shape faces, shared Studio surfaces,
16 dp gutters and icon-only 48 dp actions with tooltips. At enlarged text,
titles/context wrap and message previews remain bounded in the scrolling list.
Each bot avatar is an icon-only 48 dp action opening Edit name & appearance;
the name/message area opens the chat. Keep the avatar action independently
labelled and prevent its tap from opening the chat.
Creation uses one icon-only 56 dp floating + in the bottom-right, with the
selected tab determining bot or group creation. Omit the all-instances subtitle
and all manual refresh controls, including pull-to-refresh and overflow refresh.
Roster updates happen automatically. Keep 88 dp of trailing list padding so
every row action can scroll above the FAB.
Creation and appearance are scrollable pages; bot settings reuse Wing's
existing captured-profile editors.
Appearance edits save automatically; omit the permanent confirmation tick.
Keep typing and shape/color choices responsive during writes. Back flushes
pending changes. Reload saved appearance preserves edited fields and silently
adopts saved values for untouched fields; reserve error styling for failures.
Conflicts pause autosave until reload/review and retry or a new edit.

| Before | After | Why |
| --- | --- | --- |
| All-instances subtitle and header refresh/+ | Title and overflow above the tabs; contextual floating + | Reduces header weight and brings creation within thumb reach |
| Permanent appearance confirmation tick and red reload-success message | Automatic saving and silent successful reload | Removes unnecessary confirmation and reserves red for failures |
| Ten bot-menu actions mix shortcuts and administration | Four actions; appearance/duplicate/rename/delete move into Bot settings | Keeps everyday actions quick and configuration together |
| Appearance requires the row menu | Avatar opens the same appearance editor directly | Makes the visible identity editable in one tap |
| Small bot name beside a heavier preview | 16 sp semibold name above a muted preview | Identity leads the compact row |
| Separate pinned region in the earlier exploration | One list, pinned first with glyph | Follows the owner's selected arrangement |
| A stale full appearance form could restore untouched fields | Save only edited fields; reload refreshes untouched values | Preserves edits made in another desktop client |
| Dense fixed forms at enlarged text | Scrollable controls and separate app-bar action row | Keeps avatar, settings and save actions reachable at 320 dp/200% |

Native captures cover roster, groups, anchored menus, new-bot page and both ends
of the appearance page plus its settings handoff in light/dark at both text
sizes. [Bots](BOTS.md) records action scope, failure behavior and current desktop
differences. Synthetic previews do not establish production render acceptance.

The bot row menu contains only View screen, Pin/Unpin, Hide/Show and Bot settings.
Bot settings places appearance first, duplication below the configuration editors,
Rename profile under Advanced, and confirmed deletion at the bottom. Keep chat
entry on the name/message area and appearance entry on the avatar. Session
history stays in Recents.

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
existing usage dashboard directly, with a profile-only scope picker. Health has
no Usage row. Its order is Host, Server, Profile, as specified in the Health
refinement below.

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

All screens use WingAppBar's compact 48 dp title/action row at ordinary text.
Use the Chats 24 sp title treatment, with connection/profile context below the
row, rather than centering a title/context column in a taller toolbar. The bell
slot stays on the title row and shows an icon only for current issues; configuration
belongs in Hermes health's compact Alert settings row above Host, using an
outlined bell. Titles respect the selected text scale and grow; secondary actions
move below at enlarged text. Viewer headers delegate to the same geometry while
retaining their exact resource identity disclosure. No settings shortcut belongs
beside the bell. Keep alert rule editors unpadded: Enabled followed by two compact
sentence rows, “Alert after [minutes] if above [percent]” and
“Clear after [minutes] if below [percent]”, with independent durations. Sentence
fragments wrap at enlarged text while keeping each input beside its unit. Use
an icon-only Close action in the header. Alert settings autosave toggles and valid
threshold edits; use no Save/Undo footer or discard confirmation. Persistence
errors appear inline with an icon-only retry. Transient health notices float
below the toolbar with generous clearance, growing with text size, 24 dp side
gutters and a 360 dp width cap. Use the opaque raised surface, shared card corners,
a neutral thin border and soft elevation. Confine warning/critical color to the
small status icon and its tint; keep the title readable, the triggering usage and
threshold/duration immediately below it, and the connection name secondary
and dismissal icon-only in a 48 dp target. At enlarged text, place the icon above
full-width labels and dismissal in the upper trailing corner. Use the shared 200 ms entrance and
settle immediately with reduced motion. Health alert dialogs offer icon-only Close
and Open Hermes health actions, plus previous/next issue controls when needed.
Do not add acknowledgement or snooze controls. Closing the dialog retains the
issue count and severity colour until recovery. See [Health alerts](ADMINISTRATION.md#health-alerts).

Use 16 dp page gutters, a 4 dp spacing grid, 6 dp action corners, 8 dp group/composer corners, 24-28 sp page titles, 16 sp body text and 12-13 sp metadata. Primary action paint can be about 40 dp high inside a minimum 48 dp touch area. Text scaling must allow rows and controls to grow. Keep established compact activity density; improve touch areas without adding visible card padding.

The owner's 7 October density refinement makes compact spacing a requirement
throughout Studio. Avoid generous empty space, oversized card padding, tall
passive rows and separate lines for facts that fit together legibly. Use 8–12 dp
group insets, 4–8 dp between related facts and 12–16 dp between sections as the
starting point. Prefer aligned label/value/meter rows and short metadata lines
over spreading the same observation across several padded blocks. Keep one
timestamp at its owning section and remove repeated headings and captions.
Passive observations do not need the height of interactive controls. Preserve
the documented control targets (48 dp generally, with the accepted compact
activity-detail exception), readable typography and full values; at narrow widths or
enlarged text, wrap and grow the content rather than shrinking it or clipping it.
Whitespace must support grouping, reading or action reachability. Review the
actual phone layout for unnecessary vertical gaps in both themes.

On 18 September 2026, the owner split the shared screen header into two targets:
the connection icon and LED open the existing status/retry sheet, while the name
opens an anchored dropdown matching its displayed scope: connection-only headers
(including Chats, conversations and Activity) offer connections only; headers
showing a profile offer connections and profiles, except Analytics, whose dropdown
offers only profiles following the owner’s 19 September refinement. Each target is at least 48 dp.
Use the standard Studio popup surface and selected background tint. This applies
to Chats, conversations, Activity, Administration, Health and administration
drill-downs.

Tool and saved-agent headers use `CompactActivityRow`: zero vertical padding,
no minimum height and no gaps between rows. The owner’s 8 October tool refinement
uses exactly two single-line text rows: action, then one useful input detail (or
an exception). Ellipsize both at the available width, including enlarged text;
full titles and inputs remain readable on expansion. URLs in the subtitle omit
the HTTP(S) prefix. Timing remains beside the title, with a dash when backend
timing is unavailable. Saved-agent goals retain their wrapping. Keep any expanded-detail spacing
inside the detail content. The [density guard](../tools/architecture/rules/activity_density.md)
and rendered activity-tab tests enforce this exception without banning padding
in settings, forms or action controls.

Use Android's Roboto sans typography explicitly across component themes and monospace for code. Keep the existing compact Activity geometry. Its tabs, badges, disclosures and [accepted detail toolbars](#accepted-activity-detail-family) are deliberate density exceptions to the general control dimensions.

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

The owner's 10 October **visible-actions** refinement supersedes the initial
full-width Target. User messages sit at the right, sized to their text and
footer, with a 17% leading inset at normal text and a 20 dp inset at enlarged
text. The available width reserves the separate 44-by-48 dp Copy column;
Copy touches the bubble's upper-right edge and ends 4 dp from the viewport edge.
The message area uses the theme-adjusted `primaryContainer`, with 10 dp horizontal
and top padding and 4 dp below the text. User attachments stay inside the same
bubble and retain their original preview/open/copy behavior.

Time sits at the left of the bubble's compact footer; Edit and Restore sit at
the right. Its fill
is exactly `Color.lerp(surface, primaryContainer, .5)`: equal parts ambient chat
background and the actual displayed bubble color, including light-theme
softening. There is no divider. The footer adds no vertical padding; Edit and
Restore use the owner's selected 48-by-32 dp compact targets. At enlarged text,
or when the date and controls cannot fit side by side, the date occupies a
separate left-aligned line above the right-aligned pair of actions.
Assistant controls and Copy retain their 48 dp height. The design exploration
is archived on local branch `prototype/chat-visible-footer` at `1787e518`,
under `plans/prototypes/chat-visible-footer`.

Assistant replies use plain broad prose, omit repeated author names/avatars,
and share the same Copy column. Standalone Copy aligns with the first line rather
than occupying an extra header row. When Activity precedes an answer, Copy stays
in its disclosure header, preserving section/scroll identities and expansion.
Activity uses “Used N tools” from received calls with its existing
Timeline/Tasks/Agents/Work contents intact.

Both speakers use local `dd Mmm, HH:mm`; unavailable timestamps are omitted.
Full-date tooltips/accessibility, native selection, exact copying, attachment
behavior and streaming/busy action eligibility remain intact. Reply actions
are Fork, Read aloud and Regenerate, right-aligned below the answer. Fork uses
`WingIcons.fork`, the same Lucide `git-fork` geometry as upstream desktop's
`GitForkIcon`. Controls remain visible and available on touch without hover.

Restore confirms its destructive scope in-app, reruns the selected saved prompt
in the same conversation and removes its later history. It interrupts a running
turn first, preserves the separate composer draft and pauses queued follow-ups.
The controller validates a durable saved row against full stock history before
sending the cut; a stock busy refusal triggers bounded interrupt-and-retry of
the same cut. Definite refusal restores retained history, while uncertain
transport delivery requests readback without automatic resend. Find and passive
previews expose no editing or Restore authority. Fork remains on saved answers;
its composer icon, eligibility, runtime fact and send dispatch are removed.

Verified against upstream main `dce1e9b37581dd62e480a9064dc04a709c2940d3`
(10 October 2026): desktop `use-prompt-actions/rewind.ts`,
`session-tile-actions.ts` and `i18n/en.ts`; gateway `tui_gateway/methods_prompt.py`.
The stock request is `prompt.submit` with `truncate_before_row_id`,
`confirm_truncate` and `confirm_empty_truncate`, after `session.interrupt` when
needed. No backend changes or legacy-address fallback are introduced.

The saved-message editor uses a compact Studio header with icon-only close,
one scrollable message/warning area and a fixed Replace and resend footer.
Use the shared surfaces, borders, typography, spacing and control corners;
keep the footer above keyboard insets at 320 dp/200% text. Pending work disables
editing and dismissal; rejected work retains the correction and shows its error.

Network continuity uses a shared LED on the left of each server identity, quiet
bounded recovery, retained conversation state, and immediate notification
navigation with cached reading where available. Use these rules for
connection cues, accessible status targets and recovery journeys.

Keep the existing Activity disclosure, tool counts, Tools/Tasks/Agents/Work tabs when available, thinking disclosure, nested tool rows, guide line, selection, expansion state, scroll anchoring and copyable details. Do not add extra outer cards, timeline dots or permanent rows simply because the raster mockup draws them. Use the current component geometry as the baseline and apply color/type/border refinements. Approvals and questions remain outside collapsible tool results.

The owner-approved readable activity change replaces generic tool-result group
headers and the extra Current tools disclosure with individual action rows in
Tools. Each compact row carries an action title, target, exception notice and
right-aligned duration when supplied. Actual backend starts permit approximate
receipt-based counters. Expanded details show relevant content, including the
exact analyzed image, followed by selectable/copyable Raw details. Use semantic
status colors with text for running work and exceptions. Completed/success/
unchanged notices stay out of ordinary tool headers. Restore saved Tasks and
Agents from delivered history, with passive output disclosures for past agents.
Preserve category
selection, guide and anchored expansion. Contract: [tool activity](TOOL_ACTIVITY.md).

Saved transcript bodies are prepared within the visible lazy list and a small
scroll buffer, capped at half the viewport or 250 dp. Collapsed Activity initially
mounts only its existing header/counts; first expansion admits the existing
details, and later collapse retains visited tabs and nested disclosure state.
Keep all existing fields, actions, grouping and reading anchors intact.

The owner's subsequent 7 October refinement requires zero vertical padding in
tool-call headers and saved-agent rows. Size them to their text, with no minimum
row height or inter-row gaps; keep icons and disclosure arrows at 16 dp. These
Activity disclosures are a deliberate exception to standard action heights.
Preserve target, exception and supplied timing. A saved agent with no nonblank
summary or error is passive text without an arrow or expansion action; keep its
full goal readable. Live agent rows opening the control sheet retain their
existing action dimensions.

Task status icons follow upstream desktop: a green filled-circle tick for
completed, a spinner for in progress, a muted dashed circle for pending and a
muted slashed circle for cancelled. Keep the existing 16 dp icon slot and use
Wing's semantic success and muted colors in both themes. The native spinner
becomes a static arc with reduced motion; each state has an accessibility label.
This is task status, not option selection. Verified against upstream Hermes
commit `603007ead347608c81bf95fd7b40c3fff9e4bed5`, desktop
`apps/desktop/src/app/chat/composer/status-stack/status-row.tsx`, on 19 September
2026. The change uses the existing client task states and requires no API changes.

Keep activity status and queued-message controls above the composer. Preserve the two-row composer: draft and dictation first, then attachment/capture controls, context, the compact model controls and Send/Stop. Controls wrap at enlarged text without shrinking touch targets. Preserve existing voice states and attachment options. Inline skill references use bold text and the shared primary accent inside the editable draft, with no separate chip or action. The slash helper remains above the composer and offers only skills for a slash token inside prose; leading commands retain argument completion. Reveal completed results or read recovery within the scrolling composer without moving input focus, including longer drafts with the Android keyboard open. Selection, copy and keyboard composition remain native text behavior.

The activity summary occupies no space while idle, after completion or after
cancellation. Keep notices for ongoing work, active subagents, input requests,
loading, recovery and errors. Both this summary and the connection notice below
the header expand/fade in and collapse/fade out using the shared 200 ms motion.
Update visible status text in place; omit transitions when reduced motion is
enabled. Neither notice reserves an empty row. Brief connection interruptions
retain the existing two-second grace period before showing a notice.

The model selector opens one compact Models ledger on the current chat's provider tab, with its selected model first and visible. Keep the active provider tab in view even when it occurs late in the catalog. The small handle shares the 36dp title row instead of reserving its own row. Search uses compact 13dp text in a 36dp field, provider tabs are 32dp high, and single-line model rows are 36dp with 2dp inner vertical padding. This picker is an explicit owner-requested exception to the general 48dp action target: info, close, refresh and footer controls use 36dp targets with Material tap-target padding disabled. Do not let inherited button minimums add blank space. The footer is 44dp including its 4dp top/bottom inset. The sheet fits short lists; long lists scroll within its bounded height. Provider headings appear only in All; a selected provider uses one supplied In/Out price header with token units when needed. Rows grow for enlarged text. Each info action opens a content-sized model card showing supplied facts and the full route identifier. Missing facts are omitted. Starting a search searches all providers; an explicit tab narrows it. Selecting a model stays in the ledger; Apply commits all draft settings for this chat.

The reasoning control is a circuit-brain icon with a tiny current-level badge inside a 36dp target, following the owner-requested compact model-control exception. Its normal popup is 218 × 108dp: four columns, two rows, no heading or close row. Compact labels retain full accessible names and tooltips. Enlarge the popup for larger text. Omit Off when the backend disallows it. Fast uses a lightning icon, tinted/filled for On and neutral/outlined for Off; the picker includes the On/Off label. Omit controls without supplied availability. The footer keeps these controls, More (manual model ID/provider access), and Apply. The composer has one small inline model/reasoning/fast cluster with 14dp icons, 12sp labels and 32dp targets: chip icon plus the short model name, circuit brain plus the first reasoning letter (Min/Med/Max for the three matching levels), and a lightning icon reflecting observed fast mode. Model opens the same picker; lightning toggles fast immediately. Thinking uses Send's held-pointer interaction: ordinary taps do nothing, hold opens a narrow vertical level selector, sliding previews, release applies, and sliding away cancels. Keyboard and accessibility retain explicit level choices. A chat change, busy/disabled transition, resize or backgrounding retires the held selector. Full model ID, reasoning name and fast state remain accessible. Picker changes still wait for Apply. Preserve busy/loading/disabled rules and independent context, attachment, voice and send actions.

Model catalog choices use the shared chooser in Chat, profile defaults, helper and fallback settings, scheduled tasks, and image/video tool settings. Search stays above the list and shows matching provider groups. The selected row is tinted, and provider plus model form its identity. Refresh keeps the pending choice and search text; a saved choice missing from the current catalog remains visible with an availability note. Automatic helper routing and a scheduled task's Profile default are separate named choices. Each editor has one labelled action: Chat Apply, profile Save default, helper Set helper model, fallback Add/Save fallback, tool Use model, or task Use in task. Task Save performs the server write for the entire task. A failed save keeps the pending choice visible. The catalog filter policy stays specific to each setting. Speech model IDs remain editable fields because the server does not expose a speech model catalog through this route.

Tool model lists put the current or pending selection first, with an explicit Selected label for the saved model and Pending selection for a choice awaiting Use model. Tool setup provider lists put selected providers first with an accent border, tinted card, and visible Selected label; this border is an explicit exception to the general selection rule. Web names search and extraction selections separately. Keep the image/video provider controls and speech provider dropdown otherwise unchanged.

Preserve the current Send/Steer/Queue/Stop and Enter behavior. Preserve the message-actions entry points present in the implementation baseline, including long-press. Do not restore controls removed by later approved UX work. Steer and Queue remain one-shot composer choices with current eligibility rules, never persistent modes. Fork is only a saved-answer action. Preserve queued-message review, edit, delete and pause/resume behavior. Do not show unavailable actions as usable in a running chat.

The later owner-approved [held-slide composer actions](COMPOSER_ACTION_GESTURE.md) supersede the earlier busy-button interaction. The owner's 8 October refinement shows a tappable Stop without a held column while a connected turn is working with no draft. Typing the first character or adding an attachment restores the arrow and configured action column. Use the brief vertical glide and settling bounce for both transitions, plus the column's staggered upward reveal; reduced motion switches immediately. Preserve held-action selection, cancellation, accessibility and the device default-action preference. Its existing geometry is an explicit exception to the general control-corner tokens. Preserve the Markdown scrollbar gutters and subtle thumb styling added alongside this work.

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

Source uses `WingTokens.sourceColor` for keywords, strings, numbers, names,
variables and comments in both themes, with Studio's existing mono typography.
Chat code, Activity source and file previews share `SourceCodeText`. Grammar
coloring preserves literal text, selection and copy; numbered file receipts
retain their supplied gutter characters. Live fences color after response completion;
large or dense source remains literal to bound added rendering work. Unlabelled text and console logs use
the ordinary foreground. Diff and diagnostic colors keep their semantic owner.

Conversation file cards put icon-only Download and Open preview actions beside
the wrapping filename, using the download-to-tray arrow and outlined eye. Keep
48 dp targets, accent-colored icons, tooltips and accessible action names; the
download spinner replaces its icon without changing the row geometry. Errors
remain below the row.

Conversation images follow desktop's inline preview convention: no generic
file card or repeated filename, tap to zoom the original, and a compact download
action. On phones the action stays visible rather than depending on hover.
Previews hug the image, preserve its full aspect ratio without upscaling, and
are capped at the available chat width, 420 dp wide and 320 dp high. Loading
uses desktop's 4:3 cold frame; failed previews expose Retry while Download
remains reachable. Thumbnail decoding is bounded to the preview's physical
pixels; the viewer receives the original bytes.
Verified on 2 October 2026 against upstream Hermes
`569fd58960b93040b333cf744c8f2adc152f71bd`:
[`MarkdownImageContent`](https://github.com/NousResearch/hermes-agent/blob/569fd58960b93040b333cf744c8f2adc152f71bd/apps/desktop/src/components/assistant-ui/markdown-text.tsx),
[`ZoomableImage`](https://github.com/NousResearch/hermes-agent/blob/569fd58960b93040b333cf744c8f2adc152f71bd/apps/desktop/src/components/chat/zoomable-image.tsx),
and the stock
[`/api/fs/download` route](https://github.com/NousResearch/hermes-agent/blob/569fd58960b93040b333cf744c8f2adc152f71bd/hermes_cli/web_routers/files.py).
The existing authenticated loader supplies the owning profile and session;
no backend changes are required. `test/chat_inline_image_test.dart` covers
rendering, retries, original-image viewing, copying and phone layouts in both
themes at normal and doubled text size. Render captures use
`CAPTURE_INLINE_IMAGES=true` and `CAPTURE_FONT_DIR`.

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
The owner's 7 October server-resource design refinement adds a separate Host
group before Server, followed by Profile. Host owns machine identity, compact
CPU/memory/disk meters, uptime and load context. Its refresh reads resources;
Server refresh still runs diagnostics, and Profile refresh still checks the
selected profile. Host uses one section-owned observation time and a compact
group with inline label/value/meter rows and subordinate machine facts. Use
Studio surfaces, corners and accents; resource warning colors require actual
reported pressure. The supplied reference establishes density and hierarchy,
not a replacement palette or component system. The owner accepted the compact
inline design and requested a single loading animation: keep the Host refresh
spinner and omit the separate linear loading bar. Preserve the compact layout
while optional readings are unavailable, and wrap values at enlarged text.
The [Host resources contract](ADMINISTRATION.md#host-resources) records the
reusable connection-owned loader and independent alert-threshold evaluation.
The accepted exploration is archived on local branch
`prototype/server-health-studio` at `6b5484b`, under
`plans/prototypes/server-health-studio`; its fixtures remain synthetic.
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
5. Reading and output details: long Markdown, code, tables, file rows and viewers share readable typography and accents. Apply the activity field/action decisions within the shared geometry.

Use light/dark pairs and enlarged-text examples in verification. Inspect drawer/scope switching, repair/attention states, reading/output details and composer states in the rendered UI. A generated larger-text study does not substitute for layout verification.

Audit every screen, dialog, sheet, menu, form and custom control for legacy styling. Standard widgets must inherit Studio component themes; custom decorations must consume the shared tokens. Keep intentional geometry exceptions for the refined activity/tool presentation and content-specific previews. Record the audit and validation evidence with the implementation. Backend contracts, persistence, state transitions, shortcuts and eligibility rules remain unchanged unless the owner approves a specific behavior change.

## Activity Tasks and Agents refinement, 7 October 2026

The owner requested the other two Activity tabs be made as readable as Tools.
Keep the existing tabs, selected state, guide, backend order and parent task
indentation. Tasks use 14 sp selectable content and a separate 12 sp explicit
status line, with progress/cancellation counts above the list. No editable
checkboxes or invented task timing. Agents use 14 sp goals, an explicit status
line with backend-supported timing, readable current activity and quiet
model/tool-count metadata. A row opens the existing detail sheet with full task,
output, steer/interrupt controls and a copyable backend Details disclosure.
Preserve loading, refresh, retry, uncertainty and control eligibility. Use Studio
semantic tokens and at least 48 dp rows; enlarged text wraps statuses/metadata
without hiding reachable controls. See [the activity contract](TOOL_ACTIVITY.md).


## Native reasoning timeline, 9 October 2026

Activity's Timeline tab contains native reasoning between tool calls, using the
same compact two-line row geometry and shared detail frame. Reasoning has one
line of supplied text beneath its title. The shared circuit-brain glyph from the
reasoning selector identifies both live and saved reasoning, distinct from
Hindsight's head-shaped glyph. The shared row keeps every leading glyph at 16 dp.
Active streamed text uses Thinking;
sealed or saved text uses Reasoning. Expand to read the received Markdown, with
exact-copy and actual-overflow viewer icons. Native event source and any
separately supplied reasoning preview remain in Raw details. Omit invented
insight counts and reasoning timing. There is no separate Thinking footer.
Tasks, Agents and Work retain their selection and controls; live Activity keeps
its existing location above the composer. Saved reasoning-only messages remain
at their backend position. Live and saved segmentation need not match.

## Activity information and typography, 8 October 2026

The [information-design research](design/2026-10-08-activity-information-design.md)
records primary sources and distinguishes their findings from Wing's choices.
For Activity work, follow
[design-wing-activity](../tools/agent_skills/design-wing-activity/SKILL.md).
This charter is the authoritative presentation policy; the skill supplies the
executable decision and verification process.

### Backend API coverage

Every product observation in a screen or design prototype must have a supported
stock Hermes API acquisition path available to Wing. Before displaying a field,
record its endpoint or received API event/tool receipt, response field, meaning
and scope. Parse declared metadata from API-returned document content; derive
totals only from compatible API observations with explicit period and coverage.
Use actual captured API responses for real-data previews. Build optional widgets
only for API-supported observations; render them only when useful returned data
exists. Omit their heading, frame, actions and reserved space together when data
is absent. Unsupported metrics do not receive placeholder or unavailable cards.
Required loading/recovery flows retain their existing error handling. Publish a
populated design preview only after its API samples have been captured.

Stock source inspection establishes API contracts; actual product observations
come through those APIs. Supported stock file-list/read APIs qualify when the
resource path comes from API discovery and the returned content supplies the
observation. SSH, direct server filesystem/database reads and internal Python
calls do not qualify as data-acquisition paths for Wing or its prototypes.
Finding a real server value does not establish that Wing can obtain it. A warning
label does not authorize displaying unsupported fields. Keep designs within
verified stock API capabilities unless the owner explicitly changes that scope.

### USER-VALUE-FIRST Activity

Every visible item must provide a conscious user signal or value: understand
intent, assess actual achievement, reuse a payload, inspect a useful resource,
or recover from a problem. The main card is a curated account of the work. Raw
backend fields remain available through **Raw details** for technical inspection.
Assign every field and action deliberately; a received key alone does not earn
main-card space or a copy/viewer control.

Show the requested operation and actual reported result as distinct facts. Use
the supplied skill name as the main operation title and **Result** for its
response. Keep code with its output, requested file ranges with the content
received, Find/Replace with any supplied diff, and a vision question with its
image and actual receipt or analysis. A native image receipt establishes that
an image was loaded for the agent; it does not establish an analysis. Display
errors, warnings, meaningful no-change outcomes and partial/truncated results
where the user assesses achievement. Only backend observations establish
counts, timing, verification, changes, exit codes and analysis; qualify unknown
or last-received output.

Use the following placement rules when making the exhaustive decision table:

| Information | Placement and user value |
| --- | --- |
| Meaningful request, source, command, prompt, authored reasoning or returned payload | Main content: explains intent or supplies something the user can understand/reuse |
| Timeout, context, limit, offset and similar execution options | Quiet inline title metadata, following the compact Read file arrangement; wrap under the title at enlarged text |
| Reported failure, warning, changed/no-change result, partial content or server truncation | Visible result context when it affects what happened or the user's next action |
| Routine `dirs_created`, duplicate `resolved_path`, technical matches-format descriptions | Raw details: backend bookkeeping does not add user value to the main result |
| Skipped lint / no linter available, routine status booleans and other diagnostic plumbing | Raw details; surface a concrete actionable diagnostic when one is actually reported |
| Supplied extra/unknown fields | Assess individually against user value; retain exact technical evidence in Raw details |

Treat repeated facts as one item. File identity belongs to its resource header,
not a repeated options card and content heading. File-search matches group by
supplied path and line labels; the excerpts carry the useful result. File checks
keep actual write verification, syntax findings and semantic diagnostics
separate rather than implying broader correctness. Web-source host identity
stays quiet beside its excerpt and source actions. Unknown tools show selected
meaningful request/result content with exact Raw details available.

The maintained [field decisions](design/activity-field-policy.md) account for each
stock tool contract; use them before changing selection.

File labels show **the filename only, on one line with end ellipsis**, across
activity summaries, resource headers and viewer titles. Tap the name to reveal
the exact full supplied path in a small popup anchored to that name or tap.
Use a backend-supplied absolute path when available; a relative locator stays
relative until the backend resolves it. Display shortening never changes the
identity used for opening, loading, sharing or copying. Keep full paths in the
popup and Raw details, rather than expanding routine labels across several rows.
URLs retain meaningful source/host identity. Backend fields still require
semantic validation: source text or contradictory search locations do not earn
file actions merely because they appear in a path slot.

This policy covers tools, Tasks, live/saved Agents, reasoning, goals, loops,
heartbeats and background processes. Keep task states and parent indentation
passive, with the established status glyphs. Agent task/output, goal contracts,
recurring prompts, process commands and output tails receive the same field and
action decisions as tool payloads. Preserve backend-qualified availability and
control eligibility. An exited process without an exit code does not establish
command success. Keep cancellation, steering, retry and other actual lifecycle
controls within their existing authorization and recovery flows.

Live and saved subagent headings identify the task with its first sentence,
omitting the ending period. Cap headings at two lines with end ellipsis at every
text size; a task without a sentence-ending period uses the same two-line cap.
Periods within filenames, URLs and decimal values remain part of the sentence.
The expanded Task contains the complete original backend instructions, with its
existing scrolling, viewer and exact-copy actions. Shortening the heading never
shortens the task payload or creates an authored summary.

Saved-agent lifecycle status appears once, under the task heading, in both
collapsed and expanded rows. Do not repeat it as a detail-card footer. Keep
distinct errors and result qualifications (partial output, iteration limits,
schema failures) with the expanded result, including when no output was supplied.
A separate full-screen or modal viewer must retain its own necessary context.

Skill reads use the skill's supplied name and purpose as their compact document
card. The name stays on one line with end ellipsis; tapping it reveals the actual
source path when supplied. One header owns eye, eligible share and exact-content
copy. The eye opens received instructions, not an invented file or a new read.
Keep full instructions in that Markdown viewer, with raw/formatted switching
inside it.
Recognize the stock plugin bundle-context envelope before extracting YAML
frontmatter. Both are metadata, not document prose or Contents headings. Keep
the exact received source, including the envelope and declaration, in raw mode.
Supplied tags, author, version and directory category are quiet viewer context. Obtain category from the stock skills catalog, matched to the same skill
and profile; keep license in the exact original source. A reference section uses
actual backend file listings beneath the API-supplied skill directory. Show
one-line filenames, supplied sizes and eligible eye actions; use the same document
viewer for reference content, raw/formatted switching and exact copy/share.
Show at most five reference rows, with independent scrolling for additional
files. Keep a scrollbar thumb visible whenever additional rows exist so the
scrolling affordance is discoverable. Keep filenames on one line and retain
each file's original action target.
Omit the entire reference section when no files are returned. Omit missing fields
and technical readiness bookkeeping. If no description was
supplied, use a bounded excerpt of the actual instructions. Setup problems and
unchanged/binary receipts retain their explicit states. Historical reads do not
gain editing controls or an invented active state.

In the full skill viewer, put name-only copy on the same row as the skill name.
The document card owns raw/formatted switching, share and content copy. Scope
those actions to the displayed mode: exact Markdown in raw mode, rendered text
in formatted mode, with rich clipboard markup when available. Keep purpose,
metadata, activity and viewer controls out of copied/shared document content.
Use the same selection owner for skill instructions and reference documents.
Copy buttons write directly to the clipboard and give brief confirmation. A copy
action does not open a selection or export screen; report clipboard failure
briefly in place. Right-align the last-change date in the compact Activity card.

Section rails allocate equal travel to each section and move continuously through
its reading progress. Show ticks directly over the document, with a transparent
track and no track shadow. During dragging, the grip follows the finger directly;
preview the destination and jump on release. Hand off from the released position
without resetting the grip to the previous section. When paired with a reader
dock, the dock owns tap and keyboard access to contents; the grip only scrubs.
Give the grip an enlarged touch target inset from the phone edge without enlarging
its painted surface. Small finger drift must not cancel a pending hold. Keep
normal page scrolling available and prevent a competing page scrollbar from
overlapping the grip target.

The accepted skill reader combines a bottom dock with a six-dot grip. Place the
dock above the device's bottom safe area; it shows the current heading and
section ordinal, previous/next arrows and a tap target for independently
scrolling Contents. The prototype's design switcher does not ship. Use a 64 × 60
dp grip target, 4 dp from the right edge, around a 44 × 44 dp painted button.
Start its rail 64 dp lower than the original 20%-of-screen placement and keep
the resting button below the trigger text, including at enlarged text sizes.
Activate on a 250 ms hold or deliberate 12 dp vertical drag; tolerate small
finger drift. Keep the idle grip discoverable without obscuring document text:
use a 28%-opaque accent fill, a 55%-opaque accent outline, high-contrast dots
and no shadow. Grabbing it makes it solid. Fade ticks in over 140 ms only
while scrubbing, and prefix the destination preview with its section number. Cancellation, leaving the app and
disposal must cancel pending activation. Reduced motion suppresses animation.

Contents fits its section count, with at most five equal-height rows visible and
independent scrolling for longer lists. Row height accommodates up to two lines
of a heading at the reader's text size; the available viewport can reduce the
visible count. Tapping the sheet header or empty space dismisses it; tapping a
section navigates and dismisses. Retain the accessible close control and normal
outside-tap/back dismissal.

Skill activity metrics retain their distinct API meanings. Use the directly
returned `use_count` and `patch_count` for the main metrics. The stock learning
graph's `useCount` describes the same recorded loads/references but its filtered
graph cannot establish zero for missing nodes. Analytics read requests belong in
secondary details labeled **Read requests · [period]**, with request semantics
and profile coverage. A successful agent skill load increments both use and view
counters; their catalog sum with patches does not count distinct actions. Omit
Events and the redundant Views metric from ordinary skill UI. Never combine
unlike counters or label them lifetime successful uses.
Show numbers and profile labels alongside any chart; color alone cannot carry
the breakdown. Omit selectors for absent or unhelpful metrics.

Skill activity groups use and change observations behind one disclosure. Give
the reader a compact summary of recorded use, patches/edits and the latest valid
change date; keep per-profile charts, exact dates and scope explanations inside
it. A separate Audit card must earn its place with a distinct user task and
useful information beyond this summary. Comparative charts share a stable
profile-colour mapping; each chart retains its own metric total. Display each
count once within the disclosure: when donuts show counts, the shared legend
identifies profiles, without a repeated count table. Secondary read requests use
one stacked horizontal bar with counts inside segments and the same profile
colours. Place valid per-profile last-change dates after Read requests, under a
separator. Place a donut count inside only when it fits the actual slice;
otherwise use an external count with a colour-matched leader line. Reserve
callout space and separate neighbouring labels vertically. Keep exact counts
in chart semantics. Put charts beside each other when labels and counts fit, and stack
them at narrow widths or enlarged text. Represent confirmed zero totals without
inventing a proportional ring; missing records remain unknown.

Use directly returned skill change counters for the change summary. Stock
`/api/profiles` and `/api/fs/list` can discover the profile's skills telemetry
file; `/api/fs/read-text` supplies its per-skill `use_count`, `patch_count` and
`last_patched_at`. Match the exact skill name, validate counter values and retain
profile coverage. Hermes increments this counter for patches and full edits, so
label it patches/edits and its timestamp last change. Sum only returned records;
missing records are unknown, not zero. No time window is supplied. Never infer
patches by subtracting read/view counters from combined events. A telemetry
`created_at` can be seeded or reset and does not establish skill creation.

Keep declared author/version in their existing metadata owner. Returned learning
state and pinning can explain per-profile maintenance; a lone file modification
date belongs in quiet metadata rather than an otherwise redundant disclosure.
Label file `mtime` as file modification. The learning graph's generic timestamp
does not identify whether it came from use, view, patch, creation or file time;
it cannot establish a creation date, update date or last use. A curator-management
marker does not prove authorship. Build no unsupported creation/edit history.

Activity and Hermes administration skill reads use the same document viewer
component and declaration selection. Administration retains its captured profile,
read recovery and eligible edit/archive/uninstall actions; those controls do not
appear on historical activity receipts. Do not build a second skill document UI.

### Activity actions and viewers

Use one icon vocabulary: **eye** opens a fuller viewer or useful resource,
**copy** copies meaningful reusable content, **share** shares an eligible
resource, and **wrap** controls literal text wrapping where useful. All actions
are icon-only with precise scope-specific accessible names and tooltips,
temporary feedback and reachable targets. Keep the stable relative order
**wrap → eye → share → copy**, omitting ineligible actions; copy stays at the
trailing edge. Keep controls
adjacent to the payload/resource they affect; at enlarged text move that action
row below its full-width title instead of squeezing text between icons.

| Action | Eligibility and scope |
| --- | --- |
| Eye | A useful file/image/source resource, or received text with actual layout overflow that benefits from a fuller viewer. Short nonresource results have no eye; eligibility follows rendered overflow rather than character count. Use the same eye glyph rather than a second fullscreen vocabulary. |
| Copy | A meaningful reusable request/result/excerpt/command/source. Copy its exact supplied content, retaining original receipt text when display formatting differs. Options, status booleans and routine plumbing have no copy control. |
| Share | An actual shareable resource with its existing pending/error recovery. |
| Wrap | Nonempty literal source/output, including short code. Show the icon beside Copy in inline payloads and full text viewers; toggle between wrapped lines and horizontal scrolling. Raw Markdown viewers also expose it; formatted prose reflows without this control. |

Each payload has one action for each useful purpose. Combine resource and
content controls when they address the same read/result scope: one eye and one
copy, without duplicate resource/content copy or viewer buttons. Put resource
identifiers/URLs in their viewer and Raw details rather than adding a path/link
copy beside the payload's copy. Distinct useful edit payloads such as Find,
Replace and a supplied diff may each have their own scoped controls. A file eye
can open the full backend file even when the returned excerpt is short; use
that resource eye rather than adding a second body eye.

Raw/formatted switching belongs inside the fuller viewer. Keep the main card
focused on reading and action. Markdown receipts render formatted; other source
files, replacement strings, patches and logs stay literal, including their
Markdown-looking characters. Remove only stock receipt line-number prefixes
for Markdown display and retain the exact numbered receipt for copy. A viewer
copies its exact supplied content in either mode and preserves save/download,
share recovery and supplied partial-file facts. Opening or scrolling received
content does not imply fetching content omitted by the server.

Full file viewers use the same compact 32 dp action targets and 16 dp glyphs as
activity details. Keep the filename on one line and move actions below it at
enlarged text. Separate viewer chrome from authored content with a neutral header
rule and a document surface using Studio's shared border, corners and 8 dp
framing. Formatted Markdown and its raw mode share that document frame; avoid
adding another frame around source/image renderers that already own one.

### Accepted activity detail family

The owner's spacing and typography refinements on 8 October establish the
shared framing below. **Read options is the visible 8 dp spacing reference**
for every activity detail. These accepted properties do not establish blanket
approval of every earlier layout, action or implementation constant; apply
USER-VALUE-FIRST selection within this family.

| Property | Shared rule |
| --- | --- |
| Visible insets | 8 dp on all four sides for resource/section headers, content, images, metadata and footers |
| Compact toolbars | 32 dp high at ordinary text size, plus the 1 dp section separator; grow for wrapped/enlarged text |
| Detail icon controls | 32 × 32 dp targets with 16 dp glyphs and 8 dp icon insets; scoped exception to Studio's general 48 dp control rule |
| Inset ownership | Labels own their 8 dp vertical framing; buttons own their icon inset. Avoid a second vertical toolbar inset or extra trailing inset after the final icon |
| Outer geometry | 4 dp vertical spacing around expanded details; full available width aligned with the activity's leading icon |
| Surface and separators | Shared Studio raised/content surfaces, card corners and thin section rules across every family |
| Typography | Shared label style for headings/quiet facts, Roboto body for explanations, monospace for code, commands, paths, source and console output |
| Ordinary completion | Completed with the same muted color and outlined check icon, including backend-confirmed success |
| Exceptions and result context | Explicit errors/warnings carry semantic accents; reported diffs retain +/- markers and colors; supplied exit codes and image receipts stay quiet context |

The current implementation uses a shared **160 dp maximum inline text viewport**.
This is a changeable implementation default, not an owner-approved immutable
value. Short text uses its natural height; all received text remains available
by scrolling. Keep the single viewport within the shared 8 dp framing, with
no separate Preview or expansion footer. Keep code/table horizontal scrolling
local while prose and surrounding controls reflow. Preserve explicit server
truncation and partial-file facts. A useful-only eye supplies a fuller view
when the inline content overflows.

Shared framing belongs to `ActivityDetailsCard`, `ActivityDetailContent`,
`ActivityDetailSection`, `ActivityDetailStatus` and `ActivityDetailAction` in
[the activity renderer](../lib/core/widgets/tool_activity_details.dart).
`ToolActivityDetailsView` composes facts within that frame. Extend these owners
rather than styling each family independently. Measure visible text/icon edges
as well as widget bounds: matching Padding values alone does not establish
matching appearance. Align the image's actual leading edge with text content.

Use hierarchy, spacing and proximity before introducing another font family.
Render authored Markdown where headings, lists, links, tables and code fences
help understanding. Keep literal payloads exact for selection/copy, and use
tabular figures for comparable counts/timings. A font change needs actual phone
comparisons of punctuation and ambiguous characters. Color remains a secondary
cue alongside readable statuses, glyphs and literal diff markers.

### Family acceptance procedure

For each Activity design change, complete the skill's decision/render process
before claiming completion or uniformity:

1. Build a decision table for **every affected family, received field and
   candidate action**. State its user signal/value, main/metadata/Raw placement,
   exact action scope and eligibility. Account for empty, short, overflowing,
   partial and failed states, including intentionally omitted actions. Compare
   at least two plausible arrangements internally before selecting one.
2. Give shared framing one production owner and implement the selected table.
   Inspect nested renderers and inherited defaults, including all four visible
   insets, image alignment, font roles, toolbar geometry and footer wording,
   icon/color. Content paragraph/list spacing is distinct from shared framing.
3. For a reported inconsistency, reproduce the actual symptom with a focused
   family-level regression when feasible. Check the relevant geometry, colors,
   action eligibility and exact payload behavior. A left coordinate alone is
   partial evidence; retain loading, failures and recovery in the review.
4. Compare actual affected family members together at ordinary phone size in
   **both themes**, then at **320 dp/200% text in both themes**. Include long
   metadata, short and overflowing content, resources, errors and partial data.
   Verify the served preview bytes match the newly generated captures and that
   comparison layouts do not resize members unevenly or overflow. Test icon
   reachability, payload copy and useful viewer opening where applicable.
5. Record the specific field/action decisions and rendered properties checked,
   with remaining discrepancies or unverified states. Test counts, skill usage,
   token usage and one isolated screenshot do not establish design quality or
   family acceptance. Contrast and assistive-technology behavior require their
   own checks; captures alone do not establish accessibility conformance.
   A renewed owner report reopens acceptance; investigate the reported state.
