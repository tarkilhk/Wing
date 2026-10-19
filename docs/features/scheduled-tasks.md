# Schedule and inspect recurring work

Create from a template or edit a task, choose its time and destination, inspect history, and keep mutations tied to the intended profile and visit.

Feature ID: `scheduled-tasks`.

## Sub-features

- `scheduled-tasks.create` — Create or edit a typed schedule and delivery.
- `scheduled-tasks.inspect` — Read task details and recent runs.
- `scheduled-tasks.control` — Pause resume or request an explicitly admitted run.

## How to get to it (user POV)

Open Hermes administration → Profile → Scheduled tasks, or use the selected bot settings. Choose New task, use a server template if available, set instructions/time/delivery and create. Open a task or its Actions menu to inspect, pause or resume it.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/scheduled_tasks_edit_session_test.dart test/scheduled_tasks_screens_test.dart test/scheduled_tasks_blueprint_contract_test.dart
  ```

- **Android `scheduled-tasks`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py scheduled-tasks --output build/feature-verification/scheduled-tasks
  ```

- **Native observable result:** the scenario taps `New task`, enters `Android acceptance` in `Name (optional)` and `Prepare a daily summary.` in `Instructions`, then taps the `Create task` tooltip action. The new row must exist; `Actions for Android acceptance` → `Pause schedule` disables it, and its detail offers `Resume and run`. The keyboard is actually open, and Back returns from the detail.

## Gotchas

Hermes owns schedule time; the phone displays run timestamps locally. Run now can execute real work and leaving does not cancel it. A paused task requires Resume and run. The native fixture creates tasks but never runs a provider or production scheduler.
