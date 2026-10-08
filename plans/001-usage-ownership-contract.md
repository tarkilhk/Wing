# Captured usage observation

`UsageAnalyticsSession` owns period admission, retained partial observations,
refresh, recovery and publication lifetime for one captured profile. Existing
`UsageAnalyticsReader` retains stock reads, pricing input and shared yearly-read
deduplication. There is one period cache, inside the session. The view owns only
calendar selection, chart presentation, colors and geometry.

Verified stock Hermes main
[`8d256ff1848a96cc41faa89b89dcd7926e8e7718`](https://github.com/NousResearch/hermes-agent/blob/8d256ff1848a96cc41faa89b89dcd7926e8e7718/hermes_cli/web_routers/analytics.py)
supplies profile-scoped `analytics/models` and `analytics/usage` reads with
`days` from 1 through 365. Server-local session-start dates and independent
aggregate failure semantics remain unchanged. No backend change or new codec.

The dashboard requires a captured session factory; actual analytics composition
creates the existing reader. Profile changes replace the owner through the
existing scope key. Consumer observations contain readonly copied collections
and typed model/token facts, never a mutable source row. Prior-period results
are retained under their issued period and cannot replace the selected period.
Retired owners start no new reads or publication and close no borrowed profile.

Verification uses the existing analytics, pricing, calendar, route and failed-read
recovery controls, plus the three public owner controls in
`test/usage_analytics_session_test.dart`. A small dependency rule protects removal
of raw profile/reader policy from the dashboard. Ordering, retirement and partial
recovery remain behavioral properties. Normal/enlarged both-theme actual render
inspection is required before final UI acceptance.
