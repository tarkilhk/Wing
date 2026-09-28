import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/file_open_error_message.dart';
import '../services/remote_files_client.dart';
import '../widgets/studio_error.dart';
import '../widgets/web_output_preview.dart';

/// Loads complete HTML before handing it to the native viewer. Text previews
/// may be truncated and must never be used as the rendered document.
class HtmlPreviewScreen extends StatefulWidget {
  final String title;
  final Future<RemoteFileDownload> Function() download;
  final Future<void> Function(RemoteFileDownload) share;

  const HtmlPreviewScreen({
    super.key,
    required this.title,
    required this.download,
    required this.share,
  });

  @override
  State<HtmlPreviewScreen> createState() => _HtmlPreviewScreenState();
}

class _HtmlPreviewScreenState extends State<HtmlPreviewScreen> {
  RemoteFileDownload? _file;
  String? _source;
  String? _error;
  bool _loading = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await widget.download();
      if (!mounted) return;
      _file = file;
      if (file.bytes.length > WebOutputPreview.maxHtmlSourceLength) {
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
      if (mounted) _error = fileOpenErrorMessage(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _share() async {
    if (_sharing || _file == null) return;
    setState(() => _sharing = true);
    try {
      await widget.share(_file!);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: StudioError(fileOpenErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_source != null) {
      return WebOutputPreview(
        source: _source!,
        format: WebOutputFormat.html,
        title: widget.title,
        actionLabel: 'Save or share',
        onAction: _sharing ? null : _share,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Center(
          child: _loading
              ? const CircularProgressIndicator()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      StudioError(_error!),
                      const SizedBox(height: 12),
                      if (_file == null)
                        OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _loading = true;
                              _error = null;
                            });
                            _load();
                          },
                          child: const Text('Try again'),
                        )
                      else
                        OutlinedButton.icon(
                          onPressed: _sharing ? null : _share,
                          icon: const Icon(Icons.ios_share),
                          label: const Text('Save or share'),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
