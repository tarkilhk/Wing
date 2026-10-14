import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../cli.dart' as cli;
import '../model.dart';

const id = 'ARCH_FORM_CONFIRMATION_ACTIONS';
const owner = 'lib/core/widgets/studio_form_actions.dart';
const _retiredLabels = {
  'Cancel',
  'Save',
  'Save changes',
  'Save icon',
  'Save language',
  'Create task',
  'Apply',
  'Apply decisions',
  'Use in task',
  'Use model',
  'Save default',
  'Confirm',
  'Add',
};
const _buttons = {'TextButton', 'FilledButton', 'ElevatedButton'};

/// Rejects the concrete text-footers encountered during the family migration.
/// It does not infer a dynamic label's operation, async lifetime or reachability.
List<Finding> check(Snapshot snapshot) {
  final namespace = _Namespace(snapshot);
  final findings = <Finding>[];
  for (final source in snapshot.sources.values) {
    final visitor = _Buttons(namespace, source, findings);
    source.ast.accept(visitor);
  }
  return findings;
}

class _Buttons extends RecursiveAstVisitor<void> {
  _Buttons(this.namespace, this.source, this.findings);
  final _Namespace namespace;
  final Source source;
  final List<Finding> findings;

  (String, String?, ArgumentList)? call(Expression expression) {
    if (expression is InstanceCreationExpression) {
      final type = expression.constructorName.type;
      return (
        type.name.lexeme,
        type.importPrefix?.name.lexeme,
        expression.argumentList,
      );
    }
    if (expression is MethodInvocation) {
      final target = expression.target;
      if (target == null) {
        return (expression.methodName.name, null, expression.argumentList);
      }
      if (target is SimpleIdentifier) {
        if (_buttons.contains(expression.methodName.name) ||
            expression.methodName.name == 'Text') {
          return (
            expression.methodName.name,
            target.name,
            expression.argumentList,
          );
        }
        return (target.name, null, expression.argumentList);
      }
      if (target is PrefixedIdentifier) {
        return (
          target.identifier.name,
          target.prefix.name,
          expression.argumentList,
        );
      }
    }
    return null;
  }

  void inspect(Expression expression) {
    final invocation = call(expression);
    if (invocation == null ||
        !namespace.candidates.contains(invocation.$1) ||
        _locallyBound(expression, invocation.$2 ?? invocation.$1) ||
        !_buttons.contains(
          namespace.symbol(source.path, invocation.$1, prefix: invocation.$2),
        )) {
      return;
    }
    for (final argument
        in invocation.$3.arguments.whereType<NamedExpression>()) {
      if (!{'child', 'label'}.contains(argument.name.label.name)) continue;
      final text = call(argument.expression);
      if (text == null ||
          namespace.symbol(source.path, text.$1, prefix: text.$2) != 'Text') {
        continue;
      }
      final label = text.$3.arguments.firstOrNull;
      if (label is! StringLiteral ||
          !_retiredLabels.contains(label.stringValue)) {
        continue;
      }
      findings.add(
        Finding(
          id,
          source.path,
          source.lineAt(expression.offset),
          'text-footer:${label.stringValue}#${expression.offset}',
          'Use StudioFormActions for explicit draft confirmation; put operation names in tooltips and accessibility labels.',
        ),
      );
    }
  }

  bool _locallyBound(AstNode node, String name) {
    for (
      AstNode? ancestor = node.parent;
      ancestor != null;
      ancestor = ancestor.parent
    ) {
      final parameters = switch (ancestor) {
        FunctionExpression() => ancestor.parameters,
        MethodDeclaration() => ancestor.parameters,
        _ => null,
      };
      if (parameters?.parameters.any(
            (parameter) => parameter.name?.lexeme == name,
          ) ==
          true) {
        return true;
      }
      if (ancestor is Block) {
        for (final statement in ancestor.statements.where(
          (statement) => statement.offset < node.offset,
        )) {
          if (statement is VariableDeclarationStatement &&
              statement.variables.variables.any(
                (variable) => variable.name.lexeme == name,
              )) {
            return true;
          }
          if (statement is FunctionDeclarationStatement &&
              statement.functionDeclaration.name.lexeme == name) {
            return true;
          }
        }
      }
      if (ancestor is BlockClassBody &&
          ancestor.members.whereType<MethodDeclaration>().any(
            (method) => method.name.lexeme == name,
          )) {
        return true;
      }
    }
    return false;
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    inspect(node);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    inspect(node);
    super.visitMethodInvocation(node);
  }
}

// Follow actual authored library namespaces, including barrels, parts and
// import prefixes. Local declarations with the same spelling are unrelated.
class _Namespace {
  _Namespace(this.snapshot) {
    for (final source in snapshot.sources.values) {
      candidates.addAll(
        source.ast.declarations.whereType<GenericTypeAlias>().map(
          (alias) => alias.name.lexeme,
        ),
      );
    }
  }
  final Snapshot snapshot;
  final candidates = {..._buttons};
  final _units = <String, List<Source>>{};
  final _symbols = <String, String?>{};
  Iterable<Source> units(String path) => _units.putIfAbsent(
    snapshot.libraries[path] ?? path,
    () => snapshot.sources.values
        .where(
          (source) =>
              (snapshot.libraries[source.path] ?? source.path) ==
              (snapshot.libraries[path] ?? path),
        )
        .toList(),
  );
  String? symbol(
    String path,
    String name, {
    String? prefix,
    bool exported = false,
    Set<String> seen = const {},
  }) {
    final key = '$path:$name:$prefix:$exported';
    if (_symbols.containsKey(key)) return _symbols[key];
    final result = _lookup(
      path,
      name,
      prefix: prefix,
      exported: exported,
      seen: seen,
    );
    if (result != null || seen.isEmpty) _symbols[key] = result;
    return result;
  }

  String? _lookup(
    String path,
    String name, {
    String? prefix,
    bool exported = false,
    Set<String> seen = const {},
  }) {
    final key = '$path:$name:$prefix:$exported';
    if (seen.contains(key)) return null;
    final visited = {...seen, key};
    if (prefix == null) {
      for (final unit in units(path)) {
        for (final declaration in unit.ast.declarations) {
          if (declaration is FunctionDeclaration &&
              declaration.name.lexeme == name) {
            return null;
          }
          if (declaration is TopLevelVariableDeclaration &&
              declaration.variables.variables.any(
                (variable) => variable.name.lexeme == name,
              )) {
            return null;
          }
          if (declaration is ClassDeclaration &&
              declaration.namePart.typeName.lexeme == name) {
            return null;
          }
          if (declaration is GenericTypeAlias &&
              declaration.name.lexeme == name &&
              declaration.type is NamedType) {
            final type = declaration.type as NamedType;
            return symbol(
              unit.path,
              type.name.lexeme,
              prefix: type.importPrefix?.name.lexeme,
              seen: visited,
            );
          }
        }
      }
    }
    for (final unit in units(path)) {
      for (final directive
          in unit.ast.directives.whereType<NamespaceDirective>()) {
        if (exported && directive is! ExportDirective) continue;
        if (!exported &&
            directive is ImportDirective &&
            directive.prefix?.name != prefix) {
          continue;
        }
        if (!exported && directive is ExportDirective && prefix != null) {
          continue;
        }
        if (directive.combinators.any(
          (c) =>
              c is ShowCombinator && !c.shownNames.any((n) => n.name == name) ||
              c is HideCombinator && c.hiddenNames.any((n) => n.name == name),
        )) {
          continue;
        }
        final uris = [
          directive.uri.stringValue,
          for (final branch in directive.configurations) branch.uri.stringValue,
        ];
        for (final uri in uris) {
          if (uri != null && renderingUris.contains(uri)) return name;
          for (final dependency in unit.dependencies.where(
            (d) => d.uri == uri,
          )) {
            if (dependency.target case final target?) {
              final origin = symbol(
                target,
                name,
                exported: true,
                seen: visited,
              );
              if (origin != null) return origin;
            }
          }
        }
      }
    }
    return null;
  }
}

Future<void> main(List<String> arguments) =>
    cli.run([...arguments, '--strict'], {id: check});
