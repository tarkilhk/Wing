# Usage redesign: stock API boundary

Inspected upstream main `c62bd9f2078a946108f1c9d9b24bf118963277ef` on
18 September 2026 before implementing the approved title-switching design.
The latest commit was resolved through GitHub's API; pinned source files were
downloaded into `/tmp/wing-usage-implementation-upstream` for read-only inspection.

## Available data

- `GET /api/analytics/models?days=N&profile=NAME` supplies period totals grouped
  by model/provider, including uncached input, cache reads and output. Existing
  Wing pricing can value `openai-codex` rows at published API rates. These totals
  can power the period breakdown by model and by token type. For other providers,
  Hermes supplies a combined stored cost, not its token-type cost components.
- `GET /api/analytics/usage?days=N&profile=NAME` supplies daily uncached input,
  cache reads, output and stored costs. These daily rows have no model/provider
  dimension. Daily totals read `sessions`; the period model summary additionally
  incorporates auxiliary usage. They are not the same coverage.
- Dates are UTC session-start dates, not the date each request executed. A
  long-running session contributes accumulated counts to its start date.
- Both analytics endpoints constrain `days` to `1..365`. There is no all-time
  option, start/end date filter, cursor or daily model grouping on these routes.

## Missing data for the accepted design

1. `ALL` history beyond 365 days.
2. Selected-day and trend breakdowns by model.
3. Daily API-equivalent costs: pricing mixed-model aggregates without their
   individual counts is not valid. Stored subscription costs are zero.
4. Cost composition by token type for paid providers whose API reports only a
   combined estimate.

The missing dimensions must not be synthesized by applying the period model mix
to every day, subtracting separately timed rolling-window queries, or assuming
zero cost means free usage. Unknown data must remain distinguishable from zero.

## Other stock interfaces inspected

The session detail route returns a session's counters, but the normal paged list
filters children/hidden sessions and projects compression chains; it is not a
complete enumeration equivalent to analytics. The gateway `session.list` is also
a human-facing filtered listing; `session.usage` concerns an individual session.
The gateway billing view concerns account/subscription credit balances, not the
historical analytics cube. Console insights is a human-readable CLI report, and
session export creates files and exports transcripts; neither is an established
bounded read API for this screen's daily/model aggregates.

No backend source, deployment, database, settings or credentials were changed.

## Performance

Read-only network probes located Claw's dashboard on port 9119. Its health
request took approximately 34ms from this development machine. The health
response declares authentication required. An unauthenticated client-work
analytics request returned HTTP 401, so this does **not** establish analytics
latency or phone-to-server performance.

For the available views, the implemented loading design is two aggregate reads in
parallel per selected period, retaining the last successful result during
refresh and reusing it for day/grouping/measure selection. Those local
interactions require no API request. Avoid an N-request session scrape to make
the mockup appear complete. Actual analytics latency remains unmeasured.

## Accepted implementation

The user removed ALL and approved implementation with 1D, 7D, 30D, 90D and
365D. Both chart titles default to models, as requested. Tapping a title changes
its grouping; Tokens/Cost controls are independent for each section. Daily model
and API-equivalent cost views explain the missing data and offer the supported
token-type view. Selecting a day keeps its scope when switching controls; it
never substitutes period-wide model figures for a day's values.

The calendar shows recorded tokens, with 91-day pages for the year view and no
day slider. Selecting the same date again, or All days, restores the period
breakdown. Duplicate auxiliary model rows contribute to one model/provider bar
segment and remain individually inspectable in its detail sheet. Unknown values
remain unavailable; partial cost bars explicitly exclude unpriced values.

A rolling N-day query can cover N+1 UTC dates. The partial first date is retained.
Period cache entries live only for the open profile/connection scope; Refresh
updates both aggregates. Older data survives individual refresh failures with
an explicit retained-data notice. Model palette assignments stay stable while
switching periods. Counts and pricing sources remain accessible from a model.

Reverified upstream main at the same inspected revision immediately before
implementation. No server changes or custom endpoints are required.

Sources at the inspected revision:

- https://github.com/NousResearch/hermes-agent/blob/c62bd9f2078a946108f1c9d9b24bf118963277ef/hermes_cli/web_routers/analytics.py
- https://github.com/NousResearch/hermes-agent/blob/c62bd9f2078a946108f1c9d9b24bf118963277ef/hermes_cli/web_routers/sessions.py
- https://github.com/NousResearch/hermes-agent/blob/c62bd9f2078a946108f1c9d9b24bf118963277ef/hermes_state_sessions.py
- https://github.com/NousResearch/hermes-agent/blob/c62bd9f2078a946108f1c9d9b24bf118963277ef/tui_gateway/contracts/sessions.py
- https://github.com/NousResearch/hermes-agent/blob/c62bd9f2078a946108f1c9d9b24bf118963277ef/hermes_cli/console_engine.py
