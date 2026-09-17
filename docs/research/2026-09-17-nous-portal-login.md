# Nous Portal login: value, discovery, and Wing support

Researched 2026-09-17 against primary sources. Research only; no application or backend changes, account login, subscription purchase, or live-server test.

## Recommendation

The user clarified that the intended audience is **Nous-hosted Hermes Cloud users**, including people with no local or self-hosted server. The target feature is **Sign in with Nous → discover hosted instances → select one → connect**. Recommend supporting this as an optional connection-onboarding path, subject to verifying an Android-compatible Portal session/discovery contract. Server authentication is a dependency of this journey, not the main product feature. Provider billing login is separate background context.

This recommendation rests on first-party relevance and reduced setup effort, not measurable popularity. No published Portal subscriber count or market share was found.

## Is it like Plex identity?

**Partly.** The same Nous account participates in three distinct flows:

| Capability | Verified behavior | What it means for Wing |
| --- | --- | --- |
| Model and tool access | Hermes authenticates to Portal to use models and managed tools against account credits. | Provider setup inside an already connected server. |
| Self-hosted server identity | A dashboard can register an OAuth client with Portal and require Nous login. | Sign into a known, reachable server using the browser. |
| Hermes Cloud discovery | Official Desktop can sign in and discover account-owned Cloud instances. | Potential account-first connection onboarding. |

Sources: [Portal integration](https://hermes-agent.nousresearch.com/docs/integrations/nous-portal), [dashboard authentication](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard), [Desktop connection registry](https://hermes-agent.nousresearch.com/docs/user-guide/multi-connection-desktop).

For self-hosting, `hermes dashboard register` registers a dashboard with the account, and Portal's `/local-dashboards` page manages or revokes those registrations. Registration sends a name and optional callback URL to `/api/oauth/self-hosted-client` and stores an `agent:...` client ID. Its own post-registration instructions require the dashboard to be reachable at the supplied HTTPS host. Registration is therefore identity configuration, not evidence of a tunnel. [Pinned registration implementation](https://github.com/NousResearch/hermes-agent/blob/61e730cc0b7594eeb8e92fd8a56e4259ba87cfe6/hermes_cli/dashboard_register.py).

The official Desktop guide distinguishes Cloud account discovery from a remote gateway entered by URL. No documented Portal relay, NAT traversal, or universal discovery contract for arbitrary self-hosted servers was established in this investigation. A registered home server should not be assumed reachable from mobile data merely because both ends use Nous login. This is a bounded evidence finding, not a claim that no unpublished service exists. [Desktop guide](https://hermes-agent.nousresearch.com/docs/user-guide/desktop).

## What Portal brings

Portal combines hundreds of hosted models, managed tools, and optional Cloud hosting under one account and credit balance. Models are not limited to Nous's own models. The chief product benefit is fewer separate accounts, keys, and bills. It is metered service access, not unlimited inference. Public pricing observed on September 17:

| Plan | Monthly price | Monthly credits | Credit rollover cap |
| --- | ---: | ---: | ---: |
| Free | $0 | $0; free models | Not specified |
| Plus | $20 | $22 | $10 |
| Super | $100 | $110 | $50 |
| Ultra | $200 | $220 | $100 |

Prices are public offers rather than an authenticated checkout quote. Model counts and promotional availability differ across current pages, so Wing should use live catalogs rather than embed marketing counts. [Portal offering and pricing](https://portal.nousresearch.com/), [model catalog](https://portal.nousresearch.com/models).

Tool Gateway supports managed web search/extraction, image generation, speech synthesis, and browser automation. Tool routing can be selected independently of the main inference provider. Paid subscription access is the normal path; limited free tool pools exist for eligible accounts and are not universal. Usage consumes credits. [Tool Gateway documentation](https://hermes-agent.nousresearch.com/docs/user-guide/features/tool-gateway).

Hermes Cloud additionally hosts persistent agent instances and exposes their dashboards. Compute/storage charges are separate from model and tool consumption, though charged to the same Portal balance. It supplies hosting; provider login alone does not move an existing home server into Cloud. [Cloud service](https://portal.nousresearch.com/cloud).

## How popular?

**Public adoption remains unquantified.** Targeted searches of Nous sites, announcements, and the upstream repository found no defensible active-user, paying-subscriber, or market-share figure. This does not establish low usage.

- Portal has a dated first-party launch on March 12, 2025. That announcement describes its original offering, not its present features or pricing. [Launch announcement](https://forum.nousresearch.com/t/announcing-the-nous-portal/62).
- Upstream deliberately promoted Portal in setup; issue #644 requested placing it first. This establishes distribution priority rather than user preference. [Upstream issue](https://github.com/NousResearch/hermes-agent/issues/644).
- There are direct user reports of paid Portal use, including a Plus device-code login failure. One report establishes real use, not scale or a current unresolved defect. [Issue #47950](https://github.com/NousResearch/hermes-agent/issues/47950).
- The public model catalog displays usage rankings without absolute subscriber/request counts. Hermes stars, Nous followers, and model downloads are not Portal adoption measures. [Catalog](https://portal.nousresearch.com/models).

The supported description is **first-party, actively promoted, and integrated into the official client; popularity unknown**.

## Verified implementation baseline

Current upstream main was fetched via GitHub's commit API during this investigation: `61e730cc0b7594eeb8e92fd8a56e4259ba87cfe6`, committed `2026-09-17T15:08:43Z`. Wing source inspected at `534c3de537e6cb5e9e62dc2220b3ad1be1933491`. These are source baselines, not claims about the deployed server. [Inspected upstream commit](https://github.com/NousResearch/hermes-agent/commit/61e730cc0b7594eeb8e92fd8a56e4259ba87cfe6).

### Provider login already has client plumbing

Stock Hermes advertises `nous` with `flow: device_code`. Wing's generic provider page already renders those rows, starts sign-in, shows a user code, opens the external browser, polls status, and supports cancellation. Explicit profile scope travels with its requests. [Stock provider catalog](https://github.com/NousResearch/hermes-agent/blob/61e730cc0b7594eeb8e92fd8a56e4259ba87cfe6/hermes_cli/web_server_oauth.py), [Wing provider screen](../../lib/core/screens/administration/admin_providers_page.dart), [Wing administration repository](../../lib/core/services/administration_repository.dart).

The stock API exposes `GET /api/providers/oauth`, `POST /api/providers/oauth/nous/start`, `GET /api/providers/oauth/nous/poll/{session_id}`, and session cancellation, with profile scope. Start returns `session_id`, `flow`, `user_code`, `verification_url`, `expires_in`, and `poll_interval`. Hermes performs the Portal exchange and retains the provider credentials; Wing handles the authorization UI. A guest-account promotion path also uses this shape. This flow requires access to the server first and does not solve initial server login. [Pinned OAuth routes](https://github.com/NousResearch/hermes-agent/blob/61e730cc0b7594eeb8e92fd8a56e4259ba87cfe6/hermes_cli/web_routers/oauth.py).

### Server login is a separate missing feature

Wing's inspected `DashboardClient` implements password-based dashboard sessions, configured proxy access, and local dashboard token acquisition. No Nous native server-login or Portal Cloud discovery implementation was found in the inspected connection code. Provider sign-in in administration should not be represented as support for these connection flows. [Wing connection implementation](../../lib/core/services/connection_manager.dart).

Current stock Hermes has a native-app authentication broker:

1. The client already knows the dashboard URL and opens `/auth/native/authorize` in the browser, using PKCE and client state.
2. Hermes handles authorization with its configured identity provider, including Nous.
3. The dashboard redirects a one-time code to the client's loopback callback.
4. The client redeems it at `/auth/native/token` and rotates credentials through `/auth/native/refresh`; `/api/auth/ws-ticket` supplies WebSocket tickets.

The callback validator accepts only `http://127.0.0.1/...` or `http://[::1]/...`, not Android custom schemes or HTTPS App Links. A phone-local listener and browser/lifecycle behavior require an Android feasibility check. These existing endpoints establish a promising client-only path, not a completed mobile integration. [Pinned authentication routes](https://github.com/NousResearch/hermes-agent/blob/61e730cc0b7594eeb8e92fd8a56e4259ba87cfe6/hermes_cli/dashboard_auth/routes.py), [native broker](https://github.com/NousResearch/hermes-agent/blob/61e730cc0b7594eeb8e92fd8a56e4259ba87cfe6/hermes_cli/dashboard_auth/native_flow.py).

The bundled Nous dashboard provider verifies instance-bound tokens and handles rotating refresh credentials. Some published dashboard documentation still describes a contract without refresh tokens; the inspected current implementation takes precedence for design. Provider inference credentials and dashboard session credentials are different grants and must remain distinct. [Pinned Nous dashboard provider](https://github.com/NousResearch/hermes-agent/blob/61e730cc0b7594eeb8e92fd8a56e4259ba87cfe6/plugins/dashboard_auth/nous/__init__.py).

### Cloud discovery: concrete official-client implementation

Follow-up inspection at the same pinned upstream commit traced the official Desktop flow beyond the documentation:

1. Desktop opens Portal in its persistent Electron OAuth browser session. Portal uses Privy account-session cookies, distinct from Hermes dashboard tokens.
2. Discovery calls `GET https://portal.nousresearch.com/api/agents`, authenticated by that browser session. With multiple organizations, a `409 org_selection_required` response supplies choices; Desktop retries with `?org=<slug-or-id>`.
3. Discovery returns instance summaries including dashboard URLs. The interface lets the user choose an instance and shows its gateway state; instances without a URL cannot yet be connected.
4. Desktop opens the selected dashboard's login in the same browser session. Existing Portal identity enables automatic approval for an authorized organization member; the instance still completes its own authentication exchange.
5. The resulting instance connection is saved with its name, dashboard URL, and selected organization. It can subsequently be selected as an ordinary saved connection.

Sources: [Desktop Cloud discovery and session implementation](https://github.com/NousResearch/hermes-agent/blob/61e730cc0b7594eeb8e92fd8a56e4259ba87cfe6/apps/desktop/electron/main.ts#L8392), [Cloud picker implementation](https://github.com/NousResearch/hermes-agent/blob/61e730cc0b7594eeb8e92fd8a56e4259ba87cfe6/apps/desktop/src/app/settings/gateway-settings.tsx#L692).

**Android implication:** this is an implemented account-discovery service, but the inspected Desktop path relies on Electron owning the browser cookie store and making HTTP calls through that same session. A normal Android external-browser sign-in does not hand that cookie store to Wing. The native dashboard broker verified above solves per-instance authentication; it does not itself grant Portal discovery access. Before implementation, establish a supported Portal token/SDK or browser-session integration for Android, including renewal and organization selection. Do not assume an inference OAuth token authorizes `/api/agents` or that a Desktop cookie implementation ports directly to Android.

Portal also exposes an OAuth-protected MCP service for managing account-owned Cloud agents. That could inform further investigation, but no claim is made that its management contract is the appropriate Wing discovery interface. [Cloud MCP guide](https://hermes-agent.nousresearch.com/docs/guides/manage-hermes-cloud-with-mcp).

## Proposed scope and decision gates

1. **First validate the Cloud connection journey:** Portal login, authenticated instance discovery, organization selection, per-instance sign-in, then Wing's HTTP/profile/WebSocket readiness checks. Success means a Cloud-only user reaches their existing agent without typing its URL or copying a token.
2. **Initial product scope:** an optional “Connect Hermes Cloud” entry, browser sign-in, instance selection, and saved connections. Account expiry, no instances, unavailable/provisioning instances, and multiple organizations need clear recovery states.
3. **Keep provisioning and billing on Portal initially:** users can follow a Portal link if they need to create an instance. Creating/deleting instances, subscriptions, and lifecycle management are not necessary to validate the connection feature.
4. **Gate implementation on Android authentication feasibility:** verify the Portal discovery session contract and per-instance native flow without custom backend endpoints, patches, or plugins. Source inspection demonstrates Desktop behavior, not tested third-party mobile support.
5. **Popularity should inform priority, not capability claims:** no quantified Cloud-user adoption was established. The product rationale is opening Wing to an existing hosted-user audience and removing manual connection setup.

No implementation or deployment is authorized by this research recommendation. No legacy compatibility path is proposed. Remaining unknowns: actual Portal adoption, current deployed-server build, authenticated Cloud listing contract, Android loopback reliability, and live account entitlements.


## September 18 implementation verification

Rechecked upstream main at **`07c92d675a821d96e4aabd636bf22bde32167c38`**, committed September 17, 2026 at 15:59:50Z. Desktop still discovers Cloud instances with the persistent Portal browser session, calls `/api/agents`, handles `409 org_selection_required`, and renews expired Privy access cookies by loading Portal. The native dashboard broker still returns `{access_token, refresh_token, token_type, expires_at, provider, user_id}` and supports refresh rotation. [Current inspected Desktop](https://github.com/NousResearch/hermes-agent/blob/07c92d675a821d96e4aabd636bf22bde32167c38/apps/desktop/electron/main.ts), [inspected native broker routes](https://github.com/NousResearch/hermes-agent/blob/07c92d675a821d96e4aabd636bf22bde32167c38/hermes_cli/dashboard_auth/routes.py).

After the owner approved implementation, Wing added an app-owned Android WebView for Portal identity and a separate instance PKCE grant. Exact loopback callback interception avoids an Android custom-scheme requirement and does not send the callback to the network. Portal cookies are sent only to Portal discovery; instance access/refresh tokens stay in verified secure storage and are bound to that dashboard origin and prefix. Public source inspection, fixture tests and compilation establish the implemented contract; they do **not** establish that every real Portal login provider accepts Android WebView. The owner subsequently confirmed successful Portal login and empty-instance discovery using the deployed Android debug build. Per-instance connection and renewal remain untested against a live hosted instance because the account has none. No backend or deployed-server changes were made.
