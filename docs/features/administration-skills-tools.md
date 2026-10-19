# Inspect and configure skills and tools

Browse skills, read instructions or references, inspect tool readiness, and save supported configuration with confirmed readback.

Feature ID: `administration-skills-tools`.

## Sub-features

- `administration-skills-tools.library` — Browse and read skill instructions.
- `administration-skills-tools.readiness` — Inspect setup requirements and capability state.
- `administration-skills-tools.configure` — Save supported tool settings with confirmed readback.

## How to get to it (user POV)

Open Skills and tools in profile administration. Browse installed skills or discovery, read instructions, inspect capability readiness, and open supported tool setup. A composer skill eye also opens its reader.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/profile_skills_session_test.dart test/administration_tool_setup_test.dart test/skill_reader_session_test.dart
  ```

- **Android `slash`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py slash --output build/feature-verification/administration-skills-tools
  ```

## Gotchas

Enabled does not mean ready. Bundled instructions are read-only. A successful skill reader does not establish that an external tool can execute.
