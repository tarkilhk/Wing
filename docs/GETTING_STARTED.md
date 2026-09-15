# Getting started

Wing connects to a server you operate or have permission to use. You need Android 7.0 or newer, a configured Hermes model/provider, and a dashboard reachable from the phone. The dashboard must expose profile/session APIs and the Desktop Gateway at `/api/ws`.

## Compatibility

The recorded [live acceptance baseline](TESTING.md#recorded-live-baseline) used unmodified Hermes revision `e16f686706b1e0d5334fd1ae82190058d2a19694`. This is a tested reference, not a minimum-version promise. Earlier source research used `d15ed4445207dda418b984e8bda0f68f48b8c6f3`. Capabilities can differ between installations; the Android app probes the server before saving a connection.

The setup below follows the [official dashboard guide](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard), checked on 15 September 2026. It was documentation-checked, not reinstalled against a fresh host during this cleanup. A functioning browser dashboard alone does not prove that authenticated chat WebSockets work.

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

Download an appropriate signed APK from [this fork's releases](https://github.com/tarkilhk/hermes-android/releases), if one has been published. Use ARM64 for a compatible phone. Open the APK in Android and allow installation from that browser or file manager when prompted. Do not install an APK from an unrelated fork expecting it to update Wing.

For development builds, follow [Contributing](../CONTRIBUTING.md). A Play Store listing is not implied by the presence of store metadata in this repository.

## 4. Add your connection

Open Connections, add a connection, and enter:

| Field | Example or meaning |
| --- | --- |
| Label | A name you recognize, such as Home |
| Host | Your private-network hostname, or `https://hermes.example.com` |
| Dashboard port | `9119` for the dashboard above; `443` for a standard HTTPS proxy |
| Username and password | The dashboard credentials configured on the host |
| Dashboard path prefix | Leave blank unless your proxy serves the dashboard below a path |
| Explicit Desktop Gateway URL | Leave blank when the dashboard serves `/api/ws`; use the actual gateway URL only for a separate deployment |

Keep path prefixes in their dedicated field. Under advanced settings, custom access headers can supply access-proxy credentials. Use proxy-authenticated mode only if your deployment provides that authentication. See [Access headers](CONNECTION_DIAGNOSTICS_AND_VERSIONS.md#access-headers).

Save checks profile discovery, the gateway connection and session listing before accepting the connection. Select the intended profile, create a chat, send a short message, then leave and reopen it to verify saved history.

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
