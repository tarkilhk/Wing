# Notification ownership

ChatNotificationCoordinator remains the sole durable chat-notice journal. Its
required one-time application binding borrows the registry, connection manager,
native sink, monitoring and delivery ledger. The private application part owns
startup permission, restore/claim/release, captured target opening, interaction
review decisions, native ACK sequencing and one monitoring poller. Unbound or
retired application commands reject work. Application close precedes dependency
disposal. The UI mounts issued route/review requests and retains navigation,
dialog geometry, route reuse and end-of-frame readiness.

NativeNotificationSink interprets platform wire values and retains its private
channel. Actual fixtures compose the stable channel name; product views receive
typed channel facts. Admitted direct actions can finish after route retirement.
TranscriptReading owns reveal generation, focus and read target; exact captured
release/ACK cannot erase a newer target. Immutable NotificationInput lives in
the domain layer so the coordinator may borrow workspace without a cycle.

Existing routing, native interaction, restore, permission, preference ABA,
visibility and retention controls are preserved; two concrete lifetime/immutable
input controls supplement them. Standard private-member analysis, architecture
cycle/domain checks and27 exact retired identities protect removed patterns.
Native/rendered/performance and final whole-program acceptance remain open.
