# Investigate and manage health alerts

Configure local thresholds, receive an incident, acknowledge or snooze it, and observe recovery or renewed escalation at the correct time.

Feature ID: `health-alerts`.

## Sub-features

- `health-alerts.configure` — Save valid local threshold rules.
- `health-alerts.respond` — Acknowledge or snooze the intended occurrence.
- `health-alerts.recover` — Clear or recur only on the qualifying observation.

## How to get to it (user POV)

Choose Hermes health → Alert settings. Change local thresholds; when an issue appears open the header warning triangle or brief notice. Acknowledge or snooze it, and inspect Health alerts for retained issues.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/health_alerts_test.dart test/health_alerts_ui_test.dart
  ```

- **Android `health-normal`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py health-normal --output build/feature-verification/health-alerts
  ```

- **Android `health-large`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py health-large --output build/feature-verification/health-alerts
  ```

- **Android `health-retention`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py health-retention --output build/feature-verification/health-alerts
  ```

## Gotchas

These are device-local in-app alerts, distinct from Android notifications. Durations, hysteresis, snooze deadlines and fresh recovery determine the outcome; a warning icon alone is not proof.
