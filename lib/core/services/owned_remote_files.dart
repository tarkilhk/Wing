import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'file_open_error_message.dart';
import 'remote_files_client.dart';
import 'remote_file_saver.dart';
import 'web_preview.dart';

/// Binds requests and their transport lifetime to the chat that exposed them.
final class OwnedRemoteFiles {
  OwnedRemoteFiles({
    required this._source,
    required this.profileName,
    required this.storedSessionId,
    required this._release,
  });

  final RemoteFilesDataSource _source;
  final void Function() _release;
  final String profileName;
  final String storedSessionId;
  bool _active = true;

  void _requireActive() {
    if (!_active) throw StateError('This file owner is closed.');
  }

  Future<RemoteTextPreview> readText(String path) async {
    _requireActive();
    final preview = await _source.readText(
      path,
      profileName: profileName,
      storedSessionId: storedSessionId,
    );
    _requireActive();
    return preview;
  }

  Future<RemoteFileDownload> download(String path) async {
    _requireActive();
    final file = await _source.download(
      path,
      profileName: profileName,
      storedSessionId: storedSessionId,
    );
    _requireActive();
    return file;
  }

  Future<bool> downloadAndSave(
    String path, {
    required bool Function() admitPresentation,
  }) async {
    final file = await download(path);
    if (!_active || !admitPresentation()) return false;
    return saveRemoteFile(file);
  }

  void dispose() {
    if (!_active) return;
    _active = false;
    _release();
  }
}

/// An acquired original image. Flutter providers and thumbnail geometry are UI.
@immutable
final class ImageResource {
  ImageResource.bytes(List<int> value)
    : bytes = Uint8List.fromList(value).asUnmodifiableView(),
      uri = null;
  const ImageResource.uri(Uri value) : uri = value, bytes = null;

  final Uint8List? bytes;
  final Uri? uri;
}

/// Address admission and embedded-byte budget shared by attachment previews.
/// Remote paths are always loaded by their captured owner, never as device files.
Future<ImageResource> acquireConversationImage(
  String target,
  Future<Uint8List> Function(String)? loadRemote,
) => _acquireImageResource(
  target,
  loadRemote: loadRemote,
  allowEmbedded: false,
  allowWindowsPaths: true,
);

Future<ImageResource> acquireUserAttachmentImage(
  String target,
  Future<Uint8List> Function(String)? loadRemote,
) => _acquireImageResource(
  target,
  loadRemote: loadRemote,
  allowEmbedded: true,
  allowWindowsPaths: false,
);

Future<ImageResource> _acquireImageResource(
  String target, {
  required Future<Uint8List> Function(String)? loadRemote,
  required bool allowEmbedded,
  required bool allowWindowsPaths,
}) async {
  if (allowEmbedded && target.length > 45 * 1024 * 1024) {
    throw const FormatException('Image attachment too large');
  }
  final uri = Uri.tryParse(target);
  if (allowEmbedded && uri?.scheme == 'data') {
    final data = uri!.data!;
    if (!data.mimeType.startsWith('image/')) {
      throw const FormatException('Invalid image attachment');
    }
    final bytes = data.contentAsBytes();
    if (bytes.length > RemoteFilesClient.defaultMaxDownloadBytes) {
      throw const FormatException('Image attachment too large');
    }
    return ImageResource.bytes(bytes);
  }
  final external =
      allowEmbedded &&
          uri != null &&
          {'http', 'https'}.contains(uri.scheme) &&
          uri.host.isNotEmpty
      ? uri
      : externalWebLink(target);
  if (external != null) return ImageResource.uri(external);
  if (allowEmbedded && uri == null ||
      uri?.hasScheme == true &&
          !(allowWindowsPaths && RegExp(r'^[A-Za-z]:[\\/]').hasMatch(target)) ||
      loadRemote == null) {
    throw const FormatException('Image unavailable');
  }
  final bytes = await loadRemote(target);
  if (bytes.length > RemoteFilesClient.defaultMaxDownloadBytes) {
    throw const FormatException('Image attachment too large');
  }
  return ImageResource.bytes(bytes);
}

@immutable
final class HtmlPreviewObservation {
  const HtmlPreviewObservation({
    required this.source,
    required this.error,
    required this.loading,
    required this.sharing,
    required this.hasFile,
  });
  final String? source;
  final String? error;
  final bool loading;
  final bool sharing;
  final bool hasFile;
}

/// One route's complete original HTML, decode decision and sharing operation.
/// The source is never populated from a truncated text preview.
final class HtmlPreviewReader extends ChangeNotifier {
  HtmlPreviewReader({required this._download, required this._share});

  final Future<RemoteFileDownload> Function() _download;
  final Future<void> Function(RemoteFileDownload) _share;
  RemoteFileDownload? _file;
  String? _source;
  String? _error;
  bool _loading = false;
  bool _sharing = false;
  bool _active = true;
  int _notificationDepth = 0;

  HtmlPreviewObservation get observation => HtmlPreviewObservation(
    source: _source,
    error: _error,
    loading: _loading,
    sharing: _sharing,
    hasFile: _file != null,
  );

  Future<void> load() async {
    if (!_active || _loading || _file != null) return;
    _loading = true;
    _error = null;
    _notify();
    if (!_active) return;
    try {
      final file = await _download();
      if (!_active) return;
      _file = file;
      if (file.bytes.length > RemoteFilesClient.defaultMaxDownloadBytes) {
        _error = 'This file exceeds the 32 MiB download limit.';
      } else {
        try {
          _source = utf8.decode(file.bytes);
        } on FormatException {
          _error =
              "This HTML file can't be read here. Use Save or share to open it in another app.";
        }
      }
    } catch (error) {
      if (_active) _error = fileOpenErrorMessage(error);
    } finally {
      if (_active) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<String?> share() async {
    final file = _file;
    if (!_active || _sharing || file == null) return null;
    _sharing = true;
    _notify();
    if (!_active) return null;
    try {
      await _share(file);
      return null;
    } catch (error) {
      return _active ? fileOpenErrorMessage(error) : null;
    } finally {
      if (_active) {
        _sharing = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_active) return;
    ++_notificationDepth;
    try {
      notifyListeners();
    } finally {
      --_notificationDepth;
      if (!_active && _notificationDepth == 0) super.dispose();
    }
  }

  @override
  void dispose() {
    if (!_active) return;
    _active = false;
    _file = null;
    _source = null;
    if (_notificationDepth == 0) super.dispose();
  }
}
