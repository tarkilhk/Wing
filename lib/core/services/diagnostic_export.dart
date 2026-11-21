import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import 'connection_diagnostics.dart';
import 'platform_share.dart';

const _channel = MethodChannel('com.tarkilhk.wing/diagnostics');
bool _captureInstalled = false;
int _pendingRecords = 0;
int _droppedRecords = 0;

/// Captures typed errors, never exception prose, request values or framework context.
/// Existing error reporting keeps its original handling and propagation.
void initializeDiagnosticCapture() {
  if (_captureInstalled || defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  _captureInstalled = true;
  connectionDiagnosticSink = (record) {
    if (_pendingRecords >= 256) {
      _droppedRecords++;
      return;
    }
    _pendingRecords++;
    unawaited(
      _channel
          .invokeMethod<void>('append', record)
          .catchError((Object _) {
            _droppedRecords++;
          })
          .whenComplete(() => _pendingRecords--),
    );
  };
  final flutterHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    logConnectionDiagnostic(
      'flutter.error',
      error: details.exception,
      stackTrace: details.stack,
    );
    flutterHandler?.call(details);
  };
  final platformHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    logConnectionDiagnostic(
      'dart.unhandled_error',
      error: error,
      stackTrace: stack,
    );
    return platformHandler?.call(error, stack) ?? false;
  };
  logConnectionDiagnostic(
    'dart.started',
    details: {
      'mode': kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
    },
  );
}

/// Hides native collection, ZIP staging and platform share ordering from settings.
class DiagnosticExportSession extends ChangeNotifier {
  bool _busy = false;
  bool _closed = false;
  String? _error;
  bool get busy => _busy;
  String? get error => _error;

  Future<void> share() async {
    if (_busy || _closed) return;
    _busy = true;
    _error = null;
    notifyListeners();
    String? path;
    try {
      logConnectionDiagnostic(
        'diagnostics.export',
        details: {'dropped_dart_events': _droppedRecords},
      );
      path = await _channel.invokeMethod<String>('export');
      if (path == null || path.isEmpty) {
        throw StateError('Missing diagnostic archive');
      }
      if (_closed) return;
      await platformShare(
        ShareParams(
          subject: 'Wing diagnostic logs',
          files: [XFile(path, mimeType: 'application/zip')],
        ),
      );
    } on PlatformShareBusy catch (error) {
      _error = error.message;
    } catch (_) {
      _error = 'Could not share diagnostic logs. Try again.';
    } finally {
      // Android share_plus owns a separate provider copy before its result settles.
      if (path != null && path.isNotEmpty) {
        try {
          await File(path).parent.delete(recursive: true);
        } on FileSystemException {
          /* OS cache cleanup. */
        }
      }
      _busy = false;
      if (!_closed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
