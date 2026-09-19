# Navigation, profiles and projects

## Drawer and chat list

The drawer opens Chats, Activity, Connections, App settings and Hermes administration. Projects are a scope within Chats. There is no permanent bottom navigation or intermediate More page.

Chats browses all profiles on the selected connection. Search stays above one
compact Status / Profile / Project filter row. Each filter opens its own anchored
multi-select menu, with scrolling after five visible rows. The cross clears only
these filters. Profiles sort alphabetically; projects sort by recent activity.

Group by (Project by default) and Order by (Updated by default) sit below the
filters. Pinned chats appear once, followed by compact groups with three-chat
previews and per-group Show all. Headings, indentation and proximity establish
grouping without cards or separators. Show → Tokens adds totals across every
matching row, including rows outside the preview and in collapsed groups.

The header menu contains Show, Show automated chats, Collapse/Expand all, Mark
all as read, Archived/Active chats and New project, each with an icon. The floating
pen creates a chat. Creation asks for an owning profile unless exactly one profile
is filtered or available. Project row menus retain New chat, Rename, Appearance
and Delete. Selection uses Studio tint and row actions retain 48 dp targets.

Back unwinds the current preview or editor, then returns from a conversation to Chats. At the workspace root it opens the drawer before exiting. Navigation preserves the open work and draft.

## Profile ownership

Profile selection belongs to this client. It must not call `POST /api/profiles/active` to change the server's sticky selection. Discover canonical profiles before opening their workspace. Capture the connection/profile/chat when beginning an operation; late responses cannot retarget writes or replace a newer selection.

Modern profile-aware dashboard and Desktop Gateway contracts are required. Missing discovery/authentication is an error to explain and repair, not a reason to enter an implicit legacy profile. Selecting another profile must leave accepted work running under its original owner. See the [profile ADR](adr/0001-request-scoped-hermes-profiles.md) and [background lifetime ADR](adr/0002-background-session-continuity.md) for the original decisions.

## Filters and search

Unread status comes from the server watermark. Mark a chat read only after an explicit open and successful history load. Reconnect or foreground refresh alone must not mark it read. Retain failure state and allow retry.

The browser reads profile-owned sessions in pages of 100 with four concurrent
profile readers. Unread filters apply to the resulting index, including older
pages. Incomplete loads retain readable rows and offer Retry; incomplete token
totals are not displayed as final. Message search runs across profiles and retains
archived matches, with the stock limit of 100 results per profile; title matching
also covers the loaded index. Search, filter and archive scope intersect.

Show automated chats starts off and hides exactly `cron`, `tool`, `subagent` and
`kanban` before grouping, counts and project recency. Unknown/custom sources stay
visible; parentage alone does not imply automation. This connection preference
does not affect Activity. Project membership comes from stock `projects.tree`
`sessionIds`; the scan covers the loaded active set. Archived and excluded source
rows absent from that tree remain under Home. New filters and display choices
persist per connection on this device.

## Projects and destructive actions

Create a project using an absolute folder on the host. Repository discovery is an explicit `projects.discover_repos` scan with manual entry available. Rename, appearance and membership are server-owned metadata. Deleting a project removes its organization, not its chats or host files.

Move chat uses `workspace.move` with the durable session key, destination working folder and profile. It is not a file move or cross-profile transfer. The app freshly resumes and verifies a uniquely owned idle runtime before the mutation, then refreshes the lists and preserves the open draft. The chosen working folder is the primary project path, falling back to its first repository.

In a conversation, tap **Unassigned** or the project name beside the server to
open the project selector. The Studio sheet shows the current project and lets
you search destinations by name or working folder. Choosing a destination moves
the chat; Cancel makes no change. A failed move stays open for retry, and controls
are disabled while a move is pending. The server icon, connection indicator and
server name remain a separate target for connection details, including server
access, live-chat availability and connection retry.

Deleting a chat first verifies and closes its known idle runtime, then deletes the saved server chat. Unknown, busy or ambiguous ownership blocks the action. Only after server deletion and durable draft removal may its owned staged files be cleaned up.

These preflight checks cannot make separate server operations atomic. A runtime can change between the check and mutation. The app must surface a failed or uncertain result instead of claiming a guaranteed transaction.
