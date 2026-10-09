import 'package:flutter/material.dart';
import '../../models/bots.dart';
import '../../services/bot_profile_edit_session.dart';
import '../../theme/profile_colors.dart';
import '../../widgets/bot_avatar.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/wing_app_bar.dart';
import 'bot_settings_screen.dart';

class BotProfileEditor extends StatefulWidget {
  const BotProfileEditor({super.key, required this.createSession});
  final BotProfileEditSession Function() createSession;
  @override
  State<BotProfileEditor> createState() => _BotProfileEditorState();
}

class _BotProfileEditorState extends State<BotProfileEditor> {
  late final _session = widget.createSession();
  late final _title = TextEditingController(text: _session.title);
  final _prompt = TextEditingController();
  bool _allowPop = false;
  @override
  void initState() {
    super.initState();
    _session.addListener(_changed);
  }

  void _changed() {
    if (mounted) {
      if (_title.text != _session.title) _title.text = _session.title;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _session.removeListener(_changed);
    _session.dispose();
    _title.dispose();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final saved = await _session.save();
    if (mounted && saved) {
      setState(() => _allowPop = true);
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowPop || !_session.dirty && !_session.busy,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || _session.busy) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard edits?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (mounted && discard == true) {
        setState(() => _allowPop = true);
        Navigator.pop(this.context);
      }
    },
    child: Scaffold(
      appBar: WingAppBar(
        context: context,
        title: const Text('Edit bot'),
        actions: [
          IconButton(
            tooltip: 'Reload saved appearance',
            onPressed: _session.busy ? null : _session.reload,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: 'Save appearance',
            onPressed: _session.busy || _session.conflicted ? null : _save,
            icon: const Icon(Icons.check),
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
          if (_session.busy) const LinearProgressIndicator(),
          if (_session.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: StudioError(_session.error!),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: BotAvatar(
                name: _session.bot.profile.name,
                shape: _session.shape,
                color: _session.color,
                image: _session.image,
                size: 88,
              ),
            ),
          ),
          TextField(
            controller: _title,
            enabled: !_session.busy,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Bot name'),
            onChanged: (text) => _session.change(title: text),
          ),
          const SizedBox(height: 24),
          Text('Shape', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final shape in botShapes)
                IconButton(
                  tooltip: shape,
                  isSelected: _session.shape == shape,
                  style: IconButton.styleFrom(
                    backgroundColor: _session.shape == shape
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                  ),
                  onPressed: _session.busy
                      ? null
                      : () => _session.change(shape: shape),
                  icon: BotAvatar(
                    name: _session.bot.profile.name,
                    shape: shape,
                    color: _session.color,
                    size: 32,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Color', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            children: [
              for (var i = 0; i < desktopProfileSwatches.length; i++)
                IconButton(
                  tooltip: 'Color ${i + 1}',
                  isSelected:
                      BotAvatar.resolveColor(
                        _session.color,
                        _session.bot.profile.name,
                      ) ==
                      desktopProfileSwatches[i],
                  onPressed: _session.busy
                      ? null
                      : () => _session.change(
                          color:
                              '#${desktopProfileSwatches[i].toARGB32().toRadixString(16).substring(2)}',
                        ),
                  icon: Icon(
                    Icons.circle,
                    color: desktopProfileSwatches[i],
                    size: 28,
                  ),
                  selectedIcon: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.circle,
                        color: desktopProfileSwatches[i],
                        size: 28,
                      ),
                      Icon(
                        Icons.check,
                        size: 18,
                        color: desktopProfileSwatches[i].computeLuminance() > .4
                            ? Colors.black
                            : Colors.white,
                      ),
                    ],
                  ),
                ),
              IconButton(
                tooltip: 'Match profile color',
                onPressed: _session.busy
                    ? null
                    : () => _session.change(color: ''),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Image',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Upload avatar',
                onPressed: _session.busy ? null : _session.pickImage,
                icon: const Icon(Icons.upload_outlined),
              ),
              IconButton(
                tooltip: 'Remove avatar',
                onPressed: _session.busy ? null : _session.removeImage,
                icon: const Icon(Icons.image_not_supported_outlined),
              ),
            ],
          ),
          TextField(
            controller: _prompt,
            enabled: !_session.busy,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Describe an avatar',
              hintText: 'A friendly midnight-blue owl',
              suffixIcon: IconButton(
                tooltip: 'Generate avatar',
                onPressed: _session.busy
                    ? null
                    : () => _session.generate(_prompt.text),
                icon: const Icon(Icons.auto_awesome_outlined),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Generation uses this profile’s image provider. Upload PNG, JPEG or WebP, up to 2 MB.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 24),
          if (_session.repository.server != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Profile settings'),
              subtitle: const Text(
                'Role, instructions, model, accounts and tools',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _session.busy
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BotSettingsScreen(
                          profile: _session.repository.server!.profile(
                            _session.bot.profile.name,
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    ),
  );
}
