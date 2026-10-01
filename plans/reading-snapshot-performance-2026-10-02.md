# Reading snapshot performance fix

Scope: the first remaining CPU candidate from the production streaming/typing
investigation. Draft persistence is a separate candidate and is unchanged here.
The starting source is main commit `9a540022924c4a2cf1d103fb791de8bbece49201`.
This change is entirely in Wing's local cache; it introduces no Hermes API or
backend changes.

## Cause and change

`ProfileWorkspaceController._saveReadingSnapshot` previously JSON-encoded each
candidate live history row on the UI isolate to check its length, then projected
only four reading fields. The snapshot store already supported background
encoding, but this preliminary work happened before reaching that worker.
Stream presentation also invoked this preparation once per second despite live
text and reasoning being absent from the saved reading history.

The controller now captures only `id`, `role`, `content` and `timestamp`. The
store applies the encoded-message character limit inside its encoder, after
large snapshots have moved to the existing worker. The existing bounded small
snapshot path remains synchronous. Filtering copies containers and preserves
the caller's history. The strict per-message limit remains less than 32,768
encoded characters; the complete cache remains bounded to 2 MiB of UTF-8.
Small reading text is now retained even when excluded private metadata would
have made the original live record exceed the limit. The saved field whitelist
and cache format are unchanged.

A dirty flag prevents text/reasoning presentation from repeatedly preparing
unchanged reading history. General changes mark reading state dirty. Later
stream updates can flush a pending durable change once the existing one-second
interval expires; explicit history saves and disposal still save directly.
Save exceptions leave the state dirty for a later update to retry. There is no new
persistence timer or idle wakeup. This does not promise a trailing save after
one second without further events.

## Local reproduction

A synthetic test exercised the actual controller disposal/save path with ten
chats containing 160 history rows each. The newest 60 rows per chat were
candidates: 150 small rows retained, 450 oversized rows discarded. Oversized
content contained 280,000 characters and excluded metadata. A stopwatch enclosed
only synchronous `controller.dispose()`, including preparation and initial
store dispatch, before awaiting background completion and persistence.

Before the fix, the four synchronous samples were **409.681, 416.351, 387.655 and
385.045 ms**. They enumerated source-row keys 1,800 times. The final fixed
version measured **12.563 ms** on its first run, then **0.911, 0.965 and 1.117 ms**,
with zero source-row key enumerations. Both versions saved the same 12,457 bytes
and 150 retained messages, leaving the original 160-row histories unchanged.
These are host debug/JIT results from an intentionally large fixture, not phone
frame measurements or an estimate of everyday histories. The baseline stdout
was captured in the tool session; the supplemental probe is under ignored
`build/snapshot_cpu_probe/`. Final-run output was saved locally to
`/tmp/wing-snapshot-final-probe.log`.

## Regression coverage

- Fixed-field projection avoids whole-row traversal on the UI isolate; saved
  order, count, field whitelist and original history are checked.
- Text and reasoning streaming cross the save interval without preparing clean
  history. A durable interim message still reaches the cache while the next
  answer streams, without caching unfinished live text.
- Exact 32,767/32,768/32,769 encoded-character boundaries, escaped text,
  multibyte text, source immutability and excluded large metadata are checked.
- Existing cache bounds, background dispatch, ordered writes, restoration,
  retention, notifications and streaming presentation checks are retained.

Validation on the final source:

- 146 focused tests passed.
- Full Flutter suite: **2,693 passed**, 17 existing opt-in skips, 4 minutes
  15 seconds.
- Static analysis with fatal infos: no issues.
- Format check and `git diff --check`: clean.
- Independent source review found no remaining correctness issue after the
  pending-interim save regression was addressed with the dirty flag.
- The supplemental synchronous-work probe passed on the final source after the
  full suite completed.

## Device validation still required

No phone control, deployment or model calls were used for this fix. The prior
production trace established main-thread CPU bursts, but did not contain Dart
function stacks proving that this path caused the recorded worst frame gap.
Compare the previous and fixed builds using the same restored history and
streaming/typing replay before claiming a lower phone p99. Keep the separate
Perf QA process stopped for production measurements. Live model calls, if used,
must use Luna as requested by the owner.
