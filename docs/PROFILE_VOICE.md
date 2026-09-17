# Profile voice

Administration → Profile → Voice → Speech synthesis provider opens the combined
provider and voice editor. App settings links directly to it.
Choose a provider, then use the compact voice selector and adjacent Play button.
Credentials/setup appear for the selected provider when needed; voice controls
appear once it is ready. Models, existing credentials and custom voice IDs live
under Advanced. The separate voice page, visible sample script and permanent
Saved status have been removed.

Selecting a voice saves it immediately. Play reads the approved Wing sample using
the confirmed selection; Stop cancels pending or active playback. Android engine
and local voice choices remain in App settings.

The page captures its connection/profile and uses only vanilla Hermes APIs:

- GET `tools/toolsets/tts/config` and PUT `tools/toolsets/tts/provider`:
  provider discovery/readiness and confirmed provider selection. Existing
  credentials, setup and model editors retain their stock APIs.
- GET `config` and `config/schema`: current provider and editable voice field.
- PUT `config`: sparse update of that provider's voice field, followed by readback.
- GET `audio/elevenlabs/voices`: the account's ElevenLabs catalogue.
- POST `audio/speak`: the sample text, with an explicit profile and no voice override.

Edge suggestions match the stock desktop list. Vanilla Hermes has no general
voice catalogue endpoint, so Edge is labelled **Suggested voices**. The current
custom ID remains visible; **Advanced → Voice ID** accepts another ID. Other
providers expose a custom ID when their schema supports it, and can test their
current default. Backend source and installation remain unchanged.

Provider identity is distinct from speech engine identity: Nous Subscription and
direct OpenAI both report `tts_provider: openai`, but stock Hermes saves their
selections as `nous` and `openai` respectively. Match and confirm the managed route
using `requires_nous_auth`, including when account access is still needed. Both
routes use `tts.openai.voice`; saving a voice must preserve the selected route.
Regression fixtures include this shared-engine pair so catalogue ordering cannot
silently choose the wrong account or turn a confirmed Nous save into an error.

Rapid choices are serialized and coalesced to the latest selection. Play waits
for confirmation. Unconfirmed writes retain the last confirmed value and require
Refresh. Leaving the page lets queued saves finish against their captured target.
Refresh, selecting another voice, leaving the page or backgrounding stops audio;
late results cannot restart it. Settings are checked before and after synthesis
to reject a sample whose selection changed externally. Stock APIs do not provide
an atomic compare-and-set or report the synthesized voice ID, so cross-client
concurrency is still limited by that contract.

## Verification

- `test/profile_voice_test.dart`: scoped sparse writes, rapid selections,
  rejected/unconfirmed saves, external edits, ElevenLabs catalogue failures,
  text-only synthesis and finishing queued saves after closing the editor.
- `test/profile_voice_page_test.dart`: autosave/Play/Stop, cancellation, custom
  IDs, provider switching, readiness, unconfirmed saves, catalogue search,
  recovery, ordinary phone layouts and all five accents in light/dark at
  320 dp and 200% text.
- `test/profile_voice_live_test.dart`: opt-in real HTTP test against a disposable
  local stock server with a `voice_review` profile and Edge installed. Run with
  `--dart-define=VOICE_REVIEW_PORT=<port>`. It changes that disposable profile and
  writes the returned MP3 to `/tmp/wing-stock-voice-sample.mp3`.

For rendered widget checks, pass `--dart-define=VOICE_REVIEW=true` and
`--dart-define=CAPTURE_FONT_DIR=<directory>` containing `Roboto-Regular.ttf` and
`MaterialIcons-Regular.otf`; images go to `build/vanilla-voice-review/`.

On 17 September 2026 the real HTTP test passed against unmodified Hermes
`af4a3eba` using a disposable profile: a voice save followed by stock synthesis
produced a 32,544-byte, 5.424-second MP3. ElevenLabs uses fixture coverage here;
live account verification and listening on the user's phone remain UAT.
