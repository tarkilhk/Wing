# Configuration backups

Configuration exports include saved connection credentials and supported device
settings. Protect exported files as secrets. A passphrase encrypts the export;
conversations remain on Hermes and cloud sign-in is performed again after restore.

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

See [Testing](TESTING.md) for host and opt-in native backup checks.
