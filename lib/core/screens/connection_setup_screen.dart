import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/hermes_cloud.dart';
import '../widgets/studio_selection_tile.dart';

import '../models/connection_address.dart';
import '../services/connection_manager.dart';
import '../services/connection_setup_probe.dart';
import '../theme/wing_theme.dart';
import '../widgets/compact_switch.dart';
import '../widgets/connection_icon_picker.dart';
import '../widgets/gateway_headers_editor.dart';
import '../widgets/playful_portrait.dart';
import '../widgets/studio_action_label.dart';
import '../widgets/studio_error.dart';
import '../widgets/wing_wordmark.dart';
import 'connection_guide_screen.dart';

/// One dashboard address, an explicit sign-in, and a provisional access check.
class ConnectionSetupScreen extends StatefulWidget {
  const ConnectionSetupScreen({
    required this.onSave,
    required this.onSaveIcon,
    this.initialConnection,
    this.cloud,
    this.savedConnections = const [],
    this.createProbe = DashboardConnectionProbe.new,
    super.key,
  }) : assert(initialConnection == null || onSaveIcon != null);

  final SavedConnection? initialConnection;
  final HermesCloud? cloud;
  final List<SavedConnection> savedConnections;
  final Future<SavedConnection> Function(SavedConnection candidate) onSave;

  /// Existing connections save appearance independently of access verification.
  /// New instances keep their icon in the draft until the final save.
  final Future<void> Function(ConnectionIcon icon)? onSaveIcon;
  final ConnectionProbe Function(SavedConnection) createProbe;

  @override
  State<ConnectionSetupScreen> createState() => _ConnectionSetupScreenState();
}

enum _Step { choose, address, cloud, signIn, check, review }

class _ConnectionSetupScreenState extends State<ConnectionSetupScreen> {
  final _addressForm = GlobalKey<FormState>();
  final _signInForm = GlobalKey<FormState>();
  final _nameForm = GlobalKey<FormState>();
  final _scroll = ScrollController();
  late final TextEditingController _address;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _name;
  late final ConnectionSetupProbe _probe;
  late _AccessSettings _access;
  late ConnectionIcon _icon;
  _Step _step = _Step.choose;
  late final HermesCloud _cloud;
  CloudDiscovery? _discovery;
  List<CloudOrganization> _organizations = const [];
  CloudInstance? _instance;
  String? _organization;
  DashboardOAuthSession? _cloudSession;
  String? _cloudError;
  bool _cloudBusy = false;
  bool _cloudRoute = false;
  int _cloudGeneration = 0;

  SavedConnection? get _alreadySaved {
    if (_editing || _instance == null) return null;
    for (final saved in widget.savedConnections) {
      if (saved.cloudInstanceId == _instance!.id &&
          saved.cloudOrganization == _organization) {
        return saved;
      }
    }
    return null;
  }

  SavedConnection? _checkedConnection;
  bool _revealPassword = false;
  bool _dirty = false;
  bool _saving = false;
  bool _leaving = false;
  bool _confirmingExit = false;
  String? _saveError;

  bool get _editing => widget.initialConnection != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConnection;
    _cloud = widget.cloud ?? HermesCloud();
    _cloudRoute = initial?.isCloud ?? false;
    _step = _cloudRoute
        ? _Step.cloud
        : initial == null
        ? _Step.choose
        : _Step.address;
    _icon = initial?.icon ?? ConnectionIcon.server;
    _address = TextEditingController(
      text: initial == null
          ? ''
          : SavedConnection.joinBaseUrl(
              '${initial.useHttps ? 'https' : 'http'}://${initial.host}:${initial.dashboardPort}',
              initial.dashboardPrefix ?? '',
            ),
    );
    if (_cloudRoute) {
      _organization = initial!.cloudOrganization;
      _instance = CloudInstance(
        id: initial.cloudInstanceId!,
        name: initial.label,
        state: 'unknown',
        dashboardUrl: _address.text,
      );
      _discovery = CloudDiscovery(instances: [_instance!]);
    }
    _username = TextEditingController(text: initial?.dashboardUsername ?? '');
    _password = TextEditingController(text: initial?.dashboardPassword ?? '');
    _name = TextEditingController(text: initial?.label ?? '');
    _access = _AccessSettings(
      proxied: initial?.dashboardProxied ?? false,
      chatUrl: initial?.desktopGatewayUrl ?? '',
      headers: initial?.gatewayHeaders ?? const {},
    );
    _probe = ConnectionSetupProbe(createProbe: widget.createProbe)
      ..addListener(_probeChanged);
  }

  void _probeChanged() {
    if (!mounted) return;
    setState(() {
      if (_step == _Step.check && !_probe.checking && _probe.verified) {
        _step = _Step.review;
        _toTop();
      }
    });
  }

  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _go(_Step step) {
    FocusManager.instance.primaryFocus?.unfocus();
    if (step != _Step.review) {
      _probe.cancel();
      _checkedConnection = null;
    }
    setState(() {
      _step = step;
      _saveError = null;
    });
    _toTop();
  }

  void _continue() {
    if (!_addressForm.currentState!.validate()) return;
    final address = ConnectionAddress.parse(_address.text);
    _address.text = address.url;
    if (_name.text.isEmpty) _name.text = address.host;
    _go(_Step.signIn);
  }

  Future<void> _customSetup() async {
    final result = await Navigator.of(context).push<_AccessSettings>(
      MaterialPageRoute(builder: (_) => _CustomSetupScreen(initial: _access)),
    );
    if (result == null || !mounted) return;
    setState(() {
      _access = result;
      _dirty = true;
    });
    _go(_Step.signIn);
  }

  Future<void> _check() async {
    if (_probe.checking) return;
    if (!_cloudRoute &&
        _step == _Step.signIn &&
        !_signInForm.currentState!.validate()) {
      return;
    }
    final address = ConnectionAddress.parse(_address.text);
    final candidate = SavedConnection(
      id: widget.initialConnection?.id ?? 'new-connection',
      label: _name.text.trim(),
      host: address.host,
      port: address.port,
      useHttps: address.useHttps,
      apiKey: '',
      cloudInstanceId: _cloudRoute ? _instance!.id : null,
      cloudOrganization: _cloudRoute ? _organization : null,
      dashboardOAuth: _cloudRoute ? _cloudSession : null,
      dashboardPortOverride: address.port,
      dashboardPrefix: address.path,
      dashboardProxied: _access.proxied,
      dashboardUsername: _cloudRoute || _access.proxied
          ? null
          : _username.text.trim(),
      dashboardPassword: _cloudRoute || _access.proxied ? null : _password.text,
      desktopGatewayUrl: _access.chatUrl.isEmpty ? null : _access.chatUrl,
      gatewayHeaders: _access.headers,
    );
    _go(_Step.check);
    _checkedConnection = candidate;
    await _probe.check(candidate);
  }

  Future<void> _save() async {
    if (_saving || !_probe.verified || !_nameForm.currentState!.validate()) {
      return;
    }
    final candidate = _checkedConnection!.copyWith(
      label: _name.text.trim(),
      icon: _icon,
    );
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final saved = await widget.onSave(candidate);
      if (!mounted) return;
      _leave(saved);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError =
              'Couldn’t save this connection on this device. Your details are still here. Try saving again.';
        });
      }
    }
  }

  void _leave([SavedConnection? result]) {
    setState(() => _leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(result);
    });
  }

  Future<void> _back() async {
    if (_saving || _leaving || _confirmingExit) return;
    if (_cloudBusy) {
      _cloudGeneration++;
      await _cloud.cancel();
      if (!mounted) return;
      setState(() => _cloudBusy = false);
      return;
    }
    if (_step == _Step.check || _step == _Step.review) {
      _go(_cloudRoute ? _Step.cloud : _Step.signIn);
      return;
    }
    if (_step == _Step.signIn) {
      _go(_Step.address);
      return;
    }
    if (!_editing && (_step == _Step.address || _step == _Step.cloud)) {
      _cloudGeneration++;
      _go(_Step.choose);
      return;
    }
    if (!_dirty) {
      _leave();
      return;
    }
    _confirmingExit = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard connection setup?'),
        content: const Text('This connection has not been saved.'),
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
    _confirmingExit = false;
    if (discard == true && mounted) _leave();
  }

  @override
  void dispose() {
    _cloudGeneration++;
    _cloud.close();
    _probe.removeListener(_probeChanged);
    _probe.dispose();
    for (final controller in [_address, _username, _password, _name]) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = switch (_step) {
      _Step.choose || _Step.address || _Step.cloud => 1,
      _Step.signIn => 2,
      _Step.check || _Step.review => 3,
    };
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _saving ? null : _back),
          title: Text(_editing ? 'Edit instance' : 'Add instance'),
          actions: [
            if (_step != _Step.review)
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(
                  child: Text(
                    '$step of 3',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  controller: _scroll,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Semantics(
                                label: 'Connection setup, step $step of 3',
                                child: Row(
                                  children: [
                                    for (var index = 0; index < 3; index++)
                                      Expanded(
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            right: index == 2 ? 0 : 6,
                                          ),
                                          child: ColoredBox(
                                            color: index < step
                                                ? Theme.of(
                                                    context,
                                                  ).colorScheme.primary
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.outlineVariant,
                                            child: const SizedBox(height: 3),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 24),
                              switch (_step) {
                                _Step.choose => _chooseStep(),
                                _Step.cloud => _cloudStep(),
                                _Step.address => _addressStep(),
                                _Step.signIn => _signInStep(),
                                _Step.check => _checkStep(),
                                _Step.review => _reviewStep(),
                              },
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 24),
                            child: _footer(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String title, [String? subtitle]) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 12),
        Text(
          subtitle,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: 24),
    ],
  );

  Widget _artwork() => const Padding(
    padding: EdgeInsets.only(bottom: 24),
    child: Center(
      child: SizedBox(
        width: 220,
        height: 128,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.bottomCenter,
              child: PlayfulPortrait(size: 112, circular: true),
            ),
            Positioned(right: 6, top: 0, child: WingFeathers(width: 58)),
          ],
        ),
      ),
    ),
  );

  Widget _chooseStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _artwork(),
      _heading('Connect your agent', 'Choose how to find your Hermes.'),
      for (final cloud in [true, false]) ...[
        _panel(
          Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(cloud ? Icons.cloud_outlined : Icons.link),
              title: Text(cloud ? 'Hermes Cloud' : 'Use an address'),
              subtitle: Text(
                cloud
                    ? 'Find your instances with Nous Portal'
                    : 'Connect with a dashboard address',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                _cloudRoute = cloud;
                _go(cloud ? _Step.cloud : _Step.address);
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    ],
  );

  Future<void> _discoverCloud({bool switchAccount = false}) async {
    if (_cloudBusy) return;
    final generation = ++_cloudGeneration;
    setState(() {
      _cloudBusy = true;
      _cloudError = null;
      if (switchAccount) {
        _discovery = null;
        _instance = null;
        _organization = null;
        _organizations = const [];
        _cloudSession = null;
      }
    });
    try {
      final result = await _cloud.discover(
        organization: switchAccount ? null : _organization,
        switchAccount: switchAccount,
      );
      if (!mounted || generation != _cloudGeneration) return;
      setState(() {
        if (result != null) {
          _discovery = result;
          if (result.organizations.isNotEmpty) {
            _organizations = result.organizations;
          }
          _instance = null;
          _cloudSession = null;
          _organization = result.organization?.id;
        }
      });
    } catch (error) {
      if (mounted && generation == _cloudGeneration) {
        setState(() {
          _cloudError = error is CloudAccessException
              ? error.message
              : 'Couldn’t reach Nous Portal. Try again.';
        });
      }
    } finally {
      if (mounted && generation == _cloudGeneration) {
        setState(() => _cloudBusy = false);
      }
    }
  }

  Future<void> _continueCloud() async {
    if (_cloudBusy) return;
    if (_discovery == null || _discovery!.organizations.isNotEmpty) {
      await _discoverCloud();
      return;
    }
    final instance = _instance;
    if (instance?.canConnect != true) return;
    if (_alreadySaved case final saved?) {
      _leave(saved);
      return;
    }
    final generation = ++_cloudGeneration;
    setState(() {
      _cloudBusy = true;
      _cloudError = null;
    });
    try {
      final session = await _cloud.signIn(instance!);
      if (!mounted || generation != _cloudGeneration || session == null) return;
      _cloudSession = session;
      _address.text = instance.dashboardUrl!;
      if (!_editing) _name.text = instance.name;
      _access = const _AccessSettings();
      _username.clear();
      _password.clear();
      _dirty = true;
      setState(() => _cloudBusy = false);
      await _check();
    } catch (error) {
      if (mounted && generation == _cloudGeneration) {
        setState(() {
          _cloudError = error is CloudAccessException
              ? error.message
              : 'Couldn’t sign in to this Hermes. Try again.';
        });
      }
    } finally {
      if (mounted && generation == _cloudGeneration) {
        setState(() => _cloudBusy = false);
      }
    }
  }

  Future<void> _openPortal() async {
    try {
      if (await launchUrl(
        Uri.parse(HermesCloud.portal),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      /* Show an actionable error without platform details. */
    }
    if (mounted) {
      setState(
        () => _cloudError =
            'Couldn’t open Nous Portal. Visit portal.nousresearch.com in your browser.',
      );
    }
  }

  Widget _cloudStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _artwork(),
      _heading(
        'Where’s your Hermes?',
        _discovery == null
            ? 'Find your Cloud instances with Nous Portal.'
            : _discovery!.organizations.isNotEmpty
            ? 'Choose the organization that owns your Hermes.'
            : 'Choose the Cloud instance you want to connect.',
      ),
      if (_cloudBusy) ...[
        Semantics(
          liveRegion: true,
          child: Text('Connecting with Nous Portal…'),
        ),
        const SizedBox(height: 16),
      ],
      if (_cloudError case final message?) ...[
        StudioError(message),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _cloudBusy ? null : () => _discoverCloud(),
          child: const Text('Refresh instances'),
        ),
        TextButton(
          onPressed: _cloudBusy
              ? null
              : () => _discoverCloud(switchAccount: true),
          child: const Text('Sign in again'),
        ),
      ],
      if (_discovery == null)
        _panel(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sign in with Nous Portal'),
              SizedBox(height: 12),
              Text(
                'Continue to sign in securely, then choose your Hermes instance.',
              ),
            ],
          ),
        )
      else if (_discovery!.organizations.isNotEmpty)
        RadioGroup<String>(
          groupValue: _organization,
          onChanged: _cloudBusy
              ? (_) {}
              : (value) => setState(() => _organization = value),
          child: Column(
            children: [
              for (final org in _discovery!.organizations)
                StudioRadioTile(
                  value: org.id,
                  title: Text(org.name),
                  enabled: !_cloudBusy,
                ),
            ],
          ),
        )
      else if (_discovery!.instances.isEmpty)
        _panel(
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No Cloud instances yet'),
              SizedBox(height: 12),
              Text(
                'Create an instance in Nous Portal, then come back and refresh.',
              ),
            ],
          ),
        )
      else
        RadioGroup<String>(
          groupValue: _instance?.id,
          onChanged: (value) {
            if (_cloudBusy) return;
            setState(() {
              _instance = _discovery!.instances.firstWhere(
                (i) => i.id == value,
              );
              _cloudError = null;
            });
          },
          child: Column(
            children: [
              for (final instance in _discovery!.instances)
                StudioRadioTile(
                  value: instance.id,
                  title: Text(instance.name),
                  subtitle: Text(
                    [
                      instance.statusLabel,
                      if (instance.dashboardUrl != null)
                        Uri.parse(instance.dashboardUrl!).host,
                    ].join(' · '),
                  ),
                  enabled: !_cloudBusy && instance.canConnect,
                ),
            ],
          ),
        ),
      if (_alreadySaved != null) ...[
        const SizedBox(height: 12),
        Text('Already saved as ${_alreadySaved!.label}.'),
      ],
      if (_discovery != null) ...[
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: _cloudBusy ? null : () => _discoverCloud(),
              child: const Text('Refresh'),
            ),
            if (_organizations.length > 1 && _discovery!.organizations.isEmpty)
              TextButton(
                onPressed: _cloudBusy
                    ? null
                    : () => setState(() {
                        _discovery = CloudDiscovery(
                          organizations: _organizations,
                        );
                        _organization = null;
                        _instance = null;
                        _cloudError = null;
                      }),
                child: const Text('Change organization'),
              ),
            TextButton(
              onPressed: _cloudBusy ? null : _openPortal,
              child: const Text('Open Nous Portal'),
            ),
            TextButton(
              onPressed: _cloudBusy
                  ? null
                  : () => _discoverCloud(switchAccount: true),
              child: const Text('Switch account'),
            ),
          ],
        ),
        if (_discovery!.instances.any((instance) => !instance.canConnect))
          Text(
            'Start or manage unavailable instances in Nous Portal, then refresh.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    ],
  );

  Widget _addressStep() => Form(
    key: _addressForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (MediaQuery.viewInsetsOf(context).bottom == 0) _artwork(),
        _heading(
          'Where’s your Hermes?',
          'Use the dashboard address you open in your phone’s browser.',
        ),
        TextFormField(
          key: const Key('connection-address'),
          controller: _address,
          decoration: const InputDecoration(
            labelText: 'Dashboard address',
            hintText: 'https://hermes.example.com',
            helperText: 'Include the port and any path in this one address.',
            helperMaxLines: 4,
            errorMaxLines: 5,
          ),
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => _dirty = true,
          onFieldSubmitted: (_) => _continue(),
          validator: (value) {
            try {
              ConnectionAddress.parse(value ?? '');
              return null;
            } on FormatException catch (error) {
              return error.message;
            }
          },
        ),
        const SizedBox(height: 24),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'One address for your agent',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              const _CapabilityRow(Icons.tune, 'Profiles & settings'),
              const SizedBox(height: 8),
              _CapabilityRow(
                Icons.forum_outlined,
                _access.chatUrl.isEmpty
                    ? 'Live chat · same address'
                    : 'Live chat · custom address',
              ),
            ],
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _findAddress,
            icon: const Icon(Icons.help_outline, size: 18),
            label: const Text('Find my address'),
          ),
        ),
      ],
    ),
  );

  void _findAddress() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const ConnectionGuideScreen()),
  );

  Future<void> _pickIcon() => showConnectionIconPicker(
    context,
    connectionName: _name.text.trim(),
    initialIcon: _icon,
    onSave: (icon) async {
      if (widget.onSaveIcon != null) await widget.onSaveIcon!(icon);
      if (!mounted) return;
      setState(() {
        _icon = icon;
        if (!_editing) _dirty = true;
      });
    },
  );

  Widget _destination() => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: _panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConnectionIconButton(
                icon: _icon,
                onPressed: _saving ? null : _pickIcon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_cloudRoute) ...[
                        Text(
                          _instance!.name,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                      ],
                      Text(
                        _address.text,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_access.chatUrl.isNotEmpty) ...[
            const Divider(),
            Text(
              'Live chat: ${_access.chatUrl}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );

  Widget _signInStep() => Form(
    key: _signInForm,
    child: AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _heading(
            _access.proxied
                ? 'Connect through your proxy'
                : 'Sign in to Hermes',
          ),
          _destination(),
          if (_access.proxied)
            const Text(
              'Your access proxy handles sign-in. Wing will check that it allows profiles, live chat and history.',
            )
          else ...[
            TextFormField(
              key: const Key('connection-username'),
              controller: _username,
              decoration: const InputDecoration(
                labelText: 'Username',
                errorMaxLines: 3,
              ),
              autofillHints: const [AutofillHints.username],
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              onChanged: (_) => _dirty = true,
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter your dashboard username.'
                  : null,
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('connection-password'),
              controller: _password,
              obscureText: !_revealPassword,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Password',
                errorMaxLines: 3,
                suffixIcon: IconButton(
                  tooltip: _revealPassword ? 'Hide password' : 'Show password',
                  onPressed: () =>
                      setState(() => _revealPassword = !_revealPassword),
                  icon: Icon(
                    _revealPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              onChanged: (_) => _dirty = true,
              onFieldSubmitted: (_) => _check(),
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your dashboard password.'
                  : null,
            ),
            const SizedBox(height: 16),
            Text(
              'Use your dashboard login. Model-provider keys stay on Hermes.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (_address.text.startsWith('http:')) ...[
            const SizedBox(height: 16),
            Text(
              'HTTP does not encrypt this connection. Use a trusted private network or an HTTPS address.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Custom setup'),
            subtitle: Text(_access.description),
            trailing: const Icon(Icons.chevron_right),
            onTap: _customSetup,
          ),
          if (_access.chatUrl.isNotEmpty)
            Text(
              'Your dashboard authentication and access headers will also be sent to the chat address shown above.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    ),
  );

  Widget _checkStep() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(
        _probe.error == null
            ? 'Let’s check the connection'
            : 'One part needs attention',
      ),
      _destination(),
      _panel(
        Column(
          children: [
            for (final stage in ConnectionCheck.values) ...[
              if (stage != ConnectionCheck.profiles) const Divider(height: 28),
              _checkRow(stage),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (_probe.error case final message?) ...[
        StudioError(message),
        if (_probe.failedStage == ConnectionCheck.chat) ...[
          const SizedBox(height: 12),
          Text(
            'If you use a reverse proxy, check WebSocket forwarding for ${ConnectionAddress.parse(_access.chatUrl.isEmpty ? _address.text : _access.chatUrl).path}/api/ws.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Connection details'),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SelectableText(
                [
                  'Dashboard: ${_address.text}',
                  'Live chat: ${ConnectionAddress.parse(_access.chatUrl.isEmpty ? _address.text : _access.chatUrl).socketUrl}',
                  if (_probe.httpStatus != null) 'HTTP ${_probe.httpStatus}',
                  if (_probe.checkedAt != null)
                    'Checked: ${_probe.checkedAt!.toLocal()}',
                ].join('\n'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        TextButton(
          onPressed: () => _go(_cloudRoute ? _Step.cloud : _Step.signIn),
          child: Text(
            _cloudRoute
                ? 'Sign in to Hermes Cloud again'
                : 'Edit sign-in or custom setup',
          ),
        ),
      ] else
        Text(
          'Checking access to your Hermes. No message will be sent.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
    ],
  );

  Widget _checkRow(ConnectionCheck stage) {
    final status = _probe.statuses[stage]!;
    final failed = status == ConnectionCheckStatus.failed;
    final available = status == ConnectionCheckStatus.available;
    final pending = status == ConnectionCheckStatus.checking;
    final colors = Theme.of(context).colorScheme;
    final color = failed
        ? colors.error
        : available || pending
        ? colors.primary
        : colors.onSurfaceVariant;
    final label = switch (stage) {
      ConnectionCheck.profiles => 'Profiles & access',
      ConnectionCheck.chat => 'Live chat',
      ConnectionCheck.history => 'Chat history',
    };
    final detail = switch (status) {
      ConnectionCheckStatus.waiting =>
        _probe.error == null ? 'Waiting' : 'Not checked',
      ConnectionCheckStatus.checking => 'Checking…',
      ConnectionCheckStatus.available => 'Available',
      ConnectionCheckStatus.failed => 'Couldn’t connect',
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: pending && !MediaQuery.disableAnimationsOf(context)
                ? CircularProgressIndicator(strokeWidth: 2, color: color)
                : Icon(
                    failed
                        ? Icons.error_outline
                        : available
                        ? Icons.link
                        : Icons.more_horiz,
                    color: color,
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.titleSmall),
                Text(
                  detail,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewStep() => Form(
    key: _nameForm,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _artwork(),
        _heading(
          'Connection verified',
          'Give this Hermes a name you’ll recognize.',
        ),
        _destination(),
        TextFormField(
          key: const Key('connection-name'),
          controller: _name,
          enabled: !_saving,
          decoration: const InputDecoration(
            labelText: 'Instance name',
            hintText: 'Home',
            errorMaxLines: 3,
          ),
          textInputAction: TextInputAction.done,
          onChanged: (_) => _dirty = true,
          onFieldSubmitted: (_) => _save(),
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Give this instance a name.'
              : null,
        ),
        const SizedBox(height: 24),
        ListTile(
          key: const Key('connection-appearance'),
          contentPadding: EdgeInsets.zero,
          leading: ConnectionIconBadge(icon: _icon),
          title: const Text('Instance icon'),
          subtitle: Text(_icon.label),
          trailing: const Icon(Icons.chevron_right),
          enabled: !_saving,
          onTap: _saving ? null : _pickIcon,
        ),
        const SizedBox(height: 16),
        if (!_editing)
          Text(
            'Opens with profile ${_probe.discovery!.serverPreferred.label}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        const SizedBox(height: 16),
        const _CapabilityRow(
          Icons.link,
          'Profiles, live chat & history available',
        ),
        const SizedBox(height: 8),
        Text(
          'Access verified · no message sent',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_saveError != null) ...[
          const SizedBox(height: 20),
          StudioError(_saveError!),
        ],
      ],
    ),
  );

  Widget _footer() {
    if (_step == _Step.choose) return const SizedBox.shrink();
    final (label, action) = switch (_step) {
      _Step.choose => ('Continue', _continue),
      _Step.cloud => (
        _alreadySaved == null ? 'Continue' : 'Open instance',
        _continueCloud,
      ),
      _Step.address => ('Continue', _continue),
      _Step.signIn => ('Check connection', _check),
      _Step.check =>
        _probe.checking
            ? (
                'Cancel check',
                () => _go(_cloudRoute ? _Step.cloud : _Step.signIn),
              )
            : ('Try again', _check),
      _Step.review => (_editing ? 'Save changes' : 'Save and open', _save),
    };
    return FilledButton(
      key: const Key('connection-primary'),
      style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
      onPressed:
          _saving ||
              _cloudBusy ||
              (_step == _Step.cloud &&
                  _discovery != null &&
                  (_discovery!.organizations.isNotEmpty
                      ? _organization == null
                      : _instance?.canConnect != true))
          ? null
          : action,
      child: StudioActionLabel(label, busy: _saving || _cloudBusy),
    );
  }

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: WingRadius.card,
    ),
    child: child,
  );
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      ExcludeSemantics(
        child: Icon(
          icon,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ),
    ],
  );
}

class _AccessSettings {
  const _AccessSettings({
    this.proxied = false,
    this.chatUrl = '',
    this.headers = const {},
  });
  final bool proxied;
  final String chatUrl;
  final Map<String, String> headers;

  String get description {
    final configured = [
      if (proxied) 'Proxy sign-in',
      if (chatUrl.isNotEmpty) 'Separate chat address',
      if (headers.isNotEmpty)
        '${headers.length} access ${headers.length == 1 ? 'header' : 'headers'}',
    ];
    return configured.isEmpty
        ? 'Only if your administrator gave you extra settings'
        : configured.join(' · ');
  }
}

class _CustomSetupScreen extends StatefulWidget {
  const _CustomSetupScreen({required this.initial});
  final _AccessSettings initial;

  @override
  State<_CustomSetupScreen> createState() => _CustomSetupScreenState();
}

class _CustomSetupScreenState extends State<_CustomSetupScreen> {
  final _form = GlobalKey<FormState>();
  late final _chat = TextEditingController(text: widget.initial.chatUrl);
  late bool _separate = widget.initial.chatUrl.isNotEmpty;
  late bool _proxied = widget.initial.proxied;
  late Map<String, String?> _headers = {
    for (final key in widget.initial.headers.keys) key: null,
  };
  late bool _showHeaders = widget.initial.headers.isNotEmpty;

  @override
  void dispose() {
    _chat.dispose();
    super.dispose();
  }

  void _done() {
    if (!_form.currentState!.validate()) {
      setState(() => _showHeaders = true);
      return;
    }
    Navigator.pop(
      context,
      _AccessSettings(
        proxied: _proxied,
        chatUrl: _separate ? ConnectionAddress.parse(_chat.text).url : '',
        headers: resolveGatewayHeaderUpdate(widget.initial.headers, _headers),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Custom setup')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Most connections don’t need anything here. Use only the settings supplied by your administrator.',
                ),
                const SizedBox(height: 24),
                CompactSwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('My access proxy handles sign-in'),
                  subtitle: const Text(
                    'For a proxy that authenticates Wing’s requests. HTTPS alone does not do this.',
                  ),
                  value: _proxied,
                  onChanged: (value) => setState(() => _proxied = value),
                ),
                const Divider(height: 32),
                CompactSwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Use a separate chat address'),
                  subtitle: const Text(
                    'Normally, live chat uses your dashboard address.',
                  ),
                  value: _separate,
                  onChanged: (value) => setState(() => _separate = value),
                ),
                if (_separate) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('connection-chat-address'),
                    controller: _chat,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Chat gateway base address',
                      helperText:
                          'Use an http(s) base address. Wing adds /api/ws.',
                      helperMaxLines: 4,
                      errorMaxLines: 5,
                    ),
                    validator: (value) {
                      try {
                        ConnectionAddress.parse(value ?? '');
                        return null;
                      } on FormatException catch (error) {
                        return error.message;
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your dashboard authentication and access headers will also be sent to this address.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const Divider(height: 32),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Access headers'),
                  subtitle: const Text(
                    'Extra credentials required by some access proxies',
                  ),
                  trailing: Icon(
                    _showHeaders ? Icons.expand_less : Icons.expand_more,
                  ),
                  onTap: () => setState(() => _showHeaders = !_showHeaders),
                ),
                Visibility(
                  visible: _showHeaders,
                  maintainState: true,
                  child: GatewayHeadersEditor(
                    savedNames: widget.initial.headers.keys.toSet(),
                    onChanged: (values) => _headers = values,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 52),
                  ),
                  onPressed: _done,
                  child: const Text('Use these settings'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
