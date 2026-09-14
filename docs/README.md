# Documentation

## Using Hermes Personal

| Guide | Covers |
| --- | --- |
| [Getting started](GETTING_STARTED.md) | Server prerequisites, installation, connection and troubleshooting |
| [Feature guide](FEATURES.md) | Current controls and workflows |
| [Known limitations](KNOWN_LIMITATIONS.md) | Recovery, notification and backend boundaries |
| [Privacy](../PRIVACY.md) | Device storage, server processing, dictation and deletion |
| [Support and security](../SECURITY.md) | Reporting problems without exposing private data |

## Product and design

- [Product scope](PRODUCT_PLAN.md) and [administration roadmap](ADMINISTRATION_ROADMAP.md) preserve selected feature IDs, priorities and exclusions.
- [Design system](DESIGN_SYSTEM.md) owns shared tokens, controls and interaction preservation.
- [Administration ownership](design/2026-09-14-administration-handoff.md) maps Profile, Server and Health.
- [Brand assets](design/2026-09-14-app-icon.md) covers the portrait, wing, in-app placements and exports.

## Technical guides

| Topic | Guide |
| --- | --- |
| Navigation, profile selection, filters and projects | [App shell](APP_SHELL.md) |
| Authentication, headers, diagnostics and updates | [Connections](CONNECTION_DIAGNOSTICS_AND_VERSIONS.md) |
| Profile/server settings, credentials and supported writes | [Administration](ADMINISTRATION.md) |
| Drafts, edit/regenerate/fork and attachment history | [Conversation actions](CONVERSATION_ACTIONS_AND_READING.md) |
| Hold/slide actions and steering feedback | [Composer](COMPOSER_ACTION_GESTURE.md) |
| Queues, Activity ownership, sensitive forms and side questions | [Queues and pending input](SUPERVISION_AND_QUEUES.md) |
| Goals, criteria, loops, heartbeats and processes | [Session controls](SESSION_CONTROLS.md) |
| Child roster, output, steering and interruption | [Subagent supervision](SUBAGENT_SUPERVISION.md) |
| Command catalog, dispatch and session scope | [Slash commands](SLASH_COMMAND_SUPPORT.md) |
| Tool/todo details, history search and file references | [Execution, Find and Outputs](EXECUTION_FIND_AND_OUTPUTS.md) |
| Internal notices and synthetic task context | [Transcript projection](TRANSCRIPT_DISPLAY_TYPES.md) |
| Parent metadata and answer-version limits | [Server relationships](SERVER_CHAT_RELATIONSHIPS.md) |
| Android intake, camera and draft recovery | [Sharing and capture](SHARING_AND_CAPTURE.md) |
| File formats, downloads, native resources and HTML sandbox | [Output viewers](OPENING_OUTPUT_FILES.md) |
| Vendored Mermaid/SVG renderer and update checks | [Diagram previews](DIAGRAM_PREVIEWS.md) |
| Local delivery, event coverage and tap routing | [Notifications](BACKGROUND_NOTIFICATIONS.md) |

The short [profile ownership ADR](adr/0001-request-scoped-hermes-profiles.md) and [background continuity ADR](adr/0002-background-session-continuity.md) preserve the original architecture decisions. Each marks the historical compatibility and delivery assumptions superseded by current scope.

## Development and release

- [Contributing](../CONTRIBUTING.md), [Windows build workflow](LOCAL_BUILD_SETUP.md) and [Testing](TESTING.md).
- [Release guide](ANDROID_RELEASE_PLAN.md), [release checklist](../CODE_QUALITY_CHECKLIST.md) and [Play data safety preparation](PLAY_DATA_SAFETY.md).
- [Bug tracker](BUG_TRACKER.md) for issue links; [upstream bugs](UPSTREAM_HERMES_BUGS.md) for backend reproductions and closure criteria.
- [Changelog](../CHANGELOG.md) for product release history and [Notice](../NOTICE.md) for attribution.

Superseded plans, research inventories, mockup prompts and deployment/QA journals are retained in [Git history](https://github.com/tarkilhk/hermes-android/commits/main/docs), rather than mixed into current instructions. Historical test results do not certify a later release.
