import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wing/core/services/workspace_snapshot_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'large snapshot saves let the UI event loop run before completion',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = WorkspaceSnapshotStore(prefs, 'stall-probe');
      final snapshot = <String, dynamic>{
        'selected': 'current',
        'profiles': [
          for (var p = 0; p < 4; p++)
            {
              'name': 'p$p',
              'sessions': [],
              'projects': [],
              'chats': [
                for (var c = 0; c < 10; c++)
                  {
                    'id': 'c$c',
                    'messages': [
                      for (var m = 0; m < 60; m++)
                        {
                          'id': m,
                          'role': 'assistant',
                          'content': 'content ' * 400,
                        },
                    ],
                  },
              ],
            },
        ],
      };
      var eventLoopRan = false;
      Timer.run(() => eventLoopRan = true);
      final watch = Stopwatch()..start();
      final saving = store.write(snapshot);
      final blocking = watch.elapsedMicroseconds;
      await saving;
      expect(
        eventLoopRan,
        isTrue,
        reason: 'Large snapshot encoding must yield to input and frame events.',
      );
      final bytes = utf8
          .encode(prefs.getString('workspace_reading_v1_stall-probe')!)
          .length;
      debugPrint(
        'Snapshot save: input_messages=2400 synchronous_ms=${blocking / 1000} total_ms=${watch.elapsedMilliseconds} saved_bytes=$bytes',
      );
      expect(bytes, lessThanOrEqualTo(2 * 1024 * 1024));
      final profiles = snapshot['profiles'] as List;
      expect(profiles.length, 4);
      for (final profile in profiles) {
        for (final chat in profile['chats'] as List) {
          expect(chat['messages'], hasLength(60));
        }
      }
    },
  );

  test('newer small snapshots cannot overtake a background save', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = WorkspaceSnapshotStore(prefs, 'ordered');
    final older = store.write({
      'selected': 'older',
      'profiles': [
        {
          'name': 'older',
          'sessions': [
            for (var i = 0; i < 200; i++) {'id': i, 'title': '語' * 1000},
          ],
        },
      ],
    });
    final newer = store.write({'selected': 'newer', 'profiles': []});
    await Future.wait([older, newer]);
    expect(store.read()['selected'], 'newer');
  });
}
