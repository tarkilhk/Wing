import 'dart:convert';

enum GatewayTodoStatus { pending, inProgress, completed, cancelled }

class GatewayTodo {
  final String id;
  final String content;
  final String? parent;
  final GatewayTodoStatus status;

  const GatewayTodo({
    required this.id,
    required this.content,
    required this.status,
    this.parent,
  });
}

class GatewayTodoSnapshot {
  final int? revision;
  final List<GatewayTodo> todos;

  const GatewayTodoSnapshot({required this.revision, required this.todos});

  static GatewayTodoSnapshot? parse(dynamic value) {
    final record = _record(value);
    if (record == null || !record.containsKey('todos')) return null;
    final rawTodos = _decoded(record['todos']);
    if (rawTodos is! List) return null;
    final todos = <GatewayTodo>[];
    for (final raw in rawTodos) {
      final item = _record(raw);
      if (item == null) continue;
      final id = item['id']?.toString().trim() ?? '';
      final content = item['content']?.toString().trim() ?? '';
      final status = switch (item['status']?.toString()) {
        'pending' => GatewayTodoStatus.pending,
        'in_progress' => GatewayTodoStatus.inProgress,
        'completed' => GatewayTodoStatus.completed,
        'cancelled' => GatewayTodoStatus.cancelled,
        _ => null,
      };
      if (id.isEmpty || content.isEmpty || status == null) continue;
      final parent = item['parent']?.toString().trim();
      todos.add(
        GatewayTodo(
          id: id,
          content: content,
          status: status,
          parent: parent == null || parent.isEmpty || parent == id
              ? null
              : parent,
        ),
      );
    }
    final revision = record['revision'];
    return GatewayTodoSnapshot(
      revision: revision is num && revision.isFinite && revision >= 0
          ? revision.toInt()
          : null,
      todos: todos,
    );
  }

  static dynamic _decoded(dynamic value) {
    if (value is! String) return value;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic>? _record(dynamic value) {
    final decoded = _decoded(value);
    if (decoded is! Map) return null;
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  }
}
