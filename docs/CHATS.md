# Chats and active work

Wing helps you return to the right conversation and keep it moving from your phone.

## Find a conversation

Open **Chats** to search, pin and group conversations. Filter by profile, project or status; use **Recents** to find recent conversations and work that is running or needs input. The selected connection and profile determine what you see in Wing without changing another client's selection.

Tapping a chat in Recents opens its screen immediately; loading and any retry
stay there. Back returns to Recents even while the chat is loading.

You can open a visible chat while its profile or chat list is refreshing. Wing
opens the conversation and loads its history independently of that refresh.
Back returns to Chats while the conversation is still connecting.

Ongoing chats keep the desktop app's moving border around their row and a steady
status dot. With reduced motion, the border stays still. Opening the chat and its
actions remain available while Hermes works.

Inside a chat, tap the project name below the chat title to open the project
picker and move the chat. Tap the chat title to open **Rename chat**, or hold a
chat in the list and choose **Rename**. Type a name or tap the AI sparkle beside
the field to generate a suggestion from the conversation. Adjust it if needed,
then tap the checkmark to save. Generation and saving show progress in their
controls; errors keep your draft name available for retry. A new chat needs a
message before AI can suggest a name.

A canonical Bot Chat's avatar and name continue to open **Bot settings**.

Hidden conversations stay out of Chats by default, including a bot's continuing
**Bot Chat**, even after opening it from Bots. Tick **Show automated chats** in
Chat list options to include automated conversations and each profile's canonical
Bot Chat. A displayed canonical Bot Chat has a small version of the bot's avatar
before its name.
Search follows the same visibility choice.

## Send the next idea

Create a chat, choose a profile and send a message. Replies stream into the conversation with code, tables and available tool activity. Your draft and attached files stay in place if you navigate away.

While a reply streams, Activity contains tool calls. Reasoning appears directly
in the conversation between tool runs. The compact bar above your draft shows
subagents and completed/total tasks. Tap either side to open its drawer, then
swipe left or right to switch. Tap the selected tab or outside to close it.
Your draft stays in place. Past answers keep their existing Activity layout.

While Hermes is working, the composer can **Steer**, **Queue** or **Stop**. The default action is your choice in App settings; hold and slide the arrow for a one-time alternative. Queued follow-ups can be edited before they send and need Wing to be running and connected to drain.

The outbox above the composer appears whenever it contains queued messages.
Tap a message for Edit, Steer and Delete; hold it to edit directly. Steer accepts
text only and needs a connected active turn. Your separate draft stays in place.

## Revisit the result

Inside a chat or bot group, pinch inward to open the same conversations shown in **Recents**,
including bot groups. Cards follow message freshness: left is newer, right is
older, with the oldest and newest linked in a circle.
Unread cards carry the same quiet tint as the Recents list.
Soft edge ripples indicate replies or requests for input in other recent
conversations, including while you type with the keyboard open. Reduced motion
suppresses the ripples.
A two-finger horizontal swipe switches to the adjacent conversation directly, including
before the first pinch. Icon-only controls also
support keyboard and accessibility navigation. Opening a group shows its group
chat. Back closes the cards first. Back from a conversation opened through
Recents, a two-finger swipe or the card viewport returns to **Recents**, even
if you never opened Recents from the menu. Direct entry from **Chats** returns
to Chats; direct entry from **Bots** or **Groups** returns to Bots with its
selected tab and search intact.
When you return to
a conversation already loaded in this workspace, its retained messages appear
while Wing refreshes quietly from Hermes; new replies appear when the server
history arrives. If refresh fails,
the retained conversation stays readable with a retry notice. A conversation
without retained history still needs its initial server load, indicated by the
Wing pulse in the fixed header slot beside the instance details.

Sent messages have a compact footer with the date on the left and icon-only
Edit and Restore actions on the right. Copy sits outside the bubble at its
upper-right corner. Edit opens a correction; confirm **Replace and resend** to
replace that turn and all later history in an idle, connected chat. **Restore
checkpoint** reruns the saved prompt without editing it and can interrupt a
running turn after confirmation. Both preserve separate composer work and pause
queued follow-ups. Use **Find in chat** to search older messages, **Outputs** to
browse files, or the answer actions to regenerate or branch into another chat.
Model changes show Hermes warnings before you confirm them.

Copy actions throughout Wing write directly to the clipboard without a bottom
confirmation popup. Android may show its own clipboard confirmation.

[Explore Wing](FEATURES.md) · [Conversation details](CONVERSATION_ACTIONS_AND_READING.md)

## Questions and approvals

Questions and approvals use Wing's usual **Asked a question** Activity row.
Details start collapsed and show the question, any command, and its outcome in
the shared Activity card. Commands retain their exact source in the standard
code viewer with Copy, wrap and full-view controls. Approvals report Approved
or Rejected; these outcomes describe permission, not execution success.
Confirmed timeouts report Expired, withdrawals report Cancelled, and Closed
means the outcome is unknown.

Completed approval and secure-input entries stay where their requests first
appeared and move up as messages arrive. There is no dismiss control.
Ordinary clarification questions retain their native Activity receipt, including
choices and answers, without an additional history row. Secret response values
are never saved in request-history entries.
