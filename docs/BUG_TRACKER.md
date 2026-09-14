# Bug tracker

GitHub issues were enabled for this fork on 15 September 2026. These issues track the defects and reliability gaps documented in the current release review and backend acceptance records. Older dated reports also contain already completed fixes and unimplemented capabilities; those are not reopened as current defects.

| ID | GitHub issue | Status at this cleanup |
| --- | --- | --- |
| R1 | [Prevent dashboard redirects from forwarding session credentials](https://github.com/tarkilhk/hermes-android/issues/15) | Fixed in source |
| B2 | [Prevent queued attachments from being consumed by an unacknowledged send](https://github.com/tarkilhk/hermes-android/issues/16) | Fixed in source |
| B1 | [Persist normal-send uncertainty before dispatch so process death cannot restore a misleading draft](https://github.com/tarkilhk/hermes-android/issues/17) | Open |
| R2 | [Bound dashboard discovery and download requests with cancellation and deadlines](https://github.com/tarkilhk/hermes-android/issues/18) | Open |
| HUP-001 | [[Backend] Browser and vault target different tabs](https://github.com/tarkilhk/hermes-android/issues/19) | Open |
| HUP-002 | [[Backend] Non-default profile loop command/control mismatch](https://github.com/tarkilhk/hermes-android/issues/20) | Open |
| HUP-003 | [[Backend] Global activity omits child-only work](https://github.com/tarkilhk/hermes-android/issues/21) | Open |
| HUP-004 | [[Backend] Windows profile deletion fails after MCP activity](https://github.com/tarkilhk/hermes-android/issues/22) | Open |
| N1 | [Connected-app notifications can miss turns between status snapshots](https://github.com/tarkilhk/hermes-android/issues/23) | Open |

The credential redirect and queued attachment fixes passed regression tests in this checkout. Their issues link to the commit that integrates the fixes. This record does not claim a published release.

Backend issues are tracked here for their effect on Android. HUP-004 also has an existing upstream report and proposed fix; this cleanup did not post to upstream or modify the installed backend. See [Upstream Hermes bugs](UPSTREAM_HERMES_BUGS.md) for recorded versions and closure criteria.

[Known limitations](KNOWN_LIMITATIONS.md) gives user-facing workarounds. [The cleanup record](DOCUMENTATION_CLEANUP_2026-09-15.md) lists completed documentation and privacy work. Missing Play hosting/declarations are release tasks, not additional runtime bugs.
