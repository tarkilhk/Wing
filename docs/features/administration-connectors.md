# Configure MCP connectors

Open a connector, edit its configuration or complete its authorization, save for the captured profile, and recover or cancel setup.

Feature ID: `administration-connectors`.

## Sub-features

- `administration-connectors.configure` — Edit the captured connector.
- `administration-connectors.authorize` — Complete or cancel its access flow.
- `administration-connectors.recover` — Reconnect or retry without a stale setup taking over.

## How to get to it (user POV)

Open MCP connectors from Hermes administration or Bot settings. Choose a connector, inspect setup or access, edit supported configuration, and complete its sign-in or reconnection.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/profile_connectors_session_test.dart test/mcp_setup_test.dart test/mcp_oauth_test.dart
  ```

- **Device/external entry:** follow the user path on an authorized instance and capture its trigger/result. The host command does not establish that boundary. Report the attempted route and any missing driver or prerequisite.

## Gotchas

A connector test may launch its configured program. External authorization requires a real configured account; host OAuth tests do not certify that service.
