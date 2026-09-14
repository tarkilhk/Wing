import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android image clipboard access, invoked by the composer's paste menu.
class ImageClipboard {
  static const channel = MethodChannel(
    'com.hermesagent.hermes_android/image_clipboard',
  );
  static const mimeTypes = ['image/png', 'image/jpeg', 'image/webp'];

  static Future<bool> hasImage() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await channel.invokeMethod<bool>('hasImage') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<Uint8List> readImage() async {
    final Uint8List? bytes;
    try {
      bytes = await channel.invokeMethod<Uint8List>('readImage');
    } on PlatformException catch (error) {
      throw StateError(error.message ?? 'Unable to read the clipboard image.');
    }
    if (bytes == null || bytes.isEmpty) {
      throw StateError(
        'The clipboard image is no longer available. Copy it again.',
      );
    }
    return bytes;
  }

  static Future<Uint8List> keyboardImage(
    KeyboardInsertedContent content,
  ) async {
    if (!mimeTypes.contains(content.mimeType) || !content.hasData) {
      throw StateError(
        'Unable to paste this image. Copy a JPEG, PNG, or WebP image again.',
      );
    }
    return content.data!;
  }
}
