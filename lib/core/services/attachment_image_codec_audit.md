The attachment worker owns a bounded decoder for lossless WebP and compressed
WebP alpha. Its interface accepts validated bytes and returns decoded pixels
plus a conservative cumulative allocation charge. The package lossy VP8 decoder
receives raw alpha only. There are no package patches, backend changes, alternate
codec fallbacks, or public codec exports.

The private VP8L and alpha parts are adapted from image 4.10.1. Their MIT license
is preserved in image_codec.LICENSE. Original source SHA-256 digests and locked
hosted package artifact hashes are recorded in tools/contracts/image-codec-audit.json.
ARCH_IMAGE_CODEC_PROVENANCE rejects different image/archive versions, artifact
hashes, a floating image dependency, and codec dependency overrides (including optional pubspec_overrides.yaml). A version
change requires revisiting allocation accounting and parity, not rebaselining.

Allocation policy is 256 MiB of charged work, including the original preflight
reserve for input, retained decoded frames, orientation and encoding. This is a
conservative input-driver budget, not a measured peak VM heap or resident-memory
promise. The worker debits allocations before constructing them. Debits remain
charged for the full decode even if the GC might reclaim an earlier allocation.

The private budget owner allocates all entropy typed buffers, fixed/group Huffman
tables and extension segments, palette buffers, color caches, decoder outputs,
and raw alpha/container buffers. Huffman entries are charged 64 bytes each,
including the list reference, object fields/header and alignment; a table/list
header is additionally charged 256 bytes. Every extension uses its actual full
segment size, not merely the symbols used. Groups reserve 4096 bytes for their
five list wrappers, 64 packed objects, lists and headers. Nested transform/meta
pixels are charged by actual sample count. The sparse-group mapping allocates by
its parsed maximum group identifier and starts at -1, correcting the upstream
one-element/sentinel allocation. It is charged before allocation. Transform
objects and their per-row multiplier scratch reserve 256 + 128 * source rows.
A 2 MiB upfront debit covers the globally bounded 4096 chunk objects, tags,
views and transient list growth. Filtered alpha reserves 1024 + 384 * row count
before pinned filter loops create row-local InputBuffer wrappers.
Typed arrays include a 64-byte overhead allowance; output Image objects reserve
4096 bytes in addition to sample bytes. Other fixed decoder state reserves 512
bytes. The pinned transform and bit-reader implementation cannot introduce
unaccounted input-sized allocations through an unnoticed dependency upgrade.

JPEG preflight checks baseline/progressive 8-bit component/sampling dimensions
before image's readInfo allocates MCU coefficients. DHT selectors, symbol counts
and code-length prefix capacity, and DQT IDs/precision/payload sizes are checked
before table construction. DHTs reserve up to 16 path nodes per symbol, charged
64 bytes per node plus a table allowance, including repeated tables. PNG uses a
streaming inflation sink with exact IHDR/Adam7/frame scanline counts, so excess
output is rejected without whole-output inflation. Text/ICC/EXIF metadata is
bounded and removed before decoding. Orientation reads only a bounded direct TIFF
IFD tag; no linked/sub-IFD traversal is exposed to the package metadata decoder.

Fixtures bounded-lossless.webp, bounded-compressed-alpha.webp and
bounded-animation.webp are generated from deterministic 128 x 96 RGBA pixels
using the already installed ffmpeg/libwebp encoder. The alpha fixture uses
compressed ALPH method 1. Pixel/frame/duration/loop parity tests compare against
the locked image decoder, and the worker still enforces the stock 25 MiB output
cap. Input/pixel/frame/metadata limits and worker exit-ack occupancy are separate
runtime checks. Isolate exit acknowledgement is not a native file-descriptor
close acknowledgement; supported chooser paths currently supply regular files.

Remaining acceptance: realistic phone camera and animation transforms, peak
memory/jank observations, and cancellation on actual phone OS/runtime. Host
fixtures and static provenance guards do not substitute for those observations.
