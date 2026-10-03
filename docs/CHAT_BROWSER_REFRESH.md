# Confirmed actions and background browser refresh

Chats applies server-confirmed changes before refreshing the connection-wide
index. An action waits for its write and required local cleanup; it does not
wait for list or project-tree reads. The fixed loading bar and status label
describe background reads without disabling browsing. Read failures retain the
last snapshot and confirmed changes, with a read-only Retry above the list.

## Stock Hermes contract

Inspected upstream `NousResearch/hermes-agent` main commit
[`bd0affe5e5f723579df8902852f5d0c47795f355`](https://github.com/NousResearch/hermes-agent/commit/bd0affe5e5f723579df8902852f5d0c47795f355)
on 3 October 2026. The client requires no backend changes.

- Session PATCH acknowledges title and changed flags; DELETE completes the
  deletion. List reads supply token counts with session rows, rather than a
  separate request when Show details / Tokens is enabled.
  [Session routes](https://github.com/NousResearch/hermes-agent/blob/bd0affe5e5f723579df8902852f5d0c47795f355/hermes_cli/web_routers/sessions.py).
- `projects.create` and `projects.update` return the confirmed project;
  `projects.delete` returns the remaining projects and active project ID.
  [Project methods](https://github.com/NousResearch/hermes-agent/blob/bd0affe5e5f723579df8902852f5d0c47795f355/tui_gateway/methods_projects.py).
- Mutation responses use the saved project's `name` and `primary_path`.
  The browser tree uses `label`, `path` and session membership. Normalize the
  confirmed saved record for browser display without another tree read.
  [Saved project records](https://github.com/NousResearch/hermes-agent/blob/bd0affe5e5f723579df8902852f5d0c47795f355/hermes_cli/projects_db.py).

## Shared client lifecycle

`ProfileWorkspaceController.browserMutations` publishes typed, immutable
session and project changes after acknowledgement. Chat creation, rename,
pinning, read status, archive, deletion, moving and project changes use the same
seam. Failed submissions, menu dismissal and copying IDs publish no mutation.

`ChatBrowserData` owns both the retained index and pending confirmed changes.
It publishes each change immediately, including changes to rows outside the
controller's first session page. It coalesces concurrent refresh requests and
performs another read when an action finishes during an older read. Only
changes that predate a successful snapshot are retired; later changes continue
to win over that response. Failure keeps the changes until a successful retry.
Refreshes never replay writes or change profile ownership.

Complete retained snapshots keep their token totals visible while replacement
pages load. Active message searches remain available and are rerun after index
refresh. Background reads do not reset the selected grouping or ordering.
Manual Refresh retains its explicit ordering behavior.

## Regression checks

Run the browser action, mutation, index and list suites:

```sh
flutter test --no-pub test/chat_browser_actions_test.dart test/chat_browser_mutations_test.dart test/chat_browser_data_test.dart test/chat_list_target_test.dart
```

The action suite holds reads open after a confirmed write and checks that chat
navigation and New chat remain available. It also checks fixed progress,
retained scroll position, refresh failure and read-only retry in both themes
at normal and doubled text size. Set `BROWSER_ACTIONS_REVIEW=true` to export
production-widget captures under ignored `build/browser-actions-review/`;
provide `build/studio-roboto.ttf` and `build/studio-icons.otf` as in the existing
Chats render suite. Inspect those captures; tests alone do not establish layout
quality or device behavior.
