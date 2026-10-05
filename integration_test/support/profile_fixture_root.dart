import 'package:flutter/widgets.dart';
import 'package:wing/core/services/profile_workspace_controller.dart';

/// Owns one standalone preview's controller and its shared preferences owner.
/// WingApp-based fixtures use WingApp's corresponding lifetime instead.
class ProfileFixtureRoot extends StatefulWidget {
  ProfileFixtureRoot({required this.controller, required this.child})
    : super(key: ObjectKey(controller));

  final ProfileWorkspaceController controller;
  final Widget child;

  @override
  State<ProfileFixtureRoot> createState() => _ProfileFixtureRootState();
}

class _ProfileFixtureRootState extends State<ProfileFixtureRoot> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.controller.dispose();
    widget.controller.appPreferences.dispose();
    super.dispose();
  }
}
