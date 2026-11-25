# Connected user journeys

Use several features together and retain the exact connection, profile, conversation and draft throughout a journey.

## Sub-features

- `journeys.connect-reopen` — check a connection without moving the form, inspect its status LEDs, use Next or animated swipes with results retained for five minutes, then save it, enter its workspace, leave and reopen its credentials.
- `journeys.conversation` — find a chat, prepare a referenced/attached prompt, send or queue it, open the compact live Reasoning stack to inspect newest-first reasoning titles and tool results without losing the draft, and revisit a saved answer.
- `journeys.restore` — restore staged work after process death without repeating a submission or upload.
- `journeys.notification` — receive, open, read or dismiss a request in the exact conversation, including cold entry. Reply alerts open at the beginning of the answer after its formatted content settles.
- `journeys.voice` — grant/refuse permission, record or cancel, play or interrupt and recover a missing capability.
- `journeys.hub-skill-updates` — inspect reported Hub skill updates while browsing, retry an unavailable check, cancel or run the profile-scoped group update and inspect its result and fresh availability.
- `journeys.stock` — create/edit/delete a disposable stock-Hermes profile and project through Android controls.

## How to get to it (user POV)

Start with [connection setup](connections.md), then [Chats](chat-browser.md), [conversation work](chat-inputs.md) and [Activity](chat-activity.md). For OS entry paths start from the notification shade, Android Home, share sheet or [voice controls](voice.md). [Profile administration](profiles.md) begins in the drawer or Bot settings.

The [Hub skill updates recipe](administration-skills-tools.md#driving-it-with-wing-harnesses)
starts in Skills and tools → Manage capabilities → Discover skills. Its one
named journey includes both themes, standard/extra-large text, actual search
keyboard, held check/dispatch/readback and independent error/retry recovery.

## Driving it with Wing harnesses

Preconditions: [shared baseline](../FEATURE_MAP.md#baseline-preconditions). Each command owns its disposable emulator and keeps named receipts under the supplied output directory.

```sh
python3 scripts/test_journeys.py --output build/feature-verification/journeys
python3 scripts/test_nightly_native.py notification-cold --output build/feature-verification/journeys
python3 scripts/test_nightly_native.py voice --output build/feature-verification/journeys
```

The first command requires all four critical journeys, all seventeen roadmap journeys and actual outbox process-death recovery. Its named outcomes cover uncertain Send beside a newer draft; native clarification from composer text; local Git review; live progress and plan recovery; teammate waiting status and exact target opening; profile/project navigation; model/reference/find/output controls; current-chat account reports and recovery; approval/queue ownership; child/parent work; saved-answer edit/regenerate/fork; scoped administration/update refusal; and Hub skill availability/group-update recovery. Read those outcomes rather than inferring coverage from the suite title.
Roadmap actions wait for route completion and reveal controls before tapping,
including when the Android keyboard reduces the viewport.
The Identity save journey waits for Android's keyboard inset before checking and
tapping Save, so its keyboard-open assertion does not race the native show animation.
After the clarification journey reopens the keyboard, it uses the visible Input
needed control to recover the full confirmation target, then checks retained
answers, the unrelated draft and held retry feedback.
Roadmap failures export their exact failure-time Flutter frame and keyboard metrics under `<suite>-frames/`
and in the suite log. Native foreground, window and keyboard diagnostics at failed
suite completion are retained under `<suite>-failure/` before cleanup; later tests
may have changed that native state.
Failure frames do not require `--capture-frames`.

The approval journey checks the immediately visible Review command panel and
exact selectable command before using its icon-only Approve once action.

For the real stock-backend boundary, prepare a clean checkout of current [official Hermes main](https://github.com/NousResearch/hermes-agent), with no project `.env` or untracked files. From that checkout, build a fresh `.venv` using `python3 -m pm.build_env --source . --out .venv --extra web`. Give preparation disposable `HERMES_HOME` and `HERMES_RUNTIME_DIR` directories, as in [nightly CI](../../.github/workflows/nightly-tests.yml). Upstream PM owns the supported interpreter, committed dependency lock and dependency overrides. Set `WING_HERMES_SOURCE` to that checkout, then run from the Wing root:

```sh
python3 scripts/test_vanilla_hermes.py --hermes-source "$WING_HERMES_SOURCE" --output build/feature-verification/stock
```

`WING_HERMES_SOURCE` must point to the inspected stock checkout. The runner starts the canonical gateway with its Webapp listener, signs in with a disposable username and password, and exercises the profile/project production UI. Its backend home, profiles, credentials and process are retired after the run. Standalone `serve` cannot establish this session boundary. The recipe does not authorize a deployed-server upgrade or provider-charged generation.

For cross-instance `bots.groups`, the existing Android Bots family creates a
group from saved instances, holds capability checks and member joining, recovers
a partial join through the affected member's Retry, and sends text while
explaining the peer attachment restriction. Its four theme/text cases use the
real name-entry keyboard and export Android screenshots at the held, failure
and recovery stages. Existing local-group attachment and picker paths remain in
the same family. See the [Bots recipe](bots.md#driving-it-with-wing-harnesses).

```sh
python3 scripts/test_nightly_native.py bots --output build/feature-verification/peer-groups
```

The host `flutter test --no-pub test/conversation_assembly_test.dart` recipe also exercises group discussions in both themes and text sizes, including reading-mode return and retained group drafts above the landscape keyboard.

Phone reading is covered by the `transcript-expansion` family: enter table reading mode, rotate, return to the retained draft, reveal composer controls and use Back without leaving the chat.

For `journeys.conversation`, hold a web link while revisiting an answer to
select its text or choose where it opens. For regular taps, set the default
under App settings → Open links in. See the
[link context menu recipe](markdown.md#link-context-menu).

For `journeys.conversation`, the host Send-and-return recipe in
[conversation](conversation.md) checks that a reply arriving while Wing is in the
background opens at its beginning. Reading-position tests also cover leaving a
thread and returning after new saved history arrives.

For `journeys.conversation`, the [refused-turn recipe](conversation.md#gotchas)
checks live settlement, saved Find/reopening, passive actions and retained drafts.

For `journeys.conversation`, the [account usage recipe](model-selection.md#driving-it-with-wing-harnesses)
opens the captured chat report, holds opening/refresh/retry, retains received
content on failure and leaves during a pending read. Both themes and supported
enlarged text use the production Chat actions entry.

For `journeys.conversation`, the existing Android case
`draft model slash find outputs and context use the production chat` opens the
context ring with the real keyboard present, reads reported cache dates and
confidence independently of occupancy, and holds opening and Retry through
failure, recovery and departure. It retains the draft and checks the popover's
keyboard bounds in both themes and text sizes. See the
[context recipe](model-selection.md#driving-it-with-wing-harnesses).

For `journeys.conversation`, the existing Android cases
`subagents goals and background work keep their chat owner` and
`completed child stays in current work while the parent streams` open child
history through Activity while retaining the parent draft and controls. They
exercise saved transcript reads, held refresh and recovery, nested reading and
child resource rotation. Capture their Android frames; the companion host recipe
checks both themes and enlarged text. See the [child-reading recipe](chat-activity.md#driving-it-with-wing-harnesses).

For `journeys.conversation`, the [fresh Send recipe](chat-inputs.md#gotchas) checks
that a stopped reply or an empty paused queue does not strand the next message.

For `journeys.conversation`, the [steering recipe](chat-inputs.md#gotchas) checks
compact acceptance becoming a normal saved user bubble, with the same
presentation after cached reading is restored.

## Gotchas

Connection-to-create/reopen journeys retain Wing's installed mobile attribution:
each new socket announces after the server greeting, and each new chat includes
the same label. The focused [connection attribution checks](connections.md#gotchas)
cover these wire facts; existing saved-chat reopening remains a separate deployed
read-only proof.

Fixture native journeys, stock transport and deployed-provider acceptance prove different boundaries. Android owner recreation is not process death; require the separate process-recovery verdict. Keep each failed aggregate failed even when a focused recovery passes. Do not sum overlapping case counts. Run families serially on this workspace; retain artifacts after the owned emulator and backend are retired.

For `journeys.conversation`, also use the [read-only saved-chat contract](conversation.md#read-only-saved-chat-contract-on-an-existing-server)
when session APIs change. The fixture journeys and stock profile/project runner
do not establish that existing chats reopen on the intended deployment. This
read check needs no provider turn; sending/queueing still requires its separate
authorized journey.

For attachment refusal, the [conversation recovery recipe](conversation.md#gotchas)
checks that saved messages remain visible, Send is unavailable, and Retry keeps
the draft while attachment completes. History access does not grant write authority.

For `journeys.conversation`, the Background dock recipe in
[chat activity](chat-activity.md) verifies discovery without recurring work,
live output, Stop/Dismiss and draft retention alongside Tasks and Subagents.
Saved process receipts use the same compact rows as neighboring tools and
reasoning in Activity; expanding Process update preserves the full result after
the live process has gone. Exited processes leave the composer when their response ends; running processes remain visible, and later turns do not restore old exited rows.

### Selected Hermes features on an existing production gateway

With operator authorization for isolated QA profile/chat creation, cleanup and
real provider usage, run the dedicated production-connected Android recipe.
Credentials are read at runtime from a private file containing `provider`,
`username` and `password`; they are never compiled into the APK.

```sh
python3 scripts/test_existing_hermes_next.py --url http://GATEWAY:PORT --login-file /private/login.json --suite admin --output build/feature-verification/prod-admin-UNIQUE
python3 scripts/test_existing_hermes_next.py --url http://GATEWAY:PORT --login-file /private/login.json --suite conversation --output build/feature-verification/prod-conversation-UNIQUE
python3 scripts/test_existing_hermes_next.py --url http://GATEWAY:PORT --login-file /private/login.json --suite groups --output build/feature-verification/prod-groups-UNIQUE
python3 scripts/test_existing_hermes_next.py --url http://GATEWAY:PORT --login-file /private/login.json --suite sessions --output build/feature-verification/prod-sessions-UNIQUE
python3 scripts/test_existing_hermes_next.py --url http://GATEWAY:PORT --login-file /private/login.json --suite context --output build/feature-verification/prod-context-UNIQUE
```

The current account/cache/child additions and output-wrapping policy have focused
live targets using fresh QA profiles with the default profile's configured model:

```sh
python3 scripts/test_existing_hermes_next.py --url http://GATEWAY:PORT --login-file /private/login.json --suite additions --output build/feature-verification/prod-additions-UNIQUE
python3 scripts/test_existing_hermes_next.py --url http://GATEWAY:PORT --login-file /private/login.json --suite wrapping --output build/feature-verification/prod-wrapping-UNIQUE
```

The additions suite opens and refreshes the current chat's account report,
compares cache details with actual server-reported facts after a real reply,
and opens a delegated child's durable transcript through its parent authority.
After closing the child, the parent's completion must settle into saved history
and display its final answer without Refresh workspace.
Provider credentials must work in the fresh QA profile, and delegation must be
available. Missing cache observations or delegation are failed prerequisites,
not substituted fixtures. Cache observations establish reported facts, not actual
provider cache retention. The wrapping suite saves and reopens inherit/on/off
policy through the real editor and backend; it does not establish formatting at
an external delivery destination. Each suite retains exact owned resource
manifests and deletes its profile only after those resources are confirmed absent.
Use repeated exact `--case` names for focused recovery.

Each run owns a disposable emulator, forwards bytes to the real canonical gateway,
records app/backend identities and exact test outcomes, captures UI frames and
retires the emulator. Use a new output directory for each run. The admin suite
creates a blank uniquely named profile and one disabled MCP connector. It drives
plugin maintenance with verified empty user inventory, nonempty cached connector
status/refresh, QA-only skill lock/unlock, and a settings save with HTTP and reopened-editor readback,
then removes that profile. It does not upgrade shared plugins or modify managed policy.

The conversation suite creates uniquely identified QA chats in the default
profile, sends real provider requests through the composer, verifies unchanged
compression preview history and an actual compression commit, and checks detached
work in a fresh observer without runtime attachment. The finite background QA
calculation uses one process, constant memory and no files/network/sleeps. Owned
chat manifests survive failures; a cleanup failure retains identity for review.

The groups suite creates two blank profiles with the default profile's advertised
provider/model; provider authentication must be available to those profiles.
It saves and reopens owned group purpose, notes and routing, observes actual member
work and stops it, saves task timezone/missed-run policy/group delivery, executes
a real result into the owned group, and cancels another task execution without
pausing its schedule. It removes exact owned tasks and groups before deleting the
QA profiles. Unconfirmed cleanup retains the profiles and ownership manifests.
A separate case requests a tiny, tool-free exchange between the two QA members,
requires a reported bound of at most three rounds, and verifies one actual
Continue grant followed by Stop. An unavailable bound or grant is a failed
prerequisite, not a substituted passing scenario.

The sessions suite requests a real two-question clarification batch, stages both
answers and confirms them through the Android form, then verifies the provider's
response and retained draft. A separate owned chat selects a different advertised
model without running inference on it, then resets through Use profile default
and checks resolved model, saved history, draft and unchanged profile settings.
Missing provider clarification support or an alternate model leaves that path
unverified; ordinary text or an already-default reset is insufficient.

The context suite creates one blank QA profile on the configured provider/model,
pins only that profile to 65,536 context tokens, and verifies the canonical stats
and visible pinned limit after a real reply. It deletes the owned chat before
removing the profile, retaining the profile if chat cleanup is uncertain.

For a focused recovery, repeat `--case 'Exact named case'` to select only failed
outcomes from that suite. Preserve the original failed aggregate receipt.

An empty plugin-maintenance receipt proves dispatch and acknowledgement, not a
plugin upgrade. A disabled cached connector proves that observation, not OAuth or
connection recovery. Managed-lock refusals need an existing policy prerequisite;
this recipe never installs instance-wide locks solely for a test. Retain focused
native/host refusal proofs alongside these production outcomes and report the
unexercised production branches explicitly.

## Capture a connection incident

After an orange connection indicator or interruption, open App settings, scroll
to About and use the Share icon beside Diagnostic logs. This works while
disconnected. Choose a destination in Android to save/send the ZIP. The local
timeline survives a restart and the manifest reports collection gaps. See
[app-preferences-backup](app-preferences-backup.md) for the exact native and host
verification commands; no backend request is part of this journey.

The focused typed-approval journey opens the production conversation, reviews
folder and website requests, completes a held grant, then rejects with an optional
reason through a held failure and explicit retry. It captures both themes and the
app's standard/enlarged text preferences, including a confirmed Android keyboard inset and reachable denial/retry
actions above it. These are isolated stock-shaped server-request fixtures, not proof that a
particular deployed server produces sandbox requests.
The same case opens the production notification review for Save access rule and
holds its submission. Notification Deny dispatches directly without a reason;
keyboard denial coverage uses the conversation's optional reason field.

```sh
python3 scripts/test_journeys.py --case 'typed folder and website approvals retain scope and denial feedback' --capture-frames --output build/feature-verification/typed-approvals
```

The shared review's 320 dp/200% text and held-response checks run with
`flutter test --no-pub test/gateway_approval_panel_test.dart test/notification_approval_review_test.dart`.
`flutter test --no-pub test/selection_viewport_test.dart test/studio_selection_test.dart`
checks shared native-selection ownership and selection behavior for these fields.
Wire subject validation, exact correlation and denial payloads run with
`flutter test --no-pub test/gateway_approval_test.dart test/profile_approval_queue_test.dart`.

For `journeys.conversation`, the [teammate delivery recipe](bots.md#teammate-delivery-verification)
keeps the sender draft while opening the exact recipient. Read unknown-outcome
warnings before deciding what to do; the status view supplies no resend action.
