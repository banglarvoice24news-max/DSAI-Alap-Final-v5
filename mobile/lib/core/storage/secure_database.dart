import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'secure_store.dart';

/// A message waiting for a transport, persisted at rest only as SQLCipher
/// ciphertext. [transport] is stored as the enum `name` so this core layer
/// stays independent of feature-layer types.
class OutboxEntry {
  const OutboxEntry({
    required this.id,
    required this.threadId,
    required this.body,
    required this.transport,
    required this.createdAt,
  });

  final String id;
  final String threadId;
  final String body;
  final String transport;
  final DateTime createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'thread_id': threadId,
        'body': body,
        'transport': transport,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory OutboxEntry.fromMap(Map<String, Object?> map) => OutboxEntry(
        id: map['id']! as String,
        threadId: map['thread_id']! as String,
        body: map['body']! as String,
        transport: map['transport']! as String,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(map['created_at']! as int),
      );
}

/// SQLCipher-backed local database.
///
/// The 256-bit database key is generated with a CSPRNG on first run and kept in
/// [SecureStore] (Android EncryptedSharedPreferences / iOS Keychain), so the
/// key never touches plain application storage and is never logged.
class SecureDatabase {
  SecureDatabase({
    SecureStore? secureStore,
    Future<Directory> Function()? directoryProvider,
  })  : _secureStore = secureStore ?? SecureStore(),
        _directoryProvider =
            directoryProvider ?? getApplicationSupportDirectory;

  /// Process-wide handle so every store shares one open connection.
  static final SecureDatabase instance = SecureDatabase();

  static const String _keyName = 'db_key';
  static const String _fileName = 'nexus_secure.db';
  static const int _schemaVersion = 1;

  final SecureStore _secureStore;
  final Future<Directory> Function() _directoryProvider;

  Database? _db;

  Future<Database> open() async {
    final existing = _db;
    if (existing != null) return existing;

    final key = await _loadOrCreateKey();
    final dir = await _directoryProvider();
    final db = await openDatabase(
      p.join(dir.path, _fileName),
      password: key,
      version: _schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE outbox(
            id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            body TEXT NOT NULL,
            transport TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_outbox_thread ON outbox(thread_id, created_at)',
        );
      },
    );
    _db = db;
    return db;
  }

  Future<String> _loadOrCreateKey() async {
    final stored = await _secureStore.read(_keyName);
    if (stored != null && stored.isNotEmpty) return stored;

    final rng = Random.secure();
    final bytes = List<int>.generate(32, (_) => rng.nextInt(256));
    final key = base64Url.encode(bytes);
    await _secureStore.write(_keyName, key);
    return key;
  }

  Future<void> close() async {
    final db = _db;
    _db = null;
    await db?.close();
  }
}

/// Encrypted, durable outbox for messages that have not confirmed delivery.
class OutboxStore {
  OutboxStore({SecureDatabase? database})
      : _database = database ?? SecureDatabase.instance;

  static const String _table = 'outbox';

  final SecureDatabase _database;

  Future<void> enqueue(OutboxEntry entry) async {
    final db = await _database.open();
    await db.insert(
      _table,
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<OutboxEntry>> forThread(String threadId) async {
    final db = await _database.open();
    final rows = await db.query(
      _table,
      where: 'thread_id = ?',
      whereArgs: [threadId],
      orderBy: 'created_at ASC',
    );
    return rows.map(OutboxEntry.fromMap).toList(growable: false);
  }

  Future<void> remove(String id) async {
    final db = await _database.open();
    await db.delete(_table, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clear() async {
    final db = await _database.open();
    await db.delete(_table);
  }
}
