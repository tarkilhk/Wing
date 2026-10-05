# Profile Voice ownership

One captured `ProfileVoiceController` owns each Voice route's configuration,
provider workflow, autosave intent and sample admission. The existing
`ProfileVoiceRepository` implements stock reads and owned dispatch; it caches
no configuration or catalog. `VoiceOutputController` remains the native playback
owner, privately delegated by this route owner. There is no second provider
controller or parser: readiness reuses `ToolSetupReadiness`.

## Current unmodified stock

Official main inspected at `fdcae6debac4ad33adc449a4263433b389b563ef`.
The exact fetched UTF-8 SHA-256 source hashes are:

| Source | SHA-256 |
| --- | --- |
| `hermes_cli/tools_config_providers.py` | `b2185bad4626e16c5bb6ccbe64f31bd26bfd7d8bee0fdc119b1e655c30e35dfc` |
| `hermes_cli/web_models.py` | `1fb71cb7d0006e6e930f2bbf181135de806af71804b767dc70e919eadcbe0f17` |
| `hermes_cli/web_routers/audio.py` | `aa7bcae42dfa19010af35524c64cc5d1aa1cdb72f8532fbc7a59e5430d6d00eb` |
| `hermes_cli/web_routers/config_env.py` | `78d53e2e85df3ad0e83e52d0bad4c043ff24b768efe3a03ec2bb84b9e4cb0cbd` |
| `hermes_cli/web_routers/tools.py` | `56cbf186dfe2a2c0dc8665b29af13e1aa3f1a9ec975f1e571842dd95af472937` |

The [audio router](https://github.com/NousResearch/hermes-agent/blob/fdcae6debac4ad33adc449a4263433b389b563ef/hermes_cli/web_routers/audio.py)
and [request model](https://github.com/NousResearch/hermes-agent/blob/fdcae6debac4ad33adc449a4263433b389b563ef/hermes_cli/web_models.py)
accept only `text` for `audio/speak`. This previews the saved profile's effective
TTS configuration, not an unsaved voice/provider. No shared setting is changed
temporarily to simulate preview; no backend change or capability is invented.
Stock offers no CAS/idempotency key; before/after client observations cannot
eliminate cross-client races. Returned audio has no selected voice ID, so the
repository verifies the captured settings before dispatch and after synthesis.

Config GET returns server-expanded effective defaults; these are observed facts,
not client fallback guesses. Its schema is scoped to the requested profile.
Config PUT deep-merges a sparse patch and ACKs `ok:true`. Provider PUT separately
ACKs `ok/name/provider`, possibly needing account access. Setup POST starts a
tracked operation and is not completion. Nous retains its `nous` route while
using OpenAI's voice configuration key. Edge choices remain labelled suggestions;
ElevenLabs uses the account catalog. Current/custom IDs remain visible.

## One writer and lifetime

| Fact or transition | Owner |
| --- | --- |
| Captured connection/profile | Repository fixed for this route. |
| Effective settings and discovered default fields | Controller, immutable detached configuration values. |
| Provider readiness/catalog and selected display identity | Controller, existing pure tool readiness codec. |
| Submitted autosave target and newest coalesced intent | Controller, exact issued `ProfileVoiceSaveTarget` lease. |
| Configuration/provider/setup dispatch | Repository through existing owned settings/mutation callbacks. |
| Positive ACK | Kept separately from the subsequent readback/readiness outcome. |
| Native preparing/playing/error | Existing private player; controller derives immutable observations. |
| Credential draft/write | Existing credential editor, scoped typed navigation callback. |
| Setup result polling | Existing operation session; result page borrows it and controller finally disposes it. |
| Text draft, voice-search query, focus, dialogs/navigation | Views/composition. |

A user choice reserves its exact target and drain before observer publication.
The existing rapid-choice behavior coalesces superseded unsent choices. Each
retained target holds its connection lease. Route retirement freezes the latest
already admitted target, rejects new targets, stops sample authority/publication,
and lets admitted autosaves settle in order. The supported Jenny-held/Guy-admitted
before-close workflow still persists Guy. A retired target cannot be issued anew;
there is no constantly-true production dispatch fallback or automatic failed-write
retry. Provider/setup commands instead require the still-current route at physical
dispatch after all awaits, including authentication. Synthesis obeys route and
sample retirement too.

Configuration and provider invariants are freshly checked before each sparse
voice patch. Same-field/provider conflict never overwrites another edit. A
converged value is observed without inventing a write ACK. Failed/unknown writes
retain the last observed selection and require a read-only refresh. An ACK followed
by unavailable/different readback remains saved plus a separate unavailable or
changed current observation; it is not relabelled as an unknown mutation.

Observer retirement revokes command authority immediately. Notifier disposal
waits for the synchronous notification to unwind; child player disposal is deferred
only when that notification could originate from the player's own callback.
Already admitted leases still drain. Old snapshots and nested choice/default/provider
collections are immutable and cannot be changed by view or caller aliases.

## Presentation and subtraction

Both admin Voice libraries require typed session factories and typed navigation
callbacks. `admin_voice_routes.dart` is actual raw-profile composition: each explicit
picker replacement provisions the selected profile's fresh owner and default-field
catalog. Credential composition reuses the existing provider inventory owner to
read the selected profile's current metadata before creating its credential
editor. It never forwards A's fields or credential baseline as B's configuration. The existing settings
editor remains the sole defaults-draft/write owner. App Voice settings, parent
Administration, the live constructor and existing Voice tests use those same routes.

Removed raw `profile`/`device` widget inputs; view `_profile`, `_voices`, `_player`,
provider map/list/readiness/busy/error stores, `_base`, `_provider`, `_read`, `_run`,
preview/save/provider/setup/credential policy; landing-page schema/regex discovery;
public controller `repository` and writable settings/choices/selected/loading/saving/
fresh/error/catalogueError fields; repository's raw `profile` escape and
`speechProviderRoute`. Values move directly into `models/profile_voice.dart` without
re-exports/aliases. The original Studio controls, spacing, voice dialog/search,
Advanced custom ID, autosave, Play/Stop and native cancellation remain supported.
No generic framework, persisted format, device voice/runtime usage redesign or
second catalog cache is added.

The small existing view-adapter dependency checker can forbid raw repository/gateway
namespaces in the two completed Voice libraries; mixed composition stays outside
that finite property. Target admission/drain, uncertain effects, playback races,
configuration alias isolation and actual font geometry require behavioral evidence.
Existing preservation cases plus bounded crossing additions supply that evidence;
a source handoff alone is not runtime/render acceptance.
