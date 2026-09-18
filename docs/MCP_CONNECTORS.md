# MCP connector setup and sign-in

Wing targets unmodified upstream Hermes main, verified at
`d177b119e9c56c9ddc0b7379ffce52341ec06584` on 18 September 2026.
The [research and stock API evidence](MCP_AUTH_RESEARCH.md) distinguish runtime,
CLI and remote-client capabilities. This implementation supersedes the earlier
dashboard-callback OAuth description in Administration's MCP failure notes.

## Setup

MCP connectors has an Add connector form bound to the selected connection and
profile. Remote services offer browser sign-in, bearer token, no authentication,
or custom headers. Programs running on Hermes accept a command, one argument per
line, and optional environment credentials. The form starts empty and has no
service-specific presets. Each field includes guidance, and connection and
authentication selections explain when to use them. Bearer-token help distinguishes
the automatically added prefix from custom headers, whose values are sent exactly
as entered. Advanced fields explain OAuth registration, client authentication,
permissions, callbacks and server-local certificate files.

Advanced fields support pre-registered OAuth clients, token endpoint client
authentication, scopes, exact registered callbacks, and server-local certificate,
private-key and CA paths. Certificate upload, program installation, arbitrary
configuration import and existing authentication-mode conversion are not part
of this form. Creating a connector saves configuration; explicit testing starts
its process or connects to the service. Browser setup proceeds to sign-in.

New connectors use `mcp.servers.add`. Bearer secrets use its `bearer_token` field.
Custom header/environment values and OAuth client secrets use profile `PUT
/api/env` and random unique variable references in the connector configuration.
Secrets are not put inline in config.yaml or persisted on Android. A duplicate
name is rejected before secret writes. If a provisioning write is unconfirmed,
Wing preserves the draft and directs the user back to the list before retrying;
some profile credentials may already have been saved. There is no cross-request
transaction in stock Hermes, and Wing does not delete credentials speculatively.

## Browser sign-in

Wing uses `mcp.servers.oauth.start`, `.callback`, `.poll` and `.cancel` over the
profile gateway. It binds an HTTP loopback listener on the phone and supplies
`client_redirect_uri`. Its default port is stable for the saved connection ID,
profile name and connector name, so ordinary repeated sign-ins reuse the same
address. An occupied port produces an actionable error rather than silently
selecting a new callback for a cached registration.

Start sign-in opens the returned browser URL. Automatic loopback receipt and
manual full-URL paste use the same validation and relay: exact callback
destination, state, a single code or error, and no duplicate security parameters.
The optional issuer is relayed to Hermes for validation. Callback receipt is
not successful authorization; only Hermes's `approved` poll result confirms the
token exchange. Tokens and refresh remain owned by Hermes. Cancel and route
disposal cancel the captured session and close the listener; a late poll cannot
resurrect a cancelled flow. Unknown methods produce update guidance, with no
REST compatibility path or automatic server upgrade.

An existing `oauth.redirect_uri` remains authoritative. A configured HTTP
loopback URI is bound exactly. An explicit non-loopback HTTP(S) callback uses
manual URL relay, validated against that exact configured destination; it does
not require Wing to host that address. The authorization URL must advertise the
expected redirect before Wing opens it. A provider can still reject a callback,
client identity or registration. Previously cached registrations, a changed
connection identity, and first-time registration require live verification.

Device-code configuration produces same-host/same-profile terminal guidance.
The other-sign-in disclosure also explains the CLI path for CIMD-only providers.
Neither is presented as native remote sign-in support. Users return to Test
connection after external login, and can explicitly reload server connectors to
adopt credentials in existing sessions.

## Connection results

Connector detail shows a neutral untested state, a spinner while testing, and a
green tick with Test passed or a red cross with Test failed afterward. Available tools (count)
expands the returned tool names and descriptions; failure reasons are retained
under Failure details. Each fresh test clears the previous result and starts
with disclosures collapsed. These are explicit test observations, not cached
runtime health. The screen no longer repeats cached configuration status or
prompt/resource counts beside the test result.

A separate result card was compared with inline status above the actions. Inline
status keeps Test connection and Sign in close, avoids a second context card,
and leaves tools one tap away. The tool and failure disclosures are inspected
in both themes at normal size and at 320 dp with 200% text.

## Design and validation

The task is to add a connector and authorize access for the selected profile.
A multi-step wizard was compared with a single growing form. The latter keeps
name/address/authentication together and places provider-specific settings in
Advanced. Sign-in has one screen with a primary browser action, secondary manual
completion, status and cancellation. Both use Studio spacing, theme, controls
and fixed ownership labels. Callback instructions were shortened after reviewing
the actual enlarged-text render.

`mcp_oauth_test.dart` covers callback validation/relay, token-confirmation gating,
repeat login ports, explicit loopback and HTTPS callbacks, wrong overrides,
device-code handoff, missing RPC, cancellation/disposal races, and a real local
HTTP callback. `mcp_setup_test.dart` covers profile ownership, separate credential
storage, duplicate rejection, input validation and user-entered connector setup.
`administration_mcp_test.dart` retains probe/error/reload regressions.
`mcp_setup_layout_test.dart` renders both new screens at 390 dp and at 320 dp with
200% text in both themes, checking action reachability across all authentication
choices, program setup, populated credential rows and expanded Advanced settings.

The 18 September setup guidance revision compares two arrangements: a separate
help sheet, and explanations beside the active controls. Inline help keeps advice
with the field it explains and needs no extra taps; optional technical settings
remain collapsed under Advanced. Help uses Studio secondary text and grows with
text scaling without a line limit. The primary action remains Add connector, or
Add and sign in for browser authentication; profile context stays passive.

Guidance was checked against latest upstream main
`77ecc72bcdd5da0163cca21c8af0e95b26ba3426` on 18 September 2026, verified with
`git ls-remote`. Inspected the stock
[configuration reference](https://github.com/NousResearch/hermes-agent/blob/77ecc72bcdd5da0163cca21c8af0e95b26ba3426/website/docs/reference/mcp-config-reference.md),
[MCP RPC implementation](https://github.com/NousResearch/hermes-agent/blob/77ecc72bcdd5da0163cca21c8af0e95b26ba3426/tui_gateway/methods_tools.py)
and [OAuth metadata implementation](https://github.com/NousResearch/hermes-agent/blob/77ecc72bcdd5da0163cca21c8af0e95b26ba3426/tools/mcp_oauth.py).
This revision changes the client form and guidance, with no backend or wire changes.
Validation: all 36 setup/viewport tests pass, alongside the 40 OAuth and connector
regressions; targeted static analysis reports no issues. Actual Flutter renders
under `build/mcp-review/` were inspected in light/dark at 390 dp and at 320 dp with
200% text. Long field labels move above the input at enlarged text sizes, and
help text wraps without truncation. These are widget renders, not a new native
device or live-service acceptance run.

These tests establish client behavior against the verified wire contract. On
18 September 2026, the user confirmed successful Aspire sign-in and connection
testing on their deployed Hermes and phone. Aspire advertises PKCE and dynamic
registration; its callback allowlist is not public.
