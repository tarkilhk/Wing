# Chats and automated runs

Workspace options contains an **Include automated chats** switch, off by
default. The app remembers the setting per connection and applies it across
profiles. There is no filter bar above the chat list.

When off, the app excludes exactly `cron`, `tool`, `subagent`, and
`kanban`. Turning it on includes all sources. Unknown and custom sources remain
visible in either case. A parent session ID does not imply automation:
ordinary conversation branches remain visible.

Session listing and full-text search send the same source filters to Hermes,
before the server paginates. Refresh, archive browsing, and loading more rows
retain the selected filter. Changing it invalidates pending list and search
responses. Cached open chats retain their source so an automated run does not
return to Chats through the local cache. Running turns are not interrupted.

Project browsing applies the same visibility rule before paging its loaded
members. The current Hermes project RPC itself excludes cron/kanban and scans
at most 5,000 sessions. Enable the switch in the main profile list
to browse those runs. Activity continues to show background work.

The classification follows Hermes's own
[session recall source policy](https://github.com/NousResearch/hermes-agent/blob/c8aa5608c24e3636e77c267650c0f1f52e44adb0/tools/session_search_tool.py#L18)
and [session list/search API](https://github.com/NousResearch/hermes-agent/blob/c8aa5608c24e3636e77c267650c0f1f52e44adb0/hermes_cli/web_routers/sessions.py#L165).
Source labels describe provenance; old scripts using `cli` or `api_server`
cannot always be distinguished from conversations after the fact.

Personal build 2144 preserves the package `com.tarkilhk.hermes.android` and the
existing release signature. Its ARM64 split version code is 21442.
