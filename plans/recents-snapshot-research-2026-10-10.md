# Established snapshot approaches for Wing Recents

Wing should use the established thumbnail pattern: reuse a genuine captured
viewport when available, show missing cards immediately with their titles, and
publish each newly prepared image independently. Keep the initial preparation
bounded and prioritize what the user can see. No periodic capture timer is
needed.

## Android and browser precedents

Android captures a task when it moves into the background and shares its
GraphicBuffer with SystemUI for Recents. It can reuse the same buffer while the
application restores its screen. Saved snapshots have low and high resolution
versions; disk restoration loads the smaller version first. This is platform
infrastructure, with application customization unsupported. It captures an
existing surface; it does not render unvisited conversations inside an app.
[AOSP task snapshots](https://source.android.com/docs/core/perf/task-snapshots).

The inspected Launcher3 implementation uses a bounded cache, returns adequate
cache hits immediately, retrieves missing thumbnails asynchronously, and rejects
delivery after cancellation. High resolution loading normally requires overview
to be visible without fast flinging, with an exception for devices that only
support high resolution snapshots. This supports motion-aware loading, rather
than a promise that every operation stops during every gesture.
[TaskThumbnailCache.java at revision 4f00d6d](https://android.googlesource.com/platform/packages/apps/Launcher3/+/4f00d6d88c2c12a236eba6df33f1b23dc1874199/quickstep/src/com/android/quickstep/TaskThumbnailCache.java).

Chromium accepts a priority-ordered list of visible tab IDs and truncates it to
thumbnail cache capacity. It distinguishes retained images from compression and
write queues, and retrieves and decodes saved thumbnails asynchronously.
[TabContentManager.java at revision 7ea5884](https://chromium.googlesource.com/chromium/src/+/7ea5884269d41f52a2622a4728d5a747b3b71755/chrome/browser/tab_ui/android/java/src/org/chromium/chrome/browser/tab_ui/TabContentManager.java).

Its native manager captures available compositor surfaces, rejects duplicate
captures for the same tab while readback is pending, discards obsolete results,
and updates the corresponding layer when an image becomes available. Readbacks
also have a timeout. These are examples of independent publication and bounded
resource lifetimes, rather than a reason to wait for the whole batch.
[tab_content_manager.cc at the same revision](https://chromium.googlesource.com/chromium/src/+/7ea5884269d41f52a2622a4728d5a747b3b71755/chrome/browser/android/compositor/tab_content_manager.cc).

These pinned source examples establish design precedents, not a specification
for every current Android device or Chrome UI. Their native buffers are not
directly reusable as snapshots of individual Wing conversations.

## Flutter already supplies capture primitives

Flutter's `SnapshotWidget` replaces its child with a frozen, texture-backed
`ui.Image`. Flutter uses it in Android Q zoom page transitions to avoid repeatedly
painting complex pages during scaling. It does not support capturing platform
views in its normal mode.
[SnapshotWidget documentation](https://api.flutter.dev/flutter/widgets/SnapshotWidget-class.html).

The local Flutter 3.44.0 source, framework revision
`559ffa3f75e7402d65a8def9c28389a9b2e6fe42`, confirms this implementation in
`packages/flutter/lib/src/widgets/snapshot_widget.dart`. It keeps the image
inside its render object and captures at device pixel ratio. Its public
controller controls snapshotting and invalidation; it does not supply a
conversation cache or a preparation queue. It is relevant to a mounted child's
transition, but is not a complete replacement for Wing's independently retained
card images.

`RenderRepaintBoundary.toImage` supplies the separate image needed by such a
cache. The boundary must already have painted. Pixel ratio controls the captured
image size independently of device pixel ratio.
[toImage documentation](https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImage.html).

`toImageSync` returns a handle before rasterization finishes; it does not make
the underlying work disappear or eliminate contention.
[toImageSync documentation](https://api.flutter.dev/flutter/rendering/RenderRepaintBoundary/toImageSync.html).

The `screenshot` package provides invisible-widget capture, but wraps
the same repaint boundary primitive.
[Package documentation](https://pub.dev/packages/screenshot).
Its inspected source performs widget build, layout and paint directly, and
`captureFromWidget` converts the result to PNG before returning it. It also
offers a separate image-returning helper. Adding the package would not solve
Wing's scheduling, fidelity, invalidation or memory ownership requirements.
[Package implementation](https://raw.githubusercontent.com/SachinGanesh/screenshot/master/lib/screenshot.dart).

## Scheduling and memory constraints

Flutter widget and UI work belongs to the main isolate. Background isolates can
prepare data, but cannot independently render ten Flutter chat pages. One thread
per conversation is therefore not the appropriate capture model.
[Flutter isolate limitations](https://docs.flutter.dev/perf/isolates#no-rootbundle-access-or-dartui-methods).

An `Offstage` child still lays out but does not paint, and its animations can
continue running. Hiding a subtree does not make its work occur on a background
thread or produce a freshly painted screenshot.
[Offstage documentation](https://api.flutter.dev/flutter/widgets/Offstage-class.html).

Flutter's default scheduler refuses tasks below `Priority.animation` while an
animation is running, including a progress indicator. A continuously spinning
indicator can therefore starve a queue implemented using
`scheduleTask(Priority.idle)`. Use explicit asynchronous coordination and motion
admission; do not change the application's global scheduling strategy to make
long jobs run. Yielding between jobs cannot preempt one expensive layout.
[scheduleTask documentation](https://api.flutter.dev/flutter/scheduler/SchedulerBinding/scheduleTask.html).
The local 3.44.0 `defaultSchedulingStrategy` confirms the same priority check.

Publish a captured `ui.Image` directly through `RawImage`. PNG encoding and
decoding are optional retention operations, not prerequisites for displaying
it. The owner must dispose images when replaced or evicted.
[RawImage documentation](https://api.flutter.dev/flutter/widgets/RawImage-class.html).
Flutter's ordinary image cache uses least recently used eviction and a byte
limit, primarily through `ImageProvider`; a separately owned map of raw images
needs its own resource accounting.
[ImageCache documentation](https://api.flutter.dev/flutter/painting/ImageCache-class.html).

## Recommended Wing behavior

The following choices adapt those precedents to the requested interaction:

1. On zoom out, show cached cards or title/profile placeholders immediately, with
   the requested spinner. Capture the current real chat from its painted
   boundary during the handoff, before hiding it. Keep only its latest version.
2. Prepare missing images using faithful shared chat components. Screenshotting
   the existing plain-text rendition would preserve its poor Markdown fidelity.
   Passive preparation must not resume conversations or acquire chat execution
   authority.
3. Use one render lane. Prepare the center and its two neighbors first, then
   extend outward to at most ten unique cards in the initial batch. Ten is Wing's
   policy, not an Android or Flutter standard.
4. Publish each image independently as soon as it is ready. Pause admission of
   new render jobs during opening motion, swipes and flings. When motion settles,
   put the newly visible cards ahead of distant queued work. Other conversations
   remain browsable and can request an image on demand.
5. Reuse images while their conversation/profile identity, observed content,
   draft, theme, text scale and viewport inputs remain valid. Invalidate from
   observed changes and lifecycle events; do not poll every five seconds.
6. Enforce both a work cap and a decoded-image byte budget. Account for a capture
   in flight as well as retained images. Retain useful prepared images beyond
   just the current three-card neighborhood; otherwise outward preparation will
   immediately undo its own work.
7. Treat success, failure and timeout as terminal states for initial-batch
   progress. Stop the spinner when that bounded batch settles. Suppress and
   dispose late results after exit, profile change or superseding work; do not
   repeatedly regenerate an evicted distant image to keep the spinner alive.

Choose capture resolution for the displayed card and render each fresh page
once. Android's low/high resolution restoration loads existing files; rendering
an unvisited Flutter page twice would duplicate layout. Lower pixel dimensions
can reduce image memory and raster work, but do not by themselves reduce widget
layout complexity. Optional disk or compressed retention should follow a
demonstrated need, with a bounded encoding queue and publication before encoding.

The current implementation already owns a disposable image cache in
`lib/core/widgets/recent_conversations/conversation_card_snapshots.dart` and
serializes preparation in `recent_conversation_switcher.dart`. Extend these
existing boundaries rather than adding a new screenshot subsystem. The session
currently admits only a three-card neighborhood; extending preparation requires
matching admission and retention changes in `RecentConversationSession`.

The physical-phone capture study remains in private storage under
`docs/PERFORMANCE.md` policy. Its measurements must not be interpreted as a
guarantee that fresh hidden-page layout meets every device's frame budget. The
implementation acceptance should cover missing snapshots during interaction,
late completion after exit, failed preparation, large histories, and returning
to already captured chats.
