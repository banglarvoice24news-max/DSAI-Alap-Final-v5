import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../storage/secret_store.dart';
import '../storage/secure_store.dart';

abstract class IdentityKeyStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
}

class SecureIdentityKeyStore implements IdentityKeyStore {
  SecureIdentityKeyStore({SecureStore? store}) : _store = store ?? SecureStore();
  final SecureStore _store;

  @override
  Future<void> write(String key, String value) => _store.write(key, value);

  @override
  Future<String?> read(String key) => _store.read(key);
}

class MemoryIdentityKeyStore implements IdentityKeyStore {
  MemoryIdentityKeyStore({MemorySecretStore? store})
      : _store = store ?? MemorySecretStore();
  final MemorySecretStore _store;

  @override
  Future<void> write(String key, String value) => _store.write(key, value);

  @override
  Future<String?> read(String key) => _store.read(key);
}

class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.displayName,
    required this.publicKeyBytes,
    required this.seed,
    this.linkedAccount = false,
    this.linkedAccountHint,
  });

  final String deviceId;
  final String displayName;
  final List<int> publicKeyBytes;
  final List<int> seed;
  final bool linkedAccount;
  final String? linkedAccountHint;

  String get publicKeyB64 => base64Encode(publicKeyBytes);

  String get shortName {
    final tail = deviceId.replaceAll('-', '');
    final suffix = tail.length >= 4 ? tail.substring(tail.length - 4) : tail;
    return 'Nexus-$suffix';
  }
}

class DeviceIdentityService {
  DeviceIdentityService({IdentityKeyStore? store})
      : _store = store ?? SecureIdentityKeyStore();

  static const _seedKey = 'identity_ed25519_seed';
  static const _pubKey = 'identity_ed25519_pub';
  static const _nameKey = 'identity_display_name';
  static const _linkedHintKey = 'identity_linked_account';

  final IdentityKeyStore _store;
  final Ed25519 _ed25519 = Ed25519();

  DeviceIdentity? _cached;

  Future<DeviceIdentity> loadOrCreate({String? linkedAccountHint}) async {
    if (linkedAccountHint != null && linkedAccountHint.isNotEmpty) {
      await _store.write(_linkedHintKey, linkedAccountHint);
      _cached = null;
    }

    final cached = _cached;
    if (cached != null) return cached;

    var deviceId = await _store.read(SecureStore.deviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = const Uuid().v4();
      await _store.write(SecureStore.deviceId, deviceId);
    }

    final token = await _store.read(SecureStore.accessToken);
    final hint = await _store.read(_linkedHintKey);
    final linked = (token != null && token.isNotEmpty) ||
        (hint != null && hint.isNotEmpty);
    final storedSeed = await _store.read(_seedKey);
    if (storedSeed != null && storedSeed.isNotEmpty) {
      final seed = base64Decode(storedSeed);
      final keyPair = await _ed25519.newKeyPairFromSeed(seed);
      final pub = await keyPair.extractPublicKey();
      final name = await _store.read(_nameKey);
      final identity = DeviceIdentity(
        deviceId: deviceId,
        displayName: name ?? _displayNameFor(deviceId),
        publicKeyBytes: pub.bytes,
        seed: seed,
        linkedAccount: linked,
        linkedAccountHint: hint,
      );
      _cached = identity;
      return identity;
    }

    final seed = _randomBytes(32);
    final keyPair = await _ed25519.newKeyPairFromSeed(seed);
    final pub = await keyPair.extractPublicKey();
    final name = _displayNameFor(deviceId);
    await _store.write(_seedKey, base64Encode(seed));
    await _store.write(_pubKey, base64Encode(pub.bytes));
    await _store.write(_nameKey, name);
    final identity = DeviceIdentity(
      deviceId: deviceId,
      displayName: name,
      publicKeyBytes: pub.bytes,
      seed: seed,
      linkedAccount: linked,
      linkedAccountHint: hint,
    );
    _cached = identity;
    return identity;
  }

  Future<SimpleKeyPair> keyPair() async {
    final identity = await loadOrCreate();
    return _ed25519.newKeyPairFromSeed(identity.seed);
  }

  Future<Signature> sign(List<int> message) async {
    final kp = await keyPair();
    return _ed25519.sign(message, keyPair: kp);
  }

  Future<bool> verify({
    required List<int> message,
    required List<int> signatureBytes,
    required List<int> publicKeyBytes,
  }) async {
    return _ed25519.verify(
      message,
      signature: Signature(
        signatureBytes,
        publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      ),
    );
  }

  static String _displayNameFor(String deviceId) {
    final tail = deviceId.replaceAll('-', '');
    final suffix = tail.length >= 4 ? tail.substring(tail.length - 4) : tail;
    return 'Nexus-$suffix';
  }

  static Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rng.nextInt(256)));
  }
}
