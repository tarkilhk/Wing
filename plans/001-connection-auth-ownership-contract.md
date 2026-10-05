# Saved connection identity and sign-in ownership

The saved domain value is immutable. `SavedConnection.dashboardGrant` is an
immutable `DashboardOAuthGrant` snapshot; it cannot send HTTP, refresh credentials
or persist anything. `DashboardOAuthSession` lives in application services and
owns one rotating grant, single-flight refresh, save-before-use retries and
retirement. Every network factory and workspace controller requires one explicit
`ConnectionAccess`, from which connection metadata is derived. The old constructor
accepting only saved metadata and the old model-owned session/export are removed;
there is no lookup, reconstructed session, optional compatibility constructor or
forwarding export.

`ConnectionManager`'s existing preferences/credential-store-scoped persistence
state owns the session registry. `accessFor` accepts only a descriptor with the
current authority: endpoint, credentials, headers, cloud identity and grant
identity must match. Label/icon edits and rotating token values preserve that
owner. Deletion, imported replacement, or changed authority retire captured old
owners. Authentication completion and final physical HTTP dispatch both check
retirement. Already dispatched server work cannot be recalled.

Connection setup owns its provisional session until save/discard. A successful
probe retains access, and the explicit save snapshots the owner's latest grant,
including rotation during verification. Cancelling/closing a held native-token
exchange returns no new owner; stale route results, replaced instance discovery
and disposal retire provisional owners. Saving creates the saved registry owner;
retiring the separate provisional owner cannot retire saved access.

## Current upstream and persisted contracts

Official unmodified Hermes main was inspected at
`343500b3547e12530457c2fda60ec687e25118b4` (3 October 2026). The sources were
`hermes_cli/dashboard_auth/{routes,native_flow,refresh_singleflight}.py` and the
official desktop `apps/desktop/electron/native-oauth{,-login}.ts`. The native
PKCE/state flow uses `/auth/native/authorize`, `/auth/native/token` and
`/auth/native/refresh`; the canonical token response carries `provider: nous`,
`access_token`, `refresh_token`, `token_type: Bearer` and numeric `expires_at`.
The migration changes ownership only, not endpoints, grant rotation or server
behavior. References are read-only; no backend or deployment changes are required.

The current `connection_credentials_v1.<encoded-id>` secure payload retains its
existing field names: `api_key`, `dashboard_password`, `gateway_headers` and
`dashboard_oauth`, with the same grant ID/base/token/expiry encoding. The existing
`connection_transaction_v1` journal, read-back verification, rollback and secure
commit ordering remain authoritative. Exact password bytes are preserved through
save and secure reload; account labels may be trimmed, passwords may not. An
explicit empty password update still clears that optional credential.

Saved preferences contain only metadata. Both the manager and the public domain
metadata parser reject credential-bearing keys, including keys whose values are
null. The misleading plaintext-migration reader branches are removed. The one
supported opt-in approval-device fixture has an explicitly private full-input
schema and now parses its credential fields separately; it is not a metadata
fallback. No source content is treated as permission to access a real account.

Portable `wing-config` V2 backups remain the current format. They intentionally
exclude rotating Cloud credentials and browser identity, retaining Cloud
instance/organization metadata; restored Cloud connections require sign-in and
fail closed before HTTP. No schema alias, older-format reader, migration shim or
unacknowledged data deletion is introduced.

## Evidence and acceptance

Source-bound resolved caller inventory must include constructors, tear-offs,
alternate integration/tool roots, and their actual input contracts. The original
query's zero constructor matches exposed an analyzer qualification defect; it is
not deletion evidence. The corrected query is recorded privately with exact
source/SDK hashes. Runtime root inspection separately covers stored metadata,
secure payloads, the opt-in private fixture and current backup decoding.

The existing architecture graph rejects mutable/application-owned services in
domain libraries. The exact four domain edges resolved by this migration are
removed from the baseline only after the production graph agrees; all remaining
findings stay visible. Behavioral tests, not those static edges, establish:

- Shared saved owners, immutable opening snapshots and stable identity on rotation;
  refresh coalescing and retrying secure persistence without replaying old grants.
- Exact password bytes in saved access, secure reload and the physical login body.
- No usable session after cancelled/closed held token exchange, retired held
  refresh, or stale/disposed setup routes; verified save captures renewed tokens.
- Mismatched grant/access rejection, captured authority retirement, and zero
  physical HTTP sends/dispatch notifications after retirement during auth.
- Unchanged secure transaction, backup, setup, connection/auth/header, scoped
  gateway, remote-files, voice, versions and workspace behavior.

Private original-source hashes and narrowly restored counterfactuals retain the
red targets for newly exposed bugs. Counterfactuals restore only the precise
reviewed defect within the coherent new API; they are not claimed historical
whole revisions. Static rules do not prove OAuth sequencing, interruption-safe
storage or absence of races after an actual server dispatch. Root owns serialized
host/native and supported current-stock acceptance; no device/backend acceptance
follows from static analysis alone.

Corrected constructor query: 775 authored Dart units, 21 canonical references, no unresolved candidate spellings or semantic errors, stable before/after source hashes and census. Nine reader references comprise the manager metadata tear-off, one opt-in private-input adapter and seven metadata/round-trip/rejection assertions. Nine writer references and three metadata adapter/rejector references complete the inventory. This proves the inspected caller set on that snapshot, not arbitrary future runtime liveness. The former model-library session and runtime-error declarations are independently retired at their exact old identities; the new service owner remains supported.

## Review ledger: structural feasibility versus behavior

The table below is the public regression ledger for this slice. Structural
checks protect module direction and exact retired identities. The asynchronous
and byte-preservation properties are owned by deterministic public tests. A
matching source substring, a count of `await` expressions, or the mere presence
of `retire()` is not proof of these behaviors.

| Property / reviewed counterexample | Structural protection and precise limit | Deterministic behavioral gate |
| --- | --- | --- |
| Domain metadata held a mutable session that could refresh and persist | `ARCH_DOMAIN_DEPENDENCY` rejects application/network/storage dependencies from domain libraries. `ARCH_RETIRED_DECLARATION` rejects `DashboardOAuthSession` and `CloudAccessException` only in their former model library. Valid service declarations remain supported. These rules prove dependency/identity properties, not token or storage sequencing. | `dashboard_oauth_test.dart`: saved registry owner is shared across reload/readers, opening grant remains immutable on rotation, identity remains stable, parallel refresh coalesces, failed secure save retries without replaying refresh. |
| A cancelled/closed held native-token exchange returned a live provisional owner | Static cancellation claims are not sound: a generation check before the token await says nothing about ownership after its completion. No race linter is claimed. | `hermes_cloud_test.dart`: await actual token-handler entry, cancel/close, release canonical success, require no returned owner. |
| Instance refresh, route disposal or a late sign-in result retained a usable provisional session | Dependency and retired-declaration guards cannot establish route lifetime. No generic ban on asynchronous widget callbacks or session references is introduced. | `cloud_connection_journey_test.dart`: verified provisional owner retires on refresh/disposal; sign-in held through disposal returns an owner that is immediately retired. `dashboard_oauth_test.dart`: retire a held refresh, release success, require unchanged grant/no persistence and refused subsequent use. |
| Rotation during provisional verification saved the old opening credentials | Immutable value direction alone cannot prove which snapshot was persisted. | `connection_setup_probe_test.dart`: verification performs a real controlled renewal; opening descriptor remains unchanged; explicit verified save exposes the renewed owner snapshot; cancellation refuses the save snapshot. |
| Secure save/reload trimmed exact password bytes and made saved access disagree with its returned descriptor | A global `trim` ban is wrong for account labels and URLs. A ban on one literal password expression misses aliases and alternate adapters, so no such guard is presented as end-to-end proof. Current metadata/credential separation is structurally protected; exact secret bytes require behavior. | `secure_connection_storage_test.dart`: surrounding-space, all-space and empty values survive save/access/secure payload/reload; nonempty values reach the actual controlled `/auth/password-login` request body unchanged. Empty credentials use the explicitly configured open-dashboard path. |
| Deleted or replaced authority could retain a captured old refresh owner | The required `ConnectionAccess` input removes metadata-only client construction; its constructor rejects mismatched grant/owner identities. Static structure cannot prove retirement timing or commit ownership. | `dashboard_oauth_test.dart`: label-only edits preserve owner, changed authority rejects old descriptors and retires captured owners; deleted sessions cannot persist or supply bearers; import/journal tests retain interruption and replacement coverage. |
| Auth delivery completed after retirement and a captured client could still send | The independent owned-model mutation guard protects canonical completed-owner API provenance. It does not prove DashboardClient's physical ordering, shared owner retirement or 401 retry timing. No static count/location assertion is substituted for a transport test. | `dashboard_oauth_test.dart`: acquire a real valid bearer, hold its delivery, first prove zero physical sends/dispatch callbacks, retire owner, release delivery, then prove zero effects before classifying the refusal. The paired counterfactual removes only final access checks. Already dispatched work is outside this guarantee. |
| Metadata silently accepted plaintext credentials under a false migration comment | The metadata constructor remains live. Resolved caller/root evidence distinguishes current metadata, secure payload and explicitly private opt-in input; negative name search alone cannot remove a branch. | `connection_manager_test.dart`: canonical metadata round-trips and every credential-bearing key, including null, is rejected. Existing secure-storage tests verify the manager's rejection before hydration. The opt-in device fixture parses its private credentials separately. |

The retirement guard's complete production contract has 31 deterministic
fixtures with actual CLI violation/clean/input-error exits. That count describes
one guard's fixture coverage, not 31 authentication properties. The corrected
190-file overlay includes ten migrated callers omitted from the first snapshot;
its paired analysis passed and the root runner recorded 221 focused passing
cases across fourteen test files. The failed earlier overlay and unheld
microtask-only test are retained privately: without first establishing a held
boundary, a send before retirement is legitimate and cannot establish a race.
Root recorded actual narrowly restored counterfactual failures for cancelled/
closed token delivery (two cases), exact password preservation (one), and
provisional refresh/disposal retirement (two). The first final-send
counterfactual established its held-delivery prerequisite but classified an
unexpected success before recording the physical count. A separate revised
fixture captures success/failure, asserts physical and dispatch effects first,
and is the authoritative paired final-send gate. Its original failed fixture
and logs remain preserved. This focused result does not claim whole-host,
real-device or current-stock live acceptance.

## Change locality and retained interface limits

Change the grant value/secure representation in `DashboardOAuthGrant`; change
native acquisition/cancellation in `HermesCloud`; change renewal, rotating-grant
save retries and bearer invalidation in `DashboardOAuthSession`; change secure
transaction/adoption/retirement authority in `ConnectionManager`; change final
HTTP authentication/send enforcement in `DashboardClient`. Network adapters
receive one `ConnectionAccess` and do not parse grant fields or construct refresh
owners. The owner instance is shared even where different feature adapters own
separate HTTP clients. HTTP pooling remains connection/adapter-scoped rather
than being confused with ownership of a rotating grant.

`ConnectionAccess` is a small authority-bearing input, not a new registry or
second refresh cache. The constructor checks descriptor-grant/owner ID and base
matching; the manager additionally validates current saved authority, and
`bearerFor` validates the actual requested destination. These are distinct
checks, not a claim that constructing an access value grants arbitrary endpoints. Its persistence snapshot is deliberately active-only and
used at provisional save; saved metadata may remain an immutable opening
snapshot after token rotation. The manager remains the sole saved registry and
secure commit owner. Callers pass access explicitly; neither a global lookup nor
a metadata-only constructor can silently manufacture authority.

This slice is not certification that setup is business-free: the setup screen
still composes candidate fields and owns route steps, while the probe and cloud
service own their existing checks and network seams. A future bounded setup
coordinator can deepen that seam when migrating the remaining view workflows.
The raw DashboardClient and secure manager also still share a library. Their
separation is a possible future locality improvement, not a correctness gate or
justification for adding another facade now. No actionably unsafe interface
remains established by this read-only review beyond the documented stock
non-atomic/after-dispatch limits and pending broader acceptance.


## Setup owner continuation (implementation awaiting acceptance)

The next bounded slice is `ConnectionSetupSession` and its immutable setup
state/draft, composed by `ConnectionSetupScreen.createSession`. Editing captures
`ConnectionManager.accessFor(existing)` once, so the descriptor and saved sign-in
have one authority. Cloud setup borrows that registry owner; newly authorized
owners belong to the route and are retired on replacement, cancellation/disposal,
or acknowledged durable handoff. The setup screen retains its existing Studio
layout and owns only text/focus controllers, modal/navigation interaction and
rendering. Its owner constructs candidates, normalizes addresses and headers,
validates fields, sequences discovery/sign-in/check/save, and rejects stale
attempt results. Storage retry repeats storage only, never verification or a chat
message.

The setup contract was rechecked against official upstream
[`eb044063235fbf7a4e68dd2970ade05dbe637ff3`](https://github.com/NousResearch/hermes-agent/commit/eb044063235fbf7a4e68dd2970ade05dbe637ff3).
The inspected native authorize/token/refresh routes, profile discovery and
scoped sessions remain the existing stock APIs. The stock `/api/ws` gateway
continues to provide the scoped chat connection check; setup sends no message.
No backend changes or compatibility readers are introduced.

`ARCH_COMPLETED_SETUP_VIEW` is a separate, local semantic boundary rule:
canonical connection/auth/probe construction, direct setup transport operations,
and address/header resolution belong outside the completed setup view. Its
41 valid/invalid/unsupported fixtures and source/AOT CLI exits have passed.
That does not establish race safety, durable storage behavior or all business
policy extraction. The public setup-owner scenarios and existing screen/cloud
journeys must pass separately; rendering must still be inspected in both themes
at normal and enlarged text. Setup timing budgets and these behavioral/render
acceptance gates remain pending.
