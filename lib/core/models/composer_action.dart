enum ComposerAction {
  send('Send'),
  steer('Steer'),
  stop('Stop'),
  queue('Queue'),
  fork('Fork');

  const ComposerAction(this.label);
  final String label;

  static const runningDefaults = [steer, queue, stop];
}
