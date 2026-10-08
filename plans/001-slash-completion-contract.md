# Slash completion ownership

The existing workspace completion command captures exact chat resource/runtime
before asynchronous catalog or argument work, and rejects closed/replaced
authorities before publishing. Immutable SlashCompletion owns catalog search,
stock result validation, Unicode-codepoint to UTF16 range conversion and issued
item insertion for the exact query. The view uses two required typed callbacks
for completion and draft saving; all actual callers use the captured chat.

The suggestions widget keeps cursor extraction, debounce, request generation,
popup geometry and presentation. Results from earlier requests cannot supply
a selectable item for the current query. Selection preserves suffix and cursor;
draft persistence failures retain the chosen text and remain visible.

Existing controls and one actual Unicode/immutable-input/query-mismatch control
verify behavior. The independently runnable dependency guard is mandatory in PR
and release checks;5 exact retired identities protect removed view authority.
Native/rendered and final whole-program acceptance remain open.
