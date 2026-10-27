import 'dart:typed_data';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../core/storage/secure_database.dart';
import '../domain/models.dart';
import 'slice1_repository.dart';

class SqlSlice1Repository implements Slice1Repository {
  SqlSlice1Repository({SecureDatabase? database})
      : _database = database ?? SecureDatabase.instance;

  final SecureDatabase _database;

  Future<Database> _db() async {
    final db = await _database.open();
    await _ensureSchema(db);
    return db;
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slice1_outbox(
        message_id TEXT PRIMARY KEY,
        recipient_device_id TEXT NOT NULL,
        envelope TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        attempt_count INTEGER NOT NULL,
        last_attempt_at INTEGER,
        state TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slice1_inbox(
        message_id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender_device_id TEXT NOT NULL,
        recipient_device_id TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slice1_trusted(
        device_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        public_key TEXT NOT NULL,
        conversation_id TEXT NOT NULL,
        verified_at INTEGER NOT NULL,
        key_version INTEGER NOT NULL,
        endpoint_id TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slice1_seen(
        message_id TEXT PRIMARY KEY
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slice1_lines(
        message_id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        body TEXT NOT NULL,
        mine INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        status_label TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slice1_session(
        device_id TEXT PRIMARY KEY,
        session_key BLOB NOT NULL
      )
    ''');
  }

  @override
  Future<void> upsertOutbox(OutboxRecord record) async {
    final db = await _db();
    await db.insert(
      'slice1_outbox',
      {
        'message_id': record.messageId,
        'recipient_device_id': record.recipientDeviceId,
        'envelope': record.encryptedEnvelope.encode(),
        'created_at': record.createdAt.millisecondsSinceEpoch,
        'expires_at': record.expiresAt.millisecondsSinceEpoch,
        'attempt_count': record.attemptCount,
        'last_attempt_at': record.lastAttemptAt?.millisecondsSinceEpoch,
        'state': record.state.name,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<OutboxRecord?> outboxById(String messageId) async {
    final db = await _db();
    final rows = await db.query(
      'slice1_outbox',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _outboxFrom(rows.first);
  }

  @override
  Future<List<OutboxRecord>> pendingOutbox() async {
    final db = await _db();
    final rows = await db.query(
      'slice1_outbox',
      where: 'state NOT IN (?, ?)',
      whereArgs: [OutboxState.delivered.name, OutboxState.expired.name],
    );
    return rows.map(_outboxFrom).toList();
  }

  OutboxRecord _outboxFrom(Map<String, Object?> row) {
    return OutboxRecord(
      messageId: row['message_id']! as String,
      recipientDeviceId: row['recipient_device_id']! as String,
      encryptedEnvelope:
          EncryptedEnvelope.decode(row['envelope']! as String),
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(row['expires_at']! as int),
      attemptCount: row['attempt_count']! as int,
      lastAttemptAt: row['last_attempt_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['last_attempt_at']! as int),
      state: OutboxState.values.byName(row['state']! as String),
    );
  }

  @override
  Future<void> saveInbox(InboxMessage message) async {
    final db = await _db();
    await db.insert(
      'slice1_inbox',
      {
        'message_id': message.messageId,
        'conversation_id': message.conversationId,
        'sender_device_id': message.senderDeviceId,
        'recipient_device_id': message.recipientDeviceId,
        'body': message.body,
        'created_at': message.createdAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<InboxMessage?> inboxById(String messageId) async {
    final db = await _db();
    final rows = await db.query(
      'slice1_inbox',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return InboxMessage(
      messageId: row['message_id']! as String,
      conversationId: row['conversation_id']! as String,
      senderDeviceId: row['sender_device_id']! as String,
      recipientDeviceId: row['recipient_device_id']! as String,
      body: row['body']! as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
    );
  }

  @override
  Future<List<InboxMessage>> inboxFor(String conversationId) async {
    final db = await _db();
    final rows = await db.query(
      'slice1_inbox',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (row) => InboxMessage(
            messageId: row['message_id']! as String,
            conversationId: row['conversation_id']! as String,
            senderDeviceId: row['sender_device_id']! as String,
            recipientDeviceId: row['recipient_device_id']! as String,
            body: row['body']! as String,
            createdAt:
                DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
          ),
        )
        .toList();
  }

  @override
  Future<void> saveTrusted(TrustedContact contact) async {
    final db = await _db();
    await db.insert(
      'slice1_trusted',
      {
        'device_id': contact.deviceId,
        'display_name': contact.displayName,
        'public_key': contact.publicKeyB64,
        'conversation_id': contact.conversationId,
        'verified_at': contact.verifiedAt.millisecondsSinceEpoch,
        'key_version': contact.keyVersion,
        'endpoint_id': contact.endpointId,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<TrustedContact?> trustedByDeviceId(String deviceId) async {
    final db = await _db();
    final rows = await db.query(
      'slice1_trusted',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _trustedFrom(rows.first);
  }

  @override
  Future<List<TrustedContact>> trustedContacts() async {
    final db = await _db();
    final rows = await db.query('slice1_trusted');
    return rows.map(_trustedFrom).toList();
  }

  TrustedContact _trustedFrom(Map<String, Object?> row) {
    return TrustedContact(
      deviceId: row['device_id']! as String,
      displayName: row['display_name']! as String,
      publicKeyB64: row['public_key']! as String,
      conversationId: row['conversation_id']! as String,
      verifiedAt:
          DateTime.fromMillisecondsSinceEpoch(row['verified_at']! as int),
      keyVersion: row['key_version']! as int,
      endpointId: row['endpoint_id'] as String?,
    );
  }

  @override
  Future<bool> hasSeen(String messageId) async {
    final db = await _db();
    final rows = await db.query(
      'slice1_seen',
      where: 'message_id = ?',
      whereArgs: [messageId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<void> markSeen(String messageId) async {
    final db = await _db();
    await db.insert(
      'slice1_seen',
      {'message_id': messageId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  @override
  Future<void> saveLocalLine(ChatLine line, String conversationId) async {
    final db = await _db();
    await db.insert(
      'slice1_lines',
      {
        'message_id': line.messageId,
        'conversation_id': conversationId,
        'body': line.body,
        'mine': line.mine ? 1 : 0,
        'created_at': line.createdAt.millisecondsSinceEpoch,
        'status_label': line.statusLabel,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<ChatLine>> linesFor(String conversationId) async {
    final db = await _db();
    final rows = await db.query(
      'slice1_lines',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'created_at ASC',
    );
    return rows
        .map(
          (row) => ChatLine(
            messageId: row['message_id']! as String,
            body: row['body']! as String,
            mine: (row['mine']! as int) == 1,
            createdAt:
                DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
            statusLabel: row['status_label']! as String,
          ),
        )
        .toList();
  }

  @override
  Future<void> saveSessionKey(String deviceId, List<int> key) async {
    final db = await _db();
    await db.insert(
      'slice1_session',
      {
        'device_id': deviceId,
        'session_key': Uint8List.fromList(key),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<int>?> sessionKeyFor(String deviceId) async {
    final db = await _db();
    final rows = await db.query(
      'slice1_session',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final raw = rows.first['session_key'];
    if (raw is List<int>) return List<int>.from(raw);
    return null;
  }
}
