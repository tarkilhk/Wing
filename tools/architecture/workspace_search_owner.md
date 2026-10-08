# Workspace gateway search ownership

`ARCH_WORKSPACE_SEARCH_OWNER` prevents a second interactive search owner from
returning to the canonical workspace library. The dormant `searchChats` searched
one current profile, while shipping `ChatBrowserData.search` searches discovered
profiles and owns typed browser results, errors, query generations, and projection.
Removing the exact retired declarations is separately guarded by the canonical
retirement inventory.

The finite AST property applies to
`lib/core/services/profile_workspace_controller.dart` and its actual declared
parts. A direct method invocation named `search` whose receiver is a literal
member access ending in `.gateway` belongs only to a member of the canonical
`ProfileWorkspaceController` named:

- `refreshActivity`: resolve the captured `session.active_list` session keys to
  exact profile-owned metadata and reject ambiguous results.
- `_reconcileNotificationActivity`: resolve captured notification activity session
  keys to exact profile-owned metadata and reject ambiguous results.
- `_pendingChatTitle`: recover metadata for a captured session identity.

Those shipping callers were verified in the original source; restricting searches
to the title seam alone would incorrectly block active browser status and
notification reconciliation. New function names do not bypass this boundary.
A same-named method in a different class or a separately named local helper does
not receive the exemption. Anonymous closures remain with their containing member,
as used by the shipping metadata workflows. Unrelated libraries and unrelated
receivers' `search` methods remain valid. Parentheses, null assertions and applicable
cascade receivers are inspected through the AST. URI and named parts must have
one real containing-library owner; missing, detached, and malformed input fail
with the existing safe `ARCH_INPUT` diagnostic.

This rule does not resolve the gateway's type, aliases, computed dispatch,
method tear-offs, delegated helpers, or search argument semantics. A property
called `gateway` in this canonical library is deliberately the finite syntactic
boundary; no claim of symbol identity is made. The allowlist does not prove
exact-ID filtering, cancellation, persistence, or publication lifetime. Existing
browser query and runtime/notification behavioral checks protect those properties.
No user interface strings or query syntax are frozen, and no baseline applies.

Run the independent CI command and its finite fixtures from the application root:

```
dart run tools/architecture/rules/workspace_search_owner.dart
dart run tools/architecture/tests/workspace_search_owner_test.dart
```

Root integration should add both plain commands to the existing PR `quality` and
release `build` jobs; add the rule and fixture names to the existing mandatory
quality-gate rule and its tests, and register their supported tooling roots.
The independent command always passes `--strict` to the shared CLI, so exemptions
cannot hide recurrence.

The proposed host proof wrapper uses the same CLI, checks original source exit 1
with exactly one finding, runs the 17 AST fixtures including actual CLI exits
0/1/2, and records three current-checkout wall timings plus shared parse/rule
microseconds:

```
python3 tools/architecture/prove_workspace_search_owner.py --dart EXISTING_DART --original-root FIXED_ORIGINAL --evidence PRIVATE_JSON
```

The author performed no SDK operation. Compile, red/green execution, production
scope checks, and measured cold/repeated host timings remain Root's integration
obligations. The wrapper supplies measurements, not a speculative time ceiling.
