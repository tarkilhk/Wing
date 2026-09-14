# Historical backend experiments

Do not apply these patches as Android setup. This fork targets existing Hermes
APIs; the [product scope](../docs/PRODUCT_PLAN.md) excludes backend modifications.
These experiments target Hermes revision
`8d79c2ff57bba4b07e5b37ed90387b16541aef53` and are not current requirements or
evidence of support on an installed server. An APK update does not apply them.

| Patch | Purpose |
| --- | --- |
| 0001 | Set TCP_NODELAY on the pinned messaging API's SSE transport |
| 0002 | Scope command catalog, completion and dispatch to the requested profile |
| 0003 | Authenticated mobile registration, shared event IDs and Firebase sending |
| 0004 | Recover pending sensitive request metadata through resume/session info |
| 0005 | Persist explicit answer-version relationships and resolve current rows |
| 0006 | Recover live-session side tasks and expose running counts to Activity |

Current boundaries are documented in [local notifications](../docs/BACKGROUND_NOTIFICATIONS.md),
[pending input and side questions](../docs/SUPERVISION_AND_QUEUES.md),
[server relationships](../docs/SERVER_CHAT_RELATIONSHIPS.md) and
[connections/updates](../docs/CONNECTION_DIAGNOSTICS_AND_VERSIONS.md).
Historical patch validation does not establish live acceptance of those features.
