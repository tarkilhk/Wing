# Navigation, profiles and projects

## Drawer and chat list

The drawer opens Chats, Activity, Connections, App settings and Hermes administration. Projects are a scope within Chats. There is no permanent bottom navigation or intermediate More page.

Chat browsing keeps the connection and selected profile visible, with five recent projects, pinned chats and recents. The header menu opens compact filters. Archived chats do not offer another Archived destination. All projects omits chat filters and the duplicate New project action.

The floating plus creates a chat or project for the current view. A project row's menu offers New chat, Rename, Appearance and Delete. Use the shared menu rules in [Design system](DESIGN_SYSTEM.md), including clear labels and 48 dp touch targets.

Back unwinds the current preview or editor, then returns from a conversation to Chats. At the workspace root it opens the drawer before exiting. Navigation preserves the open work and draft.

## Profile ownership

Profile selection belongs to this client. It must not call `POST /api/profiles/active` to change the server's sticky selection. Discover canonical profiles before opening their workspace. Capture the connection/profile/chat when beginning an operation; late responses cannot retarget writes or replace a newer selection.

Modern profile-aware dashboard and Desktop Gateway contracts are required. Missing discovery/authentication is an error to explain and repair, not a reason to enter an implicit legacy profile. Selecting another profile must leave accepted work running under its original owner. See the [profile ADR](adr/0001-request-scoped-hermes-profiles.md) and [background lifetime ADR](adr/0002-background-session-continuity.md) for the original decisions.

## Filters and search

Unread status comes from the server watermark. Mark a chat read only after an explicit open and successful history load. Reconnect or foreground refresh alone must not mark it read. Retain failure state and allow retry.

Unread filtering applies to loaded results and retains Load more; it is not a complete server-side unread query. Server-backed conversation search is scoped to the selected profile and bounded to 100 results without a cursor. Loaded title matching does not search every saved body.

Include automated chats is off by default. It hides exact sources `cron`, `tool`, `subagent` and `kanban` before REST pagination. Unknown/custom sources remain visible; a parent relationship alone does not make a chat automated. The preference belongs to the connection and applies across its profiles. Activity is unaffected. Project RPC membership has its own server exclusions and a 5,000-entry cap; Android reveals those results in batches of 50.

## Projects and destructive actions

Create a project using an absolute folder on the host. Repository discovery is an explicit `projects.discover_repos` scan with manual entry available. Rename, appearance and membership are server-owned metadata. Deleting a project removes its organization, not its chats or host files.

Move chat uses `workspace.move` with the durable session key, destination working folder and profile. It is not a file move or cross-profile transfer. The app freshly resumes and verifies a uniquely owned idle runtime before the mutation, then refreshes the lists and preserves the open draft. The chosen working folder is the primary project path, falling back to its first repository.

Deleting a chat first verifies and closes its known idle runtime, then deletes the saved server chat. Unknown, busy or ambiguous ownership blocks the action. Only after server deletion and durable draft removal may its owned staged files be cleaned up.

These preflight checks cannot make separate server operations atomic. A runtime can change between the check and mutation. The app must surface a failed or uncertain result instead of claiming a guaranteed transaction.
