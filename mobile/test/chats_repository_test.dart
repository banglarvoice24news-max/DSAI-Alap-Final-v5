import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_comm/features/chats/cpaas_chat_repository.dart';

void main() {
  group('chatThreadFromSummary', () {
    test('maps counterpart metadata and unread count', () {
      final thread = chatThreadFromSummary(const {
        'counterpartId': 'u1',
        'counterpartName': 'Alice',
        'lastMessageId': 'm9',
        'lastStatus': 'DELIVERED',
        'lastMessageAt': '2026-09-11T10:05:00.000Z',
        'lastMessageMine': true,
        'unreadCount': 3,
      });

      expect(thread.id, 'u1');
      expect(thread.title, 'Alice');
      expect(thread.unread, 3);
      expect(thread.lastMessageMine, isTrue);
      expect(thread.preview, isEmpty);
      expect(thread.lastMessageAt!.toUtc(), DateTime.utc(2026, 9, 11, 10, 5));
    });

    test('falls back to counterpartId when name is missing', () {
      final thread = chatThreadFromSummary(const {'counterpartId': 'u2'});
      expect(thread.title, 'u2');
      expect(thread.unread, 0);
      expect(thread.lastMessageAt, isNull);
    });
  });
}
