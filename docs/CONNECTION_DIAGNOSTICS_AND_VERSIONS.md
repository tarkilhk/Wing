# Connections, diagnostics and backend updates

Start with [Getting started](GETTING_STARTED.md) for your first connection and [Self-hosted setup](SELF_HOSTING.md) for dashboard authentication and proxy help. Wing needs the Hermes dashboard and Desktop Gateway, rather than a model-provider API key alone.

## Returning to Wing

Wing attempts to restore the visible workspace connection when you return to the app or open a disconnected workspace. Temporary failures trigger automatic retries; **Retry connection** remains available if recovery fails. Recovery preserves drafts and does not automatically resubmit a message whose delivery is uncertain.

Changing a connection's address or credentials replaces its access configuration. Check that you are opening the intended saved instance before sending work.

## Access headers

Authenticated proxies can use **Sign in → Custom setup → Access headers**. Most connections need only the dashboard URL and login. Leave a replacement blank to keep a saved value, enter a replacement explicitly, or remove it. Header names must be unique ignoring case; names and values must be single-line. Managed authentication headers cannot be overridden.

Access secrets use secure device storage. They are included in explicit configuration exports, which can be encrypted with a passphrase. See [Configuration backups](CONFIGURATION_BACKUPS.md).

Wing refuses dashboard redirects. Enter the final address and path directly. Reads and downloads time out when the server stops responding. Some operations that change server state can remain pending longer; a read timeout does not prove that a preceding action failed.

## Diagnostics and versions

Connection diagnostics distinguish dashboard access, configured providers and resolved credentials. A credential result does not prove that a model request will succeed or that quota is available. [Hermes health](ADMINISTRATION.md#health-checks-and-diagnostics) offers profile checks, Doctor, security audit and logs.

App settings shows the installed Android version/build separately from the backend version. Releases and Changelog open Wing's release information. Android app updates are not downloaded or installed automatically.

## Update Hermes

Versions & updates can check for a server update and request it explicitly. **Changes in this update** shows available commit summaries, with a partial-history notice when needed; the server returns at most 20 summaries.

Leaving the screen does not cancel an accepted server update. If acknowledgement is lost, the outcome stays uncertain; check its status and version before repeating the request. Request acceptance alone does not mean the update completed.

When updating several configured hosts, review the targets and each host's result separately. Different addresses can refer to the same physical server. A messaging-gateway restart is separate from a TUI restart; Wing does not offer a verified remote TUI restart action.
