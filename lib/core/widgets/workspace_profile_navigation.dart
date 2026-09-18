import 'package:flutter/material.dart';

/// A successful, explicit picker selection rebuilds open profile routes. Each
/// replacement captures a fresh immutable owner; in-flight work keeps the old one.
class WorkspaceProfileNavigation extends ChangeNotifier {
  final _routes = <ModalRoute<dynamic>>{};
  String? profileName;
  bool switching = false;
  int revision = 0;
  bool _disposed = false;

  void register(ModalRoute<dynamic> route) => _routes.add(route);
  void unregister(ModalRoute<dynamic> route) => _routes.remove(route);

  bool get canSwitch => _routes.every(
    (route) =>
        !route.isActive || route.popDisposition != RoutePopDisposition.doNotPop,
  );

  Future<bool> switchTo(String name, Future<bool> Function() select) async {
    if (switching || !canSwitch) return false;
    switching = true;
    notifyListeners();
    try {
      if (!await select() || _disposed) return false;
      profileName = name;
      revision++;
      return true;
    } finally {
      switching = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
