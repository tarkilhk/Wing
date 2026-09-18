# Stock Hermes MCP authentication: research and Wing plan

Research date: 2026-09-18. Inspected upstream `NousResearch/hermes-agent` main at
[`d177b119e9c56c9ddc0b7379ffce52341ec06584`](https://github.com/NousResearch/hermes-agent/commit/d177b119e9c56c9ddc0b7379ffce52341ec06584), verified with `git ls-remote`.
This describes current stock source, not the version deployed at
`hermes.hollinger.asia`. No deployed server upgrade, backend modification, OAuth
registration, or authenticated Aspire request was performed. This research preceded implementation. See [MCP connector setup](MCP_CONNECTORS.md)
for the delivered client behavior and remaining live-provider validation.

## Finding

Wing can support several authentication methods entirely through stock Hermes,
but cannot offer every method as a native phone sign-in. The important boundary
is **what Hermes can do versus what its remote administration API exposes**.
Browser OAuth with a phone-local callback is already exposed; device code and
Hermes' built-in Client ID Metadata Document (CIMD) login are not equivalent
remote flows. Provider registration and callback policies remain external
constraints. The support matrix below is the implementation target, not a claim
that the current Wing UI already implements it.

## Support matrix

| Authentication / transport | Stock Hermes runtime or CLI | What Wing can offer with stock APIs |
|---|---|---|
| No authentication | URL-based Streamable HTTP/SSE; subprocess stdio | Configure, test, enable and reload. No sign-in. |
| Static bearer token | `headers.Authorization: Bearer …`, including secret references | Guided token entry through `mcp.servers.add` / `set_api_key`; secret stored in the selected profile. |
| Custom API-key header, Basic header, multiple headers | Arbitrary configured HTTP headers; no dedicated Basic credential exchange is required for a precomputed header | Advanced header configuration plus profile secret writes. The generic `set_api_key` operation is **not** a custom-header editor. |
| Subprocess credentials | `command`, `args`, `env`; subprocess runs on Hermes' machine | Guided environment-secret configuration. Executables and files must exist on Hermes, not Android. |
| OAuth authorization code + PKCE | Discovery, client registration/identification, browser authorization, token exchange and refresh | Native phone flow via `mcp.servers.oauth.start/poll/callback/cancel`, using a phone loopback listener and manual URL paste. |
| Pre-registered OAuth client | `oauth.client_id`, optional `client_secret`, scope and token endpoint authentication settings | Advanced settings followed by the same PKCE flow, if the provider permits that exact callback. A client secret does not mean the client-credentials grant. |
| OAuth device code | Explicit CLI login, if provider metadata advertises support | Terminal instructions now; no stock structured remote MCP device-login API was found. |
| CIMD client identification | Built-in CLI path, using allowed loopback callback ports | Terminal instructions for CIMD-only providers. Stock GUI/session OAuth disables the built-in CIMD path. |
| OAuth client-credentials grant / signed client assertions | No generic MCP grant implementation found in inspected Hermes source | Do not advertise native support. A separately obtained bearer token can be configured, but that does not provide managed client-credentials acquisition or renewal. |
| Mutual TLS / custom CA | HTTP and SSE client certificates and server-local CA paths | Advanced server-path configuration; certificate provisioning is separate. No phone certificate-upload workflow was established. |

Transport/header/stdio/TLS support is defined in the
[configuration reference](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/website/docs/reference/mcp-config-reference.md#L15-L86)
and implemented in
[transport construction](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tools/mcp_tool_transport.py#L373-L470).
The latter explicitly forwards OAuth to SSE; the reference's narrower
“HTTP/StreamableHTTP” wording should not be used to rule SSE out.
The [add/key contracts](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tui_gateway/contracts/tools_mcp_plugins.py#L412-L444)
and [implementations](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tui_gateway/methods_tools.py#L1233-L1287)
establish the remote credential boundary.

The absence of a generic MCP client-credentials grant is a source-inspection
finding, not a claim that MCP itself prohibits it. Hermes builds browser metadata
with `authorization_code` and `refresh_token`, and its explicit MCP login selects
only `browser` or `device`:
[metadata and pre-registration](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tools/mcp_oauth.py#L1076-L1146),
[CLI dispatch](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/hermes_cli/mcp_config.py#L802-L850).

## Phone OAuth: what is supported

1. Wing binds a loopback callback on the phone and passes its URI as
   `client_redirect_uri` to `mcp.servers.oauth.start` for a named connector and
   profile. Stock validation accepts HTTP with an explicit port and host
   `127.0.0.1`, `localhost`, or `::1`. Hermes then creates no listener on its host.
2. Hermes returns `session_id`, `auth_url`, and `flow: pkce`. Wing opens the URL
   in the phone browser. Hermes retains the OAuth exchange and token storage.
3. Wing receives the callback locally or lets the user paste the browser's full
   redirect URL. It relays the authorization response through
   `mcp.servers.oauth.callback`; the pasted value contains a short-lived
   authorization code, not the final access token.
4. Wing polls for `approved` or `error`. Callback receipt alone is not successful
   sign-in: the backend must exchange the code and verify that a token exists.
5. Wing can test the connector and offer reload. The RPC flow does not enable
   live reconnect by default.

These steps follow the
[wire contract](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tui_gateway/contracts/tools_mcp_plugins.py#L477-L552),
[RPC methods](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tui_gateway/methods_tools.py#L1327-L1375),
[loopback validation](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tui_gateway/mcp_oauth_sessions.py#L37-L46),
[session startup](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tui_gateway/mcp_oauth_sessions.py#L151-L207),
and [success/token checks](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tui_gateway/mcp_oauth_sessions.py#L84-L112).

**A public Hermes callback is unnecessary for this design.** The browser reaches
the phone callback; Wing reaches Hermes through the existing private connection;
Hermes makes outbound requests to the provider. Manual paste covers a browser
that cannot reach the listener. It cannot bypass a provider rejecting the
callback during registration.

There are two material limits:

- Existing `oauth.redirect_uri` overrides the URI supplied by the session bridge.
  Wing must inspect the effective callback and explain a mismatch, rather than
  silently rewriting the connector's settings. See
  [callback precedence](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tools/mcp_oauth.py#L996-L1040).
- `_maybe_use_cimd` explicitly excludes all dashboard/session bridge flows. A
  fixed phone port alone does not enable CIMD through this API. CLI CIMD and
  remote DCR/pre-registered login therefore need distinct support descriptions.
  See [CIMD eligibility](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tools/mcp_oauth.py#L957-L978).

Repeated login also needs an explicit callback-port policy. Cached DCR clients
can be bound to their original redirect URI, while the session bridge takes
precedence over cached-port selection. A fresh arbitrary phone port on every
attempt is therefore not guaranteed to work. Test re-authorization and preserve
provider-approved callback settings rather than assuming a new registration.
This follows from the same callback-precedence implementation above.

A private HTTPS dashboard callback is another possible deployment arrangement
when the phone can reach it and the provider accepts it; the browser follows the
redirect. Relaying a pasted response from an explicitly configured HTTPS callback
may also be possible through the callback RPC, but was not validated end to end
and is not the initial phone-loopback implementation commitment.

## Device login and provider restrictions

Stock `hermes mcp login <name> --flow device` discovers a device-capable
authorization server, prints a verification URL and user code, polls for the
grant, and persists the successful result in the active profile. It uses DCR or
a pre-registered client, not browser CIMD. The implementation publishes the
verification instructions to the terminal rather than a remote OAuth session.
Unsupported metadata fails rather than silently changing flow:
[device discovery/registration](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tools/mcp_oauth_device.py#L25-L119),
[authorization and persistence](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tools/mcp_oauth_device.py#L129-L219).

For a terminal handoff, the command must run on the gateway host under the same
Hermes profile. Wing should then test and reload the existing connector. It
should not run a command through an agent and scrape terminal output to pretend
that a structured device API exists. The latter is a proposed product boundary,
not a limitation on a human using the CLI.

Even supported OAuth can require provider-issued client credentials, a permitted
client identity, scopes, or an exact registered redirect. Pre-registration
supplies client identity; it does not exempt the redirect from provider policy.
Hermes also has provider-specific handling, so no universal success guarantee is
possible. See
[pre-registration](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tools/mcp_oauth.py#L1132-L1174)
and [provider defaults](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tools/mcp_oauth.py#L1043-L1073).

## Remote configuration boundaries

New connectors can use `mcp.servers.add`'s raw config for headers, OAuth settings,
or TLS paths. For HTTP connectors `mcp.servers.set_api_key` constructs an
Authorization Bearer header, so custom headers need explicit config plus secret
references. Profile credentials can be written with stock `PUT /api/env`:
[credential writer](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/hermes_cli/web_routers/config_env.py#L285-L296).

Existing advanced settings require careful editing. `PUT /api/config` deep-merges
incoming fields, so omission does not remove a stale header or OAuth setting.
The whole-map MCP replacement endpoint can remove keys but has no revision/CAS
guard; it should not underlie ordinary single-connector auth-mode changes.
Read the current config for advanced editing because the connector summary does
not provide the full header/OAuth configuration. That response can contain
secrets: never render or log the raw config, and prefer safe summaries and secret
presence indicators for ordinary screens. `set_api_key` does not remove an
existing `auth: oauth`; do not treat it as a complete auth-mode conversion. See
[merge semantics](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/hermes_cli/web_routers/config_env.py#L113-L150),
[MCP replacement](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/hermes_cli/web_routers/mcp.py#L136-L150),
and [summary contract](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tui_gateway/contracts/tools_mcp_plugins.py#L318-L391).
The config read normalization is
[shallow model normalization](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/hermes_cli/web_server_config.py#L489-L502),
not MCP secret redaction.

There is no general remote MCP authentication capability matrix in
[`gateway.capabilities`](https://github.com/NousResearch/hermes-agent/blob/d177b119e9c56c9ddc0b7379ffce52341ec06584/tui_gateway/contracts/liveness.py).
Wing should not promise that endpoint discovery identifies arbitrary API-key or
custom authentication. Guided selection and imported explicit configuration are
needed. A missing required RPC should report that the deployed Hermes needs
updating; do not silently return to the dashboard-callback REST flow.

## Aspire evidence

Aspire publishes `https://aspire-mcp.aspireapp.com/mcp` as its connector address:
[official Aspire MCP page](https://aspireapp.com/mcp).
Public GET discovery on the research date returned:

- [Protected-resource metadata](https://aspire-mcp.aspireapp.com/.well-known/oauth-protected-resource/mcp): that resource, the same-origin authorization server, bearer headers.
- [Authorization-server metadata](https://aspire-mcp.aspireapp.com/.well-known/oauth-authorization-server): authorization-code and refresh grants, PKCE `S256`, a registration endpoint, and token endpoint methods `none`, `client_secret_post`, `client_secret_basic`.
- No device authorization endpoint, client-credentials grant, or CIMD support was advertised in that response.

The screenshot's `invalid_client_metadata` / unapproved callback error shows the
previous callback was rejected. It does **not** establish that phone loopback
callbacks are rejected or accepted. The public metadata does not disclose the
callback allowlist, and no client registration was submitted during this
research. A real user-initiated sign-in is the remaining validation step after
implementation. Device code is not an evidence-backed alternative for Aspire
at present.

## Proposed implementation order

1. **Model connector authentication explicitly.** Keep the server/profile scope
   fixed throughout setup. Offer no auth, bearer token, subprocess environment
   credentials, and browser OAuth as guided choices. Put custom headers,
   pre-registered clients, and server TLS paths in advanced configuration. Do not
   label the choices “all MCP authentication.”
2. **Finish PKCE phone sign-in first.** Use the four stock RPCs with a phone
   listener and full-URL paste. Support an explicitly configured exact loopback
   host/port when a pre-registered client requires it; otherwise bind an available
   port. Validate callback destination, state, connector, profile and session;
   reject duplicate/replayed responses; keep codes out of logs; clean up on
   cancellation. Show success only after poll reports approval. Inspect existing
   callback overrides and present an actionable error when they conflict.
3. **Add precise credential configuration.** Store new secrets on Hermes and
   persist references in connector config. Separate bearer rotation from custom
   header editing. Treat changing an existing authentication mode as a distinct
   operation whose stale-key removal must be designed against the real API; do
   not implement it as an unsafe whole-profile overwrite.
4. **Expose honest handoffs.** Device-code and CIMD-only providers get same-host,
   same-profile CLI instructions followed by Test/Reload. Unsupported machine
   grants or provider restrictions get a specific explanation. Revisit native
   device/CIMD support if stock upstream exposes appropriate remote operations.
5. **Verify the boundaries.** Test successful and denied OAuth, repeated login
   with cached client registrations, fixed callback requirements, manual paste,
   wrong state/profile/session, callback override mismatch, canceled/expired
   flows, network interruption, missing RPC, and approval followed by failed
   connector test. Inspect actual phone layouts in both themes and enlarged
   text. Finally perform user-approved Aspire login and verify the connector on
   the deployed stock Hermes version.

All phases remain Android/client work against upstream Hermes. They require no
backend patch, fork, plugin, custom endpoint, or public exposure of the private
Hermes server. A server upgrade, if needed, remains a separate deployment action.
