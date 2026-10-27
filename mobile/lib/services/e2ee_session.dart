import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// X25519 ECDH + XChaCha20-Poly1305 session helper (Signal-style pre-key pattern).
class E2eeSession {
  E2eeSession();

  final X25519 _x25519 = X25519();
  final Cipher _cipher = Xchacha20.poly1305Aead();

  SimpleKeyPair? _identity;
  SecretKey? _sessionKey;

  Future<SimpleKeyPair> identityKeyPair() async {
    _identity ??= await _x25519.newKeyPair();
    return _identity!;
  }

  Future<String> publicKeyB64() async {
    final kp = await identityKeyPair();
    final pub = await kp.extractPublicKey();
    return base64Encode(pub.bytes);
  }

  Future<void> establish({
    required String theirIdentityB64,
    required String theirSignedPreKeyB64,
    String? theirOneTimePreKeyB64,
  }) async {
    final our = await identityKeyPair();
    final ephemeral = await _x25519.newKeyPair();
    final theirIdentity = SimplePublicKey(base64Decode(theirIdentityB64), type: KeyPairType.x25519);
    final theirSpk = SimplePublicKey(base64Decode(theirSignedPreKeyB64), type: KeyPairType.x25519);

    final dh1 = await _x25519.sharedSecretKey(keyPair: our, remotePublicKey: theirSpk);
    final dh2 = await _x25519.sharedSecretKey(keyPair: ephemeral, remotePublicKey: theirIdentity);
    final dh3 = await _x25519.sharedSecretKey(keyPair: ephemeral, remotePublicKey: theirSpk);

    final parts = <int>[
      ...await dh1.extractBytes(),
      ...await dh2.extractBytes(),
      ...await dh3.extractBytes(),
    ];
    if (theirOneTimePreKeyB64 != null) {
      final otpk = SimplePublicKey(base64Decode(theirOneTimePreKeyB64), type: KeyPairType.x25519);
      final dh4 = await _x25519.sharedSecretKey(keyPair: ephemeral, remotePublicKey: otpk);
      parts.addAll(await dh4.extractBytes());
    }

    final hash = await Sha256().hash(parts);
    _sessionKey = SecretKey(hash.bytes);
  }

  Future<Map<String, String>> encrypt(String plaintext) async {
    final key = _sessionKey;
    if (key == null) {
      throw StateError('E2EE session not established');
    }
    final nonce = _randomBytes(24);
    final box = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return {
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(box.concatenation(nonce: false)),
    };
  }

  Future<String> decrypt({required String ciphertextB64, required String nonceB64}) async {
    final key = _sessionKey;
    if (key == null) {
      throw StateError('E2EE session not established');
    }
    final nonce = base64Decode(nonceB64);
    final raw = base64Decode(ciphertextB64);
    final mac = Mac(raw.sublist(raw.length - 16));
    final cipherText = raw.sublist(0, raw.length - 16);
    final clear = await _cipher.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: mac),
      secretKey: key,
    );
    return utf8.decode(clear);
  }

  static List<int> _randomBytes(int n) {
    final rnd = Random.secure();
    return List<int>.generate(n, (_) => rnd.nextInt(256));
  }
}

Uint8List concatBytes(List<List<int>> chunks) {
  final total = chunks.fold<int>(0, (a, b) => a + b.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final c in chunks) {
    out.setAll(offset, c);
    offset += c.length;
  }
  return out;
}
