# Model and subscription observations

`ProfileModelCatalog` owns fetching and admission of stock model catalog and
subscription telemetry for one immutable `WorkspaceScope`. `ModelCatalog` is its
single wire decoder; `ModelChoice` carries immutable optional prices, control
availability and its provider observation. Provider route plus model ID remains
identity; display labels never change the write address.

The inspected stock Hermes commit is
`13dc3a73895aff1f823c1566bc1dd9b52fe35b65` (`hermes_cli/model_picker_inventory.py`,
`tui_gateway/methods_config.py`, `tui_gateway/methods_config_set.py`). All changes
are client-side and use the existing `model/options`, `model/info` and session
`config.get`/`config.set` contracts.

## Owner and reuse

`ProfileGateway.modelCatalog` retains the owner for its gateway lifetime.
`ProfileAdministration.modelCatalog` borrows the administration repository's
retained owner for that canonical profile, using its existing captured read
adapter. Both close with their transport owner; widget routes do not own caches.
Other screens can borrow the same owner and consume typed observations:

```dart
final catalog = await profile.modelCatalog.load();
final codex = catalog.provider('openai-codex');
final usage = codex?.usage;
```

Views receive immutable values and application callbacks. They do not decode
HTTP maps, fetch independent subscription endpoints or decide account identity.
Profile defaults, helpers, fallbacks and task editors use this same module with
`explicitOnly: true`; chat uses the normal picker policy. Those policies have
separate in-flight reads and snapshots. Ordinary concurrent reads share work;
each new load consults Hermes's cache again. `refresh: true` requests the stock
refresh and supersedes pending reads. `supersede: true` starts a new observation
without forcing remote provider probes, used for a newer editor reload. Earlier
completions cannot replace the newer snapshot, and closure rejects pending
results. Errors retain the last successful snapshot, without silently returning
it as fresh. There is no client polling or fabricated telemetry TTL.

## Supplied facts and uncertainty

Backend route prices are optional formatted input, output and cache prices.
Codex choices instead carry explicitly labelled API-equivalent rates from the
shared models.dev owner; direct OpenAI API choices use
that same rate card. Missing values remain absent. Explicit zero numeric rates
are valid; subscription inclusion is never a free API rate. The picker
shows units once per provider and the model card exposes the full ID and supplied
facts. It does not infer vision, tools, context capacity or descriptions.

Reasoning and fast flags describe offered controls. Stock Hermes defaults the
reasoning control to true when metadata is silent; this is not certification of
model capability. The backend deliberately omits `supported_efforts`. Wing uses
the stock eight-value session ladder and removes Off when
`can_disable_reasoning` is false. Fast is an On/Off control; an existing ultrafast
session remains ultrafast until the user changes it. Changing model keeps only
controls offered by the new route, reducing ultrafast to fast when only fast is
offered.

`ProviderAccountUsage` distinguishes single-account windows from account pools.
Every pooled account retains its opaque identity, label, state, windows and
optional reset time. Windows retain their account/model scope and reported
percentage. Unknown and unavailable states never become zero, missing windows
are never filled, and different accounts are never averaged or merged. Stock
Hermes handles telemetry staleness before serialization. These observations are
advisory; reading them does not rotate credentials or disable routing.

## Chat writes and verification

Opening the ledger filters to the captured chat's provider and puts its selected
model first within that provider. Provider plus model ID determines selection;
profile defaults and the catalog's first provider cannot replace it. The opening
provider tab stays visible, and All still exposes other routes. Starting search
uses all providers; explicit filters can narrow it without changing the draft.
A missing saved route remains an uncertainty notice rather than another model.
`model_chooser_test.dart` guards long catalogs, duplicate IDs, selection semantics
and cross-provider browsing; the real workspace reopening regression lives in
`profile_intelligence_test.dart`. Runtime selection and visibility require
behavioral checks; source linting cannot establish them. The composer layout regression also requires 32dp normal-text controls: model opens the picker, lightning toggles immediately, and reasoning applies only after a held slide is released. Ordinary reasoning taps and cancelled held gestures do not write; changing chats retires the selector. Disabled and keyboard paths are guarded by `chat_intelligence_picker_test.dart`.

The chat owner reads reasoning and fast for the captured live session. The
composer model button opens the picker; its small lightning toggle and held
reasoning selector use the same admitted write path as picker Apply. Picker
changes are drafts; Close discards them. Model confirmation remains before any
subsequent setting write. A partial save retains acknowledged fields and retries
unconfirmed settings without repeating the model change. Fast requires the stock
returned value before the owner displays success. Every command includes the
captured session ID and profile; it never changes profile defaults.

`profile_model_catalog_test.dart` covers read sharing, policy isolation,
supersession, closure, error retention and per-account fidelity.
`profile_intelligence_test.dart` covers captured chat admission, confirmation,
partial reasoning/fast retries, model events arriving before their acknowledgement, and preserving ultrafast.
`chat_intelligence_picker_test.dart` covers staging, control availability, cards,
commit locks and cancellation. `intelligence_sheet_layout_test.dart` renders both
themes at normal, enlarged and landscape sizes. Its density guard measures actual rendered row spacing, search, tabs and shortcut heights, and requires all 14 Codex choices, in both empty and mixed-price API observations, to fit on a 412dp phone with Apply reachable. This catches inherited Material minimums and tap-target padding; source linting cannot establish the resolved layout. Existing domain/view dependency
and intelligence read-admission guards protect the structural boundaries;
behavioral tests establish ordering and uncertainty that import linting cannot.

## Shared pricing observations

`ModelsDevPricing.shared` owns anonymous HTTPS downloads from
`https://models.dev/api.json`, independent of Hermes transport credentials. Real
`ProfileGateway` and `AdministrationRepository` factories inject its read seam
into their `ProfileModelCatalog` owners. Injected transports can supply a
controlled rate reader without making public network calls. Views perform no
rate I/O. Concurrent reads share one request across profiles and catalog policies.
The owner stores only direct `openai.models` base input/output/cache-read rates,
with exact model IDs, in a compact device cache. It revalidates after six hours
using the ETag; explicit Refresh bypasses that interval. Failures retain cached
rates with an unavailable-freshness observation and throttle ordinary retries
for one minute. Successful live rates remain usable if device persistence fails.
Invalid cache data is discarded, with no old-format migration or bundled table.

`ModelsDevPrices` is the immutable decoder. Missing, negative, nonnumeric or
nonfinite rates remain absent; it never substitutes Codex or reseller entries,
guesses aliases or applies context tiers to aggregate usage. `ModelPrices` keeps
numeric API precision independently of its display labels. `ModelCatalog`
exposes these same prices on Codex picker choices and as a historical lookup
independent of today's selectable IDs. Backend prices for other routes remain
route-specific observations. `ModelUsageCost` performs arithmetic on this typed
lookup; it owns no pricing I/O or independent rate table. Reader/session
retirement prevents deferred usage from starting a new pricing read, and the
catalog fences publication after rate enrichment as well as after backend reads.

Stock upstream `e0550c97bbd916cd5ff8fa0450e6291c31921b94`, inspected 9 October
2026, formats route prices in `hermes_cli/inventory.py` using
`hermes_cli/models_pricing.py`. Its model/options response does not expose direct
OpenAI API rates or the internal usage rate card, and Codex's included zero cost
is not an API-equivalent rate. This implementation requires no Hermes changes.

`models_dev_pricing_test.dart` guards exact source selection, numeric precision,
cache/revalidation, anonymous requests, corruption, offline retention and
recovery. `usage_cost_test.dart` guards historical-model admission and rejection
of included subscription zeroes. Static checks cannot establish runtime payload
coverage, freshness, transport headers or asynchronous ordering; these are
behavioral guards. The historical-model check was demonstrated failing with the
previous choice-only lookup. See [Analytics behavior](ADMINISTRATION.md) and
`usage_analytics_test.dart` for shared catalog enrichment and recovery.
