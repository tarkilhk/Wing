import 'answer_versions.dart';

/// An attachment in a sent user message. Paths always belong to the server.
class UserMessageAttachment {
  final String name;
  final String target;
  final bool isImage;

  const UserMessageAttachment({
    required this.name,
    required this.target,
    required this.isImage,
  });

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot > 0 && dot < name.length - 1
        ? name.substring(dot + 1).toUpperCase()
        : 'FILE';
  }
}

/// Keeps attachment bytes and server references out of the visible prose.
/// Copy/edit/replay continue to use the original message projection.
class UserMessageContent {
  final String text;
  final List<UserMessageAttachment> attachments;

  const UserMessageContent(this.text, this.attachments);

  factory UserMessageContent.fromMessage(Map<String, dynamic> message) {
    final attachments = <UserMessageAttachment>[];
    final seen = <String>{};
    void add(String target, bool isImage, [String? name]) {
      if (target.isEmpty || !seen.add(target)) return;
      final uri = target.startsWith('data:') ? null : Uri.tryParse(target);
      final leaf = target.startsWith('data:')
          ? ''
          : (uri?.pathSegments.lastOrNull ??
                target.split(RegExp(r'[/\\]')).last);
      attachments.add(
        UserMessageAttachment(
          name: name?.trim().isNotEmpty == true
              ? name!
              : leaf.isNotEmpty
              ? leaf
              : isImage
              ? 'Image'
              : 'File',
          target: target,
          isImage: isImage,
        ),
      );
    }

    final submitted = message['submitted_attachments'];
    if (submitted is List<UserMessageAttachment>) {
      for (final attachment in submitted) {
        add(attachment.target, attachment.isImage, attachment.name);
      }
    }

    Object? withoutImages(Object? value) {
      if (value is List) return value.map(withoutImages).toList();
      if (value is! Map) return value;
      if (!{'image_url', 'input_image', 'image'}.contains(value['type'])) {
        return value;
      }
      final image = value['image_url'];
      final target = image is Map ? image['url'] : image ?? value['url'];
      add(
        target is String ? target : '',
        true,
        value['name'] is String ? value['name'] as String : null,
      );
      return '';
    }

    // Read saved image parts even when the gateway supplies a separate caption.
    final content = withoutImages(message['content'] ?? message['text']);
    final display = withoutImages(message['display_content']);
    var text = answerMessageDisplayText({
      ...message,
      'content': content,
      'display_content': display,
    });
    // Gateway file uploads prepend one reference per line. Only those complete
    // lines become cards; references quoted or discussed in prose stay intact.
    text = text.replaceAllMapped(_referenceLine, (match) {
      var target = match.group(2)!;
      if (target.startsWith('"') ||
          target.startsWith("'") ||
          target.startsWith('`')) {
        target = target.substring(1, target.length - 1);
      }
      add(target, match.group(1) == 'image');
      return '';
    }).trim();
    return UserMessageContent(text, List.unmodifiable(attachments));
  }
}

final _referenceLine = RegExp(
  r'''^[ \t]*@(file|image):("[^"\n]+"|'[^'\n]+'|`[^`\n]+`|\S+)[ \t]*\r?$''',
  multiLine: true,
);
