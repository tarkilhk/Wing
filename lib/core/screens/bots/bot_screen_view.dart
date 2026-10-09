import 'package:flutter/material.dart';
import '../../services/bot_screen_session.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/wing_app_bar.dart';

class BotScreenView extends StatefulWidget {
  const BotScreenView({super.key, required this.createSession});
  final BotScreenSession Function() createSession;
  @override
  State<BotScreenView> createState() => _BotScreenViewState();
}

class _BotScreenViewState extends State<BotScreenView>
    with WidgetsBindingObserver {
  late final _session = widget.createSession();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_changed);
    _session.setVisible(true);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _session.setVisible(state == AppLifecycleState.resumed);
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_changed);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: WingAppBar(
      context: context,
      title: Text('${_session.bot.title} screen'),
      actions: [
        IconButton(
          tooltip: 'Refresh screen',
          onPressed: _session.busy ? null : _session.refresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Start screen',
          onPressed: _session.busy ? null : () => _session.power(true),
          icon: const Icon(Icons.play_arrow_outlined),
        ),
        IconButton(
          tooltip: 'Stop screen',
          onPressed: _session.busy ? null : () => _session.power(false),
          icon: const Icon(Icons.stop_outlined),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${_session.bot.instance} · ${_session.bot.profile.name}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (_session.busy) const LinearProgressIndicator(),
        if (_session.error != null) StudioError(_session.error!),
        if (_session.frame?.image case final image?)
          InteractiveViewer(child: Image.memory(image, fit: BoxFit.contain))
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 64),
            child: Center(
              child: Text(
                _session.frame?.suppressed == true
                    ? 'Someone is controlling this screen. Preview is paused for privacy.'
                    : 'No screen frame yet. Start the bot’s screen to view it.',
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'Screen preview refreshes while this page is open. Keyboard and pointer control remain in desktop.',
        ),
      ],
    ),
  );
}
