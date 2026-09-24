# Connection status investigation — 24 September 2026

## Report and limits of the phone evidence

The connection-wide label showed **Live updates interrupted**, with **Server
access: Available** and **Live chat: Unavailable**, while the current chat worked.
The user also observed this intermittently. Retrying did not clear the label.

Saved phone captures establish that symptom. They do not identify the profile
whose live observation was unavailable; the production build did not log those
owners. The connection has several profiles. The reproduced client defect below
is consistent with the phone symptom, but this specific phone occurrence is not
yet traced to that owner. No phone or server settings were changed during this
investigation.

## Reproduced cause

`ServerConnectionStatus` records each workspace gateway that attempts a live
connection. One unavailable owner intentionally keeps the connection-wide live
status interrupted, even if a different profile works.

Recovery used a different owner set: only profiles with a loaded chat list or a
currently busy chat. An attempted but unopened profile, or a transport opened
for Activity before its profile list was loaded, could therefore contribute an
unavailable observation indefinitely while **Retry connection** ignored it.

Two minimized controller regressions used the actual `ProfileGateway` reporting
and failure paths with injected transport results. Both failed before the fix:

- Fail switching to another profile; allow the original profile's RPCs to succeed;
  retry the connection. Actual label: **Live updates interrupted**; expected:
  **Connected**.
- Connect an Activity-only profile, interrupt it through a real gateway error
  path, then retry. The original profile's RPCs still succeed, but the aggregate
  remained interrupted.

The transport and controller seams suffice to reproduce this lifecycle mismatch;
no altered Hermes contract, emulator behavior, or text parsing is involved.

## Client change

The recovery owner predicate now also includes gateways with a recorded live
observation. Disconnect handling, network-loss handling, and explicit retry use
that same predicate. Existing bounded automatic retries remain bounded. Merely
browsing an untouched profile still does not open a socket for it. The aggregate
still warns about genuinely interrupted background transports.

No mutation is retried, no backend change is needed, and no compatibility path
was added. This is a change to client recovery ownership, not the Hermes API.

## Validation

- Four focused regressions cover the two failures above, network loss for an
  Activity-only profile, and avoiding sockets for untouched browser-only profiles.
- Affected controller, connection-status, real-socket status, browser transport,
  and live-activity suites: **92 passed**.
- The final four regressions also pass with explicit assertions that automatic
  retry is scheduled for the Activity-only profile and cancelled after recovery.
- Static analysis: **no issues**. Diff whitespace check passes.
- Parent review: full suite **2,708 passed / 12 opt-in skips**; static analysis
  clean on build candidate **2331**. Dependency status reviewed; retain the
  tested lockfile and defer unrelated storage major/transitive updates.

Focused command:

```sh
flutter test --no-pub test/profile_workspace_controller_test.dart --name 'retry (clears a failed unopened|recovers an interrupted activity-only|leaves browser-only)|network loss includes'
```

## Remaining phone check

After deployment, exercise the same multiple-profile connection and return from
background/lock. Confirm that working chat plus successful retry returns the
connection-wide label to Connected. If it still reports interrupted, capture the
specific profile observations and recovery membership before another change.
The exact formerly failed owner still needs a targeted phone retest; deployment
and startup evidence alone do not prove which owner caused that occurrence.

Deployment follow-up: committed as `d6cf733`, pushed to main, and installed as
signed non-debuggable Wing **2331 / 23312** with app data preserved. Package,
ARM64 architecture and pinned release certificate verified before installation;
installed package version read back. APK SHA256:
`05d8d6a6f299fc83fb9602963e07c0688445943fc5329bf1fa990c49b0726841`.
Initial launch now displays **Claw, Connected** with the existing chat list.
The same Connected label remained after a 20-second Home interval and resume.
These are startup/resume smoke passes, not proof of the exact pre-update failed
owner or a reproduced interrupted background-profile recovery on the phone.

The prevention is to keep status contributors and recovery ownership aligned;
connection health must not depend on whether the user happened to open a
profile's chat list.
