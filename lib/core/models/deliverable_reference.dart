import 'package:markdown/markdown.dart' as md;

import 'chat_output.dart';
import 'media_reference.dart';

const deliverableElementTag = 'wing-deliverable';

md.Element _fileElement(ChatOutput output) =>
    md.Element.empty(deliverableElementTag)
      ..attributes['path'] = output.path!
      ..attributes['name'] = output.label
      ..attributes['fragment'] = output.fragment ?? ''
      ..attributes['kind'] = output.kind.name;

/// Uses the Markdown parser for links, so labels, escaped destinations,
/// reference links, and surrounding prose keep normal Markdown semantics.
class DeliverableLinkSyntax extends md.LinkSyntax {
  @override
  md.Node createNode(
    String destination,
    String? title, {
    required List<md.Node> Function() getChildren,
  }) {
    final output = explicitRemoteFileOutput(destination);
    if (output == null) {
      return super.createNode(destination, title, getChildren: getChildren);
    }
    getChildren();
    return _fileElement(output);
  }
}

/// A complete file path in inline code is a deliverable, just like a file link.
/// Let the Markdown code parser own delimiters and ordinary code semantics.
class DeliverableCodeSyntax extends md.CodeSyntax {
  static final _path = RegExp(
    r'^(?:/|~[\\/]|\.\.?[\\/]|[A-Za-z]:[\\/]|\\\\)'
    r'[^\r\n<>|]*[^\\/\s]\.\w+$',
  );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    var code = match[2]!;
    if (code.length > 1 && code.startsWith(' ') && code.endsWith(' ')) {
      code = code.substring(1, code.length - 1);
    }
    if (_path.hasMatch(code)) {
      // Code spans contain literal filenames, not URL-encoded destinations.
      final output = mediaRemoteFileOutput(code);
      if (output != null) {
        parser.addNode(_fileElement(output));
        return true;
      }
    }
    return super.onMatch(parser, match);
  }
}

/// HTML reports are often returned as plain paths rather than Markdown links.
/// Require a path prefix and token boundaries so URLs and filename mentions
/// keep their Markdown meaning. Code spans and fences own their own contents.
class HtmlFilePathSyntax extends md.InlineSyntax {
  HtmlFilePathSyntax()
    : super(
        r'''(?<![^\s("'*])(?:/|~[\\/]|\.\.?[\\/]|[A-Za-z]:[\\/]|\\\\)'''
        r'''[^\s<>"'`*|]*\.html?(?=$|[\s<>"'`*,;:)\]}]|[.!?](?=\s|$))''',
        caseSensitive: false,
      );

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final output = mediaRemoteFileOutput(match[0]!);
    parser.addNode(output == null ? md.Text(match[0]!) : _fileElement(output));
    return true;
  }
}

class MediaReferenceSyntax extends md.InlineSyntax {
  MediaReferenceSyntax() : super(mediaReferencePattern, caseSensitive: false);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final target = mediaReferenceTarget(match.group(1)!);
    final output = mediaRemoteFileOutput(target);
    if (output == null) {
      parser.addNode(md.Text(match.group(0)!));
      return true;
    }
    parser.addNode(_fileElement(output));
    return true;
  }
}
