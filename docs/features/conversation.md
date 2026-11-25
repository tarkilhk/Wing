# Read and search conversation history

Open saved or streaming history, search older messages, page through a long conversation and return to the previous reading position.

Feature ID: `conversation`.

## Sub-features

- `conversation.read` — Reconcile live and saved messages. Steering becomes a normal user bubble when it appears in saved history, including on reopen and cached reading; see the [steering recipe](chat-inputs.md#gotchas). Saved history opens independently of runtime attachment; an attachment refusal keeps messages and drafts visible, with Retry to enable sending.
  A known project's name and icon remain in the conversation header during
  reopening, offline reading and failed workspace refreshes. An incomplete
  membership read retains that project; confirmed reassignment or removal
  replaces it.
- Normal chats, canonical Bot Chats and group discussions share the conversation frame and reading layout. Passive Recents cards use the same frame and composer presentation.
- Automated updates stored by Hermes as `user` + `internal_notification` appear as assistant messages, including formatted content, Copy and the assistant identity in Find. Their stored role stays unchanged; these updates are not editable human prompts or regeneratable answers.
- `conversation.reading-mode` — Use a table’s full-screen icon to hide the composer and portrait context row without leaving the conversation. The same icon or Android Back restores it; drafts remain intact. Landscape puts title and scope in one header row.
- `conversation.email-draft` — With Wing plugin 0.3.0 enabled in the selected Hermes profile and its email tools available, ask Hermes to draft an email. A returned `wing-email-draft` card shows To, optional Cc/Bcc, subject and full body. Tap the envelope-arrow icon (Open in email app) to choose a composer with those exact fields. Sending and final edits happen there. Older cards keep their original version after revisions. Missing drafts show Retry; ordinary email prose is not interpreted as a draft.
- `conversation.search` — Find and open older content.
- Async delegation completion flags keep model-facing wake text out of conversation bubbles and Find. Useful completion results remain in Activity and searchable; quoted examples stay readable.
- `conversation.position` — Page and return without losing reading position. Leaving for another thread or app keeps the current reading location, including at Latest. After sending and leaving before the reply, return to the sent message and the beginning of the reply. Opening a popup or changing a chat's decoration keeps the current viewport without starting another history restoration.
- Child activity uses this same reading viewport. Its bounded saved window preserves a surviving reading point; automatic replacement waits when that point would disappear. Explicit Refresh can return to Latest. See [child reading and recovery](chat-activity.md#gotchas).
- `conversation.recovery` — Read the structured reason for a failed turn, inspect its details and use a supplied model or provider recovery action. Selecting a model preserves the draft and never resends the failed turn.
- `conversation.context` — Tap the composer context ring to inspect occupancy and separately reported prompt-cache timing. Opening and Retry show local progress; failed reads retain the previous report. The popover preserves the draft and keyboard and closes when leaving the chat. See [cache details and their focused recipe](model-selection.md#driving-it-with-wing-harnesses).
- `conversation.git-review` — Open Chat actions → Git review for a reported local terminal workspace. Read changed files, All changes (working tree versus HEAD) and Staged (index versus HEAD), then copy an exact changed-line or hunk reference.

Refused prompts remain readable with their explanation in a distinct passive
block. They retain their saved identity through Find, reopening and offline
reading, with no Copy, Edit, Restore or replay action. A live refusal removes its
matching partial answer before history loads; newer drafts remain intact.

## How to get to it (user POV)

Open a chat from Chats, Bots, Recents, a notification or a [teammate delivery](bots.md#teammate-delivery-verification) in Background. Teammate entry resolves the exact existing Bot Chat on the same instance and shows the destination while loading. Read older messages, choose Find in chat from its menu, open a result, then return to your reading position or Latest.

Opening a reply notification positions the beginning of its answer in view,
even when the answer spans several screens. This explicit destination takes
precedence over the remembered reading position.

## Driving it with Wing harnesses

Preconditions: use the [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Use the [verification workflow](../../.agents/skills/verify-wing/SKILL.md) for launch, readiness, evidence and cleanup.

- **Host boundary:** run the focused suites below; their supplied transport/platform responses limit the proof.

  ```sh
  flutter test --no-pub test/profile_history_search_test.dart test/conversation_routes_test.dart test/conversation_reading_position_test.dart test/conversation_assembly_test.dart test/profile_row_actions_test.dart test/connection_diagnostics_test.dart
  ```

  Conversation project retention and recovery use:

  ```sh
  flutter test --no-pub test/profile_workspace_browser_test.dart --name 'conversation keeps known project|chat project appearance'
  flutter test --no-pub test/profile_recents_test.dart --plain-name 'incomplete project membership keeps the known conversation project'
  ```

  The header tests hold reopening and drive Refresh workspace through held
  project reads, failure and retry in both themes at normal and doubled text.
  The membership test also verifies that a later confirmed removal clears the
  earlier lookup failure and displays Unassigned.

  Internal-message visibility, saved-history refresh, Find and unchanged raw
  history identities are covered by:

  ```sh
  flutter test --no-pub test/internal_message_visibility_test.dart
  flutter test --no-pub test/profile_composer_actions_test.dart --plain-name 'automation start preserves'
  ```

  The internal-notification cases exercise the real conversation route in both
  themes at normal and doubled text size, history refresh, exact source copying,
  Find identity, cached-row projection and unchanged stored roles/action rights.
  `message_timestamp_test.dart` also covers notification layout in Bot Chats.

  The reading-position suite covers thread departure, covered conversations,
  app return and local prompts becoming saved history. The row-action suite
  opens a saved answer without an extra swipe, holds its read receipt, then
  checks the cleared unread state through Chats and Recents in both themes
  at normal and doubled text size. A prepared answer body line must be visible;
  an avatar, message actions or a clipped leading sliver alone leaves it unread.
  The reading-position suite covers that boundary before Latest reveals the body.
  `test/unread_runtime_repro_test.dart` replays
  a refused or held live attachment, checks the visible answer and exactly one
  fenced read receipt, then enters Chats and Recents through their real controls.
  Its Android wrapper runs the same contract on an owned API36 emulator:

  ```sh
  flutter test --no-pub test/unread_runtime_repro_test.dart
  flutter test --no-pub --no-uninstall -d <owned-api36-emulator> integration_test/unread_runtime_native_test.dart
  ```

  Reopened chats also
  load older pages when a swipe reaches the start of a short loaded page;
  later replies stay available below the remembered reading position. The
  paging cases hold the read, complete it and continue scrolling into the
  newly loaded replies. For the real Send control
  and rendered reply beginning in both themes at normal and enlarged text:

  ```sh
  flutter test --no-pub test/profile_composer_actions_test.dart --plain-name 'Send then app return'
  ```

- **Android `journeys`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py journeys --output build/feature-verification/conversation
  ```

- **Android `transcript-expansion`:** the owned-emulator driver exercises its named production-control scenarios. Require the strict receipt and [shared proof rules](../FEATURE_MAP.md#driving-and-proof); read the completed names to establish which paths ran.

  ```sh
  python3 scripts/test_nightly_native.py transcript-expansion --output build/feature-verification/conversation
  ```

### Read-only saved-chat contract on an existing server

With authorized diagnostic access, supply the gateway Webapp base URL, a private
username/password JSON file and a profile containing saved messages:

```sh
WING_HERMES_URL='https://<gateway-webapp-host>' WING_HERMES_LOGIN_FILE=/path/to/private-login.json WING_HERMES_PROFILE='<profile>' flutter test --no-pub test/existing_backend_readonly_live_test.dart
```

The named `existing saved chats reopen with canonical authority and readable
history` case reads up to three nonempty chats through production
`ProfileGateway`, mounts each over a fresh authenticated socket, accepts its
canonical authority and reads saved history twice. Empty seed data fails. The
suite reports the running backend commit and reopened count without printing
transcripts or credentials. It does not send messages, acknowledge reading,
change settings or update Hermes. This proves the deployed read contract;
Android navigation and composer behavior remain separate journey checks.
The gateway case also requires `session_authority == true` in the `gateway.ready` event payload.
Stock standalone Dashboard can pass login and ping while serving a different
session API; a current version or accepted subprotocol does not establish
canonical session support.

To check one reported conversation through the production workspace controller,
add `WING_HERMES_SESSION='<saved-session-id>'` to those environment variables and
select `--plain-name 'requested saved conversation'`. It requires nonempty saved
history before attachment completes, then reports whether canonical attachment
succeeded or a visible attachment failure remains. This targeted case establishes
readability, not permission to force takeover or proof of message submission.

Both sides of live voice appear as local chat entries labelled “Not saved to Hermes”.
They survive call ending, history refresh and chat switching while Wing runs;
they have Copy but no saved-message edit, restore or regenerate actions. They
are not included in server history search or Hermes memory.

A live voice call captures its original conversation. Browsing another chat does not retarget it. Voice delegates through the canonical queue/steering/stop owner; ending voice releases its retention lease without interrupting work. See [voice](voice.md).

The real delegated-child case in the [production gateway recipe](multi-surface-journeys.md#selected-hermes-features-on-an-existing-production-gateway)
also verifies that the parent's background completion settles into saved history
without a manual refresh. Controller regressions replay canonical running
observations independently of approval-request inventory.

## Gotchas

New chats carry Wing's mobile client identity and installed version, including
ordinary, project, replacement and canonical Bot Chat creation. See the
[connection attribution checks](connections.md#gotchas). Existing chats retain
their server-owned creation metadata.

Find's pinned Search result header scrolls within its available height when a
closing keyboard briefly leaves less space than the header needs. Back to latest
keeps its full touch target. `profile_composer_actions_test.dart` exercises this
return path with ordinary and refused rows at native density and keyboard size;
`profile_transcript_test.dart` retains normal and 84dp pinned-header checks.

A received content refusal keeps the failed-turn and queue state, but uses the
specific Message refused status. Its inline explanation replaces the generic
failure-recovery card and does not offer provider/model settings. If a refusal
notification still awaits a visibility receipt, a passive status notice keeps
that exact target reachable until read; an earlier assistant cannot clear it.
Reopening the same idle runtime retains its received failure and explanation
together, even when resume omits inflight data. Starting another turn or replacing
the runtime clears those facts; saved refusal rows never recreate live authority.
An idle resume with a greater known execution generation also retires the old
failure; it does not claim that unseen later turn succeeded.

Hermes retains a refused prompt for display while excluding its turn from model
context. Wing shows the supplied saved explanation and never resends that row.
If live input identity is unavailable, Wing preserves the unidentifiable prompt
until authoritative history arrives while retiring identified partial output.

```sh
flutter test --no-pub test/reading_snapshot_message_test.dart test/reply_segment_identity_test.dart test/workspace_reading_snapshot_test.dart test/subagent_timeline_session_test.dart
flutter test --no-pub test/profile_composer_actions_test.dart --name 'refus'
python3 scripts/test_journeys.py --case 'refused turns retain their text through settlement and reopening' --capture-frames --output build/feature-verification/refused-turns
```

The Android case uses Send, holds completion history, checks the distinct refusal
and retained draft, searches its original text and reopens the saved row. It
captures both themes at normal and enlarged text. Host cases additionally cover
failed history, offline owner recreation, identical text on separate admissions,
late completion and passive child replay. These fixtures do not invoke a provider
safety filter or mutate a deployed backend.


Streamed replies use Hermes turn, segment and UTF-16 offset identities. Replayed
segments appear once; identical words in different segments remain separate.
A partial reply retained across reconnect or process restoration belongs to its
execution admission, including an unknown execution. A queued successor cannot
keep an earlier reply alive. A successful saved-history read retires settled
local rows; a failed read preserves them. Command and review notices keep their
place between retained reply segments, including segments with identical text.

```sh
flutter test --no-pub test/reply_segment_identity_test.dart test/reading_snapshot_message_test.dart test/workspace_reading_snapshot_test.dart
```


When Hermes cannot confirm chat ownership, Wing shows the saved messages and
keeps the draft. Sending remains unavailable until normal attachment succeeds.
If the chat is open in another app, close it there, then use Retry. The refusal
alone does not prove another app holds it; Hermes can also fail to verify its
ownership records. Wing does not force ownership away from another process.
Retry shows the pulsating Wing in the header while messages stay usable.
Temporary connection failures and resume snapshots superseded by newer live
updates recover automatically, retaining messages and drafts. Retries continue
with delays capped at 30 seconds; permanent ownership refusal still requires the
recovery described above. See the [connection recovery recipe](connections.md).
Clients sharing a chat must use the same canonical gateway. A standalone
Dashboard on the same machine can hold an independent runtime over the same
saved transcript; sharing the host or database does not establish shared access.
The host recovery recipe exercises the real Recents control, readable history
during held attachment, refused sending, retained drafts and successful retry
in both themes at normal and enlarged text sizes:

```sh
flutter test --no-pub test/recent_conversation_switcher_test.dart --name 'Recents tap enters chat before held resume and history.*coordination'
```

Git review uses read-only stock Hermes endpoints. It does not stage, revert,
commit or push. SSH, Modal and per-session container paths are not treated as
host paths. An empty response says no changed files were reported, rather than
claiming the workspace is a clean Git repository. The host suites
`git_review_test.dart` and `git_review_screen_test.dart` cover read ownership,
late replies, comparisons, copy references, pending feedback and recovery.

Seeing the latest saved answer in the active conversation marks the chat read, including after opening, returning or tapping Latest. This also applies while live attachment is pending or refused; readable saved history does not require a live runtime to acknowledge shared read status. Older-history and passive previews do not acknowledge an unseen latest answer. Saved reading positions last until Wing restarts. Long-history host tests cover paging beyond the small Android fixture.
Pending-input navigation stays outside the form: below it at normal height,
or in a separate side gutter on short keyboard-open screens. The form and
composer retain scrollable access to their full action targets.

After reopening, use **Input needed** to reach a new question while preserving
the reading point until that action. Bot and Recents regressions verify visible
messages rather than raw scroll offsets, because restoring around a saved row
changes the scroll origin. The shared `settleTranscript` test helper waits for
rendered history restoration and real Markdown workers; advancing only the test
clock cannot complete worker I/O.

```sh
flutter test --no-pub test/bots_view_test.dart test/bot_group_view_test.dart test/recent_conversation_switcher_test.dart test/saved_message_actions_test.dart test/profile_conversation_ui_test.dart
```

Automatic read-acknowledgement failures are logged in the phone's diagnostics
without a conversation warning. Failed acknowledgement still leaves the chat
unread for retry; explicit Mark as read actions retain their failure feedback.
The row-action viewport regression checks rejection, diagnostic output and later
successful acknowledgement in both themes at normal and enlarged text sizes.

### Structured email draft verification

```sh
flutter test --no-pub test/email_draft_test.dart test/profile_conversation_ui_test.dart test/selection_viewport_test.dart
```

The production Markdown/card path checks exact version references, complete long
Unicode payloads, waiting reads/chooser feedback, failed reads and retry, missing
email apps, profile replacement, departure, malformed references and completion
of streaming fences. Phone layouts cover light/dark themes and enlarged text.
Subject and body selection use the shared viewport owner so hidden selection
handles cannot escape the conversation's visible reading area.
The chooser payload is a platform-channel fixture; third-party composer handling
requires a device with an email app. The plugin must be installed/enabled per
profile; its draft tool must produce the reference. No account or voice provider
credentials are required for drafts. Plain chat continues to use ordinary links.

Replies to voice-submitted Hermes work are folded under “Hermes task details”
while the original chat reading is retained. Expand to inspect the native result
and its saved actions. GPT-Live’s spoken reply stays directly readable as a local
voice entry. Correlation uses native IDs, never matching prose.
