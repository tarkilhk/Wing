import 'package:wing/core/widgets/studio_loading.dart';
import '../widgets/wing_app_bar.dart';
import '../widgets/studio_task_marker.dart';
import '../widgets/studio_error.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../services/web_preview.dart';
import '../widgets/web_link_scope.dart';

/// Bundled with the app so privacy information is available before connecting.
class PrivacyPolicyScreen extends StatefulWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  State<PrivacyPolicyScreen> createState() => _PrivacyPolicyScreenState();
}

class _PrivacyPolicyScreenState extends State<PrivacyPolicyScreen> {
  Future<String>? _policy;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _policy ??= DefaultAssetBundle.of(context).loadString('PRIVACY.md');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: WingAppBar(context: context, title: const Text('Privacy policy')),
    body: FutureBuilder<String>(
      future: _policy,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const StudioPageLoading.waiting(
            label: 'Loading privacy policy',
          );
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: StudioRetryNotice(
                message: 'Could not load the privacy policy.',
                onRetry: () => setState(() {
                  _policy = DefaultAssetBundle.of(
                    context,
                  ).loadString('PRIVACY.md');
                }),
              ),
            ),
          );
        }
        return Markdown(
          checkboxBuilder: (checked) => StudioTaskMarker(completed: checked),
          data: snapshot.data!,
          selectable: true,
          padding: const EdgeInsets.all(16),
          onTapLink: (_, href, _) async {
            final uri = href == null ? null : externalWebLink(href);
            if (uri == null) return;
            final opened = await WebLinkScope.open(context, uri);
            if (!opened && context.mounted) {
              showStudioError(context, 'Could not open the link.');
            }
          },
        );
      },
    ),
  );
}
