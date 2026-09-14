import 'package:flutter/material.dart';

import '../services/image_clipboard.dart';

/// Keeps normal text actions and uses Paste for images when one is available.
class ImagePasteMenu extends StatefulWidget {
  final EditableTextState editableText;
  final VoidCallback onPasteImage;

  const ImagePasteMenu({
    super.key,
    required this.editableText,
    required this.onPasteImage,
  });

  @override
  State<ImagePasteMenu> createState() => _ImagePasteMenuState();
}

class _ImagePasteMenuState extends State<ImagePasteMenu> {
  late final _hasImage = ImageClipboard.hasImage();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasImage,
      builder: (context, snapshot) {
        final items = [...widget.editableText.contextMenuButtonItems];
        if (snapshot.data == true) {
          final paste = ContextMenuButtonItem(
            type: ContextMenuButtonType.paste,
            onPressed: () {
              widget.editableText.hideToolbar();
              widget.onPasteImage();
            },
          );
          final index = items.indexWhere(
            (item) => item.type == ContextMenuButtonType.paste,
          );
          if (index < 0) {
            items.add(paste);
          } else {
            items[index] = paste;
          }
        }
        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: widget.editableText.contextMenuAnchors,
          buttonItems: items,
        );
      },
    );
  }
}
