# Reference files, skills and commands

Choose a filesystem reference or skill while writing, or invoke a command, with the separate editable draft retained through loading and failure.

Feature ID: `composer-references`.

## Sub-features

- `composer-references.files` — Choose a filesystem reference.
- `composer-references.skills` — Inspect or insert a skill.
- `composer-references.commands` — Select and dispatch a supported command.

## How to get to it (user POV)

Type @ for server references or bot mentions. Type / while writing for skills, or at the start for commands. Use a skill eye icon to inspect instructions without altering the draft.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.
  The workspace matrix checks that bot and file suggestions can be tapped above
  the composer at 320 dp/200% text with the portrait keyboard open, retaining
  the selected reference, authored draft and cleared IME composition.

  ```sh
  flutter test --no-pub test/composer_references_test.dart test/profile_references_test.dart
  ```

- **Android `slash`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py slash --output build/feature-verification/composer-references
  ```

## Gotchas

The same slash behaves differently at the start and inside a message. Wait for received suggestions rather than a fixed delay. A command with an uncertain result must not be repeated blindly.
