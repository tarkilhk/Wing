# Queued message editing verification

Verified on 2026-09-14 using the production conversation screen and workspace
controller. Long press opens the queued instruction in the composer. Queue
updates its existing position; Steer sends it into the running turn and removes
the queued entry after acknowledgement. Cancel, successful save, accepted
steering and confirmed deletion restore the separate draft. Its attachments
remain separate throughout editing.

The selected queued row shows a red delete cross with a 48 dp tap target. Delete
requires confirmation. The queue cannot drain while an edit is open. Pending
steering remains saved as paused work until acknowledgement. Steering supports
text only; queued attachments remain available when saving an edit.

## Automated results

- Final static analysis of the seven implementation and test files reports no issues.
- 52 focused unit and widget tests pass, including storage failures, duplicate
  entry identity, attachment preservation and immediate retry after rejection.
- All seven Android integration scenarios pass. The standard Flutter driver
  exited 0. Its output counts the final teardown as an eighth test.
- A broader run passed 1,446 tests with four skips and one unrelated failure in
  `android_launcher_shortcut_contract_test.dart`. That assertion expects a
  literal Dev package identity string changed by separate Android build work.

| Android scenario | Result |
| --- | --- |
| Long press opens the real Android keyboard; multiline Queue restores the previous text and files | Pass |
| Cancel discards the queue edit and restores the separate draft | Pass |
| Red cross opens confirmation; Cancel retains the instruction; Delete removes only the selected entry | Pass |
| Delayed Steer disables repeated submission, retains a durable paused entry, sends once and restores the draft | Pass |
| Rejected and failed Steer retain the edit and draft; retry stays tappable | Pass |
| Turn completion holds the queue until Queue is tapped, then sends the edited text once | Pass |
| Queued files survive editing with large text and the Android keyboard | Pass |

The emulator run uses `Hermes_API_36`, Android 36 x86_64, `emulator-5556`, at
1080 by 2400 and 420 dpi. The package is `com.hermesagent.hermes_android.dev`.
Every gateway transport in these scenarios is a local fixture. These tests do
not send instructions to a real Hermes session or establish live-server
delivery behavior. The physical phone was not used.

## Direct Android input checks

After the integration suite, `queued_message_native_preview.dart` ran the same
screen without the Flutter test binding. ADB input gestures and Android UI
Automator observations verified:

- A 700 ms hold opens editing directly, including after a fresh app launch.
- Android keyboard input changes the selected instruction. Queue saves the
  modification and restores the original two-line draft.
- Steer displays the modified instruction, removes only its queued entry and
  restores the draft.
- The red cross opens confirmation. Cancel retains the open edit; Delete removes
  the instruction and restores the draft.
- The first Android Back hides the keyboard while retaining the edit. The second
  Back cancels editing, restores the draft and retains both queued instructions.

An initial injected hold opened the tap menu during startup. Repeating after the
screen settled, and again after a fresh launch, passed with a 700 ms hold. An
empty Android accessibility snapshot during restart was discarded and recaptured.
Native observations are saved as `native-01-*.xml` through `native-18-*.xml` in
`build/queued-message-device/`. The emulator's original hardware-keyboard setting
was restored after testing.

## Issues found and corrected

- A snackbar after rejected steering could cover the Steer button. Edit errors
  now appear inside the composer, and immediate retry is covered on Android.
- Large text and the keyboard could overflow the composer area. The controls
  now scroll within the available height. The attachment hint was shortened.
- Removing a queue entry before steering acknowledgement could lose it on
  process exit. The entry now stays durably paused until acknowledgement.

The device harness now resets screenshot capture for each test and waits for
actual Android keyboard geometry before asserting that the keyboard opened.
Assertions about focus, delivery, preserved drafts and hit targets remain in
place.

## Environment and evidence

The first build encountered an unrelated Dart compile error that another
in-progress change corrected. The next encountered a locked Gradle output under
OneDrive. Device builds therefore used a temporary source copy at
`C:\Users\rober\AppData\Local\Temp\hermes-queued-message-device-qa`.
Hashes of the screen, controller, queued-message widget and integration test
matched the working checkout after the passing run.

An initial emulator process exited during startup. A subsequent run was blocked
by an Android System UI ANR. Those attempts are not passing evidence. The final
run used software graphics with Vulkan and Impeller disabled, after dismissing
the System UI interruption. Software-rendered debug tests do not measure
production rendering performance.

Local evidence under ignored `build/`:

- `queued-message-emulator-pass.log`: passing device run and driver exit.
- `queued-message-focused-final.log`: 52 passing focused tests.
- `queued-message-analysis-final.log`: clean final static analysis.
- `queued-message-tests.log`: broader run and unrelated package-identity failure.
- `queued-message-device/queue-01-edit-keyboard.png`: selected instruction and composer above the keyboard inset.
- `queued-message-device/queue-02-restored-draft.png`: restored text and attachment.
- `queued-message-device/queue-03-delete-confirmation.png`: confirmation dialog.
- `queued-message-device/queue-04-steered.png`: accepted steering.
- `queued-message-device/queue-05-failed-steer.png`: inline error and available actions.
- `queued-message-device/queue-06-large-text-attachment.png`: large text and retained file.
- `queued-message-device/native-04-edit-keyboard.png`: actual Android keyboard, edit actions and delete cross.
- `queued-message-device/native-09-steered.png`: native Steer result and restored draft.
- `queued-message-device/native-13-confirm.png`: native deletion confirmation.
- `queued-message-device/native-14-restored.png`: draft restored after confirmed deletion.

Flutter's integration screenshots capture the app surface; Android's keyboard
itself is outside that surface. The keyboard-open assertion reads the actual
native inset, without overriding `viewInsets`.
