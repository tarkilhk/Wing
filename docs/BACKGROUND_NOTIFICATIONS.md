# Local notifications

Hermes executes accepted work on the server. Android notification delivery is a separate client capability. This fork supports local completion and attention alerts while the app has a usable event connection. Android can suspend that connection or terminate the process. Firebase delivery was dropped from the selected scope; no compatible server sender/registration flow is verified.

## Settings and text

App settings has independent completion/input switches, optional chat titles and a permission/test action. Titles are off by default. Local messages use Finished working or Needs your attention, with the selected chat title or Tap to open the chat. The built-in test proves OS posting, not coverage of actual server work.

Avoid secrets, prompt contents and tool output in notifications. Follow [Privacy](../PRIVACY.md) for storage and optional title exposure.

## Event coverage

Loaded chats receive session events through their attached transport. The server's global `sessions.changed` broadcast is an empty, coalesced invalidation. Android uses it to reconcile status snapshots for connected targets; it does not treat it as a completion payload or attach every historical chat.

Establish a silent initial baseline, retain verified profile ownership and reconcile meaningful running/waiting/completed transitions. Unknown, disconnected or failed reads must not become completion alerts. Rapid turns can occur between snapshots, an idle transition can be missing, and a failed read can leave a gap. See [issue #23](https://github.com/tarkilhk/wing/issues/23).

Unopened child-only work also depends on the global backend contract described in [HUP-003](UPSTREAM_HERMES_BUGS.md#hup-003-global-activity-omits-child-only-work). Adding switches or passing a test notification does not close that gap.

## Tap routing

Each notification retains connection/profile/durable-chat identity. Stable IDs avoid unrelated replacement, startup navigation retries when initialization is incomplete, and stale connection credentials invalidate obsolete targets. A tap for the same open chat reuses its view; when several requests race, the newest tap wins.

Refresh server state when opening the chat. Notifications supplement that state and are not the durable record of a result or pending request. The unsent queue still needs a running, connected client to drain.

## Verification

Production-controller live-event tests, native permission/posting/tap tests and fixture reconciliation tests cover different boundaries. Recorded native tests establish posting and routing; they do not guarantee every background Android lifecycle or every server event. Use the relevant drivers listed in [Testing](TESTING.md) when notification behavior changes.
