# Bug tracker

These issues track documented client defects and backend reliability gaps. Status below was recorded on 15 September 2026; each linked issue is the current source of truth. Completed historical fixes and unimplemented capabilities are not reopened as new defects.

| ID | GitHub issue | Status at this cleanup |
| --- | --- | --- |
| R1 | [Prevent dashboard redirects from forwarding session credentials](https://github.com/tarkilhk/wing/issues/1) | Fixed in source |
| B2 | [Prevent queued attachments from being consumed by an unacknowledged send](https://github.com/tarkilhk/wing/issues/2) | Fixed in source |
| B1 | [Persist normal-send uncertainty before dispatch so process death cannot restore a misleading draft](https://github.com/tarkilhk/wing/issues/3) | Open |
| R2 | [Bound dashboard discovery and download requests with cancellation and deadlines](https://github.com/tarkilhk/wing/issues/4) | Open |
| HUP-001 | [[Backend] Browser and vault target different tabs](https://github.com/tarkilhk/wing/issues/5) | Open |
| HUP-002 | [[Backend] Non-default profile loop command/control mismatch](https://github.com/tarkilhk/wing/issues/6) | Open |
| HUP-003 | [[Backend] Global activity omits child-only work](https://github.com/tarkilhk/wing/issues/7) | Open |
| HUP-004 | [[Backend] Windows profile deletion fails after MCP activity](https://github.com/tarkilhk/wing/issues/8) | Open |
| N1 | [Connected-app notifications can miss turns between status snapshots](https://github.com/tarkilhk/wing/issues/9) | Open |

The credential redirect and queued attachment fixes passed regression tests in this checkout. Their issues link to the commit that integrates the fixes. This record does not claim a published release.

Backend issues are tracked here for their effect on Android. HUP-004 also has an existing upstream report and proposed fix; this cleanup did not post to upstream or modify the installed backend. See [Upstream Hermes bugs](UPSTREAM_HERMES_BUGS.md) for recorded versions and closure criteria.

[Known limitations](KNOWN_LIMITATIONS.md) gives user-facing workarounds. Missing Play hosting/declarations are release tasks, not additional runtime bugs.
