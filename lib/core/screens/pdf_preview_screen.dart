import '../widgets/studio_error.dart';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/pdf_preview_service.dart';
import '../services/connection_manager.dart';
import '../services/remote_files_client.dart';

class PdfPreviewScreen extends StatefulWidget {
  final String title;
  final Future<RemoteFileDownload> Function() download;
  final PdfPreviewService service;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.download,
    this.service = const PdfPreviewService(),
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  RemoteFileDownload? _file;
  PdfDocument? _document;
  Uint8List? _pageImage;
  int _page = 0;
  bool _loading = true;
  bool _failed = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      _file ??= await widget.download();
      if (!mounted) return;
      if (_document == null) {
        final document = await widget.service.open(_file!.bytes);
        if (!mounted) {
          await widget.service.close(document);
          return;
        }
        _document = document;
      }
      final image = await widget.service.render(_document!, _page);
      if (mounted) setState(() => _pageImage = image);
    } catch (error) {
      if (mounted) {
        setState(() {
          _failed = true;
          _errorMessage = error is DashboardResponseTooLargeException
              ? 'This PDF exceeds the ${(error.maxBytes / (1024 * 1024)).round()} MiB download limit.'
              : null;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showPage(int page) {
    if (_loading) return;
    setState(() {
      _page = page;
      _pageImage = null;
      _failed = false;
      _errorMessage = null;
      _loading = true;
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    final document = _document;
    if (document != null) unawaited(widget.service.close(document));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: SafeArea(
      child: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _failed
            ? SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StudioError(
                      _errorMessage ??
                          'This PDF could not be displayed. Go back to open it in '
                              'another app, or save/share it.',
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _showPage(_page),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              )
            : InteractiveViewer(
                key: ValueKey(_page),
                minScale: 1,
                maxScale: 5,
                child: Image.memory(
                  _pageImage!,
                  fit: BoxFit.contain,
                  semanticLabel: 'PDF page ${_page + 1}',
                  errorBuilder: (_, _, _) => const Text(
                    'This page could not be displayed. Go back for file options.',
                  ),
                ),
              ),
      ),
    ),
    bottomNavigationBar: _document == null
        ? null
        : SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    onPressed: _loading || _page == 0
                        ? null
                        : () => _showPage(_page - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      'Page ${_page + 1} of ${_document!.pageCount}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    onPressed: _loading || _page + 1 >= _document!.pageCount
                        ? null
                        : () => _showPage(_page + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
          ),
  );
}
