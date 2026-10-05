# Administration Logs ownership

`AdministrationLogsSession` owns one captured connection's submitted query,
read admission, response validation, retry eligibility and latest observation.
`AdminLogsPage` creates and retires that route owner. It keeps input focus and
unsubmitted search text, renders immutable observations, and submits intent.
The repository is borrowed; an admitted read retains it until settlement.
No polling, independent cache, write workflow or persisted format is added.

## Current stock contract

Inspected official NousResearch/hermes-agent commit
`fdcae6debac4ad33adc449a4263433b389b563ef`:

- [hermes_cli/web_routers/status.py](https://github.com/NousResearch/hermes-agent/blob/fdcae6debac4ad33adc449a4263433b389b563ef/hermes_cli/web_routers/status.py),
  SHA-256 `06bdb9ee27657dd6013185b969f4bccc24ca0fda642c2a5022889b9933965b56`.
- [hermes_cli/logs.py](https://github.com/NousResearch/hermes-agent/blob/fdcae6debac4ad33adc449a4263433b389b563ef/hermes_cli/logs.py),
  SHA-256 `58f43c2824de993c39aec40030e77e73bd29fc83f01c33c2bce3b1c4764ee073`.

`GET /api/logs` returns the requested `file` and a string `lines` list. A missing
log file returns that same file identity with an empty list. Unknown files fail
HTTP 400. Stock supports optional severity and case-insensitive search; the
client preserves the existing agent/errors/gateway choices and 100-line limit.
Search is sent exactly as submitted. Empty severity/search omit those parameters.
The existing connection-owned request omits `profile`; this extraction does not
retarget server logs to whichever workspace is later selected. Other stock log
files, component filters and additional features remain outside this UI slice.

## Observation transitions

| Intent / result | Owner observation |
| --- | --- |
| Initial load, refresh or submitted query | Reserve a new generation, publish loading and clear the prior result. |
| Current valid response | Copy the bounded string list into an immutable snapshot of the submitted query. |
| Current malformed response | Explicit invalid-response error; no guessed empty data. |
| Current read failure | Existing administration error classification; transient failures remain eligible for visible-screen recovery. |
| Explicit retry | A fresh read of the same typed query through the existing bounded repository read policy. |
| Older query settles | No change to current data, errors or query. |
| Route retires before dispatch | No request. |
| Route retires after read admission | Read may settle; release its retained connection lease and publish nothing. |

New file/severity/search intents remain available during a held earlier read.
Synchronous observer retirement is safe and revokes an unsent request immediately.
The fixed query schema and response codec are the sole current decode; no legacy
reader, permissive missing-lines default or compatibility constructor remains.

## Removed boundaries and preservation

Removed `AdminLogsPage.server` and `_AdminLogsPageState`'s `_file`, `_level`,
`_search`, `_version`, raw request construction, response casts and `AdminLoad`
workflow. Shared `AdminLoad` remains active elsewhere. The four real constructors
now inject the required captured session factory. Existing Studio filter spacing,
scrolling, header refresh, inline retry, log selection/copy and empty-result strings
remain presentation behavior. Usage and unfinished Voice/Plugins are unaffected.

The existing view-adapter dependency checker can prohibit canonical repository
and gateway namespaces in this completed view, while permitting typed owner
imports. It cannot establish latest-query ordering, listener retirement, read
leases, payload alias isolation or font geometry. The focused owner crossing and
existing Logs scroll/refresh and design controls own those behavioral claims.
Source extraction and authored controls are not runtime or render acceptance.
