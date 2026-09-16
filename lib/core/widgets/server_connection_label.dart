import 'package:flutter/material.dart';
import '../models/connection_icon.dart';
import '../services/server_connection_status.dart';
import '../theme/wing_theme.dart';
import 'connection_icon_picker.dart';

class ServerConnectionScope extends InheritedWidget {
  final ServerConnectionStatus status;
  const ServerConnectionScope({
    super.key,
    required this.status,
    required super.child,
  });
  static ServerConnectionStatus? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<ServerConnectionScope>()
      ?.status;
  @override
  bool updateShouldNotify(ServerConnectionScope oldWidget) =>
      status != oldWidget.status;
}

/// The server identity and its status form one accessible details target.
class ServerConnectionLabel extends StatelessWidget {
  final ServerConnectionStatus? status;
  final String label;
  final ConnectionIcon? icon;
  final String? suffix;
  final TextStyle? style;
  final AlignmentGeometry alignment;
  const ServerConnectionLabel({
    super.key,
    required this.label,
    this.icon,
    this.status,
    this.suffix,
    this.style,
    this.alignment = Alignment.centerLeft,
  });
  @override
  Widget build(BuildContext context) {
    Widget labelBody() => Semantics(
      button: true,
      label:
          '$label, ${status?.description ?? 'Not checked'}. Connection details',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (context) =>
              _ConnectionDetails(label: label, status: status),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
          child: Align(
            alignment: alignment,
            widthFactor: 1,
            heightFactor: 1,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(
                    icon!.glyph,
                    size: 16,
                    color:
                        style?.color ??
                        Theme.of(context).textTheme.bodySmall?.color,
                  ),
                  const SizedBox(width: 8),
                ],
                _ConnectionLed(
                  phase: status?.phase ?? ServerConnectionPhase.unchecked,
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: Text(
                    '$label${suffix == null || suffix!.isEmpty ? '' : ' · $suffix'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: style ?? Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return status == null
        ? labelBody()
        : ListenableBuilder(
            listenable: status!,
            builder: (_, _) => labelBody(),
          );
  }
}

/// Used beside a navigable connection row so inspecting status never selects it.
class ServerConnectionIndicator extends StatelessWidget {
  final String label;
  final ServerConnectionStatus? status;
  final ConnectionIcon icon;
  final VoidCallback onIconPressed;
  const ServerConnectionIndicator({
    super.key,
    required this.label,
    required this.onIconPressed,
    this.status,
    this.icon = ConnectionIcon.server,
  });
  @override
  Widget build(BuildContext context) {
    Widget contents() => Semantics(
      button: true,
      label:
          '$label, ${status?.description ?? 'Not checked'}. Connection details',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => _ConnectionDetails(label: label, status: status),
        ),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: _ConnectionLed(
                phase: status?.phase ?? ServerConnectionPhase.unchecked,
              ),
            ),
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConnectionIconButton(icon: icon, onPressed: onIconPressed),
        status == null
            ? contents()
            : ListenableBuilder(
                listenable: status!,
                builder: (_, _) => contents(),
              ),
      ],
    );
  }
}

class _ConnectionLed extends StatefulWidget {
  final ServerConnectionPhase phase;
  const _ConnectionLed({required this.phase});
  @override
  State<_ConnectionLed> createState() => _ConnectionLedState();
}

class _ConnectionLedState extends State<_ConnectionLed>
    with SingleTickerProviderStateMixin {
  late final AnimationController pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  );
  void sync() {
    final animate =
        widget.phase == ServerConnectionPhase.reconnecting &&
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    if (animate && !pulse.isAnimating) pulse.repeat(reverse: true);
    if (!animate) {
      pulse.stop();
      pulse.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    sync();
  }

  @override
  void didUpdateWidget(covariant _ConnectionLed oldWidget) {
    super.didUpdateWidget(oldWidget);
    sync();
  }

  @override
  void dispose() {
    pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens =
        Theme.of(context).extension<WingTokens>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? WingTokens.dark()
            : WingTokens.light());
    final color = switch (widget.phase) {
      ServerConnectionPhase.connected => tokens.success,
      ServerConnectionPhase.reconnecting ||
      ServerConnectionPhase.limited => tokens.warning,
      ServerConnectionPhase.disconnected => tokens.danger,
      ServerConnectionPhase.unchecked => tokens.muted,
    };
    return FadeTransition(
      opacity: Tween<double>(
        begin: .45,
        end: 1,
      ).animate(CurvedAnimation(parent: pulse, curve: Curves.easeInOut)),
      child: Container(
        key: const ValueKey('server-connection-led'),
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _ConnectionDetails extends StatelessWidget {
  final String label;
  final ServerConnectionStatus? status;
  const _ConnectionDetails({required this.label, this.status});
  String availability(ConnectionAvailability? state) => switch (state) {
    ConnectionAvailability.available => 'Available',
    ConnectionAvailability.unavailable => 'Unavailable',
    _ => 'Not checked',
  };
  @override
  Widget build(BuildContext context) {
    Widget contents() => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(status?.description ?? 'Not checked'),
              const SizedBox(height: 16),
              Text('Server access: ${availability(status?.access)}'),
              const SizedBox(height: 8),
              Text('Live chat: ${availability(status?.live)}'),
              if (status?.problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(status!.problem!),
                ),
              if (status?.phase == ServerConnectionPhase.disconnected)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'We’ll try again when your network returns or you reopen Wing. You can also retry now.',
                  ),
                ),
              if (status?.retry != null &&
                  status?.phase != ServerConnectionPhase.connected)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: TextButton(
                    onPressed:
                        status?.phase == ServerConnectionPhase.reconnecting
                        ? null
                        : () => status!.retry!(),
                    child: const Text('Retry connection'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    return status == null
        ? contents()
        : ListenableBuilder(listenable: status!, builder: (_, _) => contents());
  }
}
