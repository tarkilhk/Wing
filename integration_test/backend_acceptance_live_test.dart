import 'profile_admin_live_test.dart' as administration;
import 'profile_goal_unwait_live_test.dart' as goals;
import 'profile_sensitive_live_test.dart' as sensitive;

/// Runs native Android acceptance against an existing local Hermes backend.
/// Supply HERMES_TEST_PORT, forwarded to the emulator with adb reverse.
void main() {
  administration.main();
  goals.main();
  sensitive.main();
}
