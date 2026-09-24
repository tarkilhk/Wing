# Bug tracker

These issues track documented client defects and backend reliability gaps. Status was checked on 24 September 2026; each linked issue is the current source of truth.

| ID | GitHub issue | Status on 24 September 2026 |
| --- | --- | --- |
| R1 | [Prevent dashboard redirects from forwarding session credentials](https://github.com/tarkilhk/Wing/issues/1) | Closed |
| B2 | [Prevent queued attachments from being consumed by an unacknowledged send](https://github.com/tarkilhk/Wing/issues/2) | Closed |
| B1 | [Persist normal-send uncertainty before dispatch so process death cannot restore a misleading draft](https://github.com/tarkilhk/Wing/issues/3) | Open |
| R2 | [Bound dashboard discovery and download requests with cancellation and deadlines](https://github.com/tarkilhk/Wing/issues/4) | Open; connection verification bounded, general dashboard transport/download deadlines remain |
| HUP-001 | [[Backend] Browser and vault target different tabs](https://github.com/tarkilhk/Wing/issues/5) | Open |
| HUP-002 | [[Backend] Non-default profile loop command/control mismatch](https://github.com/tarkilhk/Wing/issues/6) | Open |
| HUP-003 | [[Backend] Global activity omits child-only work](https://github.com/tarkilhk/Wing/issues/7) | Open |
| HUP-004 | [[Backend] Windows profile deletion fails after MCP activity](https://github.com/tarkilhk/Wing/issues/8) | Open |
| N1 | [Connected-app notifications can miss turns between status snapshots](https://github.com/tarkilhk/Wing/issues/9) | Open |

The credential redirect and queued attachment fixes passed regression tests. Their closed issues link to the commits that integrated them.

The new-connection probe now bounds each verification stage and closes provisional resources on timeout/cancellation. The older issue #4 description predates that change; the underlying `DashboardClient` still has unbounded operations. Network continuity also adds connection recovery and recent reading snapshots. It does not persist normal-send uncertainty before dispatch (#3) or recover every completion missed between global status snapshots (#9).

Backend issues are tracked here for their effect on Android. HUP-004 also has an existing upstream report and proposed fix; this cleanup did not post to upstream or modify the installed backend. See [Upstream Hermes bugs](UPSTREAM_HERMES_BUGS.md) for recorded versions and closure criteria.

[Good to know](KNOWN_LIMITATIONS.md) gives user-facing expectations. Missing Play hosting/declarations are release tasks, not additional runtime bugs.
