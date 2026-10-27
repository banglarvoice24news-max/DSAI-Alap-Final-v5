import '../domain/models.dart';

abstract class Slice1Repository {
  Future<void> upsertOutbox(OutboxRecord record);
  Future<OutboxRecord?> outboxById(String messageId);
  Future<List<OutboxRecord>> pendingOutbox();
  Future<void> saveInbox(InboxMessage message);
  Future<InboxMessage?> inboxById(String messageId);
  Future<List<InboxMessage>> inboxFor(String conversationId);
  Future<void> saveTrusted(TrustedContact contact);
  Future<TrustedContact?> trustedByDeviceId(String deviceId);
  Future<List<TrustedContact>> trustedContacts();
  Future<bool> hasSeen(String messageId);
  Future<void> markSeen(String messageId);
  Future<void> saveLocalLine(ChatLine line, String conversationId);
  Future<List<ChatLine>> linesFor(String conversationId);
  Future<void> saveSessionKey(String deviceId, List<int> key);
  Future<List<int>?> sessionKeyFor(String deviceId);
}

class MemorySlice1Repository implements Slice1Repository {
  final Map<String, OutboxRecord> outbox = {};
  final Map<String, InboxMessage> inbox = {};
  final Map<String, TrustedContact> trusted = {};
  final Set<String> seen = {};
  final Map<String, List<ChatLine>> lines = {};
  final Map<String, List<int>> sessionKeys = {};

  @override
  Future<void> upsertOutbox(OutboxRecord record) async {
    outbox[record.messageId] = record;
  }

  @override
  Future<OutboxRecord?> outboxById(String messageId) async => outbox[messageId];

  @override
  Future<List<OutboxRecord>> pendingOutbox() async {
    return outbox.values
        .where((r) =>
            r.state != OutboxState.delivered && r.state != OutboxState.expired)
        .toList();
  }

  @override
  Future<void> saveInbox(InboxMessage message) async {
    inbox.putIfAbsent(message.messageId, () => message);
  }

  @override
  Future<InboxMessage?> inboxById(String messageId) async => inbox[messageId];

  @override
  Future<List<InboxMessage>> inboxFor(String conversationId) async {
    return inbox.values
        .where((m) => m.conversationId == conversationId)
        .toList();
  }

  @override
  Future<void> saveTrusted(TrustedContact contact) async {
    trusted[contact.deviceId] = contact;
  }

  @override
  Future<TrustedContact?> trustedByDeviceId(String deviceId) async =>
      trusted[deviceId];

  @override
  Future<List<TrustedContact>> trustedContacts() async =>
      trusted.values.toList();

  @override
  Future<bool> hasSeen(String messageId) async => seen.contains(messageId);

  @override
  Future<void> markSeen(String messageId) async {
    seen.add(messageId);
  }

  @override
  Future<void> saveLocalLine(ChatLine line, String conversationId) async {
    final list = lines.putIfAbsent(conversationId, () => []);
    final idx = list.indexWhere((l) => l.messageId == line.messageId);
    if (idx >= 0) {
      list[idx] = line;
      return;
    }
    list.add(line);
  }

  @override
  Future<List<ChatLine>> linesFor(String conversationId) async =>
      List.unmodifiable(lines[conversationId] ?? const []);

  @override
  Future<void> saveSessionKey(String deviceId, List<int> key) async {
    sessionKeys[deviceId] = List<int>.from(key);
  }

  @override
  Future<List<int>?> sessionKeyFor(String deviceId) async {
    final key = sessionKeys[deviceId];
    return key == null ? null : List<int>.from(key);
  }
}
