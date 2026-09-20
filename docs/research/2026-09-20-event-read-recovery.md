# Recover failed observations on focus and network return

Inspected stock upstream Hermes main on 2026-09-20 at
`e787529064152e690b5d5678bd2efe761dda6213` before implementation.
All changes are in Wing; no backend changes or compatibility paths are required.

## Stock contracts

- [Provider OAuth status](https://github.com/NousResearch/hermes-agent/blob/e787529064152e690b5d5678bd2efe761dda6213/hermes_cli/web_routers/oauth.py#L751)
  is a GET of worker-maintained session state. It validates the provider and
  canonical profile; missing/expired sessions return 404. Reading it on browser
  return does not start a flow or exchange a code. The existing scheduled
  polling interval is retained, and an event-triggered check replaces the
  scheduled check rather than creating a second polling chain.
- [MCP OAuth status](https://github.com/NousResearch/hermes-agent/blob/e787529064152e690b5d5678bd2efe761dda6213/tui_gateway/mcp_oauth_sessions.py#L228)
  reads the existing flow snapshot and returns pending, approved or error.
  Callback delivery and cancellation are separate operations and are never
  replayed by recovery.
- [Analytics](https://github.com/NousResearch/hermes-agent/blob/e787529064152e690b5d5678bd2efe761dda6213/hermes_cli/web_routers/analytics.py)
  provides independent GETs for model totals and daily usage. Recovery can
  retain one successful aggregate while retrying the failed one.
- [Skills](https://github.com/NousResearch/hermes-agent/blob/e787529064152e690b5d5678bd2efe761dda6213/hermes_cli/web_routers/skills.py)
  and [connector inventory](https://github.com/NousResearch/hermes-agent/blob/e787529064152e690b5d5678bd2efe761dda6213/hermes_cli/web_routers/mcp.py#L94)
  use the existing profile-scoped observation APIs. The shared administration
  loader's callbacks are reads (including `plugins.manage` with action `list`).
  Saving settings, testing connectors, and running diagnostics are separate
  user actions.

## Client design

`ReadRecovery` is a wrapper with three inputs: whether a read needs another
attempt, the read callback, and its child. It owns Flutter app lifecycle, route
return and the app's shared Android network-available signal. It only acts on
an active, current route, coalesces events before the next frame, and allows one
recovery callback at a time. Disposal detaches listeners. Initial loads remain
owned by each screen. The wrapper introduces no recurring timer and does not
retry just because a failed widget rebuilt.

Screens retain their existing error presentation and manual retry. The existing
`isTemporaryWorkspaceFailure` classifier determines whether failed observations
can recover automatically. Authentication, certificate, malformed-response and
missing-resource failures remain explicit. Pending valid OAuth sessions can be
checked on return even without a prior failure; terminal sessions stop polling.

Applied in five areas:

1. `AdminLoad` retries temporary loading failures. Stable content keys preserve
   mounted editors and unsaved text when loading/error indicators change.
2. Provider and MCP sign-in recover status polling for the same session. Start,
   callback delivery and cancellation are never automatically replayed.
3. Chat browser recovery fetches only failed profiles and failed searches for
   the current query. Successful results remain visible. Existing generation
   checks reject results from a superseded query or archive scope.
4. Chat outputs retry the failed history page (or the failed explicit refresh),
   retaining loaded outputs and pagination position. Recovery never previews,
   downloads, opens or shares a file.
5. Analytics retries only failed aggregates for the visible period and failed
   activity-year reads. Rejected yearly futures are removed from the cache;
   successful yearly reads remain shared. Selecting a previously failed period
   also gives its failed reads another attempt.

Regression coverage: `read_recovery_test.dart`, `event_read_recovery_test.dart`,
`chat_browser_data_test.dart`, and `usage_analytics_test.dart`, alongside the
existing OAuth, administration, browser and outputs suites.

## Validation

- Full Flutter suite: 2,604 passed, 12 skipped.
- Focused final OAuth/event suite: 22 passed.
- Static analysis of all 16 changed Dart files: no issues.
- Existing analytics render checks: four theme/text-size combinations passed;
  inspected generated phone screenshots in light/dark at 1× and 2× text.
