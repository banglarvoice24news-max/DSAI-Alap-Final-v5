import 'dart:convert';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../crypto/encrypted_envelope.dart';
import 'secure_database.dart';

enum OutboxState {
  queued,
  sending,
  sentWaitingAck,
  delivered,
  failedRetryable,
  expired,
}

class EncryptedOutboxRecord {
  const EncryptedOutboxRecord({
    required this.messageId,
    required this.recipientDeviceId,
    required this.envelopeJson,
    required this.createdAt,
    required this.expiresAt,
    required this.attemptCount,
    required this.state,
    this.lastAttemptAt,
    this.plaintextHint,
  });

  final String messageId;
  final String recipientDeviceId;
  final String envelopeJson;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final OutboxState state;
  final String? plaintextHint;

  EncryptedEnvelope get envelope => EncryptedEnvelope.decode(envelopeJson);

  EncryptedOutboxRecord copyWith({
    int? attemptCount,
    DateTime? lastAttemptAt,
    OutboxState? state,
  }) {
    return EncryptedOutboxRecord(
      messageId: messageId,
      recipientDeviceId: recipientDeviceId,
      envelopeJson: envelopeJson,
      createdAt: createdAt,
      expiresAt: expiresAt,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      state: state ?? this.state,
      plaintextHint: plaintextHint,
    );
  }
}

class TrustedContact {
  const TrustedContact({
    required this.deviceId,
    required this.displayName,
    required this.publicKeyB64,
    required this.safetyCode,
    required this.sessionKeyB64,
    required this.confirmedAt,
  });

  final String deviceId;
  final String displayName;
  final String publicKeyB64;
  final String safetyCode;
  final String sessionKeyB64;
  final DateTime confirmedAt;
}

class InboxRecord {
  const InboxRecord({
    required this.messageId,
    required this.senderDeviceId,
    required this.body,
    required this.createdAt,
    required this.kind,
  });

  final String messageId;
  final String senderDeviceId;
  final String body;
  final DateTime createdAt;
  final String kind;
}

class OfflineStore {
  OfflineStore({SecureDatabase? database})
      : _database = database ?? SecureDatabase.instance;

  final SecureDatabase _database;

  Future<void> ensureMigrated() async {
    final db = await _database.open();
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slice1_outbox(
        message_id TEXT PRIMARY KEY,
        recipient_device_id TEXT NOT NULL,
        envelope_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        attempt_count INTEGER NOT NULL,
        last_attempt_at INTEGER,
        state TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slice1_contacts(
        device_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        public_key_b64 TEXT NOT NULL,
        safety_code TEXT NOT NULL,
        session_key_b64 TEXT NOT NULL,
        confirmed_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slice1_inbox(
        message_id TEXT PRIMARY KEY,
        sender_device_id TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        kind TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slice1_seen(
        message_id TEXT PRIMARY KEY
      )
    ''');
  }

  Future<void> enqueue(EncryptedOutboxRecord record) async {
    final db = await _database.open();
    await ensureMigrated();
    await db.insert(
      'slice1_outbox',
      {
        'message_id': record.messageId,
        'recipient_device_id': record.recipientDeviceId,
        'envelope_json': record.envelopeJson,
        'created_at': record.createdAt.millisecondsSinceEpoch,
        'expires_at': record.expiresAt.millisecondsSinceEpoch,
        'attempt_count': record.attemptCount,
        'last_attempt_at': record.lastAttemptAt?.millisecondsSinceEpoch,
        'state': record.state.name,
      },
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  Future<EncryptedOutboxRecord?> byId(String messageId) async {
    final db = await _database.open();
    await ensureMigrated();
    final rows = await db.query(
      'slice1_outbox',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _outboxFrom(rows.first);
  }

  Future<List<EncryptedOutboxRecord>> pending() async {
    final db = await _database.open();
    await ensureMigrated();
    final rows = await db.query(
      'slice1_outbox',
      where: 'state IN (?, ?, ?, ?)',
      whereArgs: [
        OutboxState.queued.name,
        OutboxState.sending.name,
        OutboxState.failedRetryable.name,
        OutboxState.sentWaitingAck.name,
      ],
      orderBy: 'created_at ASC',
    );
    return rows.map(_outboxFrom).toList(growable: false);
  }

  Future<List<EncryptedOutboxRecord>> retryable({required DateTime now}) async {
    final db = await _database.open();
    await ensureMigrated();
    final rows = await db.query(
      'slice1_outbox',
      where: 'state IN (?, ?) AND expires_at > ?',
      whereArgs: [
        OutboxState.queued.name,
        OutboxState.failedRetryable.name,
        now.millisecondsSinceEpoch,
      ],
      orderBy: 'created_at ASC',
    );
    return rows.map(_outboxFrom).toList(growable: false);
  }

  Future<void> updateState({
    required String messageId,
    required OutboxState state,
    int? attemptCount,
    DateTime? lastAttemptAt,
  }) async {
    final db = await _database.open();
    await ensureMigrated();
    final values = <String, Object?>{'state': state.name};
    if (attemptCount != null) values['attempt_count'] = attemptCount;
    if (lastAttemptAt != null) {
      values['last_attempt_at'] = lastAttemptAt.millisecondsSinceEpoch;
    }
    await db.update(
      'slice1_outbox',
      values,
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> markExpiredIfNeeded(DateTime now) async {
    final db = await _database.open();
    await ensureMigrated();
    await db.update(
      'slice1_outbox',
      {'state': OutboxState.expired.name},
      where: 'expires_at <= ? AND state != ? AND state != ?',
      whereArgs: [
        now.millisecondsSinceEpoch,
        OutboxState.delivered.name,
        OutboxState.expired.name,
      ],
    );
  }

  Future<void> upsertContact(TrustedContact contact) async {
    final db = await _database.open();
    await ensureMigrated();
    await db.insert(
      'slice1_contacts',
      {
        'device_id': contact.deviceId,
        'display_name': contact.displayName,
        'public_key_b64': contact.publicKeyB64,
        'safety_code': contact.safetyCode,
        'session_key_b64': contact.sessionKeyB64,
        'confirmed_at': contact.confirmedAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<TrustedContact?> contact(String deviceId) async {
    final db = await _database.open();
    await ensureMigrated();
    final rows = await db.query(
      'slice1_contacts',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return TrustedContact(
      deviceId: row['device_id']! as String,
      displayName: row['display_name']! as String,
      publicKeyB64: row['public_key_b64']! as String,
      safetyCode: row['safety_code']! as String,
      sessionKeyB64: row['session_key_b64']! as String,
      confirmedAt: DateTime.fromMillisecondsSinceEpoch(row['confirmed_at']! as int),
    );
  }

  Future<List<TrustedContact>> contacts() async {
    final db = await _database.open();
    await ensureMigrated();
    final rows = await db.query('slice1_contacts', orderBy: 'confirmed_at DESC');
    return rows
        .map(
          (row) => TrustedContact(
            deviceId: row['device_id']! as String,
            displayName: row['display_name']! as String,
            publicKeyB64: row['public_key_b64']! as String,
            safetyCode: row['safety_code']! as String,
            sessionKeyB64: row['session_key_b64']! as String,
            confirmedAt:
                DateTime.fromMillisecondsSinceEpoch(row['confirmed_at']! as int),
          ),
        )
        .toList(growable: false);
  }

  Future<bool> insertInbox(InboxRecord record) async {
    final db = await _database.open();
    await ensureMigrated();
    try {
      await db.insert('slice1_inbox', {
        'message_id': record.messageId,
        'sender_device_id': record.senderDeviceId,
        'body': record.body,
        'created_at': record.createdAt.millisecondsSinceEpoch,
        'kind': record.kind,
      });
      await db.insert('slice1_seen', {'message_id': record.messageId});
      return true;
    } on DatabaseException {
      return false;
    }
  }

  Future<List<InboxRecord>> inboxFor(String senderDeviceId) async {
    final db = await _database.open();
    await ensureMigrated();
    final rows = await db.query(
      'slice1_inbox',
      where: 'sender_device_id = ?',
      whereArgs: [senderDeviceId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (row) => InboxRecord(
            messageId: row['message_id']! as String,
            senderDeviceId: row['sender_device_id']! as String,
            body: row['body']! as String,
            createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
            kind: row['kind']! as String,
          ),
        )
        .toList(growable: false);
  }

  Future<Set<String>> seenIds() async {
    final db = await _database.open();
    await ensureMigrated();
    final rows = await db.query('slice1_seen');
    return rows.map((r) => r['message_id']! as String).toSet();
  }

  Future<void> markSeen(String messageId) async {
    final db = await _database.open();
    await ensureMigrated();
    await db.insert(
      'slice1_seen',
      {'message_id': messageId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  EncryptedOutboxRecord _outboxFrom(Map<String, Object?> row) {
    return EncryptedOutboxRecord(
      messageId: row['message_id']! as String,
      recipientDeviceId: row['recipient_device_id']! as String,
      envelopeJson: row['envelope_json']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(row['expires_at']! as int),
      attemptCount: row['attempt_count']! as int,
      lastAttemptAt: row['last_attempt_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['last_attempt_at']! as int),
      state: OutboxState.values.byName(row['state']! as String),
    );
  }
}

class MemoryOfflineStore {
  final Map<String, EncryptedOutboxRecord> outbox = {};
  final Map<String, TrustedContact> contactsMap = {};
  final Map<String, InboxRecord> inbox = {};
  final Set<String> seen = {};

  Future<void> enqueue(EncryptedOutboxRecord record) async {
    if (outbox.containsKey(record.messageId)) {
      throw StateError('duplicate-message-id');
    }
    outbox[record.messageId] = record;
  }

  Future<EncryptedOutboxRecord?> byId(String messageId) async => outbox[messageId];

  Future<List<EncryptedOutboxRecord>> pending() async {
    return outbox.values
        .where((r) =>
            r.state == OutboxState.queued ||
            r.state == OutboxState.sending ||
            r.state == OutboxState.failedRetryable ||
            r.state == OutboxState.sentWaitingAck)
        .toList(growable: false);
  }

  Future<List<EncryptedOutboxRecord>> retryable({required DateTime now}) async {
    return outbox.values
        .where((r) =>
            (r.state == OutboxState.queued || r.state == OutboxState.failedRetryable) &&
            r.expiresAt.isAfter(now))
        .toList(growable: false);
  }

  Future<void> updateState({
    required String messageId,
    required OutboxState state,
    int? attemptCount,
    DateTime? lastAttemptAt,
  }) async {
    final current = outbox[messageId];
    if (current == null) return;
    outbox[messageId] = current.copyWith(
      state: state,
      attemptCount: attemptCount,
      lastAttemptAt: lastAttemptAt,
    );
  }

  Future<void> markExpiredIfNeeded(DateTime now) async {
    for (final id in outbox.keys.toList()) {
      final r = outbox[id]!;
      if (r.state != OutboxState.delivered &&
          r.state != OutboxState.expired &&
          !r.expiresAt.isAfter(now)) {
        outbox[id] = r.copyWith(state: OutboxState.expired);
      }
    }
  }

  Future<void> upsertContact(TrustedContact contact) async {
    contactsMap[contact.deviceId] = contact;
  }

  Future<TrustedContact?> contact(String deviceId) async => contactsMap[deviceId];

  Future<bool> insertInbox(InboxRecord record) async {
    if (inbox.containsKey(record.messageId) || seen.contains(record.messageId)) {
      return false;
    }
    inbox[record.messageId] = record;
    seen.add(record.messageId);
    return true;
  }

  Future<Set<String>> seenIds() async => Set.of(seen);

  Future<void> markSeen(String messageId) async {
    seen.add(messageId);
  }
}

Duration retryDelay(int attemptCount) {
  final seconds = 1 << attemptCount.clamp(0, 5);
  return Duration(seconds: seconds);
}

String envelopeWithoutPlaintext(EncryptedEnvelope envelope) =>
    jsonEncode(envelope.toJson());
