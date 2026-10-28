# Edit bot identity and behaviour

Edit instructions, identity or settings, review a conflict, and save only intended changes while retaining the draft after failure.

Feature ID: `administration-behavior`.

## Sub-features

- `administration-behavior.draft` — Edit identity instructions or settings.
- `administration-behavior.conflict` — Compare current and edited values.
- `administration-behavior.save` — Confirm intended fields while retaining failed drafts.
- `administration-behavior.prepared-compression` — Explicitly enable or disable
  preparing a compression summary ahead of need. The stock default remains off.
- `administration-behavior.subagent-route` — Choose the default provider/model for
  new delegated agents, or inherit their parent's route, with one confirmed save.

## How to get to it (user POV)

Open Settings or Identity for the selected profile in Hermes administration or Bot settings. Edit a value, compare a conflict if offered, then use Save or Close.

Open Behavior → Compression for Prepare compression ahead. It can reduce pauses,
but a prepared summary may consume tokens even if it is discarded.

Open Models and reasoning → Subagent model to choose a route through the shared
model picker. Selecting a catalog model or Inherit parent model clears a previous
direct endpoint, key and protocol together on Save. Auxiliary helper models are
separate. Existing subagents keep their current route.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/settings_edit_session_test.dart test/settings_edit_lifetime_test.dart test/profile_identity_edit_session_test.dart
  flutter test --no-pub test/delegation_model_session_test.dart test/upstream_capabilities_ui_test.dart
  ```

- **Android `administration`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py administration --output build/feature-verification/administration-behavior
  ```

## Gotchas

Unsaved text is local to the editor. Refresh, save/readback and another client changing the same field are distinct transitions. Close must retain or discard only what the current form permits.

The subagent editor treats provider, model and direct endpoint fields as one
route for conflict checking. Keep my choice explicitly rebases that route;
Use current route discards the local route and reads the current configuration.
Neither choice displays endpoint credentials.
