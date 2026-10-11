import 'dart:typed_data';

import '../models/server_reference.dart';

import '../models/hermes_profile.dart';

typedef ReferenceRead =
    Future<Map<String, dynamic>> Function(
      String endpoint,
      Map<String, String> query,
    );
typedef ReferenceCall =
    Future<Map<String, dynamic>> Function(
      String method,
      Map<String, dynamic> params,
    );

/// Transport and canonical path admission only. The preparation owner decides
/// timing, budgets, cancellation and whole-message failure.
final class ComposerReferenceRepository {
  const ComposerReferenceRepository({required this.read, required this.call});
  final ReferenceRead read;
  final ReferenceCall call;
  Future<List<HermesProfile>> agents() async {
    final response = await read('profiles', const {});
    final rows = response['profiles'];
    if (rows is! List) {
      throw const FormatException('Agent list is unavailable.');
    }
    final agents = rows.map((row) {
      if (row is! Map) throw const FormatException('Invalid agent identity.');
      return HermesProfile.fromJson(Map<String, dynamic>.from(row));
    }).toList()..sort(HermesProfile.compareForDisplay);
    if (agents.map((p) => p.name).toSet().length != agents.length) {
      throw const FormatException('Duplicate agent identity.');
    }
    return List.unmodifiable(agents);
  }

  Future<ServerReferenceDirectory> directory(String? requested) async {
    if (requested != null) ServerReferencePath.admit(requested);
    final response = await read('files', {'path': ?requested});
    final path = response['path'],
        parent = response['parent'],
        rows = response['entries'];
    if (path is! String ||
        rows is! List ||
        (parent != null && parent is! String)) {
      throw const FormatException('Invalid server directory.');
    }
    ServerReferencePath.admit(path);
    if (parent is String) ServerReferencePath.admit(parent);
    final entries = <ServerReferenceEntry>[];
    for (final row in rows) {
      if (row is! Map ||
          row['name'] is! String ||
          row['path'] is! String ||
          row['is_directory'] is! bool) {
        throw const FormatException('Invalid server entry.');
      }
      final name = row['name'] as String, target = row['path'] as String;
      if (name.isEmpty ||
          ServerReferencePath.pathContext.basename(name) != name ||
          name == '.' ||
          name == '..') {
        throw const FormatException('Invalid server name.');
      }
      try {
        ServerReferencePath.admit(target);
      } on FormatException {
        continue;
      }
      if (row['broken_link'] == true) continue;
      final dir = row['is_directory'] as bool;
      if (!dir &&
          (row['size'] is! int ||
              (row['size'] as int) < 0 ||
              row['mime_type'] is! String)) {
        throw const FormatException('Invalid server file metadata.');
      }
      entries.add(
        ServerReferenceEntry(
          name: name,
          path: target,
          directory: dir,
          size: dir ? null : row['size'] as int,
          mime: dir ? null : row['mime_type'] as String,
        ),
      );
    }
    return ServerReferenceDirectory(path, parent as String?, entries);
  }

  Future<ServerReferenceEntry> entry(
    String path, {
    bool canonical = true,
    bool folder = false,
  }) async {
    ServerReferencePath.admit(path);
    if (folder) {
      final listing = await directory(path);
      if (canonical && listing.path != path) {
        throw const FormatException('The selected folder changed. Retry.');
      }
      return ServerReferenceEntry(
        name: ServerReferencePath.pathContext.basename(listing.path),
        path: listing.path,
        directory: true,
        size: null,
        mime: null,
      );
    }
    final listing = await directory(
      ServerReferencePath.pathContext.dirname(path),
    );
    // Selection has already resolved aliases; a later alias to another target
    // is not the selected location. Never read before this canonical preflight.
    return listing.entries
            .where(
              (e) =>
                  (!canonical || e.path == path) &&
                  e.name == ServerReferencePath.pathContext.basename(path),
            )
            .firstOrNull ??
        (throw FormatException(
          '$path is unavailable. Edit the reference and retry.',
        ));
  }

  Future<Uint8List> bytes(
    ServerReferenceEntry entry, {
    required int maxBytes,
  }) async {
    ServerReferencePath.admit(entry.path);
    if (entry.directory || entry.size == null || entry.size! > maxBytes) {
      throw FormatException(
        '${entry.name} is too large to include. Edit the reference.',
      );
    }
    final response = await read('files/read', {'path': entry.path});
    final target = response['path'],
        size = response['size'],
        data = response['data_url'];
    if (target is! String) {
      throw const FormatException('Missing canonical read target.');
    }
    ServerReferencePath.admit(target);
    if (target != entry.path ||
        size is! int ||
        size < 0 ||
        size > maxBytes ||
        data is! String ||
        data.length > maxBytes * 2 + 256) {
      throw const FormatException(
        'The file changed or exceeded the read limit. Retry.',
      );
    }
    final uri = UriData.parse(data);
    if (!uri.isBase64) {
      throw const FormatException('Invalid server file encoding.');
    }
    final bytes = uri.contentAsBytes();
    if (bytes.length != size) {
      throw const FormatException('Incomplete server file read.');
    }
    return bytes;
  }

  Future<List<String>?> ignoredFilePaths(
    String directory,
    String cwd, {
    required void Function() requireCurrent,
  }) async {
    ServerReferencePath.admit(directory);
    ServerReferencePath.admit(cwd);
    // Each page is framed. The stock stdout tail cap must never look complete.
    // Single-thread traversal keeps repeated pages in the same order.
    // Re-enumeration is checked with a checksum of the bounded first 200 hits.
    final scan =
        'cd ${_quote(cwd)} && rg --files --threads 1 -- ${_quote(directory)} | head -n 200';
    final paths = <String>[];
    String? fingerprint;
    for (var offset = 1; offset <= 200; offset += 8) {
      requireCurrent();
      final command =
          "printf 'WING_BEGIN\\n'; ($scan) | cksum; "
          "($scan) | sed -n '$offset,${offset + 7}p'; printf 'WING_END\\n'";
      final result = await call('shell.exec', {'command': command});
      requireCurrent();
      if (result['code'] != 0 ||
          result['stderr'] is! String ||
          (result['stderr'] as String).isNotEmpty) {
        return null;
      }
      final output = result['stdout'];
      if (output is! String ||
          !output.startsWith('WING_BEGIN\n') ||
          !output.endsWith('WING_END\n')) {
        throw const FormatException('Folder listing was incomplete. Retry.');
      }
      final lines = output.split('\n');
      final stamp = lines[1];
      if (!RegExp(r'^\d+ \d+$').hasMatch(stamp) ||
          fingerprint != null && fingerprint != stamp) {
        throw const FormatException('Folder changed while reading. Retry.');
      }
      fingerprint = stamp;
      final page = lines.sublist(2, lines.length - 2);
      for (final path in page) {
        ServerReferencePath.admit(path);
        if (!ServerReferencePath.pathContext.isWithin(directory, path) ||
            !paths.addUnique(path)) {
          throw const FormatException('Invalid folder listing. Retry.');
        }
      }
      if (page.length < 8) {
        return paths.isEmpty ? null : List.unmodifiable(paths);
      }
    }
    return List.unmodifiable(paths);
  }

  static String _quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
}

extension on List<String> {
  bool addUnique(String value) {
    if (contains(value)) return false;
    add(value);
    return true;
  }
}
