import 'package:wing/core/theme/wing_theme.dart';
import 'package:wing/core/widgets/studio_loading.dart';
import 'package:flutter/material.dart';
import '../theme/wing_icons.dart';

class AnswerActions extends StatelessWidget {
  final VoidCallback? onBranch;
  final VoidCallback? onRegenerate;
  final bool busy;
  final VoidCallback? onReadAloud;
  final bool readingAloud;

  const AnswerActions({
    super.key,
    this.onBranch,
    this.onRegenerate,
    this.busy = false,
    this.onReadAloud,
    this.readingAloud = false,
  });

  @override
  Widget build(BuildContext context) => StudioPageLoading(
    active: busy,
    label: 'Preparing answer',
    child: Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StudioButtonPress(
          child: IconButton(
            tooltip: 'Branch in new session',
            onPressed: onBranch,
            icon: const Icon(WingIcons.fork, size: 18),
          ),
        ),
        if (onReadAloud != null)
          StudioButtonPress(
            child: IconButton(
              tooltip: readingAloud ? 'Stop reading aloud' : 'Read aloud',
              onPressed: onReadAloud,
              icon: Icon(
                readingAloud ? Icons.stop : Icons.volume_up_outlined,
                size: 18,
              ),
            ),
          ),
        StudioButtonPress(
          child: IconButton(
            tooltip: 'Regenerate response',
            onPressed: onRegenerate,
            icon: const Icon(Icons.refresh),
          ),
        ),
      ],
    ),
  );
}
