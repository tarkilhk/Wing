# Chats reliability and frame-time investigation

Source baseline: Wing `def56b227b4b334d9ec53365204a50c41e1862c2`, freshly fetched
from `origin/main` before this work. All changes are client-side.

## Reproduced failures

- Real phone and emulator logs showed HTTP 429 on password login while fetching
  project membership. Each short-lived profile reader constructed its own
  authenticated HTTP client. Four profiles meant eight sign-ins during initial
  loading and four more per refresh.
- Stock Hermes `8df0a03793784205833f9e0db12395aa33ada433`, inspected 19 September
  2026, limits `/auth/password-login` to ten attempts per client IP in sixty
  seconds (`hermes_cli/dashboard_auth/routes.py`). The backend was healthy.
- A real-transport regression test initially performed seven logins for two
  profiles and two refreshes. It now completes five refreshes with one login,
  even when every additional sign-in receives HTTP 429. Profile readers retain
  separate sockets and closing them leaves the conversation socket usable.
- Concurrent expired-session responses could discard renewed authentication.
  The regression test reproduced three logins where only two were needed.
  Invalidation now compares the credentials actually rejected and preserves
  newer credentials and any in-flight renewal.
- Overlapping refreshes issued duplicate profile page requests. A gated fixture
  reproduced four first-page requests for two profiles; coalescing produces two.
- Refresh discarded the complete index after its first page and rebuilt it after
  every subsequent page. Keep the previous snapshot while collecting the next
  one, publish each completed profile atomically, and retry transient read
  failures. Initial loading still publishes its first page promptly.

## Initial phone evidence (debug build, diagnostic only)

With 2,801 indexed chats, 2,365 visible chats and 41 groups:

- Cold index load: 4.512 seconds; warm refresh: 3.501 seconds.
- 499 captured frames: UI-build p50 2.790 ms, p95 48.762 ms, max 212.242 ms.
- 45 browser projections/rebuilds; projection alone reached 24.181 ms.
- CPU samples implicated widget rebuild/layout/semantics as well as projection.

These debug measurements identify work to remove; they do not establish release
performance. The phone was then disconnected at the owner's request.

## Emulator protocol

API 36 x86_64, KVM, 1080 × 2400, 420 dpi, 60 Hz. Real saved connection and real
Hermes data, with credentials held only in Android secure storage. No fixture
backend or server modifications. SwiftShader software graphics must be recorded
as a limitation when interpreting raster time.

Use AOT profile builds for before/after comparison, warm the list, then run three
30-second scroll sequences including a pull-to-refresh. Do not compile or run
other CPU-intensive checks during measurement. Separately complete five
consecutive refreshes and check request/error logs. Debug and profile results,
phone and emulator results, and different renderer configurations are not
interchangeable. Keep the full index for correct filters and group token totals;
three-row previews remain the default.

## Verified recovery on the real backend

With the shared authentication and refresh changes, warm refresh generations
2–6 each completed 30 paginated session reads with zero loading failures.
Exactly one password login served initial loading and all five refreshes.
Refresh durations were 7.391, 5.061, 11.278, 3.997 and 7.453 seconds. No backend
rate limit was changed or reset. Three runs at the original emulator resolution
and three at 720 × 1600 retained the same logical layout (density 280 instead of
420). The smaller viewport's UI p95 was 5.415 / 4.269 / 4.525 ms and p99 was
9.717 / 7.439 / 7.646 ms. Software Impeller raster p95 remained
31.527 / 24.567 / 25.625 ms, so these runs do **not** meet the complete frame goal.
Changing emulator resolution is an infrastructure experiment, not an app speedup.

The unchanged AOT baseline at 720 × 1600 produced UI p95 4.551 ms, p99 11.142 ms;
raster p95 24.259 ms, p99 29.315 ms (1,716 frames). Its raster cost is similar to
the fixed build. This does not establish a rendering speedup. An additional
Skia/software-rendering experiment also missed raster acceptance (p95 23.787 ms).
The host exposes only a simple-framebuffer device, without a hardware render
node. Full 60 Hz acceptance remains open for GPU-backed/physical-device evidence.
No production renderer override or resolution reduction was introduced.

The deployable performance build uses AOT profile mode with the separate Wing
Dev identity, so it preserves Dev app data and cannot replace regular Wing.
Debug/JIT measurements must not be presented as release performance.

## Regression coverage and reproduction

`flutter test --no-pub` on the connection manager, browser data and transport,
Chats Target, workspace browser/controller/registry, pagination, live status,
reading snapshots, temporary failures, Cloud journey and gateway headers passed
209 tests. `flutter analyze --no-pub --fatal-infos` passed. The paging fixture
also verifies that publishing a refreshed 2,000-chat index needs only four
notifications (start, each of two completed profiles, finish), independent of
page count.

For future GPU-backed validation, build/install the benchmark entry point:

```sh
flutter build apk --profile --build-number=<next-code> \
  --target=tools/performance/chat_frames.dart \
  --dart-define=WING_REVIEW_REVISION=<commit>
adb -s <emulator> install -r build/app/outputs/flutter-apk/app-profile.apk
# Open Chats on the real connection and dismiss setup/permission dialogs.
python3 tools/qa/measure_chat_scrolling.py --serial <emulator> \
  --label <commit-and-renderer> --output /tmp/wing-frame-results.json
```

The harness leaves the process warm, records three 30-second runs, and includes
pull-to-refresh gestures. Preserve the emulator graphics configuration and the
source/build mode alongside the JSON. The ordinary main entry point includes
no timing observer and all temporary `[DEBUG-wing-chats]` probes were removed.

Wing Dev 22669 (`1.0.1-dev-profile`) was built from this change for arm64/x86_64
with the ordinary main entry point. It installed in place on the emulator under
`com.tarkilhk.wing.dev`, retaining the saved real backend connection. All three
installed launcher shortcuts resolve to the correct Dev activity. APK SHA-256:
`5a0ad7ad0f9aa6f201d203e5a4b99ae125616800f341376e127c723744f4d421`.
The downloadable APK contains no measurement observer or bootstrap entry point.

## Final original-resolution run

The committed benchmark harness was exercised against the final application
code in AOT profile mode, restored to 1080 × 2400 / 420 dpi, with SwiftShader
and the default Impeller GLES renderer. No builds/tests ran during measurement.
See [the recorded results](2026-09-19-chat-browser-frames.json).

| 30-second run | Frames | UI p95 / p99 (ms) | Raster p95 / p99 (ms) |
| --- | ---: | ---: | ---: |
| 1 | 1,483 | 4.043 / 7.360 | 27.800 / 33.471 |
| 2 | 1,445 | 5.144 / 8.340 | 28.742 / 40.832 |
| 3 | 1,470 | 4.830 / 8.296 | 27.501 / 33.671 |

UI timing meets both acceptance thresholds in every run. Raster timing does not;
the overall scrolling goal is still open. The owner can use the ordinary AOT
Wing Dev 22669 build while GPU-backed validation remains pending. The instrumented
APK was used only on the disposable emulator, separate from the downloadable APK.
