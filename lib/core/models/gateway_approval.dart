enum GatewayApprovalChoice {
  once('once'),
  session('session'),
  always('always'),
  deny('deny');

  final String wireValue;

  const GatewayApprovalChoice(this.wireValue);

  static GatewayApprovalChoice? fromWireValue(String value) {
    for (final choice in values) {
      if (choice.wireValue == value) return choice;
    }
    return null;
  }
}

/// Ordered, request-correlated approvals for one runtime session. Replays update
/// an existing entry rather than replacing whichever command is being reviewed.
class GatewayApprovalQueue {
  final List<Map<String, dynamic>> _requests = [];
  int total = 0;
  int revision = 0;

  List<Map<String, dynamic>> get requests => List.unmodifiable(_requests);
  int get position => total - _requests.length + 1;

  bool add(Map<String, dynamic> request) {
    final id = request['request_id'];
    if (id is! String || id.isEmpty) return false;
    final index = _requests.indexWhere((item) => item['request_id'] == id);
    revision++;
    if (index >= 0) {
      _requests[index] = {..._requests[index], ...request};
      return false;
    }
    if (_requests.isEmpty) total = 0;
    _requests.add(Map.of(request));
    total++;
    return true;
  }

  void remove(String id) {
    _requests.removeWhere((item) => item['request_id'] == id);
    revision++;
    if (_requests.isEmpty) total = 0;
  }

  void clear() {
    _requests.clear();
    total = 0;
    revision++;
  }

  void reconcile(List<Map<String, dynamic>> requests) {
    final ids = requests.map((request) => request['request_id']).toSet();
    _requests.removeWhere((request) => !ids.contains(request['request_id']));
    for (final request in requests) {
      add(request);
    }
    if (_requests.isEmpty) total = 0;
    revision++;
  }
}

enum GatewayApprovalKind { command, access, network, invalid }

enum GatewayApprovalAccess { read, readWrite, invalid }

/// One decoded consent subject. Raw names retain exact bytes; display names
/// expose invisible characters without changing the target being authorized.
class GatewayApprovalRequest {
  final String command;
  final String description;
  final bool allowPermanent;
  final bool smartDenied;
  final List<GatewayApprovalChoice> choices;
  final GatewayApprovalKind kind;
  final String? path, host, label, risk;
  final GatewayApprovalAccess? access;

  GatewayApprovalRequest._({
    required this.command,
    required this.description,
    required this.allowPermanent,
    required this.smartDenied,
    required Iterable<GatewayApprovalChoice> choices,
    this.kind = GatewayApprovalKind.command,
    this.path,
    this.host,
    this.label,
    this.risk,
    this.access,
  }) : choices = List.unmodifiable(choices);

  bool get isSandbox =>
      kind == GatewayApprovalKind.access || kind == GatewayApprovalKind.network;
  bool get valid => switch (kind) {
    GatewayApprovalKind.command => true,
    GatewayApprovalKind.access =>
      path != null &&
          path!.trim().isNotEmpty &&
          access != GatewayApprovalAccess.invalid,
    GatewayApprovalKind.network => host != null && host!.trim().isNotEmpty,
    GatewayApprovalKind.invalid => false,
  };
  String get title => switch (kind) {
    GatewayApprovalKind.command => 'Review command',
    GatewayApprovalKind.access => 'Review folder access',
    GatewayApprovalKind.network => 'Review website access',
    GatewayApprovalKind.invalid => 'Invalid approval request',
  };
  String get subject => switch (kind) {
    GatewayApprovalKind.access => path ?? '',
    GatewayApprovalKind.network => host ?? '',
    _ => command,
  };
  String get displaySubject => isSandbox ? displayName(subject) : subject;
  String? get accessLabel => switch (access) {
    GatewayApprovalAccess.read => 'Read only',
    GatewayApprovalAccess.readWrite => 'Read and write',
    null || GatewayApprovalAccess.invalid => null,
  };
  String get scopeDescription =>
      'Access lasts until the sandbox is switched off.';
  String get notificationPreview => isSandbox
      ? '$title\n$displaySubject${accessLabel == null ? '' : ' · $accessLabel'}'
      : command;
  String choiceLabel(GatewayApprovalChoice choice) => switch (choice) {
    GatewayApprovalChoice.once =>
      isSandbox ? 'Allow until sandbox is switched off' : 'Approve once',
    GatewayApprovalChoice.session => 'Approve for session',
    GatewayApprovalChoice.always =>
      isSandbox ? 'Save access rule' : 'Always approve',
    GatewayApprovalChoice.deny => 'Reject',
  };
  String choiceScope(GatewayApprovalChoice choice) => switch (choice) {
    GatewayApprovalChoice.once =>
      isSandbox ? scopeDescription : 'Allow this request once.',
    GatewayApprovalChoice.session =>
      'Allow matching commands for this session.',
    GatewayApprovalChoice.always =>
      isSandbox
          ? 'Save this access rule for future use.'
          : 'Permanently allow matching commands, including in future chats.',
    GatewayApprovalChoice.deny =>
      isSandbox
          ? 'Reject this access request.'
          : 'Reject this request. The command will not run.',
  };

  /// Only the server-request access/network protocol accepts a denial reason.
  Map<String, dynamic> answer(String choice, {String? reason}) {
    if (!choices.any((item) => item.wireValue == choice) ||
        (!valid && choice != 'deny')) {
      throw ArgumentError('Approval choice is unavailable');
    }
    return {
      'choice': choice,
      if (isSandbox &&
          choice == 'deny' &&
          reason != null &&
          reason.trim().isNotEmpty)
        'reason': reason.trim(),
    };
  }

  Map<String, dynamic> get subjectFields => {
    'kind': kind.name,
    'path': path,
    'host': host,
    'label': label,
    'risk': risk,
    'access': switch (access) {
      GatewayApprovalAccess.read => 'read',
      GatewayApprovalAccess.readWrite => 'read_write',
      GatewayApprovalAccess.invalid => 'invalid',
      null => null,
    },
  };

  factory GatewayApprovalRequest.fromEventData(Map<String, dynamic> data) {
    final kind = switch (data['kind']) {
      null || 'command' => GatewayApprovalKind.command,
      'access' => GatewayApprovalKind.access,
      'network' => GatewayApprovalKind.network,
      _ => GatewayApprovalKind.invalid,
    };
    final smartDenied = data['smart_denied'] == true;
    final allowSession = data['allow_session'] != false && !smartDenied;
    final allowPermanent =
        data['allow_permanent'] != false &&
        !smartDenied &&
        (kind == GatewayApprovalKind.access ||
            kind == GatewayApprovalKind.network ||
            allowSession);
    String? string(String key) =>
        data[key] is String ? data[key] as String : null;
    final request = GatewayApprovalRequest._(
      kind: kind,
      command: string('command') ?? '',
      description: string('description') ?? '',
      path: string('path'),
      host: string('host'),
      label: string('label'),
      risk: string('risk'),
      access: switch (data['access']) {
        'read' => GatewayApprovalAccess.read,
        'read_write' => GatewayApprovalAccess.readWrite,
        null => null,
        _ => GatewayApprovalAccess.invalid,
      },
      allowPermanent: allowPermanent,
      smartDenied: smartDenied,
      choices: const [],
    );
    final choices = <GatewayApprovalChoice>[];
    for (final raw
        in data['choices'] is List ? data['choices'] as List : const []) {
      final choice = raw is String
          ? GatewayApprovalChoice.fromWireValue(raw)
          : null;
      if (choice == null || choices.contains(choice)) continue;
      if (!request.valid && choice != GatewayApprovalChoice.deny) continue;
      if (choice == GatewayApprovalChoice.session &&
          (!allowSession || request.isSandbox)) {
        continue;
      }
      if (choice == GatewayApprovalChoice.always && !allowPermanent) continue;
      choices.add(choice);
    }
    return GatewayApprovalRequest._(
      kind: kind,
      command: request.command,
      description: request.description,
      path: request.path,
      host: request.host,
      label: request.label,
      risk: request.risk,
      access: request.access,
      allowPermanent: allowPermanent,
      smartDenied: smartDenied,
      choices: choices,
    );
  }

  static String displayName(String value) {
    final runes = value.runes.toList();
    final first = runes.indexWhere((c) => c != 0x20);
    final last = runes.lastIndexWhere((c) => c != 0x20);
    return [
      for (var i = 0; i < runes.length; i++)
        if (runes[i] == 0x20 && (i < first || i > last))
          '␣'
        else if (_hidden(runes[i]))
          _escape(runes[i])
        else
          String.fromCharCode(runes[i]),
    ].join();
  }

  static String _escape(int c) => c < 0x100
      ? '\\x${c.toRadixString(16).padLeft(2, '0')}'
      : c < 0x10000
      ? '\\u${c.toRadixString(16).padLeft(4, '0')}'
      : '\\U${c.toRadixString(16).padLeft(8, '0')}';
  static final _hiddenCharacters = RegExp(
    r'[\p{C}\p{Zl}\p{Zp}\p{Default_Ignorable_Code_Point}\u2800]',
    unicode: true,
  );
  static final _lookalikeSpaces = RegExp(r'[\p{Zs}\u2423]', unicode: true);
  static bool _hidden(int c) =>
      c == 0x5c ||
      _hiddenCharacters.hasMatch(String.fromCharCode(c)) ||
      (c != 0x20 && _lookalikeSpaces.hasMatch(String.fromCharCode(c)));
}
