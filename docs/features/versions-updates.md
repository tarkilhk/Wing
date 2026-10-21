# Inspect versions and control updates

Check available versions, confirm an exact update target, follow status and read long logs; refuse a stale or changed target.

Feature ID: `versions-updates`.

## Sub-features

- `versions-updates.check` — Read current and available versions.
- `versions-updates.confirm` — Admit only the exact confirmed update target.
- `versions-updates.follow` — Follow progress automatically and scroll newest-first logs in a viewer capped at 16 text rows. The single rightmost sync control checks progress while an update is outstanding and availability otherwise.

## How to get to it (user POV)

Open connection details and its Versions/server-update controls. Check availability, inspect the exact target and confirmation, then follow status or independently scroll the log.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/backend_update_controller_test.dart test/backend_version_card_test.dart test/backend_update_model_test.dart
  ```

- **Android `journeys`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py journeys --output build/feature-verification/versions-updates
  ```

## Gotchas

The fixture journey proves refusal of a changed target, not a real server upgrade. A deployed update requires separate operator authorization. Readable log scrolling must not move surrounding actions. The sync control keeps its horizontal position before, during and after an update; explicit progress reads acknowledge the wait, while automatic snapshots remain quiet. The host card suite checks both themes and enlarged text, independent inner scrolling and the 16-row viewport.
