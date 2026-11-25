# Schedule and inspect recurring work

Create from a template or edit a task, choose its time and destination, inspect history, and keep mutations tied to the intended profile and visit.

Feature ID: `scheduled-tasks`.

## Sub-features

- `scheduled-tasks.create` — Create or edit a typed schedule, its timezone,
  missed-run policy, late-run window and delivery, including discovered groups
  and inherited/on/off output wrapping.
- `scheduled-tasks.inspect` — Read task details and recent runs.
- `scheduled-tasks.control` — Pause future runs, resume, run now, or stop the
  current execution without changing its schedule.

## How to get to it (user POV)

Open Hermes administration → Profile → Scheduled tasks, or use the selected bot settings. Choose New task, use a server template if available, set instructions/time/delivery and create. Open a task or its Actions menu to inspect, pause or resume it.

See the [scheduled-task guide](../SCHEDULED_TASKS.md) for timing and delivery semantics.

In the ordinary editor, Schedule timezone accepts an IANA name; empty inherits
the Hermes profile timezone. Missed runs can inherit, run one catch-up or skip.
Late-run window applies to cron schedules and accepts 0–1440 minutes or empty
for the computed window. Run one catch-up permits a catch-up beyond that window.
Templates retain their own settings; edit the created task to change its policy.

Results → Output wrapping chooses Hermes default, On or Off for delivery headers
and footers, including script-only tasks. Hermes default follows the profile
setting without claiming its effective value. Selecting it clears an override;
untouched settings are preserved. Details show the saved choice. Conflicting
edits use the existing Keep mine/Use server review; mismatched create or update
readback remains uncertain and is never automatically resubmitted.

Results lists discovered group chats alongside platform destinations. A result's
`@mentions` wake the named bots (`@all` addresses all); without mentions the
result is informational. Failure notices do not start a round. A group's hosting
profile remains distinct from the task's profile.

A live task offers the icon-only Stop run action in its detail and Actions menu,
including while its Run now request is still waiting for execution to finish.
Stop has its own pending feedback and duplicate-request guard; it does not
release the pending Run now request or enable conflicting edits.
Stop requested is an acknowledgement, not proof of completion: the running state
remains until Hermes reports settlement. A newer rejected Run now attempt cannot
hide an older execution that is still running. Latest attempt and recent history
retain cancelled/missed outcomes and their supplied reasons.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/scheduled_tasks_edit_session_test.dart test/scheduled_tasks_screens_test.dart test/scheduled_tasks_blueprint_contract_test.dart
  flutter test --no-pub test/scheduled_tasks_repository_test.dart test/scheduled_tasks_controller_test.dart test/scheduled_tasks_schedule_projection_test.dart
  ```

- **Android `scheduled-tasks`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py scheduled-tasks --output build/feature-verification/scheduled-tasks
  ```

- **Native observable result:** the scenario runs in light/dark at normal and
  320 dp/200% text. It taps `New task`, enters `Android acceptance` in
  `Name (optional)` and `Prepare a daily summary.` in `Instructions`, and selects
  Output wrapping → On. The actual Android keyboard is open and both footer
  actions remain above it. `Create task` shows visible progress during the held
  write; the confirmed row appears. `Actions for Android acceptance` →
  `Pause schedule` disables it, and its detail offers `Resume and run`. Editing
  wrapping to Off exercises held-save failure, retained selection and successful
  retry. Reopening confirms Off; choosing Hermes default sends an explicit reset
  and reopens as inherited. Back returns from the detail. Captures include the
  selector popup, detail, held create/save, failed save and reopened reset.

For real-backend Android verification, use the focused `wrapping` suite in the
[existing production gateway recipe](multi-surface-journeys.md#selected-hermes-features-on-an-existing-production-gateway).
It requires isolated QA mutations and the stated provider prerequisites.

## Gotchas

Hermes owns schedule time; the phone displays run timestamps locally. Unedited
policy values and exact schedule expressions are preserved. Clear a late-run
window explicitly before switching to an interval or one-time schedule. External
schedulers control their own delivery/retry timing. Run now can execute real work
and leaving does not cancel it. A paused task requires Resume and run. The native
fixture creates tasks but never runs a provider or production scheduler.

Deleting a task also requests cancellation of running work in current Hermes.
Lost cancellation responses remain uncertain and are never automatically repeated.
Review that request before another Stop; refreshing observes execution state
without resending the cancellation.
Unavailable room discovery keeps existing selections and platform destinations.

For authorized Android + production acceptance, use the `groups` suite in the
[existing-gateway journey](multi-surface-journeys.md#selected-hermes-features-on-an-existing-production-gateway).
It uses fresh owned profiles, exact group/task cleanup and real provider execution.
