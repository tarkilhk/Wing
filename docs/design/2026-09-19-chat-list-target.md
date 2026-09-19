# Chats: approved Target implementation

The owner approved the interactive Target prototype and requested implementation
on 19 September 2026. The reference prototype remains in the workspace at
`design-previews/chats-prototype/index.html`.

## Selected interface

- Search above one compact, full-width Status / Profile / Project filter row.
  Filters are independent anchored multi-select menus. No selection means all.
  Choices use selected tint; five visible row heights maximum, with scrolling
  and fixed Clear / Done actions. Profiles sort alphabetically; projects sort
  by most recent visible-source activity, then name. The trailing cross clears
  these three filters only.
- Group by and Order by are direct controls beneath the filters, with icons,
  sentence-case menu titles, and no redundant back link or total chat count.
  Project is the initial grouping; Updated is the initial ordering.
- The header menu contains Show, Show automated chats, Collapse/Expand all,
  Mark all as read, Archived/Active chats, and New project. Every item has an
  icon. No duplicate filter, grouping, ordering or global Show all control.
- Show controls Updated, Tokens, Cost and Profile metadata. Group headings sum
  tokens over all matching rows before the three-chat preview cap. Pinned rows
  appear once, in their own group. Incomplete profile loads do not present
  partial token sums as complete totals.
- Continuous Studio background, no cards or separators. Heading weight,
  indentation and a larger gap above each heading establish proximity. Chat
  rows and project actions retain 48 dp targets and grow at enlarged text.
- Five shared dot states: Needs input (amber), Working (accent), Unread (green),
  Draft (hollow muted), Idle (small muted). REST `is_active` does not imply a
  running turn. Draft means no messages yet, not an unsent follow-up. Live
  failure/reconnection text remains visible, and the conversation activity
  indicator retains its own progress behavior.

## Ownership and API

Inspected unmodified upstream Hermes main at commit
`14a346345486418aa85ed6526549412ee2665ade` before implementation:

- `hermes_cli/web_routers/sessions.py`: profile-owned REST paging, maximum 100
  rows, archive scope, sources, read watermark, search and session mutations.
- `tui_gateway/methods_config.py` and `methods_projects.py`: `projects.tree`
  accepts a session scan limit; its `sessionIds` are authoritative membership.
- `tui_gateway/project_tree.py`: group token totals sum input + output tokens;
  previews and complete membership are distinct.
- Desktop `store/session-dot-state.ts`: status precedence and five buckets.

The connection-wide browser reads four profiles concurrently and pages each in
100-row requests, deduplicating pin backfills. Project scans use short-lived reader connections, independent of live conversation
sockets, and cover the loaded active set. It never infers membership from cwd, switches the server's active
profile, or changes a chat owner. Project-tree exclusions mean archived chats
and excluded automated sources have no tree membership; they remain accessible
under Home. Local saved drafts retain recovery actions.

Show automated chats preserves Wing's exact `cron`, `tool`, `subagent`, `kanban`
classification and starts off. The browser loads the index independently of
this presentation filter and applies it before search, grouping, counts, pins
and project recency. Filters intersect across categories and union within each.

Message search retains archived matches and the stock 100-result-per-profile
limit; title matching operates over the loaded index. Results are generation
guarded, with explicit errors and retry. New chat / project asks for a profile
unless one is selected in the profile filter or only one exists. Chat/project
mutations continue through the existing owner-checked controller and dialogs.

No backend changes or deployment are part of this work.

## Verification

`chat_list_target_test.dart` exercises filter intersections, scrolling, view
persistence, menu titles, complete group totals, owner-qualified identities and
status classification. Existing browser, search, automation, project-action,
draft-recovery and Studio layout tests are updated for the selected interaction.
Actual Flutter renders use Roboto at 390 dp / 100% and 320 dp / 200% in light
and dark themes, including menus. Export with `CHAT_LIST_REVIEW=true`;
artifacts are in `build/chat-list-review/`.

Validation on the implementation: `flutter analyze --no-pub --fatal-infos`
passed; the complete local suite passed 2,455 tests with 12 opt-in skips.
Additional focused data tests cover pin deduplication, incomplete-page totals,
archive/search races and isolation from live conversation sockets. The original
conversation activity and indicator source files have no implementation diff.
