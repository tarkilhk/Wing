# Goals and background work

Open **Goal** or **Background work** from a chat's menu. The conversation's
Activity **Work** tab also shows known goals, recurring work, and processes.
Hermes runs this work on the server; it does not depend on a phone scheduler.

## Goals and criteria

The goal view shows available status, progress, constraints, criteria, and
verification results. Use Pause, Resume, Resume now, or confirmed Clear when
available. Goal contracts and verification gates are read-only; this view does
not create goals.

Add a criterion, remove an item, or clear the criteria. Remove and Clear require
confirmation. If the list changes while confirmation is open, review the updated
list first. A failed addition keeps your text so you can review it.

Actions wait for Hermes' reply and preserve unsent text, attachments, and queued
messages. A failed or uncertain action is not automatically retried. Refresh and
check the current state before another attempt, especially if another client is
also changing the goal.

## Background work

Refresh to retrieve recurring-work status and current process output. Loops offer
Pause, Resume, and Stop. Heartbeats offer Pause, Resume, and confirmed Clear.
Running processes offer targeted Stop. Finished processes retain their available
output and can be dismissed for the current app session; dismissal does not
delete server history.

Process output is a limited recent tail, refreshed on request. Available details
include the command, working directory, state, uptime, and exit code when
supplied. Opening the view does not start work.

`/stop` interrupts the selected chat and stops its verified running processes.
`/interrupt` interrupts only the chat. If process status or a stop cannot be
confirmed, refresh before retrying.

Profile scheduled tasks and [Bots](BOTS.md) have separate management pages.
See [Known limitations](KNOWN_LIMITATIONS.md) for server-dependent behavior.
