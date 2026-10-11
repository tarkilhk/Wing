# Bots

Open **Bots** from Wing's side menu to browse profiles from your saved Hermes instances. Bots and Groups have separate tabs and search. Filter bots by Working or Needs input; pinned entries lead the list. The floating + creates a bot or group for the selected tab. Lists refresh automatically while visible.

Tap a bot's avatar to edit its appearance. Tap its name or message preview to open its continuing **Bot Chat**. Back returns to the same tab, search and filter. Bot Chats use the usual conversation screen, showing its saved avatar to the left of its display name when available.

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

Recents cards show each canonical bot chat's saved name and avatar before you
open it. Appearance is prepared while the cards are still and shared with the
chat header; opening a card is not required to identify its bot.

Appearance supports a display name, eight shapes, twelve profile hues, automatic color, image upload/removal and generation through that profile's configured image provider. PNG, JPEG and WebP uploads must fit the 2,000,000-byte avatar limit.

Valid edits save automatically after a short pause. Back finishes pending saves; if saving fails, choose Keep editing or Discard. **Reload saved appearance** keeps edited fields while updating untouched ones. A conflict with another client's changes keeps your draft and asks you to reload/review before retrying. Choosing a shape after an uploaded image clears the image.

## Discussion groups

Create a hosted **Discussion** with 2–6 bots from one ready instance. Hermes runs the discussion and can continue while Wing is backgrounded. Type `@` to choose a frozen room member or `@everyone`. Members show their saved bot avatars when available; Everyone uses a group icon. Rooms offer rename, stop and disband; their member roster is fixed when created.

In an ordinary chat, `@` offers agents from the same Hermes server. A mention
identifies the agent to the current conversation; it does not forward your
message or switch chats. Contact depends on whether the current chat has
`message_agent`. If a selected profile is removed or renamed before dispatch,
Wing pauses the message for correction. Changing its display name is harmless.

An unconfirmed send stays available for review/retry. Interrupted tasks ask for explicit confirmation before retrying. Approvals apply to the request shown in that discussion.

## Screen preview and limits

View screen periodically refreshes the selected profile's screen while visible. Start/stop controls target that profile. When a human controls the screen, Hermes suppresses preview frames and Wing clears the previous image.

Screen preview is read-only; it has no keyboard or pointer control. Wing does not currently configure RoomLink peer groups, desktop Direct conversations, pet avatars or automatic screen opening. Hosted groups use bots from one instance, although the bot roster and ordinary settings work across saved instances.

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
