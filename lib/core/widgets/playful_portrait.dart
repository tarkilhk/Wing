import 'package:flutter/material.dart';

/// Shared app identity. Adjacent text supplies the accessible name.
class PlayfulPortrait extends StatelessWidget {
  const PlayfulPortrait({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      // Brand artwork keeps its launcher silhouette, independent of controls.
      borderRadius: BorderRadius.circular(size * .22),
      child: Image.asset(
        'assets/icon/icon.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
        filterQuality: FilterQuality.medium,
      ),
    ),
  );
}
