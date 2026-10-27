import 'package:uuid/uuid.dart';

import '../../core/storage/secure_store.dart';
import '../domain/crypto_protocol.dart';
import '../domain/models.dart';

abstract class IdentityKeyStore {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
}

class SecureIdentityKeyStore implements IdentityKeyStore {
  SecureIdentityKeyStore([SecureStore? store]) : _store = store ?? SecureStore();

  final SecureStore _store;

  @override
  Future<void> write(String key, String value) => _store.write(key, value);

  @override
  Future<String?> read(String key) => _store.read(key);
}

class MemoryIdentityKeyStore implements IdentityKeyStore {
  final Map<String, String> values;

  MemoryIdentityKeyStore([Map<String, String>? values]) : values = values ?? {};

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<String?> read(String key) async => values[key];
}

class IdentityService {
  IdentityService({
    IdentityKeyStore? keys,
    SecureStore? store,
    Slice1Crypto? crypto,
    Uuid? uuid,
  })  : _keys = keys ?? SecureIdentityKeyStore(store),
        _crypto = crypto ?? Slice1Crypto(),
        _uuid = uuid ?? const Uuid();

  static const publicKey = 'slice1_identity_pub';
  static const privateKey = 'slice1_identity_priv';
  static const displayNameKey = 'slice1_display_name';
  static const linkedHintKey = 'slice1_linked_account';

  final IdentityKeyStore _keys;
  final Slice1Crypto _crypto;
  final Uuid _uuid;

  Future<DeviceIdentity> loadOrCreate({String? linkedAccountHint}) async {
    var deviceId = await _keys.read(SecureStore.deviceId);
    if (deviceId == null || deviceId.isEmpty) {
      deviceId = _uuid.v4();
      await _keys.write(SecureStore.deviceId, deviceId);
    }

    if (linkedAccountHint != null && linkedAccountHint.isNotEmpty) {
      await _keys.write(linkedHintKey, linkedAccountHint);
    }

    final existingPub = await _keys.read(publicKey);
    final existingPriv = await _keys.read(privateKey);
    if (existingPub != null &&
        existingPub.isNotEmpty &&
        existingPriv != null &&
        existingPriv.isNotEmpty) {
      return DeviceIdentity(
        deviceId: deviceId,
        publicKeyB64: existingPub,
        privateKeyB64: existingPriv,
        displayName: await _keys.read(displayNameKey),
        linkedAccountHint: await _keys.read(linkedHintKey),
      );
    }

    final identity = await _crypto.createIdentity(
      deviceId: deviceId,
      displayName: 'Nexus-${deviceId.substring(0, 8)}',
      linkedAccountHint: await _keys.read(linkedHintKey) ?? linkedAccountHint,
    );
    await _keys.write(publicKey, identity.publicKeyB64);
    await _keys.write(privateKey, identity.privateKeyB64);
    await _keys.write(displayNameKey, identity.shortName);
    return identity;
  }
}
