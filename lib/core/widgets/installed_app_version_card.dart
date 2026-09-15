import 'studio_error.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../services/web_preview.dart';
import 'playful_portrait.dart';

const _changelogUrl = 'https://github.com/tarkilhk/wing/blob/main/CHANGELOG.md';
const _releasesUrl = 'https://github.com/tarkilhk/wing/releases';

typedef AppVersionLinkOpener = Future<bool> Function(Uri uri);

/// Displays the installed application's identity from Android package metadata.
class InstalledAppVersionCard extends StatefulWidget {
  const InstalledAppVersionCard({super.key, this.openLink});

  final AppVersionLinkOpener? openLink;

  @override
  State<InstalledAppVersionCard> createState() =>
      _InstalledAppVersionCardState();
}

class _InstalledAppVersionCardState extends State<InstalledAppVersionCard> {
  late final Future<PackageInfo> _info = PackageInfo.fromPlatform();

  Future<void> _open(String href) async {
    final opened = await (widget.openLink ?? openWebPreview)(Uri.parse(href));
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: StudioError('Could not open this link.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: _info,
      builder: (context, snapshot) {
        final info = snapshot.data;
        if (snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                info == null)) {
          return const Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('App version'),
              subtitle: Text('Version information is unavailable.'),
            ),
          );
        }
        if (info == null) {
          return const Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('App version'),
              subtitle: Text('Loading version information…'),
            ),
          );
        }
        return Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const PlayfulPortrait(),
                title: Text(
                  info.appName.trim().isEmpty ? 'Android app' : info.appName,
                ),
                subtitle: Text('Version ${info.version}'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: () => _open(_changelogUrl),
                      child: const Text("What's new"),
                    ),
                    TextButton(
                      onPressed: () => _open(_releasesUrl),
                      child: const Text('Releases'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
