# Connection journey: verified research

Research date: 16 September 2026. App source inspected at `160c887`.
Design research only; no app changes or live-server tests were performed.
The recorded live baseline is Hermes `e16f686706b1e0d5334fd1ae82190058d2a19694`, not a minimum-version guarantee. [Testing, lines 49–53](../TESTING.md)

## The answer in plain language

**For a normal Wing connection, the user needs one Hermes dashboard address and dashboard sign-in details.** Wing uses HTTP APIs and a live-chat WebSocket beneath that address. The second address is an advanced deployment override. The current new-connection flow creates an empty API key and requires modern profile discovery, gateway readiness and session access before saving. [New connection, lines 1289–1349](../../lib/main.dart); [ProfileGateway, lines 118–147](../../lib/core/services/profile_gateway.dart)

The terms describe different things:

| Term | Meaning | Does normal Wing setup need another address? |
| --- | --- | --- |
| Hermes dashboard | The web server supplying profiles, session history and administration APIs | This is the main address |
| Desktop Gateway | The live JSON-RPC chat transport at `/api/ws`; “Desktop” is a protocol/backend name, not a requirement to run a second desktop computer | No: Wing derives it from the dashboard base URL |
| API server | Hermes' separately enabled OpenAI-compatible service, normally on port `8642`, authenticated with `API_SERVER_KEY` | No: the current Wing add flow uses the dashboard contract |
| Messaging gateway | The Hermes service for messaging channels; the API server can run as one of its adapters | Not a second field for Wing |

Sources: [ProfileGateway, lines 118–147](../../lib/core/services/profile_gateway.dart); [WebSocket URL construction, lines 355–371](../../lib/core/services/ws_client.dart); [new connection, lines 1303–1336](../../lib/main.dart); [official API server guide](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server).

## Official upstream deployment facts

The official dashboard guide gives `hermes dashboard` a default address of `http://127.0.0.1:9119`. Remote access needs a reachable bind address and configured authentication. Its remote setup uses `--host 0.0.0.0 --port 9119 --no-open` with `HERMES_DASHBOARD_BASIC_AUTH_USERNAME`, `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` and `HERMES_DASHBOARD_BASIC_AUTH_SECRET`. `/api/status` advertises authentication providers, but that response alone does not verify authenticated chat. WebSocket failures can occur after successful sign-in. [Official dashboard guide](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard)

The official API server guide separately enables `API_SERVER_ENABLED`, uses port `8642` by default and authenticates with a bearer API key. This is a real current Hermes service; its existence does not establish that Wing's current onboarding supports it. [Official API server guide](https://hermes-agent.nousresearch.com/docs/user-guide/features/api-server); [Wing save requirements, lines 1318–1336](../../lib/main.dart)

Wing's setup guide tells users to keep provider keys on Hermes, verify the dashboard in the phone browser, and use HTTPS or an encrypted private network for remote access. `localhost` on the phone addresses the phone itself. [Getting started, sections 1–2](../GETTING_STARTED.md)

## Addresses, paths and ports in the actual app

For an illustrative dashboard base URL `https://hermes.example.com/wing`:

| Purpose | Derived request |
| --- | --- |
| Dashboard password sign-in | `POST https://hermes.example.com/wing/auth/password-login` |
| Profile discovery | `GET https://hermes.example.com/wing/api/profiles` and `/api/profiles/active` |
| Gateway authentication | `POST https://hermes.example.com/wing/api/auth/ws-ticket` |
| Live connection | `wss://hermes.example.com/wing/api/ws` with a short-lived ticket |

This example assumes the proxy actually serves this path. These are URL construction rules, not a tested deployment. [DashboardClient, lines 1153–1173, 1197–1206, 1296–1299](../../lib/core/services/connection_manager.dart); [ProfilesRepository, lines 68–85](../../lib/core/services/profiles_repository.dart); [WebSocket URL construction, lines 355–371](../../lib/core/services/ws_client.dart)

- The modern flow uses `dashboardPort`, `dashboardPrefix` and the saved HTTP/HTTPS scheme for dashboard traffic. Its WebSocket uses `desktopGatewayUrl ?? dashboard.baseUrl`. Users normally leave the override blank. [ProfileGateway, lines 118–138](../../lib/core/services/profile_gateway.dart)
- The override is a **base URL**, not the complete `/api/ws` endpoint: the socket builder appends `/api/ws`. A complete WebSocket endpoint or trailing slash can therefore produce a wrong path. Advanced copy should explicitly ask for an HTTP(S) base URL and show the derived socket route. [WebSocket URL construction, lines 355–371](../../lib/core/services/ws_client.dart)
- Current save extracts a pasted host URL's path when the dedicated prefix is blank; an explicitly entered prefix wins. A full URL field is partly supported beneath the current “Host” label already. [New connection, lines 1290–1295](../../lib/main.dart)
- Current new forms start the basic port at `9119`; a second advanced “Dashboard Port” overrides it. Without an advanced override, save uses the normalized basic port. [New connection, lines 1247–1251, 1290–1291](../../lib/main.dart)
- **Current parsing trap:** pasting `https://hermes.example.com` into a fresh form retains port `9119`. The normalizer only substitutes `443` when its supplied port was `8642`. An explicit port in a pasted URL wins. A redesigned single-URL field using normal HTTP/HTTPS ports is a proposed correction, not current behavior. [Normalizer, lines 189–222](../../lib/core/models/connection.dart); [new-form default, line 1247](../../lib/main.dart)
- An older/separate `DesktopGatewayClient` normalization path ignores an override unless its hostname differs. **Do not attribute that behavior to new connection:** `ProfileGateway` takes the override directly and can use the same host with another port or path. The inconsistency warrants a later integration audit if the flow is built. [DesktopGatewayClient, lines 71–106](../../lib/core/services/desktop_gateway_client.dart); [ProfileGateway, lines 132–138](../../lib/core/services/profile_gateway.dart)

## Authentication and storage

In dashboard-password mode, Wing posts a username/password to the dashboard and retains the returned session cookie. It mints a short-lived WebSocket ticket with that authenticated session. No user-entered chat token is necessary. [DashboardClient, lines 1195–1230, 1284–1315](../../lib/core/services/connection_manager.dart)

The access-proxy switch changes actual authentication: HTTP sends the configured custom headers without doing dashboard password sign-in, while the gateway still obtains a WebSocket ticket. Merely using an HTTPS reverse proxy is not the same as using a proxy that supplies authentication. Access headers can also accompany dashboard sign-in. [DashboardClient, lines 1260–1299](../../lib/core/services/connection_manager.dart)

When neither password nor proxy mode is configured, the current client tries to read a session token from dashboard HTML. This is an existing implementation path, **not a proposed option or a guarantee of remote access**. The proposed journey can target explicit Dashboard sign-in and Access proxy modes directly. Do not preserve a legacy anonymous mode under the guise of compatibility without owner approval. [DashboardClient, lines 1242–1273, 1286–1290](../../lib/core/services/connection_manager.dart); user working agreement supplied for this task.

Custom header names must be unique ignoring case; values must be nonempty single-line strings. Headers managed by the app, including `Authorization`, `Cookie`, `Host` and `X-Hermes-Session-Token`, cannot be overridden. Passwords and access-header values use platform secure storage and a transactional metadata/credential save. [Header validation, lines 14–57](../../lib/core/models/connection.dart); [ConnectionManager, lines 169–170, 317–358, 543–562](../../lib/core/services/connection_manager.dart)

Dashboard HTTP refuses redirects. The redesigned flow should identify a redirect and ask for the final address; it should not silently follow a redirect carrying credentials. [DashboardClient, lines 1171–1173](../../lib/core/services/connection_manager.dart); [connection diagnostics, Access headers](../CONNECTION_DIAGNOSTICS_AND_VERSIONS.md)

## What a successful connection currently proves

Current save performs the following sequence:

1. Discover `/api/profiles` and `/api/profiles/active`; reject absent or malformed profile discovery.
2. Select a discovered server-preferred profile for the probe.
3. Authenticate the gateway, open its WebSocket and wait for `gateway.ready`.
4. List profile-scoped sessions.
5. Persist the connection.

Sources: [new connection, lines 1318–1350](../../lib/main.dart); [ProfilesRepository, lines 33–34, 83–153](../../lib/core/services/profiles_repository.dart); [ProfileGateway, lines 132–147, 292 onward](../../lib/core/services/profile_gateway.dart).

The flow does **not** send an inference message. “Connection verified” is accurate; “Your model works” would overclaim. Existing diagnostics separately distinguish connection access, configured provider and resolved credentials, and explicitly say that resolved credentials do not prove model inference. [New connection, lines 1318–1336](../../lib/main.dart); [diagnostics](../CONNECTION_DIAGNOSTICS_AND_VERSIONS.md)

## Why today's experience feels confusing

These are UX findings inferred from the inspected UI and control flow:

| Observed interface | Likely user interpretation | Design consequence |
| --- | --- | --- |
| “Port” followed by advanced “Dashboard Port” | Two independent required services | One complete dashboard address |
| “Username (optional)” and “Password (optional)” | Sign-in can be skipped on a normal remote server | Explicit authentication choice |
| “Use the gateway address” beneath dashboard settings | Gateway and dashboard are interchangeable destinations | Consistent dashboard-first vocabulary |
| “Desktop Gateway URL” | Need a desktop app or a second server | Advanced “Separate live-chat address” with explanation |
| A generic failure for every thrown error | Cannot tell address, credentials, profile support or WebSocket failure apart | Stage-specific results and repair actions |
| Label is the first task | Naming takes priority over establishing the connection | Name at the completion/review stage |

Source interface: [new connection UI, lines 1412–1543](../../lib/main.dart). Generic error catch: [lines 1352–1357](../../lib/main.dart).

## Boundaries for the design proposal

**Grounded in existing capabilities:** one dashboard endpoint; dashboard credentials; custom access headers; explicit gateway base override; profile discovery; gateway-ready and session checks; saved connection naming; restore from Wing backup. [New connection](../../lib/main.dart); [offline guide, lines 29–38](../../lib/core/screens/connection_guide_screen.dart)

**New client behavior to label as proposed:** full-URL parsing with predictable port rules; early validation; explicit authentication modes; exposing individual validation stages and errors; a profile-selection step inside onboarding; distinct test and final save actions; cancel/retry that preserve entered values and discard stale results. These changes require implementation and verification before any mockup claim becomes real.

**Do not imply available:** QR pairing, local-network discovery, automatic server/proxy configuration, browser OAuth sign-in, automatic migration, successful model inference from a connection test, or an API-key-only compatibility route. None is established by this research as an implemented new-connection capability. `/api/status` provider discovery exists upstream, but using it for a new sign-in-detection step is still proposed Wing work. [Official dashboard guide](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard); [current onboarding](../../lib/main.dart)

The selected Studio charter remains the design authority: Roboto, warm light/navy-charcoal dark surfaces, teal accents, compact rectangular controls, generous touch targets, selected tint without ticks, and truthful status text. Mockups remain design studies, not rendered-app accessibility or backend acceptance evidence. [Studio charter](../DESIGN_SYSTEM.md)
