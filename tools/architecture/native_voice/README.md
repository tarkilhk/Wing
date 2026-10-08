# Native voice transfer contract

`VoiceFileWork` owns native voice temporary files and bulk file I/O. One
process-wide transfer thread admits at most two leases. Its fixed queue does
not grow, and cancellation does not replace a blocked worker. An active
lease retains admission until its producer has returned, the file has really
been deleted, and queued completion closures have been consumed. Failed
deletion retains the owned file and admission; later calls receive a busy
error. Process-death cache cleanup runs once on that same thread before any
new files are created.

The transfer payload cap is 25 MiB. Recording reads capture the actual
stopped file size before allocating, reject empty/oversized input, and detect
growth or truncation while reading in 64 KiB chunks. Playback writes validate
the byte array before admission and use checked 64 KiB chunks. Both stream
types close on the transfer thread. This bounds admitted transfer payloads,
not the entire Android heap or MethodChannel's incoming message allocation.
Startup cleanup of files left by previous processes has no directory-entry
cardinality guarantee and runs off the main thread.

The current official stock contract inspected read-only is
[audio.py at db45b44ab72af81974adfb01c9ecd6967f5bec29](https://github.com/NousResearch/hermes-agent/blob/db45b44ab72af81974adfb01c9ecd6967f5bec29/hermes_cli/web_routers/audio.py).
Stock transcription rejects decoded uploads above 25 MiB; its current speech
endpoint does not impose that output limit. Playback's existing 25 MiB limit
is client policy. No HTTP fields, MIME types, stock installation, or backend
settings change here.

`VoiceOperation` supplies exact attempt identity independently of Flutter's
reusable public ID. Recorder/recognizer/player callbacks, delayed audio focus
events and TTS utterances belong to that attempt. Android media and speech
objects still run on the main looper. `VoiceReply` settles once before calling
out, including reentrant disposal. A cancelled OS permission request keeps
its process-wide request-code slot until Android actually delivers the result,
including across Activity recreation. Cancellation clears the payload so the
held slot cannot retain a disposed Activity or authorize a new channel.

## Prevention and reproducible checks

From the repository root:

```sh
python3 tools/architecture/native_voice/run_owner_jvm.py --compile-boundary
python3 tools/architecture/native_voice/file_api_boundary.py
python3 tools/architecture/native_voice/prove_boundary.py
```

The JVM suite exercises real temporary files plus held read/write/delete and
completion delivery, growing/oversized recordings, stale generations, reused
IDs and once-only replies. `--compile-boundary` additionally compiles the
actual three voice wrappers against cached Android API 36 and Flutter
embedding APIs. It does not execute Android media APIs. Existing app JVM test
tasks also discover the two `Voice*Test` classes.

To reproduce the unbounded read counterexample without modifying live source:

```sh
python3 tools/architecture/native_voice/run_owner_jvm.py --red-growth
```

This isolated copy reinstates `file.readBytes()` and must exit 1 because a
growing recording escapes its captured size. The Kotlin PSI guard is an
independent import/fully-qualified file-API confinement rule with no baseline.
It reports `NATIVE_VOICE_FILE_API_BOUNDARY` at an actual source line, exiting
1 for violations, 0 for valid source and 2 for malformed/missing input.
`prove_boundary.py` proves all three exits in real CLI processes, including
aliases, wildcards, qualified constructors/types and unrelated methods.

The guard does **not** resolve implicit receiver types, prove thread affinity,
or prove callback ownership. For example a filesystem extension reached
through `activity.cacheDir` without an explicit file API import requires a
future resolved Kotlin semantic check. The active paths instead receive only
lease paths/results and are protected by the behavioral JVM suite and source
review. The rule cannot replace those tests.

## Feedback and Android acceptance

```sh
python3 tools/architecture/native_voice/benchmark_guard.py
```

Timing samples, compiler-cache validation and host metadata go to ignored
`build/native-voice-guard/timings.json`. A warm compiled guard over the three
wrappers has a local feedback target of 2 seconds per fresh JVM invocation;
this leaves more than twice the initial measured startup time. First
compilation and concurrent host load are recorded separately. Timing never
changes correctness exit codes.

Device acceptance must still exercise maximum supported recording/playback,
rapid stop/restart with reused IDs, permission cancellation, backgrounding,
Activity recreation, audio focus loss and disposal while each transfer is
held. Verify responsive main-thread traces, once-only method results, no late
playback, file cleanup and observed memory. Host allocation/queue tests and
API compilation do not establish device latency, RSS or Android callback
behavior.

## Permission lifecycle ownership

`NATIVE_VOICE_PERMISSION_LIFECYCLE` is a separate parsed-Kotlin property:

```sh
python3 tools/architecture/native_voice/permission_lifecycle.py
python3 tools/architecture/native_voice/prove_boundary.py
```

The canonical `MainActivity` forwards media pause directly from `onPause` and
foreground retirement directly from `onStop`. Canonical `VoiceChannel.pause`
invokes only its owned capture pause and playback stop, so permission retirement
or a new helper invocation cannot be moved into that method silently. Scope is
the two canonical classes in `com.tarkilhk.wing`; unrelated classes/receivers,
comments and strings are accepted. Missing/ambiguous owners, malformed input,
receiver shadowing, foreign imports/aliases or nested declarations that shadow
canonical owner types, noncanonical media constructors, or unsupported lifecycle
bodies fail input2 for review.
The CLI exits0/1/2; its existing fixture driver exercises both native voice rules.
Both rules share one ephemeral PSI parse helper and source/compiler/cache-key
implementation; their decisions and diagnostic IDs remain independent.
The permission CLI uses the same 2-second local feedback target for a warm
compiler cache and a fresh JVM. Record actual elapsed time in ignored evidence;
first compilation and the multi-process fixture proof have separate costs.
Timing does not change correctness exits.

This finite check does not resolve arbitrary aliases, implicit getter effects,
transitive helper policy, or prove Android callback ordering. In particular an
Android permission dialog can pause the requesting Activity while it remains
visible. The unchanged real denial/grant/Home journey in
`integration_test/voice_permission_native_test.dart`, driven by
`scripts/test_native_voice.py`, owns that semantic regression. JVM permission
slot/recreation tests prove cancellation identity, not OS lifecycle scheduling.
The new `leaveForeground` method's exact slot/owner/once-only settlement remains
covered by those owner controls and the device fixture, rather than a syntax
claim that source spelling proves permission-result timing.
