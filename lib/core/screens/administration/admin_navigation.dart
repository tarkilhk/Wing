import 'package:flutter/material.dart';
import '../../services/administration_repository.dart';
import '../../widgets/server_connection_label.dart';

/// Push connection-owned content without changing its captured owner.
Future<T?> adminPush<T>(BuildContext context, WidgetBuilder builder) =>
    _pushAdminRoute(context, (context, _) => builder(context));

/// Keep a profile page at its current place in the stack. Each explicit picker
/// selection builds a fresh page with a new immutable owner, so old asynchronous
/// work cannot write to the newly selected profile.
Future<T?> adminPushProfile<T>(
  BuildContext context,
  ProfileAdministration profile,
  Widget Function(BuildContext, ProfileAdministration) builder,
) => _pushAdminRoute(
  context,
  (context, name) =>
      builder(context, name == null ? profile : profile.server.profile(name)),
  followsProfile: true,
);

Future<T?> _pushAdminRoute<T>(
  BuildContext context,
  Widget Function(BuildContext, String?) builder, {
  bool followsProfile = false,
}) {
  final scope = ServerConnectionScope.scopeOf(context);
  return Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      builder: (_) => _AdminRoute(
        scope: scope,
        builder: builder,
        followsProfile: followsProfile,
      ),
    ),
  );
}

class _AdminRoute extends StatefulWidget {
  const _AdminRoute({
    required this.scope,
    required this.builder,
    required this.followsProfile,
  });
  final ServerConnectionScope? scope;
  final Widget Function(BuildContext, String?) builder;
  final bool followsProfile;
  @override
  State<_AdminRoute> createState() => _AdminRouteState();
}

class _AdminRouteState extends State<_AdminRoute> {
  ModalRoute<dynamic>? _route;
  String? _profileName;
  int _revision = 0;
  @override
  void initState() {
    super.initState();
    _revision = widget.scope?.profileNavigation?.revision ?? 0;
    widget.scope?.profileNavigation?.addListener(_selected);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
    if (_route != null) widget.scope?.profileNavigation?.register(_route!);
  }

  void _selected() {
    if (!mounted) return;
    final navigation = widget.scope?.profileNavigation;
    setState(() {
      if (widget.followsProfile &&
          navigation != null &&
          navigation.revision != _revision) {
        _profileName = navigation.profileName;
        _revision = navigation.revision;
      }
    });
  }

  @override
  void dispose() {
    widget.scope?.profileNavigation?.removeListener(_selected);
    if (_route != null) widget.scope?.profileNavigation?.unregister(_route!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final switching = scope?.profileNavigation?.switching ?? false;
    final page = PopScope(
      canPop: !switching,
      child: AbsorbPointer(
        absorbing: switching,
        child: KeyedSubtree(
          key: ValueKey(_profileName),
          child: Builder(
            builder: (context) => widget.builder(context, _profileName),
          ),
        ),
      ),
    );
    return scope == null
        ? page
        : ServerConnectionScope(
            status: scope.status,
            icon: scope.icon,
            onPickWorkspace: scope.onPickWorkspace == null
                ? null
                : (anchor, {required includeProfiles}) =>
                      scope.onPickWorkspace!(
                        anchor,
                        includeProfiles:
                            includeProfiles && widget.followsProfile,
                      ),
            profileNavigation: scope.profileNavigation,
            child: page,
          );
  }
}
