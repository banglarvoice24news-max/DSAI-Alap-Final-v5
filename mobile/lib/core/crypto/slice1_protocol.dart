import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../identity/device_identity.dart';
import 'encrypted_envelope.dart';

class HandshakeMaterial {
  HandshakeMaterial({
    required this.localEphPub,
    required this.localEphPriv,
    required this.remoteDeviceId,
    required this.remoteDisplayName,
    required this.remoteIdentityPub,
    required this.remoteEphPub,
    required this.transcript,
    required this.safetyCode,
    required this.sessionKeyBytes,
  });

  final List<int> localEphPub;
  final List<int> localEphPriv;
  final String remoteDeviceId;
  final String remoteDisplayName;
  final List<int> remoteIdentityPub;
  final List<int> remoteEphPub;
  final List<int> transcript;
  final String safetyCode;
  final List<int> sessionKeyBytes;
}

class DecryptedPayload {
  const DecryptedPayload({required this.kind, required this.body, required this.ackFor});

  final String kind;
  final String body;
  final String? ackFor;
}

class Slice1Protocol {
  Slice1Protocol({DeviceIdentityService? identity, Uuid? uuid})
      : _identity = identity ?? DeviceIdentityService(),
        _uuid = uuid ?? const Uuid();

  static const int version = 1;
  static const int keyVersion = 1;
  static const Duration messageTtl = Duration(hours: 24);
  static const String kdfInfo = 'nexus-slice1-v1';

  final DeviceIdentityService _identity;
  final Uuid _uuid;
  final X25519 _x25519 = X25519();
  final AesGcm _aes = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final Sha256 _sha256 = Sha256();

  Future<(List<int> pub, List<int> priv)> newEphemeral() async {
    final kp = await _x25519.newKeyPair();
    final pub = await kp.extractPublicKey();
    final priv = await kp.extractPrivateKeyBytes();
    return (List<int>.from(pub.bytes), List<int>.from(priv));
  }

  Future<HandshakeMaterial> completeHandshake({
    required DeviceIdentity local,
    required List<int> localEphPub,
    required List<int> localEphPriv,
    required String remoteDeviceId,
    required String remoteDisplayName,
    required List<int> remoteIdentityPub,
    required List<int> remoteEphPub,
  }) async {
    final transcript = await transcriptHash(
      localDeviceId: local.deviceId,
      remoteDeviceId: remoteDeviceId,
      localEphPub: localEphPub,
      remoteEphPub: remoteEphPub,
    );
    final localKp = SimpleKeyPairData(
      localEphPriv,
      publicKey: SimplePublicKey(localEphPub, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
    final remotePub = SimplePublicKey(remoteEphPub, type: KeyPairType.x25519);
    final shared = await _x25519.sharedSecretKey(
      keyPair: localKp,
      remotePublicKey: remotePub,
    );
    final session = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: transcript,
      info: utf8.encode(kdfInfo),
    );
    final sessionBytes = await session.extractBytes();
    final code = await safetyCode(
      localIdentityPub: local.publicKeyBytes,
      remoteIdentityPub: remoteIdentityPub,
      transcript: transcript,
    );
    return HandshakeMaterial(
      localEphPub: localEphPub,
      localEphPriv: localEphPriv,
      remoteDeviceId: remoteDeviceId,
      remoteDisplayName: remoteDisplayName,
      remoteIdentityPub: remoteIdentityPub,
      remoteEphPub: remoteEphPub,
      transcript: transcript,
      safetyCode: code,
      sessionKeyBytes: List<int>.from(sessionBytes),
    );
  }

  Future<List<int>> transcriptHash({
    required String localDeviceId,
    required String remoteDeviceId,
    required List<int> localEphPub,
    required List<int> remoteEphPub,
  }) async {
    final ids = [localDeviceId, remoteDeviceId]..sort();
    final eph = _orderedPair(localEphPub, remoteEphPub);
    final payload = <int>[
      ...utf8.encode(ids[0]),
      0,
      ...utf8.encode(ids[1]),
      0,
      ...eph[0],
      0,
      ...eph[1],
    ];
    final hash = await _sha256.hash(payload);
    return hash.bytes;
  }

  Future<String> safetyCode({
    required List<int> localIdentityPub,
    required List<int> remoteIdentityPub,
    required List<int> transcript,
  }) async {
    final pubs = _orderedPair(localIdentityPub, remoteIdentityPub);
    final payload = <int>[...pubs[0], 0, ...pubs[1], 0, ...transcript];
    final hash = await _sha256.hash(payload);
    final n = ByteData.sublistView(Uint8List.fromList(hash.bytes), 0, 4)
        .getUint32(0, Endian.big);
    return (n % 1000000).toString().padLeft(6, '0');
  }

  Future<List<int>> signTranscript(List<int> transcript) async {
    final sig = await _identity.sign(transcript);
    return sig.bytes;
  }

  Future<bool> verifyTranscript({
    required List<int> transcript,
    required List<int> signature,
    required List<int> publicKey,
  }) {
    return _identity.verify(
      message: transcript,
      signatureBytes: signature,
      publicKeyBytes: publicKey,
    );
  }

  Future<EncryptedEnvelope> encrypt({
    required DeviceIdentity sender,
    required String recipientDeviceId,
    required List<int> sessionKeyBytes,
    required String conversationId,
    required DecryptedPayload payload,
    DateTime? now,
    Duration? ttl,
    String? messageId,
  }) async {
    final created = now ?? DateTime.now().toUtc();
    final expires = created.add(ttl ?? messageTtl);
    final id = messageId ?? _uuid.v4();
    final nonce = _randomBytes(12);
    final body = jsonEncode({
      'k': payload.kind,
      'b': payload.body,
      if (payload.ackFor != null) 'ack': payload.ackFor,
    });
    final draft = EncryptedEnvelope(
      version: version,
      messageId: id,
      conversationId: conversationId,
      senderDeviceId: sender.deviceId,
      recipientDeviceId: recipientDeviceId,
      createdAt: created,
      expiresAt: expires,
      keyVersion: keyVersion,
      nonce: nonce,
      ciphertext: const [],
      signature: const [],
    );
    final box = await _aes.encrypt(
      utf8.encode(body),
      secretKey: SecretKey(sessionKeyBytes),
      nonce: nonce,
      aad: draft.aadBytes(),
    );
    final ciphertext = <int>[...box.cipherText, ...box.mac.bytes];
    final withCipher = EncryptedEnvelope(
      version: draft.version,
      messageId: draft.messageId,
      conversationId: draft.conversationId,
      senderDeviceId: draft.senderDeviceId,
      recipientDeviceId: draft.recipientDeviceId,
      createdAt: draft.createdAt,
      expiresAt: draft.expiresAt,
      keyVersion: draft.keyVersion,
      nonce: nonce,
      ciphertext: ciphertext,
      signature: const [],
    );
    final sig = await _identity.sign(withCipher.signaturePayload());
    return EncryptedEnvelope(
      version: withCipher.version,
      messageId: withCipher.messageId,
      conversationId: withCipher.conversationId,
      senderDeviceId: withCipher.senderDeviceId,
      recipientDeviceId: withCipher.recipientDeviceId,
      createdAt: withCipher.createdAt,
      expiresAt: withCipher.expiresAt,
      keyVersion: withCipher.keyVersion,
      nonce: nonce,
      ciphertext: ciphertext,
      signature: sig.bytes,
    );
  }

  Future<DecryptedPayload> decrypt({
    required EncryptedEnvelope envelope,
    required DeviceIdentity local,
    required List<int> senderIdentityPub,
    required List<int> sessionKeyBytes,
    required Set<String> seenMessageIds,
    DateTime? now,
  }) async {
    final clock = now ?? DateTime.now().toUtc();
    if (envelope.version != version) {
      throw CryptoException('unsupported-version');
    }
    if (envelope.recipientDeviceId != local.deviceId) {
      throw CryptoException('wrong-recipient');
    }
    if (!clock.isBefore(envelope.expiresAt)) {
      throw CryptoException('expired');
    }
    if (seenMessageIds.contains(envelope.messageId)) {
      throw CryptoException('duplicate');
    }
    final ok = await _identity.verify(
      message: envelope.signaturePayload(),
      signatureBytes: envelope.signature,
      publicKeyBytes: senderIdentityPub,
    );
    if (!ok) {
      throw CryptoException('invalid-signature');
    }
    if (envelope.ciphertext.length < 16) {
      throw CryptoException('invalid-tag');
    }
    final cipherText = envelope.ciphertext.sublist(0, envelope.ciphertext.length - 16);
    final mac = Mac(envelope.ciphertext.sublist(envelope.ciphertext.length - 16));
    try {
      final clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: envelope.nonce, mac: mac),
        secretKey: SecretKey(sessionKeyBytes),
        aad: envelope.aadBytes(),
      );
      final map = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
      return DecryptedPayload(
        kind: map['k'] as String,
        body: (map['b'] as String?) ?? '',
        ackFor: map['ack'] as String?,
      );
    } catch (err) {
      if (err is CryptoException) rethrow;
      throw CryptoException('invalid-tag');
    }
  }

  List<List<int>> _orderedPair(List<int> a, List<int> b) {
    final cmp = _compareBytes(a, b);
    return cmp <= 0 ? [a, b] : [b, a];
  }

  int _compareBytes(List<int> a, List<int> b) {
    final n = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }

  static Uint8List _randomBytes(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(n, (_) => rng.nextInt(256)));
  }
}
