import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/models/chat_list_status.dart';
import 'package:wing/core/models/profile_live_activity.dart';

void main() {
  test('input outranks working, unread and empty-row draft evidence', () {
    expect(
      chatListStatus(
        {'unread': true, 'message_count': 0},
        runtime: (needsInput: true, working: true, hasMessages: false),
        activity: ProfileLiveActivityState.running,
      ),
      ChatListStatus.needsInput,
    );
    expect(
      chatListStatus(
        {'unread': true},
        runtime: (needsInput: false, working: true, hasMessages: true),
        activity: ProfileLiveActivityState.needsInput,
      ),
      ChatListStatus.needsInput,
    );
  });

  test(
    'live working outranks unread; retained messages prevent false drafts',
    () {
      expect(
        chatListStatus(
          {'unread': true},
          runtime: (needsInput: false, working: true, hasMessages: false),
        ),
        ChatListStatus.working,
      );
      expect(
        chatListStatus(const {}, activity: ProfileLiveActivityState.running),
        ChatListStatus.working,
      );
      expect(
        chatListStatus(
          {'message_count': 0},
          runtime: (needsInput: false, working: false, hasMessages: true),
        ),
        ChatListStatus.idle,
      );
    },
  );

  test('REST activity is not runtime proof and unread precedes draft', () {
    expect(chatListStatus({'is_active': true}), ChatListStatus.idle);
    expect(chatListStatus({'message_count': 0}), ChatListStatus.draft);
    expect(
      chatListStatus({'unread': true, 'message_count': 0}),
      ChatListStatus.unread,
    );
  });
}
