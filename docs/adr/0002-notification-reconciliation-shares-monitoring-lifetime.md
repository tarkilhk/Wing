# Notification reconciliation shares the existing monitoring lifetime

Periodic checks for remotely resolved requests run only while Wing's monitoring
watcher is already active; pending notifications never start or prolong it. This
deliberately accepts delayed cleanup after monitoring stops to avoid an additional
background lifetime and resource cost on the phone; normal reconnect/resume
reconciles current state.

Accepted in the notification interview, Q15; see the
[requirements](../design/2026-09-20-notification-improvements.md#follow-up-desktop-completion-and-synchronization).
