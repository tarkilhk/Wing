# Profile overview owner

Integration design read current official unmodified Hermes at
`18fa38463490c07e7d1764520118097a5e5fdd42`: model/info, config,
providers/oauth, skills, tools/toolsets, MCP servers and the profile-scoped cron
list. Stock skills/toolsets return lists, normalized by the existing repository;
providers and connectors use their named collection wrappers. An empty provider
in model/info is valid automatic routing. Provider list rows carry nonempty
string IDs; sparse/unknown credential status is still an observation, not proof
of absent credentials or failed inference. This is a client-only extraction.

## Owners and interface

The Administration parent owns one `ProfileOverviewSession` for its captured
`WorkspaceScope`; the body borrows it and disposes only presentation resources.
The session owns targeted editor-return reads, refresh coordination and summary
projection. It composes the
existing `AdministrationOverview` and a lease on `ScheduledTasksController`.
Those remain the only observation cache and task cache/action/journal owners.
Summary values are computed from them, never retained in another cache. The
header, search and body consume that same owner. There is no ordinary Health
cache, observation-publishing callback, revision counter or label-to-read policy.
Disposal removes subscriptions, retires overview reads and releases the task
lease; it does not forget already mutating task requests.

`ProfileOverviewSummary` exposes immutable rows, destination identities, attention
and task ranking facts. Its passive text fragments retain integer and time values
for localized UI formatting. The view retains navigation callbacks, scroll/search
restoration, text localization and reduced-motion-aware row highlighting. Typed
destination identities select owner commands; labels do not select protocol reads.

Entry observes the captured profile without refreshing workspace discovery.
Header and pull-to-refresh join workspace, overview and shared task reads; an
already-running task read is awaited rather than skipped or duplicated. Editor
navigation captures the session before awaiting the route. Its return is inert
after that session retires, so a newly selected profile is never refreshed by the
old editor. Retirement removes and completes task waiters before releasing the
lease. Health/runtime paths retain their separate owner and pending obligations.

A formatter-only alternative would leave raw record interpretation, task ranking,
refresh policy and disposal obligations in the view. The selected route owner
hides those obligations without adding a repository or duplicate cache.

## Behavioral verification

```sh
flutter test --no-pub test/profile_overview_session_test.dart test/profile_overview_widget_test.dart test/profile_overview_access_boundary_test.dart test/administration_overview_test.dart test/provider_access_test.dart
```

Tests cover automatic routing, independent loading/unavailable/retained-data
facts, unknown booleans, selected credential metadata, expired access attention,
task ranking/outcomes, exact destination read sets, captured profile scope, shared
task leases, duplicate read avoidance, refresh lifetime and route disposal
while reads/navigation are held. Widget tests retain destination reachability in
both themes at enlarged text. Existing administration home/search/scroll/header
and task action tests remain required. Actual Studio rendering at normal and
enlarged phone sizes in both themes is a separate parent acceptance gate. The
ordinary parent-owner successor has passed independent source review. Its
switched-profile editor-return regression reproduces the incorrect read against
original source and passes the successor. Owner tests cover held workspace/task
refresh completion; the existing actual shell/header test covers forwarding.
The proposed additional header widget case was removed after unreliable fixture
cleanup, rather than adding overlapping verification or claiming its timeout
proved a defect. Whole-feature acceptance remains pending the focused disposition.

The old actual view mislabeled canonical automatic routing as unavailable; its
widget regression supports controlled old-view RED and new-owner GREEN. A
separate controlled public refresh regression established malformed provider
identity replacing confirmed access cache data. The access read now validates
identity before assignment, retains the prior data/time on failure, and safely
reports an initial malformed response as unavailable. It does not manufacture
identities or reinterpret unknown status as signed-out.

## Small structural guard

`ARCH_OVERVIEW_VIEW_WIRE` checks the completed overview library and its actual
parts. It forbids access to canonical transport operations, raw overview/task
cache properties, stock row/config parsers and provider-record construction.
Diagnostic remedy: render the typed summary and send commands to the route owner.
Other unmigrated administration views remain outside this completed slice.
Canonical declaration/library provenance decides findings; the syntax prefilter
only selects candidates. Same-name local/SDK symbols and typed owner commands
remain valid. Typedef constructor spelling chains only widen the prefilter;
resolved constructors still decide whether a call is the canonical parser.

```sh
dart run tools/architecture/rules/overview_view_wire.dart --json
dart run tools/architecture/tests/overview_view_wire_test.dart
flutter test --no-pub test/profile_overview_wire_guard_test.dart
```

Its independent fixture proof covers direct calls, aliases, prefixes, cascades,
method/function/constructor tear-offs, exports, typedefs, raw cache reads,
definition/consumer parts and unrelated names. The real CLI proves bad=1,
valid=0 and unverifiable=2. Candidate unresolved dynamic calls and conditional
import closures fail with input exit 2. The host wrapper is discovered by the
mandatory complete host suite; aggregation is orchestration only. No suppression
or migration baseline is needed. CI must check the full completed library and
its owner/part/import/export closure; owner, role, alias or schema changes require
a full check rather than changed-file-only sampling.

Use the existing small-rule feedback target: clean checking on a shared parsed
snapshot at most 50 ms; cold standalone JIT command at most 10 seconds. Measure
actual check, parsing, SDK startup and candidate fixture costs separately; record
runtime evidence privately under ignored `build/architecture-program/`. No timing
noise changes correctness or silently expands a budget. The clean path starts
no semantic resolver; candidate inputs legitimately pay resolved-analysis cost.

This rule establishes direct canonical wire/cache access ownership only. It does
not prove every business policy left the UI, arbitrary wrapper dataflow, async
ordering, cache substitution or safe malformed responses. In particular, static
shape validation cannot establish that a failed refresh retained the previous
confirmed map and timestamp; the public controlled refresh regression is the
semantic guard for that property. No regex or raw-source assertion substitutes
for these behavior checks.
