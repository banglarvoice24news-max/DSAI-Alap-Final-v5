import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_comm/offline_slice1/data/slice1_repository.dart';
import 'package:nexus_comm/offline_slice1/domain/models.dart';

EncryptedEnvelope _env(String id) {
  final now = DateTime.utc(2026, 1, 1);
  return EncryptedEnvelope(
    version: 1,
    messageId: id,
    conversationId: 'a:b',
    senderDeviceId: 'a',
    recipientDeviceId: 'b',
    createdAt: now,
    expiresAt: now.add(const Duration(hours: 1)),
    keyVersion: 1,
    nonce: 'nonce',
    ciphertext: 'cipher',
    signature: 'sig',
  );
}

void main() {
  test('outbox state transitions stay unique by messageId', () async {
    final repo = MemorySlice1Repository();
    final envelope = _env('m1');
    var record = OutboxRecord(
      messageId: 'm1',
      recipientDeviceId: 'b',
      encryptedEnvelope: envelope,
      createdAt: envelope.createdAt,
      expiresAt: envelope.expiresAt,
      attemptCount: 0,
      state: OutboxState.queued,
    );
    await repo.upsertOutbox(record);
    record = record.copyWith(state: OutboxState.sending, attemptCount: 1);
    await repo.upsertOutbox(record);
    record = record.copyWith(state: OutboxState.sentWaitingAck);
    await repo.upsertOutbox(record);
    record = record.copyWith(state: OutboxState.delivered);
    await repo.upsertOutbox(record);
    expect(repo.outbox.length, 1);
    expect(repo.outbox['m1']!.state, OutboxState.delivered);
    expect(await repo.pendingOutbox(), isEmpty);
  });

  test('failed retryable remains pending', () async {
    final repo = MemorySlice1Repository();
    final envelope = _env('m2');
    await repo.upsertOutbox(
      OutboxRecord(
        messageId: 'm2',
        recipientDeviceId: 'b',
        encryptedEnvelope: envelope,
        createdAt: envelope.createdAt,
        expiresAt: envelope.expiresAt,
        attemptCount: 2,
        lastAttemptAt: envelope.createdAt,
        state: OutboxState.failedRetryable,
      ),
    );
    expect((await repo.pendingOutbox()).single.messageId, 'm2');
  });

  test('retry backoff doubles with attempt count', () {
    Duration delayFor(int attemptCount) {
      return Duration(milliseconds: 1000 * (1 << attemptCount.clamp(0, 6)));
    }

    expect(delayFor(0), const Duration(seconds: 1));
    expect(delayFor(1), const Duration(seconds: 2));
    expect(delayFor(2), const Duration(seconds: 4));
    expect(delayFor(3), const Duration(seconds: 8));
  });
}
