import '../storage/offline_store.dart';

abstract class OfflineRepository {
  Future<void> enqueue(EncryptedOutboxRecord record);
  Future<EncryptedOutboxRecord?> byId(String messageId);
  Future<List<EncryptedOutboxRecord>> pending();
  Future<List<EncryptedOutboxRecord>> retryable({required DateTime now});
  Future<void> updateState({
    required String messageId,
    required OutboxState state,
    int? attemptCount,
    DateTime? lastAttemptAt,
  });
  Future<void> markExpiredIfNeeded(DateTime now);
  Future<void> upsertContact(TrustedContact contact);
  Future<TrustedContact?> contact(String deviceId);
  Future<bool> insertInbox(InboxRecord record);
  Future<Set<String>> seenIds();
  Future<void> markSeen(String messageId);
  Future<List<InboxRecord>> inboxFor(String senderDeviceId);
  Future<List<TrustedContact>> contacts();
}

class MemoryOfflineRepository implements OfflineRepository {
  MemoryOfflineRepository([MemoryOfflineStore? store])
      : _store = store ?? MemoryOfflineStore();

  final MemoryOfflineStore _store;

  @override
  Future<void> enqueue(EncryptedOutboxRecord record) => _store.enqueue(record);

  @override
  Future<EncryptedOutboxRecord?> byId(String messageId) => _store.byId(messageId);

  @override
  Future<List<EncryptedOutboxRecord>> pending() => _store.pending();

  @override
  Future<List<EncryptedOutboxRecord>> retryable({required DateTime now}) =>
      _store.retryable(now: now);

  @override
  Future<void> updateState({
    required String messageId,
    required OutboxState state,
    int? attemptCount,
    DateTime? lastAttemptAt,
  }) =>
      _store.updateState(
        messageId: messageId,
        state: state,
        attemptCount: attemptCount,
        lastAttemptAt: lastAttemptAt,
      );

  @override
  Future<void> markExpiredIfNeeded(DateTime now) => _store.markExpiredIfNeeded(now);

  @override
  Future<void> upsertContact(TrustedContact contact) => _store.upsertContact(contact);

  @override
  Future<TrustedContact?> contact(String deviceId) => _store.contact(deviceId);

  @override
  Future<bool> insertInbox(InboxRecord record) => _store.insertInbox(record);

  @override
  Future<Set<String>> seenIds() => _store.seenIds();

  @override
  Future<void> markSeen(String messageId) => _store.markSeen(messageId);

  @override
  Future<List<InboxRecord>> inboxFor(String senderDeviceId) async {
    return _store.inbox.values
        .where((r) => r.senderDeviceId == senderDeviceId)
        .toList(growable: false);
  }

  @override
  Future<List<TrustedContact>> contacts() async =>
      _store.contactsMap.values.toList(growable: false);
}

class SqlOfflineRepository implements OfflineRepository {
  SqlOfflineRepository({OfflineStore? store}) : _store = store ?? OfflineStore();

  final OfflineStore _store;

  @override
  Future<void> enqueue(EncryptedOutboxRecord record) => _store.enqueue(record);

  @override
  Future<EncryptedOutboxRecord?> byId(String messageId) => _store.byId(messageId);

  @override
  Future<List<EncryptedOutboxRecord>> pending() => _store.pending();

  @override
  Future<List<EncryptedOutboxRecord>> retryable({required DateTime now}) =>
      _store.retryable(now: now);

  @override
  Future<void> updateState({
    required String messageId,
    required OutboxState state,
    int? attemptCount,
    DateTime? lastAttemptAt,
  }) =>
      _store.updateState(
        messageId: messageId,
        state: state,
        attemptCount: attemptCount,
        lastAttemptAt: lastAttemptAt,
      );

  @override
  Future<void> markExpiredIfNeeded(DateTime now) => _store.markExpiredIfNeeded(now);

  @override
  Future<void> upsertContact(TrustedContact contact) => _store.upsertContact(contact);

  @override
  Future<TrustedContact?> contact(String deviceId) => _store.contact(deviceId);

  @override
  Future<bool> insertInbox(InboxRecord record) => _store.insertInbox(record);

  @override
  Future<Set<String>> seenIds() => _store.seenIds();

  @override
  Future<void> markSeen(String messageId) => _store.markSeen(messageId);

  @override
  Future<List<InboxRecord>> inboxFor(String senderDeviceId) =>
      _store.inboxFor(senderDeviceId);

  @override
  Future<List<TrustedContact>> contacts() => _store.contacts();
}
