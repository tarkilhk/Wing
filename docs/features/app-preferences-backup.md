# Personalize and back up Wing

Change appearance or device preferences, export connections and settings, then restore them with the intended passphrase and credential retention.

Feature ID: `app-preferences-backup`.

## Sub-features

- `app-preferences-backup.personalize` — Save and preview device preferences.
- `app-preferences-backup.export` — Write the chosen backup through Android.
- `app-preferences-backup.restore` — Read back settings and credentials with explicit outcomes.

## How to get to it (user POV)

Open App settings from the drawer. Change theme, accent or text size. Use its export/restore controls to back up connections/preferences with an optional passphrase, then review a restore result.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/app_preferences_test.dart test/app_preferences_pending_authority_test.dart test/backup_restore_outcomes_test.dart test/config_backup_exact_credentials_test.dart
  ```

- **Android `journeys`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py journeys --output build/feature-verification/app-preferences-backup
  ```

- **Android `backup`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py backup --output build/feature-verification/app-preferences-backup
  ```

## Gotchas

Backup contains sensitive connection material. Use only owned fixture data and retain exact credential semantics. Wrong passphrases and storage/provider failures must preserve the existing configuration.
