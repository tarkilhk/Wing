# Administration emulator acceptance

Validation of the administration implementation published as `d32cc83`, using
Android emulator `emulator-5556` and the installed Hermes backend at
`e16f686706b1e0d5334fd1ae82190058d2a19694`.

The device is Android 36, 1080×2400 pixels at 420 dpi. The persistent build
checkout is `C:/Users/rober/Documents/Projects/hermes-android`. The tests use
production widgets, HTTP and profile RPC clients. There is no injected Hermes
transport. A small external stdio MCP service supplies a disposable connector.
Each mutation run uses its own temporary Hermes home and two QA profiles.

## Results

Local emulator acceptance is complete for the coverage below, with independent
backend reads after mutations. The backend and external-account limits remain
explicitly unverified. Results span the recorded runs and targeted retests;
they are not a claim that one uninterrupted full-suite run was green.

| Area | Verified behavior |
| --- | --- |
| Settings | All 22 exposed memory, execution, approval, compression and reach/recovery fields save; the second profile stays unchanged |
| Profiles | Create, rename, clone configuration, delete, and open the selected profile back in the Profile tab |
| Credentials | Shared-root and explicit profile key save/removal; blank obscured input; the other profile's local key store remains unchanged |
| Local skills | Search, usage ordering, read, edit instructions, save/readback, archive |
| MCP | Enable/disable, profile isolation, actual stdio connection, tool listing, prompt/resource counts, remove |
| Model defaults | Main model selection, explicit helper model/reasoning assignment, automatic assignments, reset-all, add/reorder/remove fallbacks |
| Identity | Description and SOUL saved through the administration entry and independently read back |
| Health | All five usage ranges; agent/errors/gateway log choices, severity and search; confirmed runtime connector reload |
| Diagnostics | Doctor and security audit ran to completion; both returned exit code 0 |
| Navigation | Every Profile drill-down, Server/Health tab ownership, provider recovery link and return navigation |
| Hub | Official preview, install, group update and uninstall reached completed actions; inventory matched |
| Capabilities | Inert profile plugin, existing skill and configured toolset toggled in both directions with readback |
| Provider sign-in | Real device authorization started, pending status polled, cancellation confirmed, no account access granted |
| Existing server | Actual app-drawer entry, Profile/Server/Health navigation, connection callback and backend version/update check passed against the owner's running Hermes server |
| Guided providers | Web search/extraction selections; all reported STT, TTS, image and video provider rows; model pages and available model selections; recognition language and automatic speech defaults |
| Remaining setup | All seven browser rows, including composed backend selection and managed-account messaging; computer-use selection; X search, Home Assistant and Spotify expose setup/credentials without a no-op provider switch |

The final integrated checks include the provider-status and compact-control
changes published through `1ca2d27`. The native driver waits for asynchronous
results, selects visible scrolling lists rather than editable text scrollables,
and distinguishes dialog labels from content behind the dialog.

## Fixed Android issues

The skill editor's save confirmation covered its Close button. The native
hit-test trace identified the snackbar as the pointer recipient. Settings and
skill editor actions now occupy the scaffold's bottom navigation area, with the
keyboard inset reserved. Snackbars appear above the actions. The live skill
edit/archive test passes with the fix. Fifty-five focused host UI checks also pass,
including a new regression that checks snackbar/footer separation with a 280 dp
keyboard inset.

A completed provider request could also call its loader's refresh callback
after the user had left the page. The emulator recorded `setState() called after
dispose()`. A minimal host regression reproduced that failure before the fix.
The loader now ignores callbacks after disposal, and the regression passes.
Static analysis reports no issues.

Nous speech selection exposed a third UI issue. Hermes acknowledges the saved
choice with `needs_nous_auth`, but deliberately reports no active provider until
the account has access. The app treated this as a generic verification failure.
It now explains that the selection was saved and still needs account access.
Other provider selections still require matching active-provider readback.
The native Nous speech case verifies the message and the persisted `nous`
provider value. A focused host regression also covers this response contract.

Browser selection can compose a cloud provider with a browser backend. Hermes
can report both rows active while `active_provider` contains only the first.
The app now accepts the selected row's own `is_active` readback as well.

X search, Home Assistant, Spotify and Langfuse report setup/credential rows without
a persisted provider selection. Their no-op "Use provider" actions are removed;
the existing credential and setup controls remain. The current backend matrix
does not expose a selection capability flag, so the app records the known
selectable toolsets explicitly. Host regressions cover these four integrations
and a browser response with multiple active rows.

## Backend and external limits

- Windows profile deletion after MCP activity returned HTTP 500 because Hermes
  retained an open `logs/mcp-stderr.log` handle. The emulator's create/rename/
  clone/delete test uses profiles without active connector handles and passes.
  The launcher stops its owned backend process tree before removing the QA home.
- Memory correction/deletion, MCP per-tool writes, arbitrary-owner credential
  pool details and exact profile retained-file sizes remain limited by the
  audited backend contracts. Their unavailable UI is intentional.
- Provider sign-in approval, account refresh/revocation, externally hosted MCP
  OAuth approval, paid provider inference, dependency installation and backend
  self-update are not claimed as validated by these tests.
- The tests do not establish Android process-death recovery for pending OAuth or
  background actions. Pending flow identity is not persisted by the current UI.
- Langfuse has setup metadata in installed Hermes source but is absent from this
  server's toolset inventory. Its direct configuration route returns HTTP 400.
  The native driver now follows the reported inventory and records that category
  as unavailable. Its setup-only rendering is covered by a host regression.

## Reproduce

From the persistent checkout with the disposable emulator already booted:

```powershell
.\tools\qa\run-administration-live.ps1
```

The launcher starts the real installed Hermes server on a free loopback port,
adds ADB reverse forwarding, creates isolated QA data, builds/installs the test
APK, runs the native tests, then stops its server and deletes only its temporary
home. `-Name '<test-name-pattern>'` selects a subset. `-KeepBackend` retains the
owned backend and QA home for diagnosis; the caller must stop it afterward.
Logs are retained under `build/admin-live-<timestamp>/` and are ignored by Git.
The normal Hermes server, installed source, owner profiles and credentials are
not modified.

Key local evidence:

- `build/admin-live-20260914-212339/flutter.log`: nine passing live groups.
- `build/admin-live-20260914-213309/flutter.log`: navigation, expanded model/helper
  assignments, Hub lifecycle, capability switches and provider sign-in passed.
- `build/admin-live-run3.log`: native Profile navigation sweep and MCP probe.
- `build/admin-live-regressions-final.log`: fifty-five passing administration,
  app-shell, provider-status and compact-control checks after integrating main.
- `build/admin-live-analyze-final.log`: static analysis with no issues.
- `build/admin-late-refresh-red.log`: the reproduced disposal failure before its fix.
- `build/admin-existing-server-live.log`: passing read-only app-shell acceptance.
- `build/admin-guided-rerun.log`: all web selections completed before the Nous
  speech case exposed the saved-versus-active distinction.
- `build/admin-guided-final.log`: complete STT/TTS/image/video sweep passed in
  11m40s, including Nous readback and speech defaults.
- `build/admin-integrated-main-live.log`: seven integrated scenarios passed after
  main's provider-status and compact-control changes. Browser and remaining
  offered setup rows also completed before the driver incorrectly attempted the
  unavailable Langfuse route. This inventory assumption was corrected.
- `build/admin-remaining-setup-live.log`: the corrected remaining setup sweep
  passed in 1m01s and explicitly recorded Langfuse as unavailable.
- `build/admin-profile-live.png`: actual native administration Profile tab.

The initial host-only report is in
[the implementation record](ADMINISTRATION_IMPLEMENTATION_2026-09-14.md).

Native screenshots: [Profile](design/admin-acceptance/profile.png) and
[Behavior](design/admin-acceptance/behavior.png).
