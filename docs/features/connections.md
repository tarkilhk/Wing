# Connect to Hermes

Verify and save or import a connection, reopen it securely, and recover from authentication or network failure without accepting a cancelled setup.

Feature ID: `connections`.

## Sub-features

- `connections.verify` — Validate credentials and connection details.
- `connections.save` — Persist and reopen the selected connection.
- `connections.recover` — Retry authentication or cancel setup safely.

## How to get to it (user POV)

Open connection setup at first launch or use the instance switcher to add a connection. Verify and save its host/authentication details, or import a shared connection, then reopen it.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/connection_setup_session_test.dart test/connection_setup_transport_test.dart test/connection_import_transaction_test.dart test/secure_connection_storage_test.dart test/connection_diagnostics_test.dart
  ```

- **Android `journeys`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py journeys --output build/feature-verification/connections
  ```

## Gotchas

A successful probe does not establish a saved connection. Reopen from Android secure storage. Cancelled or replaced setup must not acquire the next route.

Rejected HTTP writes record their method, endpoint family and status in phone
diagnostics. Logs omit authentication values, response bodies and conversation
content; diagnostics do not change write retry or error behavior.
