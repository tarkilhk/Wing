# Chat notifications represent relevant state, not an event history

Wing will show one notification per scoped chat, prioritizing unresolved input
over newer results and advancing it as requests resolve. This trades an Android
history of individual events for a current, actionable notice, requiring explicit
tracking of pending input, unread results, and dismissal rather than simply
posting each event; the chat remains the place to read the full conversation.

Accepted in the notification design conversation on 20 September 2026; see the
[requirements](../design/2026-09-20-notification-improvements.md).
