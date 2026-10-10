# Configuration backups

Configuration exports include saved connection credentials and supported device
settings. Protect exported files as secrets. A confirmed passphrase of at least
eight characters encrypts the export; leaving both passphrase fields empty
chooses plaintext explicitly. Saved device settings include appearance, composer
action, notifications, device voice choices and per-connection visibility.
Profile settings, chat drafts and cached transcripts are not part of this export;
conversations remain on Hermes and cloud sign-in is performed again after restore.

Open App settings and choose Backup configuration. Confirm the export, then
choose a receiving app in Android's share sheet. Backups, downloaded outputs and
skill text share one pending share operation. If another offer is still open,
finish that share sheet and try again.

Each export has its own temporary directory and unique filename. Wing keeps its
original while Android prepares the share and waits for the result. Once that
operation succeeds, is dismissed or fails, Wing removes its original directory.
Closing the backup screen during an admitted share does not remove the original
early. Android's share plugin creates a separate provider-cache copy; it can
remain until another share replaces the cache or the cache is cleared. Files
saved by a receiving app have that app's retention rules. Dismissing the chooser
does not promise deletion of every copy. See [sharing from Wing](SHARING_AND_CAPTURE.md#sharing-from-wing).

The current portable format is `wing-config` version 2. Imports accept that version
directly; older formats must be exported again with the current app. Per-connection
visibility uses the saved connection's logical ID in the backup and in the current
device preference namespace, so signing in again does not reset this filter.
Device identity keys are never exported. The previous identity-based visibility
namespace is not read or migrated; its filter returns to the default.

Input and output are limited to 2 MiB, with at most 256 connections, 2,048 settings,
65,536 UTF-16 code units per string and 12 nested levels. The file reader counts
actual streamed bytes, including files whose provider reports an inaccurate size.
Malformed encryption parameters are rejected before key derivation.

Restore validates connections and supported settings before mutating storage.
Unknown settings or invalid setting types/values are skipped and counted in the
result. Connection metadata and credentials use one serialized transaction with a
durable rollback journal; an interrupted, unacknowledged transaction is rolled back
before connections can be read. Plaintext credential metadata is rejected.

Merge adds or updates the imported connections while retaining others. Replace
removes connections absent from the backup. Supported settings are a sparse
patch: only explicitly saved fields in the backup are restored. A settings
failure after the connection transaction commits does not undo those confirmed
connection changes. The result reports whether previous settings were restored,
could not be verified or could not be restored; review that outcome before
retrying.

See [Testing](TESTING.md) for host and opt-in native backup checks.
