import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../cli.dart';
import '../model.dart';

const id = 'ARCH_LOADING_FAMILY';
const owner = 'lib/core/widgets/studio_loading.dart';

/// Keeps all asynchronous loading visuals in the Studio loading family.
List<Finding> check(Snapshot snapshot) {
  final findings = <Finding>[];
  for (final source in snapshot.sources.values) {
    final visitor = _LoadingCalls(allowRefreshMechanics: source.path == owner);
    source.ast.accept(visitor);
    for (final offset in visitor.offsets) {
      findings.add(
        Finding(
          id,
          source.path,
          source.lineAt(offset),
          'shared-owner',
          'Use StudioLoading for local work, StudioLoadingRegion for content, or StudioRefresh for pull refresh.',
        ),
      );
    }
  }
  return findings;
}

class _LoadingCalls extends RecursiveAstVisitor<void> {
  _LoadingCalls({required this.allowRefreshMechanics});
  final bool allowRefreshMechanics;
  final offsets = <int>[];
  static const _names = {
    'LinearProgressIndicator',
    'CircularProgressIndicator',
    'CupertinoActivityIndicator',
    'RefreshIndicator',
  };
  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    final type = node.constructorName.type.toSource().split('.').last;
    final mechanics =
        allowRefreshMechanics &&
        type == 'RefreshIndicator' &&
        node.constructorName.name?.name == 'noSpinner';
    if (_names.contains(type) && !mechanics) offsets.add(node.offset);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final mechanics =
        allowRefreshMechanics &&
        node.methodName.name == 'noSpinner' &&
        node.target?.toSource().split('.').last == 'RefreshIndicator';
    if (!mechanics &&
        (_names.contains(node.methodName.name) ||
            _names.contains(node.target?.toSource().split('.').last))) {
      offsets.add(node.offset);
    }
    super.visitMethodInvocation(node);
  }
}

Future<void> main(List<String> args) => run(args, {id: check});
