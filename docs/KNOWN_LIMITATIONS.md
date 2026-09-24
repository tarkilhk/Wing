# Known limitations

Wing needs a current Hermes dashboard and Desktop Gateway. Older API-only/SSE setups are not supported. Some commands and controls depend on your Hermes server, provider or host environment.

## Connection and recovery

Wing keeps recent chats and unsent drafts available during interruptions and retries brief outages. If it does not reconnect, reopen the chat or tap **Retry**. Some dashboard requests and downloads can remain pending if the server stops responding ([issue #4](https://github.com/tarkilhk/Wing/issues/4)).

If Android closes just after a message reaches Hermes, its draft may reappear without a warning. Check chat history before sending it again. Wing does not resend it automatically ([issue #3](https://github.com/tarkilhk/Wing/issues/3)).

## Notifications

Background alerts need Wing to remain running; screen-off delivery may also require allowing background battery use. After a force-stop, process termination or reboot, reopen Wing. Very short turns in unopened chats can be missed ([issue #9](https://github.com/tarkilhk/Wing/issues/9)), and Hermes may omit child-only work from its global activity feed ([issue #7](https://github.com/tarkilhk/Wing/issues/7)).

## Storage and files

Recent messages are cached for reading, but Wing is not a complete offline archive. Configuration backups include connections and preferences, not chat history, drafts or queued prompts. Clearing app storage does not delete server history.

A draft supports up to 10 attachments and 64 MiB total; generic files are limited to 16 MiB each. Downloads are limited to 32 MiB, and interactive HTML previews to about one million characters. Your provider or server may impose smaller limits.

## Current scope

Wing does not offer a general remote filesystem browser, bot/group-chat or messaging/webhook administration, or synchronized older answer alternatives. Scheduled tasks are supported. [Explore Wing's features](FEATURES.md).
