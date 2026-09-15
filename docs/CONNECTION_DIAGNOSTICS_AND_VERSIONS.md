# Connections, diagnostics and backend updates

Use [Getting started](GETTING_STARTED.md) for password connection setup. The app requires the authenticated modern dashboard and Desktop Gateway. Connection identity includes the configured endpoint and credentials; changing it invalidates the old transport and its pending results.

## Access headers

Advanced headers support authenticated proxies through the existing connection editor. Keep a saved value by leaving its replacement blank, replace it explicitly, or remove it. Names are unique ignoring case; names and values must be single-line. Managed authentication headers cannot be overridden.

Secrets use the same secure storage and transactional save/rollback path as connection credentials. They are included only in explicit configuration export (optionally encrypted with a passphrase), never in displayed URLs, errors or logs. Credential changes must not leave the visible connection and stored secret out of sync.

Dashboard HTTP requests refuse redirects, including requests authenticated with the dashboard session token. Configure the final URL and path directly. WebSocket authentication retains its redirect checks. Some HTTP operations still lack a deadline; see [issue #18](https://github.com/tarkilhk/wing/issues/18).

## Diagnostics and versions

Diagnostics are manual authenticated checks of dashboard/session access, `setup.status` and `setup.runtime_check`. Results distinguish connection access, configured provider and resolved credentials. A resolved credential does not establish successful model inference.

App settings reads the installed Android version/build through package metadata. Backend identity is reported separately. Releases and Changelog open this fork's pages; there is no automatic Android update polling or installation.

Health distinguishes the dashboard process's runtime profile from the selected profile. Use `profiles/active.current` for the runtime identity, not the sticky `active` selection. Missing runtime identity means unknown; unrelated server operations remain usable.

## Backend updates

The update flow checks `/api/hermes/update/check`, explicitly requests `POST /api/hermes/update`, and reads `/api/actions/hermes-update/status`. Track the action name and accepted PID. Preserve both `receipt` and `summary` from the completed response; a summary alone or a generic process exit is not proof of a successful update.

A lost acknowledgement is uncertain. Do not automatically retry a potentially accepted update. Leaving the screen does not cancel work already running on the server. Report per-host failure, reconnect and verified version/result separately from request acceptance. A replacement process under the same action name cannot be credited to the original request.

For several hosts, require an explicit target list and recheck eligibility before each write. Deduplicate configured scheme, normalized host, port and path prefix; this does not establish physical-server identity across DNS aliases. Capture each target's credentials and retain independent outcomes.

No authenticated remote TUI restart API has been verified. A messaging-gateway restart is a different operation and must not be presented as TUI restart.

Profile description/SOUL, usage and provider configuration are covered in [Administration](ADMINISTRATION.md).
