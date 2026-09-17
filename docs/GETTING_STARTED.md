# Getting started

Wing connects to a server you operate or have permission to use. You need Android 7.0 or newer, a configured Hermes model/provider, and a dashboard reachable from the phone. The dashboard must expose profile/session APIs and the Desktop Gateway at `/api/ws`.

## Compatibility

The recorded [live acceptance baseline](TESTING.md#recorded-live-baseline) used unmodified Hermes revision `e16f686706b1e0d5334fd1ae82190058d2a19694`. This is a tested reference, not a minimum-version promise. Capabilities can differ between installations; Wing probes the server before saving a connection.

The setup below follows the [official dashboard guide](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard), checked on 16 September 2026. A functioning browser dashboard alone does not prove that authenticated chat WebSockets work; the connection checks below verify that access separately.

## 1. Prepare the Hermes host

Install and configure Hermes using its [official documentation](https://hermes-agent.nousresearch.com/docs/). Confirm that the selected profile can answer a message on the host before connecting Android. Keep model-provider keys on Hermes; the Android connection form needs dashboard credentials.

For a source installation, install the dashboard extras from the Hermes checkout in its existing environment:

```sh
uv pip install -e ".[web,pty]"
```

Use the installation-specific instructions in the official guide if you do not use a source checkout. Hermes Desktop normally starts a local backend; that localhost-only service needs an explicitly configured reachable dashboard for a separate phone.

## 2. Start an authenticated dashboard

Configure the following variables in the host's protected Hermes `.env` or service environment. Supply your own values, and never commit this file:

```dotenv
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=<your-dashboard-username>
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=<a-strong-unique-password>
HERMES_DASHBOARD_BASIC_AUTH_SECRET=<a-random-signing-secret>
```

Generate the signing secret with `openssl rand -base64 32`, or an equivalent secure generator. Then start the dashboard:

```sh
hermes dashboard --host 0.0.0.0 --port 9119 --no-open
```

This listens on network interfaces. Restrict access with your firewall and use an encrypted private network or an HTTPS proxy. Plain HTTP on shared Wi-Fi does not encrypt credentials. Do not use `--insecure` as an authentication workaround. Check `hermes dashboard --help` and the official guide if your installed version has different options.

Keep the process running. From the phone's browser, open the dashboard address and check that your credentials work. The address must identify the host machine; `localhost` on the phone means the phone itself.

## 3. Install the Android app

Download an appropriate signed APK from [Wing's latest release](https://github.com/tarkilhk/Wing/releases/latest). Use ARM64 for a compatible phone. Open the APK in Android and allow installation from that browser or file manager when prompted. Updates must use Wing's package and signing identity.

Open Wing. The welcome screen offers **Connect your agent**, **Restore configuration** and an offline **Connection guide**. App settings are available from the drawer before connecting a server.

For development builds, follow [Contributing](../CONTRIBUTING.md). A Play Store listing is not implied by the presence of store metadata in this repository.

## 4. Add your connection

Tap **Connect your agent** on the welcome screen, or **Add connection** from **Connections**.

1. **Address:** enter the complete dashboard base address, such as `http://hermes.home:9119`, `https://hermes.example.com`, or `https://hermes.example.com:8443/hermes`. Include the scheme, any custom port and any proxy path in this single field. HTTP and HTTPS use their standard ports (80 and 443) when you omit the port. The normal Hermes dashboard port `9119` must be included explicitly for a direct connection.
2. **Sign in:** enter your dashboard username and password. These are not your model-provider credentials. Wing normally uses this same dashboard address for profiles, live chat and history.
3. **Check connection:** Wing checks profile access, the authenticated chat WebSocket and session listing separately. Each stage shows its result; a failed stage gives its own recovery guidance. You can cancel without saving, correct your details and try again.
4. **Save and open:** give the verified connection a recognizable name, then save it to open Chats. A successful check establishes connection access; it does not send a message or verify model inference. Select the intended profile, send a short message, then leave and reopen it to verify saved history.

**Custom setup** is under sign-in, for extra settings supplied by your administrator:

- **My access proxy handles sign-in** is only for a proxy configured to authenticate Wing's requests. An HTTPS reverse proxy alone does not establish this.
- **Use a separate chat address** accepts a complete HTTP(S) base address when live chat is explicitly served elsewhere. Wing adds `/api/ws`; do not paste that endpoint into the field. Review this destination because it also receives chat authentication and configured access headers.
- **Access headers** supplies extra proxy credentials when required, including alongside normal dashboard sign-in. Values remain hidden after saving. Most connections do not need headers. See [Access headers](CONNECTION_DIAGNOSTICS_AND_VERSIONS.md#access-headers).

There is no separate API-server address, API key or second port in the normal journey. The standalone OpenAI-compatible API service on port `8642` is not used by this setup. Connection edits use the same address/sign-in/check flow and retain the connection's identity. Failed checks do not replace the saved connection; failed local saves keep your draft for retry.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Dashboard unreachable | Host address, port, firewall, VPN and whether the process is still running |
| Browser login works, app login fails | Username/password mode, advanced headers, actual final URL and path prefix |
| Profiles load but chat fails | Proxy WebSocket upgrade support, `/api/ws` routing and gateway authentication |
| Redirect or HTTP 301/302/307/308 | Enter the final dashboard URL directly; authenticated requests refuse redirects |
| Unsupported profile/session API | Confirm the server provides the modern dashboard/Desktop Gateway contracts |
| No notification after leaving | Local alerts need an active client connection; check Android permission and App settings |
| Draft returns after the app closed during Send | Read the latest server history before sending again; the original may already have completed |

For proxy deployments, route HTTP APIs and WebSockets to the same intended Hermes installation and preserve its configured authentication. Public health/status success does not establish authenticated chat access. Send redacted diagnostics with the client version, backend revision if known, Android version and reproduction steps. See [Security](../SECURITY.md) and [Known limitations](KNOWN_LIMITATIONS.md).
