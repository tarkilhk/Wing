# Make Wing straightforward to change

Purpose: one owner for each business fact, presentation-only views, cohesive
modules, small interfaces, removed dead code and deterministic prevention of
encountered incorrect patterns. Production migrations and subtraction take
priority. Verify changed contracts and broader integration milestones.

Follow the [original program](001-clean-architecture-program.md),
[verification contracts](001-clean-architecture-verification.md),
[architecture map](../docs/ARCHITECTURE.md),
[feature inventory](001-feature-inventory.md) and
[dead-code disposition](001-dead-code-inventory.md). The reusable
[guard-writing skill](../tools/agent_skills/create-regression-guards/SKILL.md)
is available to agents by path. The user started this program on 3 October 2026.

| Phase | Outcome | Status |
| --- | --- | --- |
| 0 | Initial ownership/root/dead-code inventory; linters and CI baseline | DONE |
| 1 | Ownership/data-loss fixes and durable prevention | DONE |
| 2 | Inactive paths deleted; dependency inversions removed | DONE |
| 3 | Complete task/model/diagnostics owner pilot | DONE |
| 4 | Every remaining feature migrated or reviewed against the target | DONE |
| 5 | Conversation facts and lifetimes have explicit owners | DONE |
| 6 | Native/resource responsiveness and matched phone performance | DONE |
| 7 | Whole-checkout finite dead-code/root closure and prevention | DONE |
| 8 | Independent review and final device/current-stock acceptance | DONE |

All nine original phases are complete. The final quiet-device acceptance and QA
restoration closed the remaining obligations on 6 October 2026. Production
source is fixed at `8af0db73b446f2c0d12f9e31afb08a870a4e5a11`; subsequent commits
record acceptance and completion. Closure applies to the agreed finite reviewed
inventory and verification scopes below.

## Accepted architecture and subtraction

The current reviewed source contains 1,504 authored files, 358 production Dart
files, 348 libraries and 143 views. All production files received full source
review and explicit reviewed-delta supplements. The architecture map names 29
responsibility boundaries; the feature inventory has no unexplained view row.
Three independent change-locality traces cover pending input, model assignment
and stock answer mapping.

Conversation facts have separate owners: `ComposerSession` owns unsent work and
ordered persistence; `TranscriptReading` owns immutable history and paging;
`ChatRuntime` owns execution, recovery and pending input; the workspace coordinates
captured transport and lifetime admission. Views forward commands and render
observations. Feature owners retain configuration baselines, conflicts, readback,
OAuth/operation polling and scoped mutations. Business facts are not writable
through views or peer owners.

The finite reviewed deletion inventory has zero confirmed or deferred deletion
leads, and the migration baseline is empty. The existing retirement guard protects
809 exact removed identities. There are 68 independently runnable Dart linters,
with invalid/valid fixtures and mandatory CI enforcement, plus five native guard
properties and the Python checks. Static checks protect precise properties; held-I/O and event-order
regressions cover lifetime, durability and uncertainty.

Conversation rejection handling separates `rejectSavedPromptEdit` from
`rejectRegeneration`. Physical dispatch does not decide conversation execution:
a definite edit rejection restores captured execution, while the existing
regeneration-failure behavior remains explicit. The obsolete ambiguous command
is removed and guarded. Actual rejection, lost-ACK and journal-held disposal
regressions protect the semantic distinction.

## Accepted local verification

Accepted production analysis, all mandatory architecture commands, ordinary Android
APK build, product-mode instrumentation and pinned Chromium renderer isolation
pass. Composed host coverage spans all 464 default test files: 3,833 unique actual
passes, 17 documented skips and no remaining failure. This is completed file
coverage plus the final affected-file rerun, not one uninterrupted green runner.
The failed predecessor and erroneous nonexistent-file command remain recorded
and are excluded from accepted totals.

The subsequent phone-probe batch passed focused analysis, eight Dart fixture
cases, eight replay-driver checks, nine release-marker checks and both authored
census and Dart entry-point guards. Production files are unchanged; these checks
are a scoped supplement to the accepted production run.

The subsequent bounded central-owner review found and fixed a stale intelligence
read in the existing workspace owner. A held old `config.get` cannot overwrite
newer hydration or a newer load after reconnect. Thirty focused owner/linter
cases pass, analysis of the changed Dart files has no issues, the independent
read-admission linter reports zero findings, and census/main-root coverage passes.
The mandatory CI-gate fixture checks passed against the unchanged final workflow
and gate files. The new guard's invalid/valid CLI fixtures prove failure
propagation; its source and compiled feedback runs stay within the documented
budgets. This is a bounded reviewed production successor, not a new whole-host
or whole-device run. The live observer now obtains actual reasoning readback
from this existing owner instead of assuming create/resume metadata includes it.

Native source/root review, nine native guard/proof commands and 27 JVM controls
cover the final source, with scoped predecessor reuse where source is unchanged. Sixty-four affected
normal/enlarged light/dark renders were inspected. These checks do not certify
physical-phone performance or a deployed server. Exact source/APK/test bindings,
skips and successor dispositions live in ignored `build/architecture-program/`;
private device captures remain outside Git under the performance policy.

The installed disposable-emulator monitoring, seven file/photo/share cases, and
held-provider intake/camera-recreation journeys pass. Their private receipts record
source bindings, retained build hashes and any unaffected-source reuse. Native voice now separates media
pause from foreground retirement: a permission dialog cannot cancel its own
request through `onPause`. A separate Kotlin linter protects that boundary and
its actual original counterexample. The installed offline voice driver now passes
denial, retry/grant, Home cancellation, AAC capture/cancellation, playback
decoding/interruption and five installed offline TTS samples, with empty voice
caches after both suites. Earlier VM-load and OS-ANR failures remain preserved.
Those offline checks do not certify speech intelligibility or live providers.
Physical-phone acceptance is recorded separately below.

## Accepted device and runtime verification

Matched offline streaming replay has passed on the authorized physical phone.
This scoped result covers exact synthetic text and native typing during the
stream; the additional typing, background and live-runtime scopes are recorded
separately. Three short-history and two long-history typing captures passed
with zero unchanged transcript setup and workspace notifications. Interrupted
attempts stopped when the QA app lost foreground. The synthetic ownership
question is answered; further repetitions are not scheduled. The original QA
app and device settings were restored. Android presentation timestamps were
unavailable, so frame timing is not reported as input-to-present latency.
Phone probes are separate opt-in
roots; production owners and views are unchanged.

The representative real-claw phone workflow now passes: the same owned QA
session was reused, Luna and actual low reasoning were verified through the
workspace owner, and one request completed with its final response rendered.
The completion sentinel was independently visible in retained screenshots; the
observer's mounted-sentinel flag was false and remains recorded separately.
One native unsent draft entered after completion survived reopening the chat
and Android Home/return. Capture stopped before navigation. The original QA APK
was restored in place, with its version and unchanged device settings verified;
app data and profile defaults were preserved. Earlier setup failures remain in
private evidence. This covers real-use behavior on the existing deployment,
not latest-deployed acceptance, concurrent typing, input-to-present latency or
energy savings. Do not repeat this completed question or create another QA
session without a concrete new requirement.

One instrumented profile-mode resource capture also completed against real Claw
after the user's backend upgrade, reusing the owned chat and verified Luna/low.
It retains CPU samples, memory/process/thermal endpoints, raw Flutter frame
timings and the complete response/render observations. Streaming and completed
frame groups are recorded separately. The observer remained active during the
resource window, so its CPU measurements do not establish production idle CPU,
battery savings or a matched before/after improvement. Raw measurements remain
private. The original QA APK was restored in place, its version and saved system
settings verified, and the measurement tunnel removed. The owned test draft was
re-entered, but its final character count was not verified. Active native
monitoring/wake-lock observations were not captured in this interval. Do not
repeat this captured workload without an observed issue.
The isolated background fixture's interrupted setup remains inconclusive: no
timed policy arm or quiet interval ran, and its package was removed before the
real capture. That attempt does not establish a production service failure or
close restricted-policy acceptance.
The subsequent real-Claw background attempt also stopped during chat-selection
setup, before any request or policy mutation. Its quiet window did not run.
The original QA APK was restored, the original policy retained, and the tunnel
removed. The user directed attention back to the maintainability purpose after
the setup took too long. That attempt provided no acceptance evidence. The
resumed checks below close active-work acceptance; the earlier automation failure
does not establish a product defect.

The real active-work checks under normal and restricted policy, completion and
recovery, native monitoring release, and the ten-minute no-work quiet interval
passed. Reuse the accepted matched replay, typing and real streaming/resource
evidence; do not repeat those captures without a concrete new finding.

The latest-stock runtime item is accepted using the completed post-upgrade owned
QA journey and the user's explicit confirmation that Claw is running the latest
Hermes backend code. The observed clean checkout matched upstream main at
`93cbf617c7007286a249cc00506c012933fb537c`. Running-source identity is supported by
the user's confirmation, rather than an independent post-upgrade launcher check.
No further backend investigation or deployment is needed for this item. No server
or profile change has been made by this cleanup program.

On the resumed phone connection, both authorized active-work checks passed
against the fixed production source `8af0db73b446f2c0d12f9e31afb08a870a4e5a11`.
Each dispatched one real Luna/low turn in the existing owned QA chat, completed
while Wing was backgrounded, and released the native monitoring service,
notification and wake lock after completion. The restricted arm explicitly used
`RUN_ANY_IN_BACKGROUND=ignore`; it does not establish forced deep Doze or every
OEM/network policy. Android no longer reported the service as foreground during
the restricted background interval, but the service, monitoring notification and
wake lock remained present until completion, then disappeared. Normal-policy
notification publication was observed after the initial sample; the raw initial
negative result is retained in private evidence.

Reopening showed the complete answer and completion marker with the Luna/low
route unchanged. The original QA APK was restored in place and its version,
original default background policy, and measurement-tunnel removal were verified.
Earlier setup/restoration uncertainty is resolved. Do not repeat the two accepted
active-work checks without a concrete finding. Raw observations, screenshots and
receipts remain private.

The final quiet check used the same production source with a private passive
timer wrapper. It preserved the production periodic timer callbacks and recorded
their creation, active state and ticks without device queries during the full
ten-minute interval. Android's screen history recorded no screen-on transition;
native monitoring resources were absent at both endpoints. After the user
unlocked the phone, the same retained probe generation showed zero notification
polling timers created, zero active and zero ticks. The initial background RPC
timeout and Format-2 history interpretation are retained in the private evidence;
the interval was not repeated. This checks unnecessary monitoring and polling,
not battery savings or every OEM policy. The original QA APK, default background
policy and measurement-tunnel cleanup were verified after restoration.

No goal acceptance obligation, production migration or confirmed deletion lead
remains open in this reviewed inventory. A future material finding requires a bounded fix,
prevention decision and affected verification. Do not start another generic
cleanup framework or repeat unaffected tests to increase totals.

## Continuing changes

Find the canonical owner in the architecture map; assign explicit module/file
ownership before parallel edits. Update relevant interfaces, callers and role
records together. Ordinary UI edits do not require global audit SHA-map updates.
Prefer small, direct replacements and remove superseded code in the same batch.
Protect each encountered incorrect pattern with an existing or small new linter
where sound; use semantic regressions when static detection cannot establish it.

Work client-only against current stock Hermes. Backend changes, deployment and
external mutations require separate authorization. Backward compatibility
requires explicit user approval. Preserve Studio appearance, supported behavior,
captured scope, uncertainty, durability and unrelated changes.
