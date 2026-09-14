# Sharing into a draft

Share text, links, images or files into a reviewed draft. The composer also offers Camera, Photos, Files and supported clipboard-image intake.

Incoming text, links, images and files open a review. With multiple connections, choose the destination server first. The review displays its connection, lets the user choose a discovered profile and either a new or existing conversation, and exposes pagination for older chats. Add to draft is the only write action; Send remains a separate action in the composer.

The controller prepares every incoming attachment against the existing draft's limits before changing the draft. It preserves existing text, attachments, queued messages and uncertain-delivery status. Shared text is appended with a blank separator. Preparation failures clean only newly staged files, and a changed destination draft is left intact. Successful staging uses the existing durable draft store.

The exact pending share is acknowledged only after staging succeeds. Cancelling leaves the content available from the Home Review control; Discard explicitly removes it. A failed New chat staging attempt reuses the already-created conversation on retry. It does not delete a server chat or create another one on every retry.

Native intake keeps unsent text and attachment copies in private app storage before destination selection. A small persisted queue owns pending shares; Flutter displays the oldest and acknowledges its ID only after draft staging or explicit Discard. Copies are removed after that acknowledgement is saved. The queue survives app restart and holds at most ten shares and 128 MiB of files; each share allows ten files, 64 MiB of files and 256 Ki characters of text. Imports are serialized, and unreadable or oversized input fails as a whole with a visible error. It does not silently import only some selected files.

If clearing an incoming share fails after its conversation draft was saved, the app opens the saved draft and explains that the pending share can be discarded from Home. A failed Discard leaves the review controls available. These are unsent drafts only; no conversation history or execution state is stored in the intake queue.

Photos and Files feed the same attachment path. Images receive the existing sanitization and file limits.

Camera opens the phone's camera application through Android's capture intent. It writes to a single granted URI in private pending-intake storage and adds no camera permission or Flutter dependency. The originating connection identity, profile and chat are captured before launch. On return, the same review opens with that chat selected, including when it is outside the first history page. If ownership changed or the chat cannot be reopened, the photo remains available and review asks for a destination. Adding the photo preserves the existing draft; Send is still separate.

The capture descriptor is saved before launch. Successful nonempty output, up to 64 MiB, enters the existing durable intake queue. Cancellation removes only that capture. Recovery checks the descriptor when Hermes resumes, retains completed output and deduplicates by intake ID. URI grants are revoked on return. An active camera reserves queue capacity so another incoming share cannot consume its space.

## Interruption and recovery

An interruption after saving the conversation draft but before acknowledging intake can offer the share again. Review remains mandatory and nothing sends automatically. A copy interrupted before native intake commits may need to be shared again.

A locally created chat can expire while Camera is open. Same-process return joins any reconnect and preserves the draft/settings. If the original session is confirmed missing after process death, New chat with recovered draft moves the existing draft in one storage write, preserves uncertainty, pauses queues and resets upload references. Staging failure retains that recovered draft and retries reuse the new chat. Missing files remain visible for removal or reattachment. Send stays explicit.

Empty abandoned capture output is cleared when Android returns. Keep it pending while Camera is foreground so a file still being written is not treated as complete. Chats also exposes saved drafts without a loaded chat row through the same verified missing-session recovery path.

Samsung checks covered picker/camera cancellation, successful capture, reviewed file/photo intake and restart recovery. File upload acceptance does not guarantee automatic workspace-reference expansion; see [conversation attachments](CONVERSATION_ACTIONS_AND_READING.md#attachments-in-history) and [Testing](TESTING.md).
