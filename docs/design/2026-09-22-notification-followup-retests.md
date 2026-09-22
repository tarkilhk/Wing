# Focused notification follow-up retests

These are the two live cases to run **after the fixes are validated and installed**.
Build **2327** is validated and installed on the phone (Android version code
23272). These address the partial and failed runs in the
[22 September results](2026-09-22-notification-retest-results.md), without repeating
all five cases. Automated/native evidence is in the
[fix record](2026-09-22-notification-followup-fixes.md). Both live cases are finished: **A failed; B partially passed** (restoration
passed, read clearing failed). See the [live results](2026-09-22-notification-followup-live-results.md).
The steps below remain the reproductions for the next fixes.

The user operates the same Hermes desktop chat. Codex operates Wing and records
native notification state. Show desktop prompts directly in the conversation.
If a desktop decision is needed, give an explicit **NOW** cue in the conversation;
do not rely solely on a question card. The structured request timed out after
five minutes in the earlier runs, so finish its phone interaction promptly.

## A — Useful input notification before opening the chat

1. With no test request pending and prior results read/dismissed, force-stop and
   relaunch Wing. Reconnect on the owning chat list. **Do not open the test chat.**
2. Ask the user to send this in the same desktop chat:

   ```text
   WING-COLD-INPUT: Sleep for 30 seconds using a terminal tool, then use one
   real stock structured clarification batch with three questions:
   environment (Preview/Production), color (Blue/Green), and output
   (Summary/Checklist). Wait for my answers. After all three, report the
   selected values briefly. If the real batch is unavailable, report BLOCKED.
   ```

3. Confirm Watching starts and background Wing before input arrives.
4. Before opening the chat, require one notification containing **3 questions**,
   the actual first question/choices, and Review. Generic “Open the chat to
   continue” is a failure when the current structured request is available.
5. Tap Review; answer Preview, Blue, Summary promptly on the phone. Capture
   3 → 2 → 1 and the final resolution. Do not spend the request window navigating
   settings; preview privacy is covered independently in automated/native checks.

## B — Restore an unread reply after force-stop/relaunch

1. Return to the connected chat list. Ask the user to send:

   ```text
   Sleep for 30 seconds using a terminal tool, then reply exactly:
   WING-RESTORE-REPLY: The unread result is ready. Open Wing to read it.
   ```

2. Observe monitoring, background Wing, and capture the exact final reply notice.
   Leave it unread; record its chat notification ID.
3. Force-stop Wing, then relaunch to the chat list and allow reconnect. A notice
   need not remain visible while Android has the app force-stopped. On relaunch,
   require the **same reply and notification ID** to return without a fresh alert.
   Opening the app/list must not mark the result read or start extra monitoring.
4. Tap the restored notification. It must open the owning chat at the latest
   available answer under the agreed stock-Hermes rule. Reach the answer/bottom
   and verify clearing. Relaunch once more: the read notice must stay absent.
5. Automated/native checks separately cover explicit dismissal not resurrecting,
   current privacy/preferences, and stale input/races. If a live dismissal repeat
   is needed, generate a genuinely new result before swiping it; never add a
   manual Mark unread workflow or reuse a read result as if it were fresh.

## Record outcomes

Record installed build, genuine backend event, initial text/count/actions,
restored identity/content/alert flags, read/dismiss behavior, and watcher state.
Keep automated fixture passes separate from stock-Hermes live passes. Preserve
existing partial/failed labels until their exact live reproductions pass.
