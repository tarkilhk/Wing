enum ComposerAction {
  send('Send'),
  steer('Steer'),
  stop('Stop'),
  queue('Queue'),
  fork('Fork');

  const ComposerAction(this.label);
  final String label;

  static const preferenceKey = 'composer_running_action';
  static const runningDefaults = [steer, queue, stop];

  static ComposerAction fromPreference(String? value) =>
      runningDefaults.where((action) => action.name == value).firstOrNull ??
      steer;
}
