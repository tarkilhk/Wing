import 'dart:async';

import 'package:flutter/material.dart';

import '../services/owned_remote_files.dart';
import '../services/remote_files_client.dart';
import '../widgets/studio_error.dart';
import '../widgets/web_output_preview.dart';

/// Route wiring and rendering for a captured, complete HTML reader.
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
  late final _reader = HtmlPreviewReader(
    download: widget.download,
    share: widget.share,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_reader.load());
  }

  Future<void> _share() async {
    final error = await _reader.share();
    if (mounted && error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: StudioError(error)));
    }
  }

  @override
  void dispose() {
    _reader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _reader,
    builder: (context, _) {
      final observation = _reader.observation;
      if (observation.source != null) {
        return WebOutputPreview(
          source: observation.source!,
          format: WebOutputFormat.html,
          title: widget.title,
          actionLabel: 'Save or share',
          onAction: observation.sharing ? null : _share,
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: Center(
            child: observation.loading
                ? const CircularProgressIndicator()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StudioError(observation.error!),
                        const SizedBox(height: 12),
                        if (!observation.hasFile)
                          OutlinedButton(
                            onPressed: _reader.load,
                            child: const Text('Try again'),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: observation.sharing ? null : _share,
                            icon: const Icon(Icons.ios_share),
                            label: const Text('Save or share'),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    },
  );
}
