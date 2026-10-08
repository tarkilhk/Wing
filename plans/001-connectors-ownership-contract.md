# Profile connectors and MCP setup ownership

This slice targets current, unmodified Hermes at
`55bea1ddf1754dcacb87f13185df1eb1273c0a6e`. The seven inspected sources are
byte-identical to the earlier `8d5e3e412138342e8bf30443e72bd4e6a9abd057`
inspection. Private retained source/provenance is
`/tmp/wing-connectors-upstream-55bea/provenance.json`; this is source research,
not evidence from a deployed backend.

| Official source | Retained UTF-8 SHA-256 |
| --- | --- |
| [MCP HTTP routes](https://github.com/NousResearch/hermes-agent/blob/55bea1ddf1754dcacb87f13185df1eb1273c0a6e/hermes_cli/web_routers/mcp.py) | `abf6e113d59099a467131f11b2b173eb95fd0be453fea9256cc939a17e4f26ef` |
| [HTTP request models](https://github.com/NousResearch/hermes-agent/blob/55bea1ddf1754dcacb87f13185df1eb1273c0a6e/hermes_cli/web_models.py) | `d8473c2e03b596133db350cf2b83f9a1c824dc50c846153a27afca3b00bfa757` |
| [RPC methods](https://github.com/NousResearch/hermes-agent/blob/55bea1ddf1754dcacb87f13185df1eb1273c0a6e/tui_gateway/methods_tools.py) | `fa3f58c9dfa2bda293460a10b6ec14ac6626ca927d78b5f04bebda48717ce0e0` |
| [RPC summaries](https://github.com/NousResearch/hermes-agent/blob/55bea1ddf1754dcacb87f13185df1eb1273c0a6e/tui_gateway/mcp_rpc_helpers.py) | `d342e741349c6d025d324a627e5be8a3bf35edc9d5befc6e26688da5b7c4f633` |
| [HTTP summaries](https://github.com/NousResearch/hermes-agent/blob/55bea1ddf1754dcacb87f13185df1eb1273c0a6e/hermes_cli/web_server_mcp.py) | `9cb49f7059c12e7c275cd0b9d477ae6198c52449ec76660aedb7329d77d129e7` |
| [Credential HTTP routes](https://github.com/NousResearch/hermes-agent/blob/55bea1ddf1754dcacb87f13185df1eb1273c0a6e/hermes_cli/web_routers/config_env.py) | `94883d53aaa8096cb4bf3c9d619369b6e522db5153fb2fe911742aa54bc94d7f` |
| [Credential lifecycle](https://github.com/NousResearch/hermes-agent/blob/55bea1ddf1754dcacb87f13185df1eb1273c0a6e/hermes_cli/credential_lifecycle.py) | `1f7cbdf1e6be3468eeb1c35e25e9b8478be310f1e50ec470785e596e89a505ba` |

## One owner for each fact

`ProfileConnectorsSession` owns the captured profile inventory, command
admission, test observation, read validity, pending read intent, and process-wide
reload confirmation. Immutable observations contain summaries and tools, never
raw connector configuration or credentials. An issued detail route borrows that
inventory while it remains live. Every explicit picker replacement whose
matching inventory retired constructs a fresh inventory for that selected profile; it cannot carry an A observation into B. Releasing the child
revokes its unsent command while an already dispatched operation can settle.

`McpSetupSession` owns one provisioning draft and its validation. Text editing
controllers forward raw input; the owner interprets argument lines, headers,
credential names, authentication, callback addresses and certificate paths.
`McpOAuth` remains the sole PKCE/callback/poll/cancel owner with private mutable
facts and read-only observations. No second OAuth flow writer was introduced.

`admin_connector_routes.dart` supplies the required captured factories and
explicit picker navigation. The list and detail/setup/sign-in libraries render
typed observations and supply dialogs, browser launch, clipboard and navigation.
The moved `admin_plugins_page.dart` retains its existing mixed plugin workflow;
that workflow is not claimed complete by this extraction.

| Trigger | Owner transition and authoritative fact |
| --- | --- |
| Read inventory | Reserve reading generation, decode one current summary schema, publish a frozen list only after a valid read. Malformed/failed reads retain history and block edits until a fresh valid observation. |
| Enable/remove/test | Reserve confirmation/admission before notifying; re-read membership and revalidate the captured profile; require route authority immediately before owned HTTP delivery. Test is an observed probe, not a configuration ACK. |
| Enable/remove ACK | Validate the exact ACK, retain the saved/removed fact, then independently read current inventory. A failed readback cannot convert an ACK into an unconfirmed mutation or authorize replay. |
| Unknown setting outcome | Retain history and require an explicit read before another setting command. No automatic mutation retries. |
| Add connector | Validate the frozen draft before I/O, check fresh profile/list membership, provision generated profile credential keys, then send the rich stock RPC create with a final physical dispatch fence. |
| Partial provisioning | Credential writes and create are separate operations. Unconfirmed delivery blocks resubmission in that editor and offers return to the list; no invented transaction, cleanup or automatic replay. |
| OAuth/retirement | Own phone loopback and flow state; fence unsent RPC after connection awaits, retain admitted server work through settlement/cancel, retire notifications immediately and close the listener. |
| Reconnect | Explicit server-wide confirmation, one process-wide `reload.mcp` without `profile`, and a final captured authority callback. Timeout/connection loss remains honestly unconfirmed; a later explicit confirmation is a new user request. |

HTTP create's stock model cannot carry custom headers, registered OAuth client
settings or TLS paths. The existing `mcp.servers.add` RPC supports those current
fields; it is the selected current interface, not a compatibility fallback.
Credential PUT requires `ok:true` and the exact generated key. RPC create
requires `ok:true`, exact name and a valid stock summary. Plugin-provided
connectors remain read-only where current stock refuses edits/removal/sign-in.
Supported zero-tool successful probes remain successful. No prompt/resource
count UI has been added.

Stock does not provide a client CAS, idempotency token or atomic span covering
preflight, multiple credential writes and connector create. Fresh reads and
captured authority do not close cross-client races. The client does not claim
that a failed credential/create sequence was rolled back or erase generated
keys it cannot safely prove unused.

## Subtraction and prevention

Removed the view's raw list/probe/config maps, enabled-write/readback workflow,
setup normalization/credential provisioning and reload RPC workflow.
`McpSetup.save` and `McpSetupUnconfirmed` are removed; setup writes require the
captured editor session. The reload button's state class is removed. Public OAuth
facts now have private backing and read-only getters; raw `McpOAuth.profile` is
removed. Plugin declarations moved with their real parent imports, without
re-exports. No persistent journal or new cache/format was added.

The finite prevention property is absence of declared canonical
`administration_repository.dart`/`profile_gateway.dart` namespaces in the two
completed view libraries and their actual parts/export namespace. Actual raw
composition and the unfinished plugin module are outside that property.
The existing small view dependency checker can enforce this; it cannot prove
physical dispatch order, partial outcomes, lease settlement or widget geometry.

Focused behavioral coverage keeps the existing MCP setup/OAuth/editor/picker
assertions and adds three public owner cases in
`test/profile_connectors_session_test.dart`: ACK plus malformed readback without
duplicate delivery; child retirement while physical admission is held; and
setup retirement after held membership while the parent remains usable.
Existing fixtures now return the inspected stock summaries rather than partial
invented records. Source-only successor handoff is not a test/render acceptance
claim; root owns focused validation and Studio render review.
