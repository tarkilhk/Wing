# Studio implementation and component audit

Implemented on `codex/studio-revamp`, initially based on `1ad2746` and rebased onto `4c8a9f3`. The design charter was published separately to main in `1ad2746`.

## Result

The [Studio charter](../DESIGN_SYSTEM.md) now drives the app theme, including compact 6 dp controls, 8 dp panels, explicit Roboto typography, paired light/dark surfaces and the existing five accent preferences. Search sits below profile scope at the top of Chats. The bottom shelf contains New chat or the existing Project action. The context fuse has been removed and replaced by an 18 dp ring with a separate 48 dp target and accessible usage details. Warning thresholds remain 65% and 85%; unknown occupancy remains unknown.

The existing administration panels are grouped under Profile, Server and Health. They remain mounted across tab changes, retaining results, disclosure state and pending work. Identity/default-model editing and skills/tools remain profile-owned. Connection management and backend versions are under Server; existing usage and diagnostics are under Health. Shared provider account management and other roadmap-only editors have not been invented for the redesign. The [ownership handoff](2026-09-14-administration-handoff.md) remains the source for their future placement.

## Behavior boundary

Application controllers, gateway clients, models, authentication, persistence, notification logic, clipboard handling and transcript scroll anchoring are unchanged. Existing callbacks and eligibility rules remain in place for send/stop, Enter, model/reasoning Apply, Queue/Steer/Fork, approvals, questions, queued-message edits, attachment/camera/voice actions and saved-message actions.

The only service edit transports an optional appearance map over the existing private media-preview channel. It carries brightness and four UI colors from the captured Flutter preview to its Android activity. Downloaded bytes, MIME resolution, errors, lifecycle, playback and file cleanup are unchanged. The native Back button keeps the same finish callback and receives a compact Studio face. The diagram wrapper and its error panel use Studio surfaces; document content, renderer configuration and sandbox policy are unchanged.

Approved layout changes are Search/New chat placement, the ring and its detail view, compact model/reasoning labels and the administration tabs. No additional functional capabilities are included.

## Audit method and findings

Enumerated every Dart UI file, scanned all of `lib/` for widget construction and theme overrides, then checked the Android activities, embedded viewer assets and launch resources. Reviewed shared themes, local button styles, explicit borders/radii, palette literals, selection states, dialogs/sheets and widget paths reached through menus or errors. The table below accounts for every one of the 54 Flutter UI entry/helper files. The three theme files are reviewed separately below.

The final source scan finds no `ContextFuse`, app-owned `StadiumBorder` or `CircleBorder`, or fixed red/gray UI colors in Flutter screens/widgets. Legacy 14/16/18/20/24 dp control corners are removed except for the newly approved held-action selector preserved below. Standard controls use the shared Studio theme. Custom decorations use `HermesRadius` and semantic theme colors, subject to the explicit preservation exceptions.

Intentional exceptions:

- The owner's later held-slide composer keeps its 14 dp action corners, 20 dp selector corners, elevation, animation curves and timings, gestures, cancellation and accessibility behavior exactly as added on main. Its colors inherit Studio. The device default-action setting remains available in Administration / Profile, adjacent to the default-model card. Markdown retains the new 3 dp rounded scrollbar and reserved 12 dp table gutter.
- Activity tabs retain their existing 7/4 dp corners, compact tool badges retain 6 dp corners, and disclosures retain their 28 dp visual density, anchoring and expansion behavior. These were expressly preserved by the owner.
- The image-attachment error badge retains its 4 dp corner. Context/status rings, avatar initials, accent swatches and project color selectors remain circular indicators rather than rounded action buttons.
- The default-model sheet's explanatory metadata and compact Markdown details retain 14 sp text so the existing small-screen keyboard layout remains usable. Normal body text is 16 sp.
- Native media playback controls, text selection/paste toolbars, external file pickers/viewers and the Android keyboard retain platform behavior. The app-owned native media Back button is restyled.
- Media pixels, white PDF pages, authored HTML/SVG, generated diagram content and brand launcher artwork retain their own colors. A neutral modal shadow remains in the chat-action sheet. These are not legacy app-control styling.
- The iOS starter project is not shipped by this Android fork; its placeholder launch assets are outside this Android UI revamp.

## Shared themes and native UI

| Source | Outcome |
| --- | --- |
| [hermes_theme.dart](../../lib/core/theme/hermes_theme.dart) | One palette, typography ramp and complete component theme. Maintains semantic statuses independently of accent. |
| [profile_workspace_theme.dart](../../lib/core/theme/profile_workspace_theme.dart) | Delegates to Studio; preserves preference keys, five accent choices and stable profile colors. |
| [profile_markdown_style.dart](../../lib/core/theme/profile_markdown_style.dart) | Studio code surfaces and corners; existing table scrolling, quote merging and compact detail density retained. |
| [MediaPreviewActivity.kt](../../android/app/src/main/kotlin/com/hermesagent/hermes_android/MediaPreviewActivity.kt) | Themed header, text and compact Back button; platform media controls retained. |
| [MediaPreviewChannel.kt](../../android/app/src/main/kotlin/com/hermesagent/hermes_android/MediaPreviewChannel.kt) | Carries optional UI colors; media handling unchanged. |
| [MermaidDiagramView.kt](../../android/app/src/main/kotlin/com/hermesagent/hermes_android/MermaidDiagramView.kt) and [viewer CSS](../../android/app/src/main/assets/diagrams/index.html) | Studio canvas/error panel; authored content and rendering policy unchanged. |
| Android drawable launch backgrounds and values/values-night colors/styles | System light/dark launch and window canvas match Studio. App theme overrides apply once Flutter renders. |

## Complete Flutter UI inventory

| File | Controls or presentation | Treatment |
| --- | --- | --- |
| [main.dart](../../lib/main.dart) | AlertDialog, Card, FilledButton, FloatingActionButton, IconButton, ListTile, OutlinedButton, TextButton, TextField | Explicit decorations migrated; shared component themes |
| [app_settings_content.dart](../../lib/core/screens/app_settings_content.dart) | Card, ChoiceChip, ListTile, TextButton | Shared component themes; existing implementation retained |
| [backend_updates_screen.dart](../../lib/core/screens/backend_updates_screen.dart) | AlertDialog, FilledButton, OutlinedButton, TextButton | Shared component themes; existing implementation retained |
| [chat_outputs_screen.dart](../../lib/core/screens/chat_outputs_screen.dart) | FilledButton, IconButton, ListTile, TextButton | Explicit decorations migrated; shared component themes |
| [pdf_preview_screen.dart](../../lib/core/screens/pdf_preview_screen.dart) | IconButton, OutlinedButton | Shared component themes; existing implementation retained |
| [profile_capabilities_screen.dart](../../lib/core/screens/profile_capabilities_screen.dart) | AlertDialog, ExpansionTile, FilledButton, IconButton, SegmentedButton, Switch, TextButton, TextField | Shared component themes; existing implementation retained |
| [profile_project_actions.dart](../../lib/core/screens/profile_project_actions.dart) | AlertDialog, FilledButton, IconButton, ListTile, TextButton, TextField | Explicit decorations migrated; shared component themes |
| [profile_row_actions.dart](../../lib/core/screens/profile_row_actions.dart) | AlertDialog, FilledButton, ListTile, TextButton, TextFormField | Shared component themes; existing implementation retained |
| [profile_transcript.dart](../../lib/core/screens/profile_transcript.dart) | Card, FilledButton, TextButton | Explicit decorations migrated; shared component themes |
| [profile_workspace_browser.dart](../../lib/core/screens/profile_workspace_browser.dart) | FilledButton, IconButton, ListTile, TextButton, TextField | Explicit decorations migrated; shared component themes |
| [profile_workspace_screen.dart](../../lib/core/screens/profile_workspace_screen.dart) | AlertDialog, Card, FilledButton, IconButton, ListTile, OutlinedButton, TextButton, TextField, TextFormField | Explicit decorations migrated; shared component themes |
| [shared_draft_review.dart](../../lib/core/screens/shared_draft_review.dart) | Card, FilledButton, ListTile, TextButton | Explicit decorations migrated; shared component themes |
| [workspace_overview_content.dart](../../lib/core/screens/workspace_overview_content.dart) | Card, FilterChip, IconButton, ListTile, TabBar | Explicit decorations migrated; shared component themes |
| [activity_shimmer.dart](../../lib/core/widgets/activity_shimmer.dart) | Custom presentation inherits Studio text and colors | Existing geometry, timing and expansion behavior retained; Studio colors/type inherited |
| [anchored_expansion_tile.dart](../../lib/core/widgets/anchored_expansion_tile.dart) | ExpansionTile | Existing geometry, timing and expansion behavior retained; Studio colors/type inherited |
| [answer_actions.dart](../../lib/core/widgets/answer_actions.dart) | IconButton | Shared component themes; existing implementation retained |
| [app_drawer.dart](../../lib/core/widgets/app_drawer.dart) | Drawer, ListTile | Explicit decorations migrated; shared component themes |
| [backend_version_card.dart](../../lib/core/widgets/backend_version_card.dart) | AlertDialog, Card, ExpansionTile, FilledButton, TextButton | Shared component themes; existing implementation retained |
| [chat_find_sheet.dart](../../lib/core/widgets/chat_find_sheet.dart) | ExpansionTile, TextButton, TextField | Explicit decorations migrated; shared component themes |
| [chat_image_preview.dart](../../lib/core/widgets/chat_image_preview.dart) | IconButton, OutlinedButton | Shared component themes; existing implementation retained |
| [chat_intelligence_picker.dart](../../lib/core/widgets/chat_intelligence_picker.dart) | ExpansionTile, FilledButton, IconButton, ListTile, TextButton, TextField | Explicit decorations migrated; shared component themes |
| [composer_attachment_tile.dart](../../lib/core/widgets/composer_attachment_tile.dart) | IconButton, InputChip | Explicit decorations migrated; shared component themes |
| [composer_action_button.dart](../../lib/core/widgets/composer_action_button.dart) | Animated IconButton, held selector, accessibility actions | Owner's latest main implementation preserved verbatim; themed colors inherited |
| [composer_action_settings.dart](../../lib/core/widgets/composer_action_settings.dart) | Card, ChoiceChip | Owner's latest main implementation preserved verbatim; reachable in Administration / Profile |
| [config_backup_card.dart](../../lib/core/widgets/config_backup_card.dart) | Card, FilledButton, IconButton, OutlinedButton, TextButton, TextField | Explicit decorations migrated; shared component themes |
| [context_ring.dart](../../lib/core/widgets/context_ring.dart) | AlertDialog, IconButton, TextButton | New compact ring replaces the fuse; existing usage calculation and thresholds retained |
| [gateway_clarify_dialog.dart](../../lib/core/widgets/gateway_clarify_dialog.dart) | AlertDialog, FilledButton, ListTile, TextButton, TextField | Explicit decorations migrated; shared component themes |
| [gateway_headers_editor.dart](../../lib/core/widgets/gateway_headers_editor.dart) | IconButton, OutlinedButton, TextFormField | Shared component themes; existing implementation retained |
| [gateway_sensitive_prompt_panel.dart](../../lib/core/widgets/gateway_sensitive_prompt_panel.dart) | FilledButton, TextButton, TextField | Explicit decorations migrated; shared component themes |
| [image_paste_menu.dart](../../lib/core/widgets/image_paste_menu.dart) | Custom presentation inherits Studio text and colors | Platform text selection toolbar retained; Paste handlers unchanged |
| [installed_app_version_card.dart](../../lib/core/widgets/installed_app_version_card.dart) | Card, ListTile, TextButton | Shared component themes; existing implementation retained |
| [markdown_code_block.dart](../../lib/core/widgets/markdown_code_block.dart) | IconButton | Explicit decorations migrated; shared component themes |
| [markdown_message_content.dart](../../lib/core/widgets/markdown_message_content.dart) | OutlinedButton | Shared component themes; existing implementation retained |
| [profile_activity_status.dart](../../lib/core/widgets/profile_activity_status.dart) | Custom presentation inherits Studio text and colors | Existing geometry, timing and expansion behavior retained; Studio colors/type inherited |
| [profile_activity_tabs.dart](../../lib/core/widgets/profile_activity_tabs.dart) | Custom presentation inherits Studio text and colors | Existing geometry, timing and expansion behavior retained; Studio colors/type inherited |
| [profile_background_work_panel.dart](../../lib/core/widgets/profile_background_work_panel.dart) | AlertDialog, Card, FilledButton, TextButton | Shared component themes; existing implementation retained |
| [profile_chat_indicator.dart](../../lib/core/widgets/profile_chat_indicator.dart) | Custom presentation inherits Studio text and colors | Shared component themes; existing implementation retained |
| [profile_default_model_sheet.dart](../../lib/core/widgets/profile_default_model_sheet.dart) | AlertDialog, ExpansionTile, FilledButton, IconButton, ListTile, TextButton, TextField | Explicit decorations migrated; shared component themes |
| [profile_diagnostics_panel.dart](../../lib/core/widgets/profile_diagnostics_panel.dart) | Card, FilledButton, ListTile, OutlinedButton | Explicit decorations migrated; shared component themes |
| [profile_editor_sheet.dart](../../lib/core/widgets/profile_editor_sheet.dart) | AlertDialog, FilledButton, IconButton, TextButton, TextField | Explicit decorations migrated; shared component themes |
| [profile_execution_activity.dart](../../lib/core/widgets/profile_execution_activity.dart) | ListTile | Existing geometry, timing and expansion behavior retained; Studio colors/type inherited |
| [profile_goal_panel.dart](../../lib/core/widgets/profile_goal_panel.dart) | AlertDialog, FilledButton, IconButton, TextButton, TextField | Explicit decorations migrated; shared component themes |
| [profile_message.dart](../../lib/core/widgets/profile_message.dart) | IconButton | Explicit decorations migrated; shared component themes |
| [profile_queued_messages.dart](../../lib/core/widgets/profile_queued_messages.dart) | IconButton | Explicit decorations migrated; shared component themes |
| [profile_review_notice_card.dart](../../lib/core/widgets/profile_review_notice_card.dart) | TextButton | Shared component themes; existing implementation retained |
| [profile_subagent_panel.dart](../../lib/core/widgets/profile_subagent_panel.dart) | FilledButton, IconButton, ListTile, OutlinedButton, TextButton, TextField | Shared component themes; existing implementation retained |
| [profile_tool_activity.dart](../../lib/core/widgets/profile_tool_activity.dart) | Custom presentation inherits Studio text and colors | Existing geometry, timing and expansion behavior retained; Studio colors/type inherited |
| [profile_transcript_disclosure.dart](../../lib/core/widgets/profile_transcript_disclosure.dart) | Custom presentation inherits Studio text and colors | Existing geometry, timing and expansion behavior retained; Studio colors/type inherited |
| [profile_usage_panel.dart](../../lib/core/widgets/profile_usage_panel.dart) | Card, FilledButton, IconButton, ListTile, TextButton | Shared component themes; existing implementation retained |
| [project_folder_picker.dart](../../lib/core/widgets/project_folder_picker.dart) | AlertDialog, ListTile, OutlinedButton, TextButton, TextField | Shared component themes; existing implementation retained |
| [side_question_delivery_card.dart](../../lib/core/widgets/side_question_delivery_card.dart) | Card | Shared component themes; existing implementation retained |
| [slash_command_suggestions.dart](../../lib/core/widgets/slash_command_suggestions.dart) | ListTile, TextButton | Shared component themes; existing implementation retained |
| [text_size_settings_card.dart](../../lib/core/widgets/text_size_settings_card.dart) | Card, ListTile | Shared component themes; existing implementation retained |
| [web_output_preview.dart](../../lib/core/widgets/web_output_preview.dart) | IconButton | Shared component themes; existing implementation retained |

## Final integration with graphical additions

Rebased onto main at `4c8a9f3`. The composer action model, animated held-slide button, action settings and Markdown rendering component are byte-for-byte identical to main. The composer keeps main's action eligibility and dispatch methods, with the Studio context ring alongside it. Administration keeps the new device preference beside the default-model card. The Markdown theme retains main's scrollbar treatment and table gutter.

Validation on the combined tree: static analysis passed; all 1,564 tests passed with ten environment-gated skips; the 42-case visual export passed, including held-action transition and settled frames at normal and 2x text sizes. The signed ARM64 APK built and passed signature, package and non-debuggable checks: `com.tarkilhk.hermes.android`, version `2.36.2`, code `22192`. It was not installed or published. Review exports use real shadows rather than Flutter's diagnostic shadow outlines.

## Earlier verification

The results and screenshots below record the original implementation. The rebase preserves main's saved-title fix and chat-header project picker. The large-text layout tests now scroll the drawer to reveal navigation items before tapping, including when CI's test font places them below the viewport. Application behavior is unchanged by this test adjustment. Post-rebase validation passed: static analysis reported no issues, and the full test suite passed 1,543 tests with ten environment-gated skips. The original APK predates the rebase.

- `flutter analyze --no-pub`: no issues.
- `flutter test --no-pub --reporter expanded`: 1,525 passed, eight environment-gated tests skipped. This includes existing behavior tests and the new 42-case Studio matrix.
- `flutter test --no-pub --dart-define=STUDIO_REVIEW=true test/studio_layout_test.dart`: rendered UI review. Both themes, all five accents, 320/360 dp phones, 840 dp tablets, 2x phone text and a 280 dp keyboard inset are covered. Context/model/send targets remain separate and at least 48 dp. Body, secondary and primary-action contrast checks pass for every accent/theme pair.
- `node scripts/test-diagram-preview.mjs`: flowchart/sequence/pie, SVG, HTML controls, error handling, sandboxing and content restrictions passed in headless Chrome.
- Android ARM64 release APK: built and verified by `scripts/build-personal-release.ps1`, including personal signature, package identity and non-debuggable checks. Package `com.tarkilhk.hermes.android`, version `2.34.3`, code `22142`. The APK remains a local build artifact; it was not installed or published.

The final 42-case render run also covers administration, the drawer and settings at 2x text on a 320 dp phone. Administration tab padding was reduced to keep all three labels readable without shrinking text or touch targets. The layout suite passed again after that spacing change.

Live authentication, server mutations, device camera/microphone and playback against user media were not exercised for this visual change. Their existing deterministic contracts pass; no claim of new end-to-end backend acceptance is made.

## Rendered review

These images show actual Flutter widgets with authored fixture data, Android Roboto/monospace fonts and Flutter Material icons. They are not generated mockups and contain no live server data. Keyboard examples reserve the keyboard inset; they do not render an Android keyboard.

| Surface | Light | Dark |
| --- | --- | --- |
| Chats | [Light](studio-review/light-chats-1.0.png) | [Dark](studio-review/dark-chats-1.0.png) |
| Conversation and ring | [Light](studio-review/light-conversation-1.0.png) | [Dark](studio-review/dark-conversation-1.0.png) |
| 2x text and keyboard | [Light](studio-review/light-keyboard-2.0.png) | [Dark](studio-review/dark-keyboard-2.0.png) |
| Controls and states | [Light](studio-review/light-controls.png) | [Dark](studio-review/dark-controls.png) |
| Drawer | [Light](studio-review/light-drawer.png) | [Dark](studio-review/dark-drawer.png) |
| App settings | [Light](studio-review/light-settings.png) | [Dark](studio-review/dark-settings.png) |
| Intelligence | [Light](studio-review/light-intelligence.png) | [Dark](studio-review/dark-intelligence.png) |
| Administration, Profile | [Light](studio-review/light-administration-profile.png) | [Dark](studio-review/dark-administration-profile.png) |
| Administration, Server | [Light](studio-review/light-administration-server.png) | [Dark](studio-review/dark-administration-server.png) |
| Administration, Health | [Light](studio-review/light-administration-health.png) | [Dark](studio-review/dark-administration-health.png) |
| Held action, keyboard open | [Light](studio-review/light-held-action-1.0.png) | [Dark](studio-review/dark-held-action-1.0.png) |
| Held animation, 2x text | [Light](studio-review/light-held-action-transition-2.0.png) | [Dark](studio-review/dark-held-action-transition-2.0.png) |
| Administration, 2x text | [Light](studio-review/light-administration-health-large-text.png) | [Dark](studio-review/dark-administration-profile-large-text.png) |
| App settings, 2x text | [Light](studio-review/light-settings-large-text.png) | [Dark](studio-review/dark-settings-large-text.png) |

For exports, place the emulator's `/system/fonts/Roboto-Regular.ttf` and `/system/fonts/DroidSansMono.ttf` in `build/studio-roboto.ttf` and `build/studio-mono.ttf`, and Flutter's `MaterialIcons-Regular.otf` in `build/studio-icons.otf`. Run the render command above. Font files remain local build inputs and are not committed. Normal CI tests do not need the font copies or export flag.
