# Conversation runtime ownership

ProfileChat keeps a private final ChatRuntime and exposes only its readonly
ChatRuntimeObservation. Runtime owns execution, connection recovery, correlated
approvals/questions/secure input, activity and revision tickets. Execution and
recovery remain independent: pending input does not erase a completed turn, and
a successful input receipt may restore transport readiness without starting a
turn. Passive reading snapshots cannot grant live execution authority.

ComposerSession owns outgoing durability and acknowledged consumption;
TranscriptReading owns rows/paging/passive snapshots; the workspace controller
owns captured resources, keys and physical RPC admission. Runtime holds no secret
reply values. Request models own clarification encoding and secure response
normalization/encoding; dialogs retain transient controllers/selection.

Captured tickets fence preparation, persistence, reconnect/readback, answered or
replaced requests and final dispatch. A held submission acknowledgement blocks
reopening. Obsolete mutable ProfileChat APIs and UI policy methods are removed.

Two independently runnable guards protect the canonical passive runtime surface
and secure panel codec dependency. Existing retirement enforcement protects48
further removed declarations. Async ordering and uncertainty are verified by
existing held-future/input/queue/command/reopen controls, rather than claimed by
static checks. Both guards are mandatory in PR and release workflows.

This contract closes the bounded runtime/request-policy migration. Browser,
notifications, supervision, shared drafts, native/resource/device evidence and
final whole-code acceptance remain separately inventoried obligations.
