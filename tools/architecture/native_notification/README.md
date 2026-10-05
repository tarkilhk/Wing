# Retired notification bulk action

The accepted Dart service subtraction removed `TurnNotificationSink.cancelAll`
and the plugin/native implementations. The only remaining registration was the
literal `cancelAll` case in `ChatNotifications.attach`; repository source search
found no retained Dart, integration, or channel root invoking it. Stock Flutter
and Android entrypoints do not independently invoke this app-owned channel action.

This closure removes that case and the exclusive zero-argument branch of
`NotificationHandleStore.invalidate`. The helper now requires an integer ID;
its retained filter has exactly the same effect for every concrete ID. The sole
supported production caller is the `cancel` case. `NotificationManagerCompat`
remains imported because `show` still posts notifications. No channel or supported
per-ID action is removed.

The original native security test's three final statements only exercised the
retired bulk invalidation option. Those statements are removed. The rest of
`replacementAndCancellationRevokeOnlyTheirNotification` remains unchanged,
including both action/main handles revoked for ID 42 and the independent ID 43
handle still consumable. Every original JVM security test method remains;
forgery, purpose, expiry, persistence failure, replacement, replay and dismissal
assertions are untouched.

`NATIVE_NOTIFICATION_RETIRED_ACTION` is a finite Kotlin PSI check. In the canonical
package/object it examines `setMethodCallHandler` lambda registrations and
rejects a literal `cancelAll` condition on the first parameter's `.method`, through
`when` branches or direct equality dispatch. Parentheses, renamed handler
parameters, and escaped string literals are supported. Comments, display strings,
unrelated objects, other receivers' methods and unrelated `when` subjects are
valid. Missing canonical source/owner and malformed source fail safely with exit 2.

This is syntactic dispatch retirement, not symbol/type identity or runtime
lifetime proof. Aliases, computed strings, delegated dispatch, nested variable
shadowing and indirect helper registrations are outside its finite contract.
The scoped check does not prohibit unrelated Android notification APIs or
establish per-ID cancellation security; retained JVM/runtime regressions own those.
The existing cached Kotlin compiler helper is reused; no tooling is installed.

Root should run both independent commands and require them in existing PR/release
quality gates and the required-gate guard, then register their tool roots:

```
python3 tools/architecture/native_notification/retired_action.py
python3 tools/architecture/native_notification/prove_boundary.py
```

The fixture command exercises ten finite cases and actual CLI exits 1/0/2. Before
acceptance, run the same action command with `--source FIXED_ORIGINAL_NATIVE_FILE`
for one violation and with the joined current source for zero, and run the existing
`NotificationInteractionSecurityTest` JVM suite. Record cold/repeated actual
host timings as evidence; no speculative time threshold applies. The author
performed Python syntax/JSON/hash inspection only, with no SDK/device/network job.
