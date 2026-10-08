# Profile plugins ownership

`ProfilePluginsSession` owns one captured profile's immutable inventory and toggle
workflow. Its interface is `state`, `refresh()` and `toggle(issuedRow, enabled)`.
The view creates and retires that route owner, renders its facts, and forwards
intent. The existing scoped administration/gateway adapters perform all I/O;
there is no parallel catalog, polling loop, journal or persisted format.

Official latest main inspected at `667b232535c343aaa78c2eba14aa5cf1e13decd8`:

| Exact source | SHA-256 |
| --- | --- |
| `tui_gateway/methods_tools.py` | `fd9a67109d52999910da69368ebdb39362b41ff15e1a29a2beae241dd70a7128` |
| `hermes_cli/plugins_cmd.py` | `4585adee44486d4c0cd81903f4131392e167e4e2e4795eb701489eab38ad653f` |

The [scoped stock RPC](https://github.com/NousResearch/hermes-agent/blob/667b232535c343aaa78c2eba14aa5cf1e13decd8/tui_gateway/methods_tools.py)
accepts `plugins.manage` list and toggle. Inventory provides unique canonical
`key`, display `name`, `source`, `description` and configuration `status`:
`enabled`, `disabled`, or `not enabled`. Toggle sends only the exact captured
canonical key and desired boolean, plus the gateway's immutable profile.
Its positive receipt has `ok:true`, canonical `name`, `unchanged`,
`restart_required` and `gateway_reloaded`. Optional activation data and other
plugin features are not interpreted by this bounded client module.

Stock disable changes configuration and needs restart; it does not unwire already
running handlers. Inventory enabled status is not a runtime liveness claim.
A restart-required ACK is explained through the existing transient message
surface; no restart command or backend change is introduced.

| Transition | Owner fact |
| --- | --- |
| Fresh valid list | Copied immutable rows; toggle admission enabled. |
| Failed/malformed list | Last observation retained, current validity false, explicit read error; no mutation authority. |
| Toggle admission | Busy reserved before listeners; only an issued current row is accepted. |
| Fresh preflight | Exact identity checked; same-field change blocks overwrite, convergence needs no write or invented ACK. |
| Physical mutation | Fresh profile membership, connected gateway, route-authority check adjacent to stock RPC send. |
| Positive ACK | Typed retained fact, independent of the subsequent inventory read. |
| Unknown dispatched result | No replay; read-only refresh required. |
| ACK then failed/different readback | Saved plus unavailable/different current observation; no relabelled unknown mutation. |
| Route retirement | Reject new intents and unsent mutation immediately; admitted reads/writes drain their retained connection lease without late publication. |

The session has one operation phase and no independently writable busy flag.
Synchronous observer retirement is supported: command authority is revoked
immediately and notifier storage is disposed after that notification unwinds.
Client preflight/readback cannot provide CAS, idempotency or eliminate another
client's simultaneous changes. A read-only refresh never silently retries a write.

Both actual Administration plugin factories capture the explicitly selected
profile and create a fresh route owner. Removed declarations are
`AdminPluginsPage.profile`, `_AdminPluginsPageState._busy`, and
`_AdminPluginsPageState._toggle`; raw `AdminLoad`/map parsing/RPC/readback policy
is removed from its build method. The existing notice, row labels, switches,
spacing and Refresh affordance remain. Live direct RPC inventory characterization
is not a view factory and remains supported.

The existing finite view-adapter dependency checker can prevent canonical raw
`administration_repository` or `profile_gateway` imports/exports in this completed
view. Issued-row identity, lifetime, immutable alias isolation, uncertainty and
ACK/readback ordering require the bounded behavioral controls. Source handoff
is not runtime or render acceptance.
