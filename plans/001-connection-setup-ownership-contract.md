# Connection setup ownership contract

Connection setup constructs one candidate, checks profile access/live chat/history
without sending a message, then explicitly saves it. `ConnectionSetupSession`
owns this workflow; `ConnectionSetupScreen` retains Studio's existing layout,
text/focus controllers, field error display, icon/credential modals and navigation.
No extra transport, repository, persistent cache or compatibility interface is
introduced.

The view requires one `createSession` factory. Main constructs the route owner
with an exact captured `ConnectionManager.accessFor(existing)` when editing and
null for a new connection. The access descriptor and sign-in cannot be supplied
independently. Saved connections are a required read capability, not a captured
list: the owner computes the Open offer and reads current membership immediately
before the command. This closes deletion during discovery or between rendering
and tapping Open. Subsequent navigation remains subject to the connection
registry's current-authority checks.

An existing Cloud destination borrows its registry OAuth owner for checking.
Route disposal never retires that owner. Failed-check recovery drops the borrowed
reference and can obtain new provisional authorization. Newly authorized owners
belong exclusively to the attempt: destination/account replacement, disposal and
late results retire them, and successful durable saving retires them before the
navigation animation. The registry then owns saved access. A failed save retains
its provisional verified draft for storage-only retry.

Raw address, username, exact password, name, icon and custom-access inputs live
in an immutable draft. Validation/normalization, candidate construction and
header-secret retention are owner/domain operations. Modal access edits use an
opaque ticket tied to the exact owner and opening revision. Stale or foreign
tickets cannot overwrite the current credential draft. Name/icon changes retain
access verification; changed access inputs revoke it. The published check map
and discovery lists are immutable, and the view receives only the preferred
profile label rather than a mutable discovery collection.

There is one admitted logical Cloud operation. Cancellation keeps admission
closed until browser cancellation settles. Generations fence late results;
provisional owners returned late are retired. The owner checks closure directly
before starting a probe or storage callback, including synchronous presentation
listeners. An already-started durable save may finish after route closure but
cannot request navigation. Probe stage deadlines and actual HTTP/send authority
remain the existing transport owners' responsibilities; generation checks do not
claim to physically interrupt remote work.

## Current stock contract

Inspected official upstream main
[`eb044063235fbf7a4e68dd2970ade05dbe637ff3`](https://github.com/NousResearch/hermes-agent/commit/eb044063235fbf7a4e68dd2970ade05dbe637ff3):

- [`dashboard_auth/routes.py`](https://github.com/NousResearch/hermes-agent/blob/eb044063235fbf7a4e68dd2970ade05dbe637ff3/hermes_cli/dashboard_auth/routes.py), native flow and refresh singleflight: existing native authorize/token/refresh and ws-ticket contracts.
- [`web_routers/profiles.py`](https://github.com/NousResearch/hermes-agent/blob/eb044063235fbf7a4e68dd2970ade05dbe637ff3/hermes_cli/web_routers/profiles.py): canonical profiles and active discovery.
- [`web_routers/sessions.py`](https://github.com/NousResearch/hermes-agent/blob/eb044063235fbf7a4e68dd2970ade05dbe637ff3/hermes_cli/web_routers/sessions.py): scoped session history.
- [`web_routers/chat_ws.py`](https://github.com/NousResearch/hermes-agent/blob/eb044063235fbf7a4e68dd2970ade05dbe637ff3/hermes_cli/web_routers/chat_ws.py) and web server: `/api/ws` stock gateway and preaccept authentication gates.

Setup reuses the existing vanilla transports. No server changes or new endpoints
are needed; no data/persistence format changes or legacy readers are added.

## Regression ledger and acceptance

| Observable property | Guard and static limitation |
| --- | --- |
| Candidate/auth/probe construction, registry work and canonical setup operations stay outside the completed view | `ARCH_COMPLETED_SETUP_VIEW`; exact semantic declarations only, not every possible business expression or wrapper |
| Address/login validation and exact password/header values survive checking and saving | Public setup session cases plus existing screen/transport tests; a general trim ban cannot establish data flow |
| Held check cannot verify changed inputs; late authorization/discovery cannot publish after back/close | Controlled setup session and Cloud journey cases; static await/generation counting cannot establish event order |
| Saved OAuth is borrowed; provisional authorization retires on replacement/close/durable handoff | Public saved-owner/provisional-owner cases; structural import checks cannot prove lifetime |
| Held discovery and stale Open offer cannot navigate to a deleted saved destination | Required fresh saved read capability and two controlled session cases; no automatic save, cache or fallback |
| Foreign/stale credential modal cannot replace current draft | Opaque edit-ticket cases; visual modal ownership is not revision authority |
| Storage failure preserves draft and retry repeats storage only | Public session/storage and existing screen journeys; transport tests independently establish no prompt |
| Entry listener closure starts zero probes/storage; durable late save starts no navigation | Effect-before-outcome public cases; static callback placement is insufficient |
| Retired saved sign-in after verification cannot escape as an uncaught save error | Public owner retirement/save-refusal case |
| Existing Studio controls fit normal/enlarged text in both themes | Existing screen/cloud widget matrices and opt-in PNG capture; actual render inspection remains required |

Auth and secure persistence have their separate
[contract](001-connection-auth-ownership-contract.md). Setup's initial 21 public
owner scenarios are authored and scoped analysis is clean, but their host
execution is pending at this freeze. The 41 static fixtures and actual source/AOT
CLI 1/0/2 passed; production CLI is clean. Numeric feedback budgets, full host
coverage, rendered phone inspection and current-stock/device checks are not
claimed complete.
