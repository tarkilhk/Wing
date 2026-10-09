# Bots

Open **Bots** from Wing's side menu. The screen lists profiles from every saved
Hermes instance as bots, with Bots and Groups tabs. Search either roster; filter
bots by Working or Needs input. Pins lead the same list and show a pin glyph.
Bot pins and appearance synchronize through profile metadata. Group pins are
device preferences, as in desktop's room records. The floating + creates a bot
or group for the selected tab. Both rosters update automatically on entry,
every eight seconds while visible, and after actions. There is no manual
refresh control or pull-to-refresh gesture.

Tap a bot's avatar to edit its name and appearance directly. Tap its name or
message area to open its continuing **Bot Chat**. Its truncated preview comes from
that same chat, rather than a scheduled task or another recent conversation.
Back returns to the preserved Bots tab, search and filter. Another saved
instance opens through Wing's secure workspace-entry flow; an edited or removed
connection cannot retarget an old row's request.

## Profile options

The row menu offers chat, screen preview, pin/unpin, hide/show, appearance,
profile settings, duplicate, recent session, rename and delete. Show hidden bots
is in the roster overflow. Default cannot be deleted. New bot and Duplicate
use stock profile creation; duplication excludes channel bindings to avoid
taking over messaging channels. Fresh profiles inherit the instance's launch
credentials/model defaults, as indicated before creation.

Appearance includes a display title, eight classic desktop shapes, twelve
profile hues, name-derived color, image upload/remove and generation through
the captured profile's configured image provider. PNG/JPEG/WebP images are
streamed through Wing's allocation preflight and limited to the stock
2,000,000-byte avatar limit. Valid edits save automatically after a short typing
pause; Back flushes pending edits before leaving. There is no confirmation tick.
Only actual user edits are sent, and edits made during a write are saved next.
Reload saved appearance rereads the name, shape, color and avatar, preserving
edited fields and adopting fresh untouched fields. Successful reload is silent.
A desktop metadata conflict keeps the draft and requires Reload/review, then an
explicit retry or another edit. Metadata and asset saves acknowledge separately,
so a retry does not resend an already-saved section. If pending edits cannot be
saved when leaving, the editor offers Keep editing or Discard.

**Profile settings** opens the existing role/SOUL, model/defaults, provider
accounts/credentials and skills/tools/library/hub/plugin editors for that
captured profile. A row's display title and its canonical profile name are
separate choices.

## Groups and screens

Create a hosted **Discussion** room with 2–6 profiles from one ready instance.
The gateway owns the discussion driver and can continue work while Wing is
backgrounded. Tap a member's @handle to insert a mention. Messages replay from
the room log; Wing does not synthesize replies from private bot chats. Retry of
an unconfirmed send retains its event ID and exact text for the open visit.
One-time approvals and denials carry the precise request/task/generation fence.
Interrupted tasks have an explicit retry confirmation. Rooms also offer rename,
stop and disband. Their roster is fixed when created.

Screen preview periodically reads stock `display.thumbnail` while visible.
Start/stop controls target the same profile. Hermes suppresses frames while a
human controls the screen, and Wing removes the previous frame in that state.

Current desktop differences: Wing does not yet configure RoomLink peer groups,
desktop's client-coordinated Direct conversations, pet avatars, automatic
screen opening, or live keyboard/pointer control. Screen preview is read-only.
The roster and standard profile settings work across saved instances; hosted
group creation is currently within one instance. These are client scope limits,
not missing custom backend endpoints.

## Ownership and verified upstream

Inspected stock upstream Hermes main
`5f045f842a60184748dda30acb9fecbd961cc18b` on 9 October 2026:
`tui_gateway/methods_profiles.py`, `methods_session.py`, `server.py`,
`methods_groups.py`, `hosted_room_driver.py`, `methods_display.py`,
`methods_images.py`, `gateway/hosted_rooms.py` and the desktop
`apps/desktop/src/plugins/hermes-bots` implementation. No backend modification,
plugin, custom endpoint, deployment upgrade or old-protocol fallback is added.

| Fact/action | Owner and admission |
| --- | --- |
| Saved-instance sources | `savedBotsSession` resolves current secure registry authority; commands retain exact instance identity |
| Roster and commands | `BotsSession` retains per-instance observations on read failure and fences stale publications/retired view commands |
| Wire parsing | `BotsRepository` validates current stock objects, profile ownership, revisions, monotonic log cursors and room authority |
| Continuing chat | Exact server-owned `Bot Chat` title; hidden/follow-profile-config creation, eager title materialization, re-list/adopt after a race |
| Working/input status | `session.active_list` has no profile field: prove unique ownership through hidden-inclusive profile search before attribution; ambiguity/read failure stays unknown |
| Appearance | `BotProfileEditSession` owns debounced serial autosaves, changed-field drafts, metadata CAS, silent reload/review and partial acknowledgements; Back flushes before disposing |
| Hosted discussions | `BotGroupSession` owns log replay, visible polling, exact frozen sends and fenced approval/recovery commands |
| Screen | `BotScreenSession` owns visible read-only frame polling and profile-scoped power actions |
| Presentation | Native views own navigation, text input, tab/filter/search and geometry; established settings editors retain their own save workflows |

The source and fixture checks establish the client contract. A live current
Hermes instance, configured image provider and physical Android device are still
needed to smoke-test provider generation and real display behavior.
