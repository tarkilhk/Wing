# Hermes Cloud connection journey — design review

Status: implementation approved by the owner after the consistency revision; implemented September 18. Equal Cloud/address entry follows the unchanged welcome. The instance picker always uses selection plus Continue, including a single instance. Empty accounts link to Nous Portal and can refresh after creation. The owner confirmed successful Portal login and empty-instance discovery on Android. Connecting to a running Cloud instance remains untested.

Owner review correction: preserve the full richness and appearance of the original address journey. The abbreviated first mock is not a replacement specification. Cloud and address must use a consistent second-screen composition, including the same identity artwork and heading treatment.

## Task and primary action

A person who already uses Nous-hosted Hermes wants their existing agent in Wing without locating its address or copying credentials. The entry action is **Hermes Cloud**; completion remains **Save and open**. One connection means one hosted instance. Profiles remain choices inside that instance's workspace.

## Desktop code: follow the flow, verify the mobile session

The official Desktop source gives a concrete reference for Portal sign-in, `GET /api/agents`, organization selection, instance summaries, per-instance authentication, and saving a connection. It is straightforward to follow the sequence and data handling. It is not a direct Electron-to-Flutter port: Desktop's Portal discovery uses an app-owned browser session and Privy cookies. Wing uses an app-owned Android WebView and its private cookie store for Portal discovery; the owner confirmed that their Portal sign-in and empty-instance discovery work on Android. Instance-level native OAuth is a separate existing stock contract. See the [source research](../research/2026-09-17-nous-portal-login.md), implementation rechecked against upstream commit `07c92d675a821d96e4aabd636bf22bde32167c38` (September 17).

Per-instance authentication uses stock `/auth/native/authorize`, `/auth/native/token` and `/auth/native/refresh`. The browser intercepts the exact generated loopback callback before navigation; PKCE and state are verified by Wing and the stock broker. No listener, custom app-scheme redirect or backend change is needed. The original design preview remains simulated.

## Two entry arrangements compared

**A — two clear routes (owner selected).** Keep welcome unchanged. Connect your agent opens a portrait-led **Connect your agent** screen with a compact grouped pair of equally weighted actions. Tapping a route advances immediately; no selection-then-Continue step. This chooser has a different title from the destination screens so it does not repeat the address screen's heading.

```
New connection
                 [existing portrait and feathers]
Connect your agent
Choose how to find your Hermes.

Hermes Cloud                                  ›
Find your instances with Nous Portal
───────────────────────────────────────────────
Use an address                                ›
Connect with a dashboard address
```

This costs address users one route-selection tap, but Cloud users do not have to interpret a hostname field. Both groups have equal visual weight and accessible row targets. Put address-specific help on the address route rather than making the chooser look like an address form.

**B — address first (considered, not selected).** Retain the dashboard address form and Continue; add a quieter “Using Hermes Cloud?” action. Existing address users gain no taps, but the Cloud audience initially sees an irrelevant field and can mistake Cloud for an advanced option. This is why A better fits the expanded audience.

## Proposed Cloud journey

```
Existing welcome → Connect your agent
                  → Hermes Cloud → Nous sign-in
                                    ↓
                      organization, only if required
                                    ↓
                      choose a hosted instance
                                    ↓
                   existing three connection checks
                                    ↓
                   Connection verified → Save and open
                                    ↓
                    existing Chats and profile selection
```

The existing Connections → Add entry starts at route choice without repeating welcome. Use an address opens the current address → sign-in → check → review flow. It keeps its custom setup and address guide.

### Matched destination screens

Both routes share the existing 112 dp portrait and original pointed feather cluster, the **Where’s your Hermes?** title, identical gutters and type scale, the same progress treatment, and a bottom **Continue** action. Only the task-specific content differs:

| Address | Cloud, after sign-in |
| --- | --- |
| “Use the dashboard address you open in your phone’s browser.” | “Choose the Cloud instance you want to connect.” |
| Dashboard address field and complete-address helper | Instance rows with name and reported state |
| Original “One address for your agent” panel with Profiles & settings and Live chat · same address | Selected instance uses Studio's tinted background without a tick |
| Find my address | Use a different Nous account |
| Continue to existing sign-in | Continue with the selected instance |

The proposed Cloud list now uses selection followed by Continue, replacing the earlier immediate navigation on row tap. This adds one deliberate confirmation tap for multi-instance users and gives both routes consistent interaction and action placement. Unavailable instances retain their specific manage/recovery path. The same selection plus Continue interaction is retained for one instance.

Preserve the actual address flow beyond this screen too: destination panel, password reveal/autofill, provider-key explanation, Custom setup with proxy/chat/header controls, factual checks and recovery, and complete name/icon/profile review. Do not replace those with a generic login form or a shortened wizard when implementing Cloud.

### Portal handoff

Use the same portrait-led destination frame while handing off to Nous, with “Sign in with Nous to find your Cloud instances.” Show the Portal destination during the handoff; return to the same unfinished setup. Cancellation is a normal return, not an error or a half-saved connection. Do not build Wing's own username/password form for a Nous account. The browser's provider-owned screens are external to Wing's matched screen layout.

Android presents an app-owned browser with visible destination and Close action; cancellation returns to the unfinished setup. The preview's “Simulate return from Nous” is a design-review control, not product copy.

### Instance choice

Title: **Where’s your Hermes?**, matching the address route. List names and the returned availability state, using compact full-width rows. Select an available instance, then Continue to authenticate/check it. Keep URLs in details rather than as the main identity. Distinguish instances from profiles.

For multiple organizations, show a compact organization choice only when the discovery response requires it. Do not display a single-option organization selector. Changing organizations clears the old results before fetching new ones.

For one instance, retain the same picker and Continue interaction. The proposed auto-skip was not adopted. Do not auto-create a saved connection or switch the active workspace merely because discovery returns one instance.

### Same check and completion experience

Reuse the exact three real stages: **Profiles & access → Live chat → Chat history**. Discovery or a running status is not evidence that these checks passed. No model request is sent. Keep truthful status words and clear state indicators.

On success the familiar portrait and feathers return with **Connection verified**. Prefill Connection name from the Cloud instance's name. Keep icon customization, server-preferred profile context, and explicit **Save and open**. Preserve secure-save failures and verified drafts. Select the saved connection only after a successful save.

The constant identity through this flow is the selected instance name. Carry it from picker to check to review without adding repeated cards or persistent success banners. Do not turn Cloud discovery into a new dashboard.

## Edge journeys for review

| State | Proposed behavior |
| --- | --- |
| No instances | “No Cloud instances yet.” Open Nous Portal to create one; Refresh after return.  |
| Provisioning/no dashboard URL | Show the reported state; no Connect action until a URL exists. Refresh is available. |
| Stopped instance | Open Portal to manage it, then refresh. Do not silently start billable compute. |
| Sign-in cancelled | Return to the unfinished connection journey with a retry action. |
| Portal session expired | Sign in again; retain the intended instance when its identity is known. |
| Instance access removed | Explain access was denied; choose another instance/account. Do not use cached membership as authorization. |
| Profiles work, live chat fails | Preserve the successful check and name the failed stage; retry without discarding Cloud selection. |
| Instance already saved | Offer Open connection, rather than silently adding a duplicate. Match the Portal instance ID and organization. |
| Add another Cloud connection | Reuse valid Portal sign-in and show the instance chooser; still authenticate/check the selected instance. |

Initial scope is discovering and connecting existing instances. Creation, deletion, subscriptions, billing, and start/stop controls stay on Portal. Supporting multiple separately signed-in Nous accounts is not implied by this first proposal; account switching must not erase existing saved connections.

## Visual and interaction contract

Follow [Studio](../DESIGN_SYSTEM.md) and the [approved connection journey](2026-09-16-connection-journey.md): Roboto, 16 dp gutters, 6 dp action corners, 8 dp groups, 112 dp portrait at entry/completion, warm light canvas and navy dark surfaces, active user accent. Keep the original pointed feather cluster in native UI. Welcome remains 144 dp and unchanged.

Palette: canvas `#F7F7F4` / `#101B24`; panel `#FFFFFF` / `#192934`; ink `#1B2D36` / `#EBF1F2`; muted `#586970` / `#ADBDC4`; teal `#126D70` / `#65C7BC`; selection `#E2F1EE` / `#20454A`. No Portal-branded replacement theme, confetti, checkmark badges, or new hero animation.

Editable controls: route, instance, final local name/icon. Passive context: account/organization, instance source/name, opening profile. Temporary status: browser handoff, discovery, connection checks, saving. Keep those roles visually distinct.

Short transitions may carry instance identity between steps, but the current Flutter flow does not already implement a shared-element morph; do not promise one as preserved behavior. No artificial loading hold. Maintain readable status with reduced motion. Native keyboard, TalkBack, and enlarged-text validation belong to implementation acceptance.

## Implementation and acceptance

- The original address form, authentication/custom setup, checks and review are reused.
- Cloud lists organizations only when Portal requests a choice. Instances select with Studio tint; stopped, starting and failed instances have a Portal management path.
- Portal cookies remain in app browser storage. Each instance gets a separate HTTPS/path-bound PKCE grant; tokens are persisted through verified platform secure storage, and concurrent clients share token renewal.
- Instance HTTP uses Bearer authentication. WebSockets use the stock single-use ticket endpoint. OAuth mode fails closed when credentials are missing; it does not try another authentication mode.
- Connection backups retain Cloud identity but exclude browser sessions and rotating tokens. Restored Cloud connections must sign in again through Edit connection.
- Account switching clears the app browser session; it does not delete saved instance grants.
- Cancellation and stale async results cannot advance or save a dismissed journey. Existing instances offer Open connection.

Rendered Flutter screens were inspected at 390 dp normal text and 320 dp/200% text in light and dark themes. Captures live under `build/cloud-review/`. Unit/widget tests exercise discovery, PKCE, invalid callbacks, secure persistence, renewal, destination binding, cancel, empty accounts, duplicates and the full check/save journey. Android compilation validates the platform bridge. The complete Flutter suite passed: 2,121 tests, with 12 existing skips. Static analysis reported no issues. The APK is `build/app/outputs/flutter-apk/app-debug.apk`.

Device acceptance, September 18: the owner confirmed that the deployed Wing Dev APK successfully signs in to Nous Portal and correctly shows that their account has no Cloud instances. This validates their account’s browser sign-in and the empty discovery path. Remaining acceptance: multiple-organization discovery and connecting to a running Cloud instance, including refresh after expiry. Other identity providers’ WebView support is not established. No backend or deployed-server changes were made.
