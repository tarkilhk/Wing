# Background notifications

Wing can keep watching connected work while you use other apps. Its ongoing Android notification shows a summary such as **Watching 3 chats · 2 working · 1 needs approval**. Replies and requests for input appear as separate chat alerts.

## Enable monitoring

1. Connect Hermes and allow Android notifications in **App settings → Notifications**.
2. Enable the reply or attention alerts you want. Monitoring starts automatically when a chat begins work while Wing is visible.
3. If Wing reports battery restrictions, choose **Allow background activity** and approve Android's exemption prompt.

There is no separate monitoring switch. Idle chats do not start monitoring. Monitoring uses additional battery and stops when the watched work finishes, after posting final alerts. Another working chat or live child task can keep it active. Disabling both alert categories or revoking notification permission stops it.

Android force-stop, process termination, reboot, connectivity loss and manufacturer restrictions can interrupt delivery. Reopen Wing after restarting your phone or terminating its process. Work started elsewhere cannot wake a stopped Wing app. Accepted Hermes work continues on the server.

## Choose alert content

Notification settings has independent reply and attention switches, **Show message previews**, and a permission/test action. **Test notification** checks Android posting, rather than delivery of real server events.

Alerts show their chat and connection/profile. Reply previews omit reasoning, code blocks, tool output and URLs. Turning previews off keeps the chat name and short status. Secure-input alerts use fixed text. Lock-screen visibility also depends on Android settings.

Unanswered requests take priority over unread results. When several requests are pending, they are shown in order. Dismissing a notification does not answer or deny the request.

## Answer approvals and open chats

Approval actions require unlocking the phone. Depending on the request, an alert offers Once, Session, Always or Deny. Session applies to matching commands for that session. Permanent approval opens a confirmation in Wing. Long or incomplete commands, or hidden previews, require review in the app.

The alert stays visible while an answer is being sent. A failure keeps the request available; changed or expired requests require reopening the chat for review.

Tap an individual alert to open its original chat. The ongoing monitoring notification opens Wing without selecting a chat; an Android group header is not an individual chat destination. Reading the latest answer in Wing clears that result's alert. Opening older history does not. If newer history has arrived, an older alert may open the latest available answer.

## Delivery limits

Wing monitors connected work and reconciles reported changes while it remains connected. It does not subscribe to every historical chat. Very short work in unopened chats, missing server events and child-only activity can leave alert gaps. Temporary disconnections retain drafts and recent reading, but do not guarantee replay of every missed outcome.

Opening a chat refreshes its server state. Notifications help you return to work; the conversation on Hermes remains the record to check. Unsent follow-ups still need a running, connected Wing client. See [Queues and pending input](SUPERVISION_AND_QUEUES.md).
