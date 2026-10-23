import 'package:flutter/material.dart';

import '../models/composer_reference.dart';
import 'conversation_reading_scope.dart';
import 'recent_conversations/conversation_gestures.dart';
import 'wing_app_bar.dart';

/// Conversation chrome. Execution and navigation authority stay with callers.
class ConversationPage extends StatelessWidget {
  const ConversationPage({
    super.key,
    this.scaffoldKey,
    this.drawer,
    required this.header,
    required this.body,
  });

  final GlobalKey<ScaffoldState>? scaffoldKey;
  final Widget? drawer;
  final WingAppBar header;
  final Widget body;

  @override
  Widget build(BuildContext context) => Scaffold(
    key: scaffoldKey,
    drawer: drawer,
    appBar: header,
    body: SafeArea(top: false, bottom: false, child: body),
  );
}

/// One transcript/footer arrangement, including read-only worker conversations.
class ConversationLayout extends StatelessWidget {
  const ConversationLayout({
    super.key,
    required this.transcript,
    this.contextHeader,
    this.footerBuilder,
  });

  final Widget transcript;
  final Widget? contextHeader;
  final Widget Function(BuildContext, BoxConstraints)? footerBuilder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final reading = ConversationReadingScope.maybeOf(context)?.active == true;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (contextHeader != null)
            Visibility(
              visible: !reading,
              maintainState: true,
              child: contextHeader!,
            ),
          Expanded(child: ConversationGestureBoundary(child: transcript)),
          if (footerBuilder != null)
            Visibility(
              visible: !reading,
              maintainState: true,
              child: footerBuilder!(context, constraints),
            ),
        ],
      );
    },
  );
}

/// Keeps suggestions loose and the action end of a tall footer reachable.
class ConversationFooter extends StatelessWidget {
  const ConversationFooter({
    super.key,
    required this.constraints,
    required this.child,
    this.suggestions,
    this.controller,
  });

  final BoxConstraints constraints;
  final Widget child;
  final Widget? suggestions;
  final TextEditingController? controller;

  Widget _content(BuildContext context) {
    final value = controller?.value;
    final querying =
        value != null &&
        MentionQuery.at(
              value.text,
              value.selection.extentOffset,
              collapsed: value.selection.isValid && value.selection.isCollapsed,
            ) !=
            null;
    final fullHeightComposer =
        ConversationReadingScope.keyboardOpen(context) &&
        (!querying || ConversationReadingScope.compact(context));
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: constraints.maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (suggestions != null) Flexible(child: suggestions!),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight:
                  constraints.maxHeight *
                  (fullHeightComposer
                      ? 1
                      : querying
                      ? .4
                      : .7),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: SafeArea(top: false, child: child),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => controller == null
      ? _content(context)
      : ListenableBuilder(
          listenable: controller!,
          builder: (context, _) => _content(context),
        );
}
