# Profile model ownership pilot

The main-model edit route is owned by `ProfileModelEditSession`; fallback edits
are owned by `ProfileFallbackEditSession`. Widgets retain layout, input controls,
modal presentation and navigation. These are completed local slices, not a claim
that the remaining model settings or administration views are clean.

`ConfiguredModel` parses the canonical stock `model/info` strings and preserves
empty automatic-provider/unconfigured values. Catalog values use `ModelChoice`;
fallback values use immutable `FallbackModel` objects retaining routing metadata.
Malformed fallback configuration is reported without silently rewriting it.
Legacy string rows and coerced identities have no compatibility reader.

The main owner captures its profile and opening provider/model pair, including
automatic-provider observations that cannot become an explicit catalog choice.
It validates membership and observes that pair again before either initial or
confirmed dispatch. Disposed routes cannot dispatch after a held validation or
confirmation, or publish late readback. A conflict exposes a read-only review of the current exact provider/model pair
and the retained wanted pair. Its opaque ticket belongs to the same route, local
revision and review request. Keep mine explicitly adopts that observation as the
baseline while preserving the wanted choice; Use server replaces the pending
choice, including a raw automatic-provider observation. Cancel changes neither.
These decisions are local only: Save default remains the sole mutation command.
Another choice, review, load, save or disposal retires old tickets. A dirty load
preserves the opening baseline and choice. A later server change still refuses
at Save, including changes during expensive-model confirmation. Review observes
model/info, then checks fresh profile membership before issuing its ticket.

Back and Close intentionally cancel an uncommitted model choice without a dirty
confirmation dialog. Public route tests characterize that existing behavior and
reopening reads the actual server model. Independent catalog generations reject
older refreshes. Initial loading cannot start a competing picker refresh.

Main, fallback and helper commands use distinct owned mutation capabilities.
Authentication and credential renewal check command authority immediately before
HTTP dispatch; generic mutations cannot substitute for these capabilities.
Per-call authority retires on settlement and timeout even when the route remains
open. Uncertainty begins at actual dispatch. Controlled real-HTTP tests cover
held authentication released after route retirement or settled timeout; the same
four tests reproduce an actual late write on the frozen original owners.
Logical connection closing intentionally drains accepted retained operations;
physical closure and command retirement still block new dispatch.

Fallback picker tickets capture row identity and revision before catalog reads
and modal completion. Removing or reordering a row cannot retarget a delayed
selection. A failed save keeps its pending edit and opening baseline; a fresh
review ticket is required to adopt changed server configuration. Readback must
verify the requested chain before reporting success.

The diagnostics row receives `ModelAccessObservation`, a passive typed projection
of the overview's existing cache. It creates no additional request/cache owner.
Malformed model refreshes retain confirmed data and report failure; disposed
overviews cannot begin another request.

Controlled regressions are in `profile_model_edit_session_test.dart`,
`profile_fallback_edit_session_test.dart` and `administration_overview_test.dart`.
Real-route behavior and appearance remain covered by the default/fallback sheet,
diagnostics panel and Studio widget tests. Independent review produced red/green
cases for automatic-provider baseline loss, catalog response ordering, and
post-disposal overview reads. Static source shape cannot establish those response
orderings, so these are behavioral prevention contracts.

The independent `ARCH_COMPLETED_MODEL_VIEW` guard checks completed view paths for
canonical transport calls/tearoffs, wire parsers and reserved wire-map indexing.
Its semantic fixtures prove invalid/valid/input-error CLI exits. See
`tools/architecture/rules/completed_model_view.md` for exact scope and budgets.
Import, role and cycle rules protect the broader dependency graph.

The main conflict-recovery batch inspected official unmodified stock Hermes
`8b66a51036c1e20920a17cdd049fdf55c968d683`: `web_routers/models.py` GET model/info,
GET model/options and POST model/set, and `web_models.py` ModelAssignment.
Earlier main/fallback work inspected `2b52acc2d8ceea37d06945a8bbc7deddaa30de63`;
remaining defaults work inspected `db45b44ab72af81974adfb01c9ecd6967f5bec29`.
Future integration acceptance must refresh current stock again. Stock mutation APIs have no atomic expected-version
condition. Client preflight cannot prevent a change after observation, and
`model/info` does not expose every routing field such as `base_url`. Host tests
do not establish current-stock mutations or physical-phone acceptance.

Frozen source hashes, red/green logs and measurements belong in ignored
`build/architecture-program/`. Final full-program checks remain pending.

Main-model recovery prevention is behavioral: controlled tests hold reads,
remove the profile, replace the local choice, dispose the owner and change the
server again after review or during confirmation. The existing completed-view
and dependency guards protect the wire-policy boundary; they do not establish
review freshness or the non-atomic server race. The original public conflict
case failed because Review changes was absent after a verified zero-write
conflict. Original Back/Close characterization passed. The parent verified 39
owner/UI checks and 61 affected transport/default/helper/fallback/chooser checks,
then inspected all four actual theme/text-scale renders against the frozen
successor. Independent reader-load review accepted the owner/view boundary.
These scoped results do not establish final native/current-stock acceptance.
`CAPTURE_MODEL_REVIEW=true` produces four real-SDK-font 320px light/dark
1x/2x dialog captures in `build/model-review/` for that review.

Two layouts were compared: keeping a second picker inline duplicates the normal
catalog/selection controls; the chosen compact Review action opens one scrollable
current/wanted decision dialog and leaves the existing sheet and Save action in
place. No persistent heading or dismissal confirmation was added.
