# Provider views use application commands

`ARCH_PROVIDER_VIEW_PROTOCOL` checks the completed inventory and credential/device-sign-in libraries:

- `lib/core/screens/administration/admin_providers_page.dart`
- `lib/core/screens/administration/admin_provider_credentials.dart`

Actual parts inherit their containing library. The existing provider-recovery detail slice remains separately owned and is not certified by this guard.

Syntax cheaply selects protocol and canonical wire-parser names. Findings require analyzer-resolved canonical declaration provenance: `ProfileAdministration`, `AdministrationRepository`, `DashboardClient`, the new provider metadata/device value factories and parsers, `administrationRows`, `providerInventoryStatus`, or `dart:convert.jsonDecode`. Calls, method/capability tear-offs, named factory calls/tear-offs, aliases, barrels, inherited members, cascades and parts are covered by fixtures. Same-named unrelated declarations and passive typed values are allowed. Dynamic/unresolved candidate accesses and conditional candidate dependency provenance fail as input errors; a single selected platform is not an all-platform proof. This finite rule does not claim to detect every invented wire parser or business expression.

Run independently:

```sh
dart run tools/architecture/rules/provider_view_protocol.dart --root . --json
dart run tools/architecture/tests/provider_view_protocol_test.dart
```

SDK selection uses the shared validated `tools/architecture/dart_sdk.dart` helper, including explicit `--sdk PATH` for compiled binaries outside the checkout. A supplied invalid SDK fails even without candidates. The optional fixture runner `--compiled PATH` proves compiled bad/valid/input exits and exact locations alongside the interpreted standalone command.

Exit codes are 0 for valid, 1 for a canonical view violation, and 2 for unverifiable/invalid input. Fixtures assert diagnostic ID/file/line and execute the real standalone CLI for all three exits. The host wrapper has a two-minute correctness watchdog. Warm compiled full-checkout feedback target is one second; interpreted startup target is fifteen seconds. Measurements and compiled executables belong under ignored `build/`, not in public Git. The targets are not device-performance claims.

## Behavioral ownership contract

Current upstream was read at `33eedf29c941a192032b71ded8c719cbf63ca63a`: `hermes_cli/web_routers/config_env.py`, `hermes_cli/web_routers/oauth.py`, `hermes_cli/credential_lifecycle.py`, `hermes_cli/web_models.py`, and `hermes_cli/web_server_oauth.py`. Client changes require no backend mutation or extension. Env PUT/DELETE acknowledge JSON `ok:true` plus the exact key. Device start uses canonical `session_id`, `flow`, `user_code`, `verification_url`, `expires_in`, and `poll_interval`; polls and cancellation acknowledgements carry the exact session ID. Missing fields and unsupported status aliases are rejected, not supplied by compatibility readers. DELETE is the strict owned physical HTTP capability, never a generic transport fallback.

`ProviderInventorySession` retains good immutable safe metadata when a refresh is malformed. Environment fields omit token previews and secret values. `ProviderCredentialEditSession` retains only the explicit password draft and safe metadata, checks current editability/stored-state and profile membership, and supplies required per-call dispatch authority revoked on retirement/settlement. A dispatched unconfirmed change keeps the draft and requires an explicit fresh metadata review before another explicit action. Stock cannot atomically compare a credential version, and an `is_set` observation cannot verify its exact value.

`ProviderDeviceSignInSession` owns one exact attempt, one poll, a fixed client lifetime of at most fifteen minutes, and captured cleanup leases. A current canonical `session_id` is captured separately for cleanup even when required display fields are malformed; invalid/missing identities never authorize a guessed cancellation or an alias read. Display rejection still blocks replay regardless of cleanup success. A retired successful start cancels its returned identity without publishing; disposal cancels a known pending identity even while a read is held. An accepted cancellation drains after route retirement. Deadline cleanup is explicit, and failed cleanup cannot authorize another attempt. A delivered start without a usable confirmed session cannot be automatically replayed: stock exposes no idempotency or unknown-start reconciliation operation. Cleanup failure remains unconfirmed; client code cannot promise remote cancellation without a stock acknowledgement.

Runtime regressions are in `test/provider_inventory_session_test.dart`, `test/provider_credential_edit_session_test.dart`, `test/provider_device_sign_in_session_test.dart`, and the public `test/provider_credential_lifetime_test.dart`. They control membership, physical send, already-dispatched response and poll completion. They check retained malformed observations, channel/custom ownership, changed stored-state, uncertainty/review, held-auth-like timeout settlement, exact cancellation, deadline behavior and late completion. The pure value probe is `tools/architecture/tests/provider_values_test.dart` (host wrapper `test/provider_values_guard_test.dart`). The static rule does not prove these races, backend atomicity, device UI quality, or actual credential validity.

Bare inherited getter/method capability capture is also selected and requires canonical resolved declaration provenance. A same-named local parameter/reference is accepted; fixtures protect both cases.

`test/provider_view_protocol_guard_test.dart` enforces both the actual complete-scope production CLI and the independent fixture runner in the full host test gate. Fixture success alone is not a production scan; a clean no-candidate production scan alone is not resolver correctness.
