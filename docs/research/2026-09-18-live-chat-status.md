# Live chat status ownership

Verified upstream `NousResearch/hermes-agent` main on 2026-09-18 with
`git ls-remote`: `a566d20d226a8e2ef0747639dc8a3fc1c43f9dba`.
The matching read-only source confirms:

- `hermes_cli/dashboard_auth/routes.py`: `POST /api/auth/ws-ticket` mints a
  single-use WebSocket upgrade ticket.
- `hermes_cli/web_routers/chat_ws.py`: `/api/ws` delegates to the stock
  `tui_gateway.ws.handle_ws` JSON-RPC transport.
- `tui_gateway/ws.py`: the connection starts with `gateway.ready`.

## Reproduction and cause

The transport regression test opens a workspace gateway and a separate
administration gateway through their production factories. Closing only the
administration socket leaves workspace RPCs operational, but previously changed
the shared live chat status to `unavailable`.

Administration registered `administration:<profile>` alongside workspace chat
owners. Any failed owner makes the aggregate unavailable, but workspace retry
only reconnects workspace gateways. Consequently an idle administration socket
could leave the indicator amber even after a successful chat reconnect.

## Client-only correction

Only workspace gateways report live chat availability. Administration still
reports dashboard access and exposes failures to callers, and opens its RPC
socket on demand. No protocol or backend changes are required.

The regression uses real local HTTP/WebSocket transports and also verifies that
an available administration socket cannot hide a chat disconnect, that chat
reconnect restores availability, and that closing administration does not erase
workspace status. A separate status test retains failure reporting for background
chat profiles; the aggregate's failure precedence is unchanged.

Run: `flutter test --no-pub test/live_chat_status_transport_test.dart test/server_connection_status_test.dart`.
