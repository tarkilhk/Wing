# Slash commands

Type `/` in the composer to browse the connected gateway's catalog. Search matches names, aliases and descriptions across commands, plugins and installed skills. Choosing a result inserts it into the draft; Send executes it. Argument completion uses the server's replacement offset. Refresh the workspace after changing skills.

## Dispatch contract

| Method/result | Client behavior |
| --- | --- |
| `commands.catalog` | Read names, aliases, descriptions and availability |
| `complete.slash` | Complete arguments at the returned replacement offset |
| `command.dispatch` | Resolve skills, bundles, user commands and plugins |
| `slash.exec` | Run a built-in only after dispatch explicitly reports that it does not own the command |
| `skill` / `send` | Submit expanded content through the normal attachment/streaming path, displaying the invocation |
| `prefill` | Return text to the composer for editing |
| `exec` / `plugin` | Show command output without starting a model turn |

An error or timeout must not trigger another handler and risk executing twice. Every request retains its profile and, where required, runtime session ID. Late results belong to that chat after navigation. Commands must not select a slash worker's unrelated CLI session.

`/yolo` uses the dedicated current-session configuration path and displays the server's effective state. It does not change global defaults. `/steer`, status, interruption and side questions can address an active turn; commands starting an ordinary turn wait for idle. Busy slash drafts use Send.

## Limits

Catalog presence is not proof of mobile support. Terminal-only, messaging-only and host-microphone commands retain their requirements; host microphone commands do not capture the phone microphone. A command can still be entered by name if the catalog is stale.

Display-only output stays in client memory, outside saved model history, and leaves attachments in the composer. Skills starting a turn use the existing upload path. Cold side-task recovery remains limited as described in [Queues and pending input](SUPERVISION_AND_QUEUES.md).

Modern profile-aware server handlers are required. Earlier patch experiments are historical and are not setup instructions for Wing. Do not modify a server to satisfy a client feature or infer current stock support from a patched test run.

Regression coverage lives in `test/slash_commands_test.dart`. The opt-in `test/slash_profile_live_contract_test.dart` and `integration_test/slash_commands_live_test.dart` compare disposable skills across two profiles. Read their fixture prerequisites before using an authorized server; see [Testing](TESTING.md).
