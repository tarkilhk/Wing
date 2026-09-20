import 'package:markdown/markdown.dart' as md;

import 'chat_output.dart';
import 'media_reference.dart';

const deliverableElementTag = 'wing-deliverable';

md.Element _fileElement(ChatOutput output) =>
    md.Element.empty(deliverableElementTag)
      ..attributes['path'] = output.path!
      ..attributes['name'] = output.label
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
