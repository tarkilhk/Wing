import 'package:flutter_test/flutter_test.dart';
import 'package:wing/core/services/chat_outputs_session.dart';

void main() {
  test(
    'retiring from a loading observation does not dispatch history',
    () async {
      var reads = 0;
      final owner = ChatOutputsSession(
        loadHistory: (_) async {
          reads++;
          throw StateError('must not read');
        },
        download: (_) async => throw StateError('must not download'),
        readText: (_) async => throw StateError('must not read text'),
      );
      owner.addListener(owner.dispose);
      await owner.load();
      expect(reads, 0);
      await owner.load(refresh: true);
      expect(reads, 0);
      owner.dispose();
    },
  );
}
