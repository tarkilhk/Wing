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

Bot conversations use the Chats screen and select Chats in the drawer. A
confirmed canonical conversation shows its bot name in the top bar. Assistant
messages use the shared transcript layout without repeated author names or
avatars. The bot title also applies when opened through Recents or a notification,
and to its current compression tip. Project controls remain below the title.
Other conversations retain their saved titles. While appearance is loading or
unavailable, the saved chat title remains.

As on desktop, hidden Bot Chats stay out of the default Chats list. Opening a bot
does not change that visibility. **Show automated chats** in Chat list options
reveals canonical Bot Chats across profiles; their rows prefix **Bot Chat** with
the bot icon. Bots remains the direct route to a continuing conversation.

## Profile options

The row menu offers View screen, Pin to top/Unpin, Hide bot/Show bot and
**Bot settings**. Show hidden bots remains in the roster overflow. Chat opens
from the name/message area; appearance opens from the avatar or Bot settings.
Recent conversations remain in Recents rather than the bot menu.

Bot settings puts appearance first, followed by the existing configuration
editors and Duplicate bot. Advanced contains Rename profile, which changes the
underlying profile name rather than the display title (the default profile
retains its identity and only its display name can change). Delete bot sits at the
bottom and retains the existing confirmation; default cannot be deleted.
After a confirmed rename/delete, returning from profile management closes the
old settings route so subsequent actions cannot target an obsolete profile.
New bot and Duplicate
use stock profile creation; duplication excludes channel bindings to avoid
taking over messaging channels. Fresh profiles inherit the instance's launch
credentials/model defaults, as indicated before creation.
Bot settings keeps the captured instance/profile throughout those editors;
opening it does not change the selected chat's profile or model.

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
so a retry does not resend an already-saved section. Each acknowledgement updates
the editor's immutable saved bot record without discarding later draft changes.
Returning to Bot settings carries that record; reopening appearance retains the
confirmed image or removal. Choosing a shape after a saved upload clears the
image. If pending edits cannot be saved when leaving, the editor offers Keep
editing or Discard.

**Bot settings** opens the existing role/SOUL, model/defaults, provider
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

Chat-list visibility was verified against stock upstream main
`a62979dc3601c9eae455bff5b35ba8f9bed0df30`:
[`methods_session.py`](https://github.com/NousResearch/hermes-agent/blob/a62979dc3601c9eae455bff5b35ba8f9bed0df30/tui_gateway/methods_session.py)
provides the exact `session.list` lookup with `title: "Bot Chat"` and
`include_hidden: true`, returning the canonical root and current `resolved_id`.
[`sessions.py`](https://github.com/NousResearch/hermes-agent/blob/a62979dc3601c9eae455bff5b35ba8f9bed0df30/hermes_cli/web_routers/sessions.py)
excludes hidden rows from paged listings, exposes exact hidden-inclusive metadata,
and omits hidden flags from search results. `ProfileGateway` reads root visibility
and current-tip accounting; `ChatBrowserData` supplements the canonical row only
when automated chats are enabled, deduplicates a retained tip, and verifies
search visibility through exact metadata when the paged list cannot establish it.
The list view receives a scalar canonical-bot marker rather than inferring identity
from a title. See [the regressions](TESTING.md#hidden-bot-chats).

The conversation header was verified against stock upstream main
`3637c512fc3211bdccb61b7140d09ac1018508ba` on 10 October 2026:
`tui_gateway/methods_profiles.py` supplies `canonical_session.id`, its
`resolved_id`, profile metadata and `profiles.get_asset`. `BotsSession` owns a
passive appearance read per displayed conversation; it does not start roster,
presence or group polling. The view validates the result against the displayed
conversation and supplies the top bar title, without
reloading on composer changes. Passive Recents pages borrow only matching
appearance. Leaving the destination clears the displayed appearance, so reopening
the same chat adopts newly saved appearance. The stock `Bot Chat` title remains
unchanged because Hermes uses it to identify the canonical root.

Inspected stock upstream Hermes main
`5f045f842a60184748dda30acb9fecbd961cc18b` on 9 October 2026:
`tui_gateway/methods_profiles.py`, `methods_session.py`, `server.py`,
`methods_groups.py`, `hosted_room_driver.py`, `methods_display.py`,
`methods_images.py`, `gateway/hosted_rooms.py` and the desktop
`apps/desktop/src/plugins/hermes-bots` implementation. No backend modification,
plugin, custom endpoint, deployment upgrade or old-protocol fallback is added.

Profile creation and hosted-room contracts were rechecked on 10 October 2026 at
stock upstream `dce1e9b37581dd62e480a9064dc04a709c2940d3`:
[`methods_profiles.py`](https://github.com/NousResearch/hermes-agent/blob/dce1e9b37581dd62e480a9064dc04a709c2940d3/tui_gateway/methods_profiles.py)
retains full/configuration clone selection, channel exclusion and launch-default
inheritance;
[`methods_groups.py`](https://github.com/NousResearch/hermes-agent/blob/dce1e9b37581dd62e480a9064dc04a709c2940d3/tui_gateway/methods_groups.py)
retains gateway-owned room creation, authority state and idempotent typed sends.

Live ownership was rechecked on 10 October 2026 at stock upstream
`0c4b0c283279ae0c91eff88526c4a6d4b60a8b9d` in
[`sessions.py`](https://github.com/NousResearch/hermes-agent/blob/0c4b0c283279ae0c91eff88526c4a6d4b60a8b9d/hermes_cli/web_routers/sessions.py).
Search resolves a compression ancestor to its current tip, so it cannot prove
ownership of an exact live session key. `BotsRepository` uses the profile-scoped
`ProfileGateway.sessionMetadata` read instead. It requires the requested session
ID and canonical profile in the returned row. Only a typed session-not-found
response for that endpoint establishes absence; transport failures, malformed
rows and missing profiles leave status unknown.

| Fact/action | Owner and admission |
| --- | --- |
| Saved-instance sources | `savedBotsSession` resolves current secure registry authority; commands retain exact instance identity |
| Roster and commands | `BotsSession` retains per-instance observations on read failure and fences stale publications/retired view commands |
| Wire parsing | `BotsRepository` validates current stock objects, profile ownership, revisions, monotonic log cursors and room authority |
| Continuing chat | Exact server-owned `Bot Chat` title; hidden/follow-profile-config creation, eager title materialization, re-list/adopt after a race |
| Working/input status | `session.active_list` has no profile field: exact `sessionMetadata` reads prove unique ownership in a canonical profile, including compression ancestors; ambiguity or unavailable ownership stays unknown |
| Appearance | `BotProfileEditSession` owns debounced serial autosaves, changed-field drafts, metadata CAS, silent reload/review and independent metadata/asset acknowledgements in the saved bot record; Back flushes before disposing |
| Hosted discussions | `BotGroupSession` owns log replay, visible polling, exact frozen sends and fenced approval/recovery commands |
| Screen | `BotScreenSession` owns visible read-only frame polling and profile-scoped power actions |
| Presentation | Native views own navigation, text input, tab/filter/search and geometry; established settings editors retain their own save workflows |

The [architecture map](ARCHITECTURE.md) locates these owners alongside the
existing administration and conversation boundaries. Source and fixture
verification follows [the testing policy](TESTING.md#verification-scope-and-stopping).

The source and fixture checks establish the client contract. A live current
Hermes instance, configured image provider and physical Android device are still
needed to smoke-test provider generation and real display behavior.
