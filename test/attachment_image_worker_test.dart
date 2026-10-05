import 'dart:async';
import 'dart:isolate';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image_lib;
import 'package:flutter_test/flutter_test.dart';

import 'package:wing/core/services/attachment_image_preflight.dart';
import 'package:wing/core/services/attachment_image_worker.dart';

int _crc(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
    }
  }
  return crc ^ 0xffffffff;
}

Uint8List _word(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value);
List<int> _chunk(String type, List<int> bytes) {
  final body = [...ascii.encode(type), ...bytes];
  return [..._word(bytes.length), ...body, ..._word(_crc(body))];
}

Uint8List _png(
  int width,
  int height,
  List<int> inflated, {
  int bits = 8,
  int interlace = 0,
}) => Uint8List.fromList([
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  ..._chunk('IHDR', [
    ..._word(width),
    ..._word(height),
    bits,
    6,
    0,
    0,
    interlace,
  ]),
  ..._chunk('IDAT', ZLibCodec().encode(inflated)),
  ..._chunk('IEND', []),
]);

Uint8List defaultImageApng() => Uint8List.fromList([
  137,
  80,
  78,
  71,
  13,
  10,
  26,
  10,
  ..._chunk('IHDR', [..._word(1), ..._word(1), 8, 6, 0, 0, 0]),
  ..._chunk('acTL', [..._word(2), ..._word(0)]),
  ..._chunk('IDAT', ZLibCodec().encode([0, 255, 0, 0, 255])),
  ..._chunk('fcTL', [
    ..._word(0),
    ..._word(1),
    ..._word(1),
    ..._word(0),
    ..._word(0),
    0,
    1,
    0,
    10,
    0,
    0,
  ]),
  ..._chunk('fdAT', [
    ..._word(1),
    ...ZLibCodec().encode([0, 0, 255, 0, 255]),
  ]),
  ..._chunk('fcTL', [
    ..._word(2),
    ..._word(1),
    ..._word(1),
    ..._word(0),
    ..._word(0),
    0,
    1,
    0,
    10,
    0,
    0,
  ]),
  ..._chunk('fdAT', [
    ..._word(3),
    ...ZLibCodec().encode([0, 0, 0, 255, 255]),
  ]),
  ..._chunk('IEND', []),
]);

Uint8List cameraJpeg() {
  const width = 4032, height = 3024;
  final source = image_lib.Image(width: width, height: height, numChannels: 3);
  final pixels = source.toUint8List();
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final p = (y * width + x) * 3;
      pixels[p] = x * 255 ~/ width;
      pixels[p + 1] = y * 255 ~/ height;
      pixels[p + 2] = (x + y) & 255;
    }
  }
  return image_lib.encodeJpg(
    source,
    quality: 85,
    chroma: image_lib.JpegChroma.yuv420,
  );
}

void main() {
  test(
    'JPEG rejects dimensions before the decoder can allocate MCU blocks',
    () {
      final bytes = image_lib.encodeJpg(image_lib.Image(width: 16, height: 16));
      for (var p = 2; p + 9 < bytes.length; p++) {
        if (bytes[p] == 255 && bytes[p + 1] == 192) {
          bytes[p + 7] = 255;
          bytes[p + 8] = 255;
          break;
        }
      }
      expect(
        () => inspectAttachmentImage(bytes),
        throwsA(
          isA<AttachmentImageException>().having(
            (error) => error.message,
            'dimension limit',
            contains('dimensions'),
          ),
        ),
      );
    },
  );

  test('valid JPEG dimensions and MCU charges are inspected', () {
    final info = inspectAttachmentImage(
      image_lib.encodeJpg(image_lib.Image(width: 32, height: 16)),
    );
    expect((info.width, info.height, info.frames), (32, 16, 1));
    expect(info.chargedBytes, lessThan(maxAttachmentImageChargedBytes));
  });

  test('small PNG dimensions cannot hide excess inflated data', () {
    final bomb = _png(1, 1, List<int>.filled(2 * 1024 * 1024, 0));
    // Cached image's decoder accepts trailing inflated bytes. This fixture is
    // deliberately small enough to reproduce the old flaw without an OOM.
    expect(image_lib.decodePng(bomb), isNotNull);
    expect(
      () => inspectAttachmentImage(bomb),
      throwsA(
        isA<AttachmentImageException>().having(
          (error) => error.message,
          'inflation limit',
          contains('inflation'),
        ),
      ),
    );
  });

  test(
    'PNG rejects short inflation, oversized canvas, and unsupported bit depth',
    () {
      for (final bytes in [
        _png(1, 1, [0, 0]),
        _png(65535, 65535, [0]),
        _png(1, 1, [0, 0, 0, 0, 0], bits: 4),
      ]) {
        expect(
          () => inspectAttachmentImage(bytes),
          throwsA(isA<AttachmentImageException>()),
        );
      }
    },
  );

  test('16-bit PNG charges and decodes its actual sample width', () async {
    final bytes = _png(1, 1, [0, 255, 255, 0, 0, 0, 0, 255, 255], bits: 16);
    final job = AttachmentImageWorker.shared.prepareBytes(
      bytes,
      maxOutputBytes: maxAttachmentImageOutputBytes,
    );
    final result = await job.result;
    final decoded = image_lib.decodePng(result.bytes)!;
    expect(decoded.getPixel(0, 0).r, 65535);
    expect(decoded.getPixel(0, 0).a, 65535);
  });

  test('Adam7 exact scanline accounting accepts one-pixel image', () {
    expect(
      inspectAttachmentImage(_png(1, 1, [0, 1, 2, 3, 255], interlace: 1)).width,
      1,
    );
  });

  test(
    'lossless decode charges allocation drivers within the budget',
    () async {
      final bytes = base64Decode(
        'UklGRh4AAABXRUJQVlA4TBEAAAAvAUAAAAdQiirUo/+BiOh/AAA=',
      );
      final preflightCharge = inspectAttachmentImage(bytes).chargedBytes;
      final result = await AttachmentImageWorker.shared
          .prepareBytes(bytes, maxOutputBytes: maxAttachmentImageOutputBytes)
          .result;
      expect(image_lib.decodePng(result.bytes), isNotNull);
      expect(result.inspection.chargedBytes, greaterThan(preflightCharge));
      expect(
        result.inspection.chargedBytes,
        lessThanOrEqualTo(maxAttachmentImageChargedBytes),
      );
    },
  );

  test('all animated PNG frames lose metadata and preserve pixels', () async {
    final source = image_lib.Image(width: 2, height: 2, numChannels: 4)
      ..textData = {'fixture': 'private text'};
    source.setPixelRgba(0, 0, 255, 0, 0, 255);
    final frame = image_lib.Image(width: 2, height: 2, numChannels: 4)
      ..textData = {'fixture': 'private second frame'};
    frame.setPixelRgba(0, 0, 0, 255, 0, 255);
    source.addFrame(frame);
    final result = await AttachmentImageWorker.shared
        .prepareBytes(
          image_lib.encodePng(source),
          maxOutputBytes: maxAttachmentImageOutputBytes,
        )
        .result;
    final decoded = image_lib.decodePng(result.bytes)!;
    expect(decoded.frames, hasLength(2));
    for (final frame in decoded.frames) {
      expect(frame.textData == null || frame.textData!.isEmpty, isTrue);
      expect(frame.exif.isEmpty, isTrue);
      expect(frame.iccProfile, isNull);
    }
    expect(decoded.frames[0].getPixel(0, 0).r, 255);
    expect(decoded.frames[1].getPixel(0, 0).g, 255);
    expect(
      utf8.decode(result.bytes, allowMalformed: true),
      isNot(contains('private')),
    );
  });

  test(
    'cancelling an admitted job releases the queue for a following valid job',
    () async {
      final bytes = image_lib.encodePng(
        image_lib.Image(width: 256, height: 256),
      );
      final first = AttachmentImageWorker.shared.prepareBytes(
        bytes,
        maxOutputBytes: maxAttachmentImageOutputBytes,
      );
      final firstError = expectLater(
        first.result,
        throwsA(isA<AttachmentImageException>()),
      );
      first.cancel();
      await firstError;
      final next = await AttachmentImageWorker.shared
          .prepareBytes(bytes, maxOutputBytes: maxAttachmentImageOutputBytes)
          .result;
      expect(next.bytes, isNotEmpty);
      await first.started;
      expect(first.isCancelled, isTrue);
    },
  );

  test(
    'output upload limit is enforced before returning encoded bytes',
    () async {
      final bytes = image_lib.encodePng(image_lib.Image(width: 2, height: 2));
      final job = AttachmentImageWorker.shared.prepareBytes(
        bytes,
        maxOutputBytes: 1,
      );
      await expectLater(
        job.result,
        throwsA(
          isA<AttachmentImageException>().having(
            (error) => error.message,
            'output quota',
            contains('upload budget'),
          ),
        ),
      );
    },
  );

  test(
    'worker reads only bounded file bytes and closes the source handle',
    () async {
      final dir = await Directory.systemTemp.createTemp('wing-image-worker-');
      try {
        final file = File('${dir.path}/image.png');
        await file.writeAsBytes(
          image_lib.encodePng(image_lib.Image(width: 2, height: 2)),
        );
        final result = await AttachmentImageWorker.shared
            .prepareFile(
              file.path,
              maxOutputBytes: maxAttachmentImageOutputBytes,
            )
            .result;
        expect(image_lib.decodePng(result.bytes)!.width, 2);
        await file.delete();
        final oversized = File('${dir.path}/oversized.png');
        final handle = await oversized.open(mode: FileMode.write);
        await handle.truncate(maxAttachmentImageInputBytes + 1);
        await handle.close();
        await expectLater(
          AttachmentImageWorker.shared
              .prepareFile(
                oversized.path,
                maxOutputBytes: maxAttachmentImageOutputBytes,
              )
              .result,
          throwsA(
            isA<AttachmentImageException>().having(
              (error) => error.message,
              'input quota',
              contains('64 MiB'),
            ),
          ),
        );
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'cancel before spawn returns keeps occupancy until actual old exit',
    () async {
      final spawnReturn = Completer<AttachmentImageProcess>();
      final entered = Completer<void>();
      final oldExit = Completer<void>();
      var starts = 0;
      var kills = 0;
      final worker = AttachmentImageWorker(
        startProcess: (port, input, limit) async {
          starts++;
          if (starts == 1) {
            entered.complete();
            return spawnReturn.future;
          }
          port.send(['invalid', 'controlled second completion']);
          return AttachmentImageProcess(() {}, exited: Future.value());
        },
      );
      final first = worker.prepareBytes(Uint8List(8), maxOutputBytes: 1024);
      final failed = expectLater(
        first.result,
        throwsA(isA<AttachmentImageException>()),
      );
      await entered.future;
      first.cancel();
      await failed;
      final next = worker.prepareBytes(Uint8List(8), maxOutputBytes: 1024);
      final nextDone = expectLater(
        next.result,
        throwsA(isA<AttachmentImageException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        starts,
        1,
        reason: 'A pending spawn still owns its resource reservation.',
      );
      spawnReturn.complete(
        AttachmentImageProcess(() {
          kills++;
        }, exited: oldExit.future),
      );
      await Future<void>.delayed(Duration.zero);
      final beforeExit = starts;
      final requestedKills = kills;
      oldExit.complete();
      await nextDone;
      expect(beforeExit, 1);
      expect(requestedKills, 1);
      expect(starts, 2);
    },
  );

  test(
    'kill request cannot release old worker before its exit acknowledgment',
    () async {
      final oldExit = Completer<void>();
      var starts = 0;
      var kills = 0;
      final worker = AttachmentImageWorker(
        startProcess: (SendPort port, Object input, int limit) async {
          starts++;
          if (starts == 1) {
            return AttachmentImageProcess(() {
              kills++;
            }, exited: oldExit.future);
          }
          port.send(['invalid', 'controlled replacement completion']);
          return AttachmentImageProcess(() {}, exited: Future.value());
        },
      );
      final first = worker.prepareBytes(Uint8List(8), maxOutputBytes: 1024);
      final failed = expectLater(
        first.result,
        throwsA(isA<AttachmentImageException>()),
      );
      await first.started;
      try {
        first.cancel();
        first.cancel();
        await failed;
        final next = worker.prepareBytes(Uint8List(8), maxOutputBytes: 1024);
        final nextDone = expectLater(
          next.result,
          throwsA(isA<AttachmentImageException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(kills, 1);
        expect(
          starts,
          1,
          reason: 'kill is not synchronous release acknowledgment.',
        );
        oldExit.complete();
        await nextDone;
        expect(starts, 2);
      } finally {
        if (!oldExit.isCompleted) oldExit.complete();
      }
    },
  );
  test(
    'unexpected worker exit releases occupancy and fails without a result',
    () async {
      final worker = AttachmentImageWorker(
        startProcess: (port, input, limit) async =>
            AttachmentImageProcess(() {}, exited: Future.value()),
      );
      final first = worker.prepareBytes(Uint8List(8), maxOutputBytes: 1024);
      await expectLater(first.result, throwsA(isA<AttachmentImageException>()));
      final next = worker.prepareBytes(Uint8List(8), maxOutputBytes: 1024);
      await expectLater(next.result, throwsA(isA<AttachmentImageException>()));
    },
  );
  test(
    'cyclic EXIF IFD chain is removed before the codec can traverse it',
    () async {
      // Two zero-entry directories point at each other. Raw byte-size bounds do
      // not stop cached ExifData.read from repeatedly allocating directories.
      final tiff = Uint8List.fromList([
        73,
        73,
        42,
        0,
        8,
        0,
        0,
        0,
        0,
        0,
        14,
        0,
        0,
        0,
        0,
        0,
        8,
        0,
        0,
        0,
      ]);
      final payload = [...ascii.encode('Exif'), 0, 0, ...tiff];
      final jpeg = image_lib.encodeJpg(image_lib.Image(width: 3, height: 2));
      final bytes = Uint8List.fromList([
        255,
        216,
        255,
        225,
        (payload.length + 2) >> 8,
        (payload.length + 2) & 255,
        ...payload,
        ...jpeg.sublist(2),
      ]);
      final inspection = inspectAttachmentImage(bytes);
      final source = attachmentImageCodecSource(bytes, inspection);
      expect(source.length, jpeg.length);
      expect(
        utf8.decode(source, allowMalformed: true),
        isNot(contains('Exif')),
      );
      final result = await AttachmentImageWorker.shared
          .prepareBytes(bytes, maxOutputBytes: maxAttachmentImageOutputBytes)
          .result;
      expect(image_lib.decodeJpg(result.bytes)!.width, 3);
    },
  );

  test(
    'bounded direct orientation survives metadata removal and rotation',
    () async {
      final original = image_lib.Image(width: 3, height: 2);
      original.exif.imageIfd.orientation = 6;
      original.exif.imageIfd[0x010e] = image_lib.IfdValueAscii(
        'private fixture',
      );
      final bytes = image_lib.encodeJpg(original);
      final inspection = inspectAttachmentImage(bytes);
      expect(inspection.orientation, 6);
      expect(
        utf8.decode(
          attachmentImageCodecSource(bytes, inspection),
          allowMalformed: true,
        ),
        isNot(contains('private fixture')),
      );
      final result = await AttachmentImageWorker.shared
          .prepareBytes(bytes, maxOutputBytes: maxAttachmentImageOutputBytes)
          .result;
      final decoded = image_lib.decodeJpg(result.bytes)!;
      expect((decoded.width, decoded.height), (2, 3));
      expect(decoded.exif.isEmpty, isTrue);
    },
  );

  test(
    'malformed out-of-range TIFF orientation directory fails before decoding',
    () {
      final jpeg = image_lib.encodeJpg(image_lib.Image(width: 2, height: 2));
      final payload = [
        ...ascii.encode('Exif'),
        0,
        0,
        73,
        73,
        42,
        0,
        255,
        255,
        255,
        127,
      ];
      final bytes = Uint8List.fromList([
        255,
        216,
        255,
        225,
        0,
        payload.length + 2,
        ...payload,
        ...jpeg.sublist(2),
      ]);
      expect(
        () => inspectAttachmentImage(bytes),
        throwsA(isA<AttachmentImageException>()),
      );
    },
  );
  test(
    'separate default-image APNG retains current codec-supported frame behavior',
    () async {
      final bytes = defaultImageApng();
      final original = image_lib.decodePng(bytes)!;
      expect(original.frames, hasLength(2));
      expect(inspectAttachmentImage(bytes).frames, 2);
      final output = await AttachmentImageWorker.shared
          .prepareBytes(bytes, maxOutputBytes: maxAttachmentImageOutputBytes)
          .result;
      final restored = image_lib.decodePng(output.bytes)!;
      expect(restored.frames, hasLength(original.frames.length));
      for (var i = 0; i < original.frames.length; i++) {
        final before = original.frames[i].getPixel(0, 0),
            after = restored.frames[i].getPixel(0, 0);
        expect(
          (after.r, after.g, after.b, after.a),
          (before.r, before.g, before.b, before.a),
        );
      }
    },
  );
  test(
    '12 MP camera-sized JPEG completes sanitation without resizing',
    () async {
      final bytes = cameraJpeg();
      final inspected = inspectAttachmentImage(bytes);
      expect(
        inspected.chargedBytes,
        lessThanOrEqualTo(maxAttachmentImageChargedBytes),
      );
      final output = await AttachmentImageWorker.shared
          .prepareBytes(bytes, maxOutputBytes: maxAttachmentImageOutputBytes)
          .result;
      final restored = image_lib.decodeJpg(output.bytes)!;
      expect((restored.width, restored.height), (4032, 3024));
      expect(
        output.bytes.length,
        lessThanOrEqualTo(maxAttachmentImageOutputBytes),
      );
      final center = restored.getPixel(2016, 1512);
      expect(center.r, closeTo(127, 16));
      expect(center.g, closeTo(127, 16));
      expect(restored.exif.isEmpty, isTrue);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  for (final name in [
    'bounded-lossless',
    'bounded-compressed-alpha',
    'bounded-animation',
  ]) {
    test(
      '$name preserves pixels, alpha, frames and animation metadata',
      () async {
        final bytes = File('test/fixtures/images/$name.webp').readAsBytesSync();
        final original = image_lib.decodeWebP(bytes)!;
        final result = decodeBoundedAttachmentWebP(
          bytes,
          inspectAttachmentImage(bytes),
        );
        expect(
          result.chargedBytes,
          lessThanOrEqualTo(maxAttachmentImageChargedBytes),
        );
        expect(result.image.frames, hasLength(original.frames.length));
        expect(result.image.loopCount, original.loopCount);
        for (var i = 0; i < original.frames.length; i++) {
          expect(
            result.image.frames[i].toUint8List(),
            original.frames[i].toUint8List(),
          );
          expect(
            result.image.frames[i].frameDuration,
            original.frames[i].frameDuration,
          );
        }
        final sanitized = await AttachmentImageWorker.shared
            .prepareBytes(bytes, maxOutputBytes: maxAttachmentImageOutputBytes)
            .result;
        expect(
          sanitized.inspection.chargedBytes,
          greaterThan(inspectAttachmentImage(bytes).chargedBytes),
        );
        expect(
          sanitized.inspection.chargedBytes,
          lessThanOrEqualTo(maxAttachmentImageChargedBytes),
        );
        expect(
          image_lib.decodePng(sanitized.bytes)!.frames,
          hasLength(original.frames.length),
        );
      },
    );
  }
  test('lossless Huffman allocation refuses insufficient remaining budget', () {
    final bytes = base64Decode(
      'UklGRh4AAABXRUJQVlA4TBEAAAAvAUAAAAdQiirUo/+BiOh/AAA=',
    );
    final actual = inspectAttachmentImage(bytes);
    final reserved = AttachmentImageInspection(
      format: actual.format,
      width: actual.width,
      height: actual.height,
      frames: actual.frames,
      chargedBytes: maxAttachmentImageChargedBytes - 2 * 1024 * 1024 - 8192,
    );
    expect(
      () => decodeBoundedAttachmentWebP(bytes, reserved),
      throwsA(
        isA<AttachmentImageException>().having(
          (e) => e.message,
          'driver',
          contains('Huffman'),
        ),
      ),
    );
  });
  test(
    'compressed alpha refuses allocation before unbounded package decoder',
    () {
      final bytes = File(
        'test/fixtures/images/bounded-compressed-alpha.webp',
      ).readAsBytesSync();
      final actual = inspectAttachmentImage(bytes);
      final reserved = AttachmentImageInspection(
        format: actual.format,
        width: actual.width,
        height: actual.height,
        frames: actual.frames,
        chargedBytes: maxAttachmentImageChargedBytes - 2 * 1024 * 1024,
      );
      expect(
        () => decodeBoundedAttachmentWebP(bytes, reserved),
        throwsA(
          isA<AttachmentImageException>().having(
            (e) => e.message,
            'driver',
            contains('raw alpha'),
          ),
        ),
      );
    },
  );
  test(
    'JPEG table selectors and oversubscribed Huffman symbols are rejected before decoding',
    () {
      final valid = image_lib.encodeJpg(image_lib.Image(width: 8, height: 8));
      int marker(int code) {
        for (var i = 2; i < valid.length - 1; i++) {
          if (valid[i] == 255 && valid[i + 1] == code) return i;
        }
        throw StateError('Missing JPEG marker');
      }

      final badQuant = Uint8List.fromList(valid)..[marker(219) + 4] = 0x24;
      final badClass = Uint8List.fromList(valid)..[marker(196) + 4] = 0x20;
      final badCodes = Uint8List.fromList(valid)..[marker(196) + 5] = 3;
      for (final bytes in [badQuant, badClass, badCodes]) {
        expect(
          () => inspectAttachmentImage(bytes),
          throwsA(isA<AttachmentImageException>()),
        );
      }
      final inspected = inspectAttachmentImage(valid);
      expect((inspected.width, inspected.height), (8, 8));
    },
  );
  test('compressed alpha refuses row-wrapper allocation before filtering', () {
    final bytes = File(
      'test/fixtures/images/bounded-compressed-alpha.webp',
    ).readAsBytesSync();
    final actual = inspectAttachmentImage(bytes);
    final complete = decodeBoundedAttachmentWebP(bytes, actual);
    // Use observed successful work to leave less room late in the same decode;
    // this fixture has compressed gradient-filtered alpha, not a mocked debit.
    final reserved = AttachmentImageInspection(
      format: actual.format,
      width: actual.width,
      height: actual.height,
      frames: actual.frames,
      chargedBytes:
          actual.chargedBytes +
          maxAttachmentImageChargedBytes -
          complete.chargedBytes +
          32 * 1024,
    );
    expect(
      () => decodeBoundedAttachmentWebP(bytes, reserved),
      throwsA(
        isA<AttachmentImageException>().having(
          (e) => e.message,
          'driver',
          contains('alpha filter row wrappers'),
        ),
      ),
    );
  });
}
