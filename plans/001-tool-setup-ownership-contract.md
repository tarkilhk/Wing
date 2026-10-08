# Tool setup ownership

This slice moves the provider matrix, eligibility, model staging, stock response
validation and setup dispatch from the tool setup widgets into one captured
`ProfileToolSetupSession`. The model page borrows that route owner. Credentials
remain with `ProviderCredentialEditSession`; model values reuse `ModelChoice`.
The main/auxiliary `ProfileModelDefaultsSession` is not a tool catalog owner.

## Inspected stock

Official upstream main was read on 4 October 2026 and rechecked through the
official GitHub commit API on 5 October 2026, unchanged at
[`af90026aa09949579bd423d24def3d38f743cde0`](https://github.com/NousResearch/hermes-agent/commit/af90026aa09949579bd423d24def3d38f743cde0).
The inspected UTF-8 source hashes are:

| Source at that commit | SHA-256 |
| --- | --- |
| `hermes_cli/web_routers/tools.py` | `56cbf186dfe2a2c0dc8665b29af13e1aa3f1a9ec975f1e571842dd95af472937` |
| `hermes_cli/web_models.py` | `1fb71cb7d0006e6e930f2bbf181135de806af71804b767dc70e919eadcbe0f17` |
| `hermes_cli/tools_config_providers.py` | `b2185bad4626e16c5bb6ccbe64f31bd26bfd7d8bee0fdc119b1e655c30e35dfc` |
| `hermes_cli/tools_config.py` | `204f7d689f1b303971b19dc91161acc0f31bf98a3b89cc97b1ced6731158d71b` |
| `hermes_cli/tools_config_post_setup.py` | `cb32fe0a49b8cba3a880f66bc61fcc73b9a79d4921bd886337e17e4b84426833` |
| `hermes_cli/web_routers/models.py` | `8c09d80dd568b81dc63ce9bd5471f97088661ea8978c869672297047a53c9f19` |

The [tool routes](https://github.com/NousResearch/hermes-agent/blob/af90026aa09949579bd423d24def3d38f743cde0/hermes_cli/web_routers/tools.py)
and [request models](https://github.com/NousResearch/hermes-agent/blob/af90026aa09949579bd423d24def3d38f743cde0/hermes_cli/web_models.py)
define these current contracts:

| Command/read | Fact established |
| --- | --- |
| GET `tools/toolsets/{tool}/config` | Named tool, category, fresh provider metadata/readiness and active backend observations; multiple browser rows can be active. |
| PUT `.../provider` | ACK `ok/name/provider`, plus requested web `capability`; optional `needs_nous_auth` means selection is saved without account readiness. |
| GET `.../models?provider=...` | Tool-specific id/display/strengths/speed/price catalog and plugin identity. `current` includes server default resolution and is not proof of an explicit stored value. |
| PUT `.../model` | ACK `ok/name/model/plugin`; image/video generation only. |
| POST `.../post-setup` | ACK `ok/name/pid/key`; `tools-post-setup` action was started, not completed. |

Web selections always name `search` or `extract`; this client does not use the
server's legacy omitted-capability web path. Provider-selection controls belong
to the seven categories that write backend choices: web, STT, TTS, image/video
generation, browser and computer use. Credential-only categories retain setup
and credential controls without an invented provider choice. Post-setup accepts
globally known server setup keys; the client additionally requires the key to
appear in this captured tool's fresh matrix before dispatch.

No backend edits, plugin additions, version aliases or compatibility readers are
part of this slice. Stock supplies no compare-and-swap or idempotency key.
Client preflight cannot prevent a concurrent server write after that observation.

## Fact owners and transitions

| Fact | Sole owner | Transition |
| --- | --- | --- |
| Profile/connection/tool identity | Captured session | Fixed for route lifetime; widgets receive label/name only. |
| Readiness matrix, selected badges/order, available actions | Session and pure codec | Strict complete decode, then immutable replacement. Failed/malformed reads retain the prior observation as history and revoke mutation admission. |
| Model catalog/current/plugin | Same session | Provider-target changes invalidate the older read and pending intent. Same-target refresh retains a dirty intent's opening baseline. |
| Pending model and opening current/plugin | Same session | Staging creates no request. Fresh catalog preflight detects a changed choice/plugin; convergence is a read observation, not an invented write ACK. |
| Operation admission | Same session | Idle → confirming → saving → result review → idle. Confirmation reserves duplicate admission but does not display saving progress. |
| Write acknowledgement | Same session | Exact stock identity/value receipt establishes a saved selection or started setup independently of readback. |
| Setup result/polling | Existing `AdministrationOperationSession` | Tool owner creates it from the receipt; result page borrows it; finally disposes tracking when navigation settles. |
| Credential draft/write | Existing credential editor | Immutable matrix metadata supplies key/is-set; no secret values are read or cached by tool setup. |
| Dialogs/navigation/scroll/model query | Widgets | Present facts, supply confirmation/result callbacks and call owner commands. |

Each mutation first observes the relevant current stock matrix/catalog, then
checks fresh profile membership, then uses the existing owned HTTP callback.
That callback rechecks route authority at actual dispatch, including after held
authentication. The query and body both name the captured canonical profile.
There is no generic-write fallback.

Known validation/authentication/not-found HTTP rejections remain rejected.
Dispatched timeouts, malformed receipts and other unconfirmed outcomes require
explicit read-only review. No retry sends a mutation automatically. A successful
ACK survives a failing follow-up read; the notice reports saved/started while
the separate read observation remains unavailable. Setup completion is never
inferred from its start ACK.

The route retains one repository lease; admitted reads/commands retain a lease
through settlement. Disposal revokes generations/dispatch immediately and does
not cancel an already dispatched server operation. Late observations do not
publish or navigate. Notification storage disposal waits only for a synchronous
listener notification to unwind, so listener-driven route retirement is safe.

## Scope and subtraction

New values and owner: `profile_tool_setup.dart`, `profile_tool_setup_session.dart`.
The source migration replaces provider/model policy in `AdminToolSetupPage` and
`AdminToolModelsPage`, including their raw reads/writes, matrix/catalog parsers,
busy/error/pending fields, eligibility list, selected-label/order logic and
receipt/readback interpretation. It must preserve the current Studio layout,
dialogs, selected semantics, model staging and captured result route.

`AdminToolSetupList` was removed after the canonical accepted-1280 query found
four references, all within the class, and zero external callers, unresolved
spellings or resolution errors across 888 authored Dart units. Root also checked
non-Dart selectors, assets, scripts and root registrations. It is not retained
as an alternate setup route.
`AdminVoicePage` moved with its actual parent/test imports to `admin_voice_page.dart`,
without a re-export or alias. Its dynamic schema discovery and the existing
synthesis page's provider/playback workflow remain explicitly separate
voice-slice obligations. The completed tool/model library has no raw repository
namespace and no actual parts.
The existing speech repository and credential owner are reused, not duplicated.

The source wiring captures one required session factory and a credential-editor
navigation callback; it removes raw transport and mutable policy state from the
completed setup/model views. Existing TTS callers compose the unchanged speech
synthesis page directly. The child model route borrows the parent session and
receives an issued immutable `ToolModelEditor` identity. Child disposal revokes
its unsent command, including the callback checked after held authentication;
it does not dispose the parent or erase its draft. An already dispatched ACK
may still settle into the live parent after the child closes. No second catalog
or model cache is introduced. Existing focus/network read recovery is retained:
the owner classifies recoverable read failures and the shared presentation
wrapper requests a read-only refresh, never a mutation replay.

Focused behavioral and render acceptance remain pending; no passing tests or UI
completion are claimed. Meaningful focused coverage will preserve selected
provider ordering, separate web choices, staged-model retry, ACK/read failure,
malformed-read admission, captured dispatch and confirmation/retirement behavior.
No new guard framework or matrix is required by this extraction.

A known HTTP validation rejection may retain its freshly verified catalog for
an explicit retry. A dispatched timeout or malformed acknowledgement does not:
the draft remains and a fresh read is required before another command. This
separates rejection from uncertain delivery without replaying a mutation.
