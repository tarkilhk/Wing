# Connected user journeys

Use several features together and retain the exact connection, profile, conversation and draft throughout a journey.

## Sub-features

- `journeys.connect-reopen` — verify and save a connection, enter its workspace, leave and reopen its credentials.
- `journeys.conversation` — find a chat, prepare a referenced/attached prompt, send or queue it, inspect Activity and revisit a saved answer.
- `journeys.restore` — restore staged work after process death without repeating a submission or upload.
- `journeys.notification` — receive, open, read or dismiss a request in the exact conversation, including cold entry.
- `journeys.voice` — grant/refuse permission, record or cancel, play or interrupt and recover a missing capability.
- `journeys.stock` — create/edit/delete a disposable stock-Hermes profile and project through Android controls.

## How to get to it (user POV)

Start with [connection setup](connections.md), then [Chats](chat-browser.md), [conversation work](chat-inputs.md) and [Activity](chat-activity.md). For OS entry paths start from the notification shade, Android Home, share sheet or [voice controls](voice.md). [Profile administration](profiles.md) begins in the drawer or Bot settings.

## Driving it with Wing harnesses

Preconditions: [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Each command owns its disposable emulator and keeps named receipts under the supplied output directory.

```sh
python3 scripts/test_journeys.py --output build/feature-verification/journeys
python3 scripts/test_nightly_native.py notification-cold --output build/feature-verification/journeys
python3 scripts/test_nightly_native.py voice --output build/feature-verification/journeys
```

The first command requires all four critical journeys, all nine roadmap journeys and actual outbox process-death recovery. Its named outcomes cover uncertain Send beside a newer draft; profile/project navigation; model/reference/find/output controls; approval/queue ownership; child/parent work; saved-answer edit/regenerate/fork; and scoped administration/update refusal. Read those outcomes rather than inferring coverage from the suite title.

For the real stock-backend boundary, prepare a clean checkout of current [official Hermes main](https://github.com/NousResearch/hermes-agent), with no project `.env` or untracked files. Create its `.venv` and install its web dependencies using `.venv/bin/python -m pip install -e ".[web]"` from that checkout, matching the preparation in [nightly CI](../../.github/workflows/nightly-tests.yml). Set `WING_HERMES_SOURCE` to that checkout, then run from the Wing root:

```sh
python3 scripts/test_vanilla_hermes.py --hermes-source "$WING_HERMES_SOURCE" --output build/feature-verification/stock
```

`WING_HERMES_SOURCE` must point to the inspected stock checkout. The runner owns a temporary backend/profile dataset and exercises the profile/project production UI. It does not authorize a deployed-server upgrade or provider-charged generation.

The host `flutter test --no-pub test/conversation_assembly_test.dart` recipe also exercises group discussions and read-only working histories in both themes and text sizes, including reading-mode return and retained group drafts above the landscape keyboard.

Phone reading is covered by the `transcript-expansion` family: enter table reading mode, rotate, return to the retained draft, reveal composer controls and use Back without leaving the chat.

## Gotchas

Fixture native journeys, stock transport and deployed-provider acceptance prove different boundaries. Android owner recreation is not process death; require the separate process-recovery verdict. Keep each failed aggregate failed even when a focused recovery passes. Do not sum overlapping case counts. Run families serially on this workspace; retain artifacts after the owned emulator and backend are retired.
