import 'dart:io';

import '../dart_sdk.dart';
import '../rules/chat_runtime_observation.dart' as rule;
import '../proof_process.dart';

void require(bool value, String reason) {
  if (!value) throw StateError(reason);
}

const imports =
    "import '../models/chat_runtime.dart';\nimport 'chat_runtime.dart' as execution;\n";
const chat = '''class ProfileChat {
  final execution.ChatRuntime _runtime;
  ChatRuntimeObservation get runtime => _runtime.observation;
  ProfileChat(this._runtime);
}
''';

Future<void> main(List<String> args) =>
    withProofProcesses(() => _proofMain(args));

Future<void> _proofMain(List<String> args) async {
  require(
    args.isEmpty || args.length == 2 && args.first == '--original',
    'Use [--original ORIGINAL_SOURCE_ROOT]',
  );
  final root = Directory.systemTemp.createTempSync('wing-runtime-observation-');
  final sdk = dartSdkPath(Directory.current.path);
  var passed = 0;
  void write(String path, String content) {
    final file = File('${root.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  void reset({
    String? owner,
    String? model,
    Map<String, String> extra = const {},
  }) {
    final lib = Directory('${root.path}/lib');
    if (lib.existsSync()) lib.deleteSync(recursive: true);
    write(
      rule.model,
      model ??
          rule.stored.entries
              .map(
                (entry) =>
                    'class ${entry.key} {\n${entry.value.map((name) => 'final Object? $name = null;').join('\n')}\n}',
              )
              .join('\n'),
    );
    write(
      rule.runtime,
      "import '../models/chat_runtime.dart';\nclass ChatRuntime { ChatRuntimeObservation get observation => ChatRuntimeObservation(); }",
    );
    write(rule.owner, owner ?? imports + chat);
    for (final entry in extra.entries) {
      write(entry.key, entry.value);
    }
  }

  Future<void> verdict(int expected, String label, {String? subject}) async {
    try {
      final findings = await rule.check(root, sdkPath: sdk);
      require(
        expected != 2 && findings.isEmpty == (expected == 0),
        '$label: unexpected verdict $findings',
      );
      for (final finding in findings) {
        require(
          finding.id == rule.id &&
              finding.line > 0 &&
              {rule.owner, rule.model}.contains(finding.file),
          '$label: identity/location',
        );
      }
      if (subject != null) {
        require(
          findings.any((f) => f.subject == subject),
          '$label: missing $subject',
        );
      }
    } on FormatException {
      require(expected == 2, '$label: unexpected INPUT');
    } on FileSystemException {
      require(expected == 2, '$label: unexpected missing input');
    }
    passed++;
  }

  try {
    reset();
    await verdict(0, 'private owner and passive canonical getter');
    reset(
      owner:
          imports +
          chat.replaceAll(
            'ChatRuntimeObservation get',
            'ChatRuntimeObservation? get',
          ),
    );
    await verdict(1, 'nullable getter', subject: 'ProfileChat.runtime');
    reset(
      owner:
          imports +
          chat.replaceAll(
            'final execution.ChatRuntime',
            'execution.ChatRuntime',
          ),
    );
    await verdict(1, 'mutable owner', subject: 'ProfileChat._runtime');
    reset(
      owner:
          imports +
          chat
              .replaceAll(
                'final execution.ChatRuntime',
                'late final execution.ChatRuntime',
              )
              .replaceAll('ProfileChat(this._runtime);', 'ProfileChat();'),
    );
    await verdict(1, 'late final public write slot');
    reset(owner: 'class ProfileChat { String runtimeId = "old"; }');
    await verdict(
      1,
      'original owner lacks passive getter',
      subject: 'ProfileChat.runtime',
    );
    reset();
    final goodModel = File('${root.path}/${rule.model}').readAsStringSync();
    reset(
      model: goodModel.replaceFirst(
        'final Object? runtimeId',
        'Object? runtimeId',
      ),
    );
    await verdict(
      1,
      'mutable runtime fact',
      subject: 'ChatRuntimeObservation.runtimeId',
    );
    reset(
      model: goodModel.replaceFirst(
        'final Object? activityEntries',
        'Object? activityEntries',
      ),
    );
    await verdict(
      1,
      'mutable activity observation',
      subject: 'ChatRuntimeObservation.activityEntries',
    );
    reset(
      model: goodModel.replaceFirst(
        'final Object? activityEntries = null;',
        '',
      ),
    );
    await verdict(2, 'missing native activity observation');
    reset(
      model: goodModel.replaceFirst(
        'class ChatApproval {',
        'class ChatApproval { set other(Object? value) {}',
      ),
    );
    await verdict(1, 'fact setter', subject: 'ChatApproval.other');
    reset(
      model: goodModel.replaceFirst(
        'final Object? correlation = null;',
        'late final Object? correlation;',
      ),
    );
    await verdict(1, 'uninitialized late final fact');
    reset(
      model: goodModel.replaceFirst(
        'final Object? requestId = null;\nfinal Object? serverRequestId = null;',
        'Object? requestId, serverRequestId;',
      ),
    );
    await verdict(1, 'grouped mutable fact declarations');
    reset(
      owner:
          '$imports${chat}class WidgetState { Object? runtimeId; set runtime(Object? value) {} }',
      extra: {'lib/unrelated.dart': 'class ProfileChat { Object? runtimeId; }'},
    );
    await verdict(0, 'unrelated names and classes');
    reset(
      owner:
          "import '../models/chat_runtime.dart' as facts show ChatRuntimeObservation;\nimport 'barrel.dart' as execution;\n${chat.replaceAll('ChatRuntimeObservation get', 'facts.ChatRuntimeObservation get')}",
      extra: {
        'lib/core/services/barrel.dart':
            "export 'chat_runtime.dart' show ChatRuntime;",
      },
    );
    await verdict(0, 'prefix show and reexport runtime identity');
    reset(
      owner:
          '${imports}typedef Facts = ChatRuntimeObservation;\n${chat.replaceAll('ChatRuntimeObservation get', 'Facts get')}',
    );
    await verdict(0, 'canonical alias resolves to fact identity');
    reset(
      owner:
          "import '../models/chat_runtime.dart' hide ChatRuntimeObservation;\nimport 'chat_runtime.dart' as execution;\nclass ChatRuntimeObservation {}\n${chat.replaceAll('=> _runtime.observation', '=> ChatRuntimeObservation()')}",
    );
    await verdict(
      1,
      'same spelling wrong canonical type',
      subject: 'ProfileChat.runtime',
    );
    reset(
      owner:
          imports +
          chat.replaceAll('final execution.ChatRuntime', 'final Object'),
    );
    await verdict(1, 'wrong owner type', subject: 'ProfileChat._runtime');
    reset(
      owner:
          imports +
          chat.replaceFirst(
            'class ProfileChat {',
            "class ProfileChat { set runtime(ChatRuntimeObservation value) {}",
          ),
    );
    await verdict(1, 'runtime setter', subject: 'ProfileChat.runtime');
    reset(
      owner:
          imports +
          chat.replaceFirst(
            'class ProfileChat {',
            'class ProfileChat { final execution.ChatRuntime exposed = execution.ChatRuntime();',
          ),
    );
    await verdict(
      1,
      'public execution authority',
      subject: 'ProfileChat.exposed',
    );
    reset(
      owner:
          imports +
          chat.replaceFirst(
            'class ProfileChat {',
            'class ProfileChat { execution.ChatRuntime get exposed => _runtime;',
          ),
    );
    await verdict(1, 'public execution getter', subject: 'ProfileChat.exposed');
    reset(
      owner: "${imports}part 'chat_part.dart';\n$chat",
      extra: {
        'lib/core/services/chat_part.dart':
            "part of 'profile_workspace_controller.dart';\nclass UiState { Object? runtimeId; }",
      },
    );
    await verdict(0, 'unrelated controller part');
    reset(
      owner:
          imports +
          chat.replaceFirst(
            'class ProfileChat {',
            'class ProfileChat extends Other {',
          ),
    );
    await verdict(2, 'unknown inherited surface');
    reset(
      owner:
          imports +
          chat.replaceAll(
            'ChatRuntimeObservation get runtime => _runtime.observation;',
            '',
          ),
    );
    await verdict(
      1,
      'missing observation getter',
      subject: 'ProfileChat.runtime',
    );
    reset(
      model: goodModel.replaceFirst(
        'class ChatApproval',
        'class OtherApproval',
      ),
    );
    await verdict(2, 'missing canonical fact authority');
    reset();
    write(rule.runtime, 'class OtherRuntime {}');
    await verdict(2, 'missing canonical runtime authority');
    reset(
      owner:
          "import 'other.dart' if (dart.library.io) 'alternate.dart';\n$imports$chat",
    );
    await verdict(2, 'conditional canonical owner input');
    reset();
    File('${root.path}/${rule.model}').deleteSync();
    await verdict(2, 'missing model file');
    if (args.isNotEmpty) {
      reset(owner: File('${args.last}/${rule.owner}').readAsStringSync());
      await verdict(
        1,
        'actual original production owner',
        subject: 'ProfileChat.runtime',
      );
    }
    final executable = File(
      'tools/architecture/rules/chat_runtime_observation.dart',
    ).absolute.path;
    for (final expected in [0, 1, 2]) {
      reset(
        owner:
            imports +
            (switch (expected) {
              1 => chat.replaceAll(
                'ChatRuntimeObservation get runtime => _runtime.observation;',
                '',
              ),
              2 => chat.replaceAll('class ProfileChat', 'class OtherChat'),
              _ => chat,
            }),
      );
      final result = await runProofProcess('$sdk/bin/dart', [
        'run',
        executable,
        '--root',
        root.path,
        '--sdk',
        sdk,
      ]);
      require(
        result.exitCode == expected,
        'CLI $expected: ${result.stdout}\n${result.stderr}',
      );
      if (expected == 1) {
        require(
          '${result.stdout}'.contains('[${rule.id}]') &&
              '${result.stdout}'.contains('ProfileChat.runtime'),
          'CLI finding identity',
        );
      }
      if (expected == 2) {
        require(
          '${result.stderr}'.contains('[${rule.id} INPUT]'),
          'CLI input identity',
        );
      }
      passed++;
    }
    stdout.writeln(
      '${rule.id}: $passed finite fixtures and source CLI exits passed',
    );
  } finally {
    root.deleteSync(recursive: true);
  }
}
