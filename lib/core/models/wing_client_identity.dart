/// Descriptive stock Hermes attribution. It grants no authentication or policy.
final class WingClientIdentity {
  WingClientIdentity({required String version})
    : wire = Map<String, String>.unmodifiable({
        'name': 'wing',
        'version': _validatedVersion(version),
        'kind': 'mobile',
      });

  final Map<String, String> wire;

  static String _validatedVersion(String version) {
    if (version.isEmpty ||
        version.length > 64 ||
        version.codeUnits.any((unit) => unit < 0x21 || unit > 0x7e)) {
      throw ArgumentError.value(version, 'version', 'Invalid client version');
    }
    return version;
  }
}
