# Advanced connection headers

B04 adds custom access-proxy headers to the existing connection editor under
**Custom proxy and dashboard details**. For example, an access proxy can require
a client ID and client secret in separate headers. Password authentication stays
in its existing fields.

Saved header values are hidden. Leave a saved value blank to retain it, enter a
replacement to change it, or remove the row to delete it. A new or renamed header
requires a value. Names are unique without regard to case. Managed authentication
and transport headers cannot be overridden. Values must be nonblank single-line
text. The connection probe uses the candidate headers before saving.

Values reuse the existing verified secure credential transaction, including
rollback on failure. They are omitted from ordinary connection preferences and
included in the existing encrypted configuration backup. They are not placed in
URLs or error messages. Changing a header changes the connection identity, so
an old authenticated transport is not reused with new credentials.

The modern dashboard, profile discovery, profile gateway, remote file client
and Desktop gateway paths share these headers. The WebSocket handshake uses the
same captured connection values. Hermes still supplies its own session cookie,
token and JSON content type.

All dashboard HTTP requests reject redirects, including ordinary session-token
and password-authenticated requests without custom headers. Configure the final
address directly; credentials must not follow a redirect to another origin.
The WebSocket custom-header guard remains in place.

## Contract evidence

Desktop revision `d15ed4445207dda418b984e8bda0f68f48b8c6f3` exposes custom remote
headers in `connections-registry.tsx`, with names-only saved display and
`Record<string, null | string>` updates in `global.d.ts`. Android mirrors the
keep/replace/remove behavior using its existing credential storage.

The installed Dart SDK's `WebSocket.connect` adds caller headers to a regular
HTTP request without disabling redirects. Its HTTP redirect implementation
copies custom headers. The original HTTP and WebSocket guards disabled redirects when custom headers
were present. The 15 September correction applies the HTTP guard to every
dashboard request so Hermes session-token headers receive the same protection.

Verification for 2.15.0: 1,124 tests passed, four opt-in skips, clean analyzer. Focused checks cover secure rollback/persistence, connection identities, form validation and retained edits, encrypted backup, token/password/proxy authentication, WebSocket tickets, and real HTTP/WebSocket redirects. The WebSocket redirect regression was confirmed failing without the guard and passing with it. No live proxy credentials or backend settings were changed.

Deployment on 2026-09-12: signed Personal 2.15.0 / 21642 passed certificate/package checks, installed in place wirelessly and launched on the owner's phone. No real proxy credentials were changed during verification.
