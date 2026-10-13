import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../cli.dart';
import '../model.dart';

const id = 'ARCH_LOADING_FAMILY';
const owner = 'lib/core/widgets/studio_loading.dart';
const desktopChatRows = 'lib/core/screens/profile_workspace_browser.dart';

/// Keeps page loading in Studio while preserving desktop chat-work borders.
List<Finding> check(Snapshot snapshot) {
  final findings = <Finding>[];
  for (final source in snapshot.sources.values) {
    final visitor = _LoadingCalls(
      allowRefreshMechanics: source.path == owner,
      allowDesktopChatRows: source.path == desktopChatRows,
    );
    source.ast.accept(visitor);
    for (final offset in visitor.offsets) {
      findings.add(
        Finding(
          id,
          source.path,
          source.lineAt(offset),
          'shared-owner',
          'Use StudioLoadingRegion or StudioPageLoading to report page progress to the shared header slot; keep StudioLoading for local media/status and StudioRefresh for gestures.',
        ),
      );
    }
  }
  return findings;
}

class _LoadingCalls extends RecursiveAstVisitor<void> {
  _LoadingCalls({
    required this.allowRefreshMechanics,
    required this.allowDesktopChatRows,
  });
  final bool allowRefreshMechanics;
  final bool allowDesktopChatRows;
  bool _forbidden(String? name) =>
      _names.contains(name) &&
      !(allowDesktopChatRows && name == 'ChatWorkingBorder');
  final offsets = <int>[];
  static const _names = {
    'LinearProgressIndicator',
    'CircularProgressIndicator',
    'CupertinoActivityIndicator',
    'RefreshIndicator',
    'ActivityShimmer',
    'ChatWorkingBorder',
    'StudioLoadingOverlay',
  };
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.toSource().split('.').last;
    final mechanics =
        allowRefreshMechanics &&
        type == 'RefreshIndicator' &&
        node.constructorName.name?.name == 'noSpinner';
    final contentPage =
        type == 'StudioLoading' && node.constructorName.name?.name == 'page';
    if (contentPage || (_forbidden(type) && !mechanics)) {
      offsets.add(node.offset);
    }
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final mechanics =
        allowRefreshMechanics &&
        node.methodName.name == 'noSpinner' &&
        node.target?.toSource().split('.').last == 'RefreshIndicator';
    final contentPage =
        node.methodName.name == 'page' &&
        node.target?.toSource().split('.').last == 'StudioLoading';
    if (contentPage ||
        (!mechanics &&
            (_forbidden(node.methodName.name) ||
                _forbidden(node.target?.toSource().split('.').last)))) {
      offsets.add(node.offset);
    }
    super.visitMethodInvocation(node);
  }
}

Future<void> main(List<String> args) => run(args, {id: check});
