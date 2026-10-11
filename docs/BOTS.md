# Bots

Open **Bots** from Wing's side menu to browse profiles from your saved Hermes instances. Bots and Groups have separate tabs and search. Pinned entries lead the list. Names and message previews sit on the left, with saved artwork on the right. The floating + creates a bot or group for the selected tab. Lists refresh automatically while visible.

Tap a bot's avatar to edit its appearance. Tap its name or message preview to open its continuing **Bot Chat**. Back returns to the same tab and search. Bot Chats use the usual conversation screen, showing its saved avatar to the left of its display name when available.

Explicitly selected classic shapes blink and move in the Bots roster and the
open Bot Chat header, with stronger motion and dots while working. Pictures
and avatars without an explicit saved shape choice stay still. Select a shape
in the appearance editor—even the currently displayed shape—to save that
choice in Hermes and enable its animation. Motion respects reduced motion and
pauses when hidden or backgrounded. Recents previews and message avatars stay
static.

Bot Chats stay hidden from the default Chats list. Enable **Show automated chats** in Chats to reveal them, or open them directly through Bots. Displayed Bot Chats show a small version of the bot's avatar before their name. Other conversations retain their saved titles.

## Profile options

The row menu offers View screen, Pin to top/Unpin, Hide bot/Show bot and **Bot settings**. The roster menu offers Show hidden bots. Bot pins and appearance synchronize through Hermes; group pins are saved on this device.

Bot settings contains appearance, configuration editors, Duplicate bot and profile management. The display name is separate from the underlying profile name. The default profile can change its display name but cannot be deleted or have its underlying identity renamed.

Creating a bot uses the instance's launch credentials and model defaults, as explained before creation. Duplication excludes channel bindings to avoid taking over messaging channels. Settings always apply to the chosen instance/profile, without switching the currently selected chat.

Recents cards show each canonical bot chat's saved name on the left and avatar
on the right before you open it. Group discussions appear in the same last-message
order, with their room artwork or member avatars. Unread replies show a green
New answer dot; reading the latest visible discussion messages clears that cue. Appearance is prepared while the cards are still and shared with the
chat header; opening a card is not required to identify its bot.

Appearance supports a display name, eight shapes, twelve profile hues, automatic color, image upload/removal and generation through that profile's configured image provider. PNG, JPEG and WebP uploads must fit the 2,000,000-byte avatar limit.

Valid edits save automatically after a short pause. Back finishes pending saves; if saving fails, choose Keep editing or Discard. **Reload saved appearance** keeps edited fields while updating untouched ones. A conflict with another client's changes keeps your draft and asks you to reload/review before retrying. Choosing a shape after an uploaded image clears the image.

## Discussion groups

Create a hosted **Discussion** with 2–6 bots from one ready instance. Hermes runs the discussion and can continue while Wing is backgrounded. Type `@` anywhere in your message to choose a frozen room member or `@everyone`. Search by the bot's name or Hermes handle; selecting Pace inserts `@Pace`, while Wing retains its canonical Hermes identity. Members show their saved bot avatars when available; Everyone uses a group icon. Tap a group’s icon in the Groups roster to open its editor directly; tap its name or message area to open the discussion. Open **Edit group** from a group’s roster actions or the discussion’s options menu, including discussions opened from Recents, to change its name, icon color or picture. Upload, generate or remove the picture, then use the checkmark to save to Hermes. Membership and the Hermes instance are fixed when created. Rooms also offer stop and disband.

In an ordinary chat, `@` anywhere in your message offers agents from the same Hermes server with their
saved bot avatars when available. Search also matches saved bot titles; selection
inserts the readable name. Names with spaces use quoted editable text. Duplicate
names include a handle to distinguish them. Commas, quotes and brackets delimit bot names;
hyphens and underscores remain part of the name. A mention
identifies the agent to the current conversation; it does not forward your
message or switch chats. Contact depends on whether the current chat has
`message_agent`. If a selected profile is removed or renamed before dispatch,
Wing pauses the message for correction. Changing its display name is harmless.

In chats and discussions, reference suggestions refresh after a brief pause in
typing (300 ms). The previous rows stay visible while the next results load,
keeping the composer steady. Select a row once the refresh finishes.

Tap member rows to add 2–6 bots. Picked bots move into their own strip above
search, with a remove icon for each. Search by name or @handle to find bots to
add; removing a picked bot returns it to the list. Leave the
name blank to use the selected bots' names, or enter a name of up to 64 characters.
Choose a Hermes instance when several are ready.

The default room icon uses the first letter of its name and a random color from
Hermes/Wing's usual color palette. The color stays fixed while you edit and is
saved on Hermes.

Upload a room picture, generate one from a description, or remove it. Generation
uses the chosen instance's default profile image provider. Uploads accept PNG,
JPEG and WebP up to 2 MB. Wing crops a 256 px square thumbnail and compresses it
to at most 45 KB for upload. Creating the group saves its picture on the chosen
Hermes backend; another Wing device connected to that backend can load it.
Removing a picture restores the letter icon. Icons appear in the group list and
conversation header. Desktop uses a
separate room format and does not currently display Wing's hosted-room pictures.

The bottom dock previews your room and keeps Create group above the keyboard.
Creation becomes available with at least two members. If it cannot be confirmed,
the form fixes the room details so you can retry the same group.

An unconfirmed send stays available for review/retry. Interrupted tasks ask for explicit confirmation before retrying. Approvals apply to the request shown in that discussion.

Your bubbles show User and an icon-only Copy aligned in the header. Bot replies
show the sender's saved avatar and name, formatted text, links, code and
timestamps, with Copy in the same header. Type `@` in the composer to choose a
member; the picker inserts at the cursor. The conversation opens
at its latest messages; scrolling up keeps your place as replies arrive. The down
arrow returns to the latest messages with the same motion as normal chats.

Tap the instance and bot count under the title for a compact member list
anchored beneath that row, with saved names and avatars. Tap outside or use Back
to dismiss it. The conversation uses a group icon when no picture is saved.
The ellipsis menu contains Edit group, working histories, Refresh and Stop.
Refresh rereads messages, activity and approval state; it does not restart the bots. Wing also
refreshes this state automatically. Recognized bot mentions display as bold,
colored `@Name` text. Copy preserves the original message.
While work is active, the empty composer offers Stop; entering a draft offers
Send. A compact status above the composer shows sending, loading, work or
approval needs. Hermes currently exposes group activity rather than individual
bots typing, so Wing displays “Bots are working…”.

Internal group workers stay out of the default Chats list and chat notifications,
so they do not produce `Group: <UUID>` alerts, including after opening a worker
from an earlier notification. Replies to bot-to-bot messages in Bot Chat are also
silent; replies to your own messages still notify you. Read group replies and
answer approvals in the discussion. Wing does not currently send a separate
group notification.
On Android 12 and later, the group transcript supports system scroll capture;
the composer and keyboard are outside the capture area, and capture restores
your reading position.

## Bot screen

Choose **View screen** from a bot’s row menu to watch its live desktop. The bot
needs a supported Linux host with the Hermes Bot Screen components installed.
Start/stop controls target the selected bot; stopping is unavailable while a
human holds control.

Use the control icon in the floating bar to take control. If another device has
control, Wing asks before replacing it. Trackpad mode lets you move one finger
to position the pointer, tap to click, and hold then move to drag. Pinch to zoom;
move two fingers together to scroll. The controls tray also provides mouse
buttons, zoom buttons and Fit screen. Direct touch taps the target itself;
Move view pans without sending desktop input.

Turn the phone sideways to enter full screen automatically. Returning upright
restores the normal viewer; the fullscreen icon works in either orientation.
Exit fullscreen keeps your control. Use the bar's handle to dock it at the top
or bottom when it covers something you need.

Open the phone keyboard from the bar to type. The desktop keeps its magnification
and brings the last clicked point into the uncovered area; use Move view if the
caret has moved elsewhere. Text is cleared locally after sending. Extra controls
include Enter, Tab, Escape, Backspace, arrows and Ctrl/Alt/Shift. Selected modifiers
apply to each key and are released remotely after that key. Back closes the
keyboard first, then the controls tray or fullscreen, before leaving the viewer.

Hand control back when finished, then tell the bot to continue. Closing the
screen hands back this phone’s control. If that cannot be confirmed, Wing keeps
the screen open for recovery. Backgrounding or losing the connection leaves
control held until you explicitly hand it back. If the controller belongs to
another connection or device, force hand-back asks for confirmation.

Wing does not currently configure RoomLink peer groups, desktop Direct
conversations, pet avatars or automatic screen opening. Hosted groups use bots
from one instance, although the bot roster and ordinary settings work across
saved instances.

See [Administration](ADMINISTRATION.md) for profile configuration and [Chats](CHATS.md) for conversation actions.

Messages from other bots appear on the left with their name, avatar when available,
formatted text and time. Copy copies the message body. Replies from the bot you
are talking to stay visible as normal answers. Received bot instructions cannot
be edited or restored as your own prompts.

In Activity, **Message agent** shows the sent **Message** and its **Queued**
acknowledgment. When Hermes returns the matching delivery result, Wing appends
**Exchange complete** with the reply below it. Each available timestamp appears
on the right in your local time. Queued means handed off, not delivered.
Pending, unknown and failed outcomes retain their own labels; avoid resending
when the outcome is uncertain. Raw details keeps the exact receipts.

An unmatched “Bot delivery process finished” notice stays separate. Expand
Output to inspect the runner's command and result.

### Bot working histories

Internal group-worker sessions stay out of Recents and ordinary chat notifications.
To inspect one, open the group, choose **⋯ → Bot working histories**, then select
a bot. The viewer is read only: it loads saved messages without starting a bot
turn. It uses the normal chat transcript, including reasoning and tool sections,
automatic older-page loading and the latest-message arrow. Refresh rereads the
saved history. Back returns to the shared group
and preserves your draft. Send group messages from the group composer.

If no current worker history is available, the viewer says so. A failed read
shows an error with Refresh; it does not claim the history is empty.
