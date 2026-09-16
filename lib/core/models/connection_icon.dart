/// App-owned connection appearance. These names are persisted locally and in
/// configuration backups; they are never sent to Hermes.
enum ConnectionIcon {
  server,
  cloud,
  home,
  terminal,
  globe,
  database,
  rocket,
  beaker,
  repo,
  folder,
  star,
  target,
  lightbulb,
  book,
  bug,
  desktop;

  /// Connections and backups created before icon selection use Server.
  /// A present, unrecognized value is invalid rather than silently replaced.
  static ConnectionIcon fromStored(Object? value) {
    if (value == null) return ConnectionIcon.server;
    if (value is String) {
      for (final icon in values) {
        if (icon.name == value) return icon;
      }
    }
    throw const FormatException('Unrecognized connection icon.');
  }
}
