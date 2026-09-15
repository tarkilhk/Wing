import 'package:flutter/services.dart';

import 'remote_files_client.dart';

class PdfDocument {
  final String id;
  final int pageCount;

  const PdfDocument(this.id, this.pageCount);
}

/// Temporary native PDF resources, released when the reader closes.
class PdfPreviewService {
  static const channelName = 'com.tarkilhk.wing/pdf_preview';
  final MethodChannel _channel;

  const PdfPreviewService({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  Future<PdfDocument> open(Uint8List bytes) async {
    if (bytes.isEmpty ||
        bytes.length > RemoteFilesClient.defaultMaxDownloadBytes) {
      throw StateError('This PDF could not be displayed.');
    }
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('open', {
        'bytes': bytes,
      });
      final id = result?['documentId'];
      final pages = result?['pageCount'];
      if (id is String && id.isNotEmpty) {
        if (pages is int && pages > 0) return PdfDocument(id, pages);
        await close(PdfDocument(id, 0));
      }
    } on PlatformException {
      // Native decoder errors can contain paths or document details.
    } on MissingPluginException {
      // External viewers remain available on unsupported platforms.
    }
    throw StateError('This PDF could not be displayed.');
  }

  Future<Uint8List> render(PdfDocument document, int page) async {
    if (page < 0 || page >= document.pageCount) {
      throw ArgumentError('Invalid PDF page');
    }
    try {
      final image = await _channel.invokeMethod<Uint8List>('render', {
        'documentId': document.id,
        'page': page,
      });
      if (image != null && image.isNotEmpty) return image;
    } on PlatformException {
      // Keep native exceptions out of the user-facing error.
    } on MissingPluginException {
      // The caller retains the downloaded PDF and external-viewer option.
    }
    throw StateError('This PDF page could not be displayed.');
  }

  Future<void> close(PdfDocument document) async {
    try {
      await _channel.invokeMethod<void>('close', {'documentId': document.id});
    } on PlatformException {
      // Disposal is best effort after the route or engine has closed.
    } on MissingPluginException {
      // The native engine may already have released its resources.
    }
  }
}
