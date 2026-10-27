import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

class Slice1Crypto {
  Slice1Crypto({
    Ed25519? ed25519,
    X25519? x25519,
    AesGcm? aead,
    Hkdf? hkdf,
    Random? random,
    Uuid? uuid,
  })  : _ed25519 = ed25519 ?? Ed25519(),
        _x25519 = x25519 ?? X25519(),
        _aead = aead ?? AesGcm.with256bits(),
        _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
        _random = random ?? Random.secure(),
        _uuid = uuid ?? const Uuid();

  static const int protocolVersion = 1;
  static const int keyVersion = 1;
  static const Duration defaultTtl = Duration(hours: 24);
  static const String kdfInfo = 'nexus-slice1-v1';

  final Ed25519 _ed25519;
  final X25519 _x25519;
  final AesGcm _aead;
  final Hkdf _hkdf;
  final Random _random;
  final Uuid _uuid;

  String newMessageId() => _uuid.v4();

  Future<DeviceIdentity> createIdentity({
    required String deviceId,
    String? displayName,
    String? linkedAccountHint,
  }) async {
    final pair = await _ed25519.newKeyPair();
    final priv = await pair.extractPrivateKeyBytes();
    final pub = await pair.extractPublicKey();
    return DeviceIdentity(
      deviceId: deviceId,
      privateKeyB64: base64Encode(priv),
      publicKeyB64: base64Encode(pub.bytes),
      displayName: displayName,
      linkedAccountHint: linkedAccountHint,
    );
  }

  SimpleKeyPair identityKeyPair(DeviceIdentity identity) {
    final priv = base64Decode(identity.privateKeyB64);
    final pub = SimplePublicKey(
      base64Decode(identity.publicKeyB64),
      type: KeyPairType.ed25519,
    );
    return SimpleKeyPairData(priv, publicKey: pub, type: KeyPairType.ed25519);
  }

  Future<SimpleKeyPair> newEphemeral() => _x25519.newKeyPair();

  Future<String> publicB64(SimpleKeyPair pair) async {
    final pub = await pair.extractPublicKey();
    return base64Encode(pub.bytes);
  }

  Future<List<int>> deriveSessionKey({
    required SimpleKeyPair localEph,
    required String remoteEphPubB64,
    required HandshakeTranscript transcript,
  }) async {
    final remote = SimplePublicKey(
      base64Decode(remoteEphPubB64),
      type: KeyPairType.x25519,
    );
    final shared = await _x25519.sharedSecretKey(
      keyPair: localEph,
      remotePublicKey: remote,
    );
    final salt = (await Sha256().hash(transcript.canonicalBytes())).bytes;
    final okm = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: salt,
      info: utf8.encode(kdfInfo),
    );
    return okm.extractBytes();
  }

  Future<String> signTranscript({
    required DeviceIdentity identity,
    required HandshakeTranscript transcript,
  }) async {
    final sig = await _ed25519.sign(
      transcript.canonicalBytes(),
      keyPair: identityKeyPair(identity),
    );
    return base64Encode(sig.bytes);
  }

  Future<bool> verifyTranscript({
    required String publicKeyB64,
    required HandshakeTranscript transcript,
    required String signatureB64,
  }) async {
    return _ed25519.verify(
      transcript.canonicalBytes(),
      signature: Signature(
        base64Decode(signatureB64),
        publicKey: SimplePublicKey(
          base64Decode(publicKeyB64),
          type: KeyPairType.ed25519,
        ),
      ),
    );
  }

  Future<String> safetyCode(HandshakeTranscript transcript) async {
    final digest = await Sha256().hash(transcript.canonicalBytes());
    final bytes = digest.bytes;
    final value = ByteData.sublistView(Uint8List.fromList(bytes))
        .getUint32(0, Endian.big);
    return (value % 1000000).toString().padLeft(6, '0');
  }

  Future<EncryptedEnvelope> encryptText({
    required DeviceIdentity sender,
    required String recipientDeviceId,
    required String conversationId,
    required String plaintext,
    required List<int> sessionKey,
    DateTime? now,
    Duration ttl = defaultTtl,
    String? messageId,
  }) {
    return _seal(
      sender: sender,
      recipientDeviceId: recipientDeviceId,
      conversationId: conversationId,
      plaintext: jsonEncode({'type': 'text', 'body': plaintext}),
      sessionKey: sessionKey,
      now: now ?? DateTime.now().toUtc(),
      ttl: ttl,
      messageId: messageId,
    );
  }

  Future<EncryptedEnvelope> encryptAck({
    required DeviceIdentity sender,
    required String recipientDeviceId,
    required String conversationId,
    required String ackMessageId,
    required List<int> sessionKey,
    DateTime? now,
  }) {
    return _seal(
      sender: sender,
      recipientDeviceId: recipientDeviceId,
      conversationId: conversationId,
      plaintext: jsonEncode({'type': 'ack', 'messageId': ackMessageId}),
      sessionKey: sessionKey,
      now: now ?? DateTime.now().toUtc(),
      ttl: const Duration(hours: 6),
    );
  }

  Future<EncryptedEnvelope> _seal({
    required DeviceIdentity sender,
    required String recipientDeviceId,
    required String conversationId,
    required String plaintext,
    required List<int> sessionKey,
    required DateTime now,
    required Duration ttl,
    String? messageId,
  }) async {
    final id = messageId ?? newMessageId();
    final createdAt = now;
    final expiresAt = now.add(ttl);
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final aad = utf8.encode([
      protocolVersion.toString(),
      id,
      conversationId,
      sender.deviceId,
      recipientDeviceId,
      createdAt.millisecondsSinceEpoch.toString(),
      expiresAt.millisecondsSinceEpoch.toString(),
      keyVersion.toString(),
    ].join('|'));
    final box = await _aead.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(sessionKey),
      nonce: nonce,
      aad: aad,
    );
    final envelope = EncryptedEnvelope(
      version: protocolVersion,
      messageId: id,
      conversationId: conversationId,
      senderDeviceId: sender.deviceId,
      recipientDeviceId: recipientDeviceId,
      createdAt: createdAt,
      expiresAt: expiresAt,
      keyVersion: keyVersion,
      nonce: base64Encode(nonce),
      ciphertext: base64Encode(box.concatenation(nonce: false)),
      signature: '',
    );
    final sig = await _ed25519.sign(
      utf8.encode(envelope.signedCanonical),
      keyPair: identityKeyPair(sender),
    );
    return EncryptedEnvelope(
      version: envelope.version,
      messageId: envelope.messageId,
      conversationId: envelope.conversationId,
      senderDeviceId: envelope.senderDeviceId,
      recipientDeviceId: envelope.recipientDeviceId,
      createdAt: envelope.createdAt,
      expiresAt: envelope.expiresAt,
      keyVersion: envelope.keyVersion,
      nonce: envelope.nonce,
      ciphertext: envelope.ciphertext,
      signature: base64Encode(sig.bytes),
    );
  }

  Future<bool> verifyEnvelopeSignature({
    required EncryptedEnvelope envelope,
    required String senderPublicKeyB64,
  }) {
    return _ed25519.verify(
      utf8.encode(envelope.signedCanonical),
      signature: Signature(
        base64Decode(envelope.signature),
        publicKey: SimplePublicKey(
          base64Decode(senderPublicKeyB64),
          type: KeyPairType.ed25519,
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> decryptEnvelope({
    required EncryptedEnvelope envelope,
    required List<int> sessionKey,
  }) async {
    final raw = base64Decode(envelope.ciphertext);
    if (raw.length < 17) {
      throw const FormatException('ciphertext too short');
    }
    final cipherText = raw.sublist(0, raw.length - 16);
    final mac = Mac(raw.sublist(raw.length - 16));
    final clear = await _aead.decrypt(
      SecretBox(cipherText, nonce: base64Decode(envelope.nonce), mac: mac),
      secretKey: SecretKey(sessionKey),
      aad: utf8.encode(envelope.aad),
    );
    return jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
  }

  String conversationId(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join(':');
  }
}
