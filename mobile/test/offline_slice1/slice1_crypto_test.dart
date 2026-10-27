import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_comm/core/storage/secure_store.dart';
import 'package:nexus_comm/offline_slice1/data/identity_service.dart';
import 'package:nexus_comm/offline_slice1/domain/crypto_protocol.dart';
import 'package:nexus_comm/offline_slice1/domain/models.dart';
import 'package:uuid/uuid.dart';

void main() {
  final crypto = Slice1Crypto();

  Future<(DeviceIdentity, DeviceIdentity, List<int>, List<int>, HandshakeTranscript)>
      paired() async {
    final alice = await crypto.createIdentity(deviceId: 'alice');
    final bob = await crypto.createIdentity(deviceId: 'bob');
    final aliceEph = await crypto.newEphemeral();
    final bobEph = await crypto.newEphemeral();
    final transcript = HandshakeTranscript(
      localDeviceId: alice.deviceId,
      remoteDeviceId: bob.deviceId,
      localIdentityPub: alice.publicKeyB64,
      remoteIdentityPub: bob.publicKeyB64,
      localEphPub: await crypto.publicB64(aliceEph),
      remoteEphPub: await crypto.publicB64(bobEph),
    );
    final bobView = HandshakeTranscript(
      localDeviceId: bob.deviceId,
      remoteDeviceId: alice.deviceId,
      localIdentityPub: bob.publicKeyB64,
      remoteIdentityPub: alice.publicKeyB64,
      localEphPub: await crypto.publicB64(bobEph),
      remoteEphPub: await crypto.publicB64(aliceEph),
    );
    final aliceKey = await crypto.deriveSessionKey(
      localEph: aliceEph,
      remoteEphPubB64: await crypto.publicB64(bobEph),
      transcript: transcript,
    );
    final bobKey = await crypto.deriveSessionKey(
      localEph: bobEph,
      remoteEphPubB64: await crypto.publicB64(aliceEph),
      transcript: bobView,
    );
    return (alice, bob, aliceKey, bobKey, transcript);
  }

  test('identity creation stores public and private material', () async {
    final id = await crypto.createIdentity(deviceId: 'dev-1', displayName: 'Nexus');
    expect(id.deviceId, 'dev-1');
    expect(id.publicKeyB64, isNotEmpty);
    expect(id.privateKeyB64, isNotEmpty);
    expect(id.publicKeyB64, isNot(id.privateKeyB64));
  });

  test('secure identity reload reuses the same keys and uuid', () async {
    final store = MemoryIdentityKeyStore();
    const uuid = Uuid();
    final first = await IdentityService(keys: store, uuid: uuid).loadOrCreate();
    final second = await IdentityService(keys: store, uuid: uuid).loadOrCreate();
    expect(second.deviceId, first.deviceId);
    expect(second.publicKeyB64, first.publicKeyB64);
    expect(second.privateKeyB64, first.privateKeyB64);
    expect(store.values.containsKey(IdentityService.privateKey), isTrue);
    expect(store.values.containsKey(IdentityService.publicKey), isTrue);
    expect(store.values.containsKey(SecureStore.deviceId), isTrue);
  });

  test('optional account hint is persisted without replacing identity keys', () async {
    final store = MemoryIdentityKeyStore();
    const uuid = Uuid();
    final created = await IdentityService(keys: store, uuid: uuid).loadOrCreate();
    final linked = await IdentityService(keys: store, uuid: uuid).loadOrCreate(
      linkedAccountHint: '+8801712345678',
    );
    expect(linked.deviceId, created.deviceId);
    expect(linked.publicKeyB64, created.publicKeyB64);
    expect(linked.privateKeyB64, created.privateKeyB64);
    expect(linked.linkedAccountHint, '+8801712345678');
    expect(store.values[IdentityService.linkedHintKey], '+8801712345678');
    expect(store.values[IdentityService.privateKey], created.privateKeyB64);
  });

  test('safety code is deterministic for the same transcript', () async {
    final pair = await paired();
    final a = await crypto.safetyCode(pair.$5);
    final b = await crypto.safetyCode(pair.$5);
    expect(a, b);
    expect(a.length, 6);
  });

  test('safety code mismatches when identity keys differ', () async {
    final pair = await paired();
    final other = HandshakeTranscript(
      localDeviceId: pair.$5.localDeviceId,
      remoteDeviceId: pair.$5.remoteDeviceId,
      localIdentityPub: pair.$5.localIdentityPub,
      remoteIdentityPub: pair.$1.publicKeyB64,
      localEphPub: pair.$5.localEphPub,
      remoteEphPub: pair.$5.remoteEphPub,
    );
    expect(await crypto.safetyCode(pair.$5), isNot(await crypto.safetyCode(other)));
  });

  test('encrypt then decrypt round-trips text', () async {
    final pair = await paired();
    final envelope = await crypto.encryptText(
      sender: pair.$1,
      recipientDeviceId: pair.$2.deviceId,
      conversationId: 'alice:bob',
      plaintext: 'hello',
      sessionKey: pair.$3,
    );
    final clear = await crypto.decryptEnvelope(
      envelope: envelope,
      sessionKey: pair.$4,
    );
    expect(clear['type'], 'text');
    expect(clear['body'], 'hello');
  });

  test('tampered ciphertext is rejected', () async {
    final pair = await paired();
    final envelope = await crypto.encryptText(
      sender: pair.$1,
      recipientDeviceId: pair.$2.deviceId,
      conversationId: 'alice:bob',
      plaintext: 'hello',
      sessionKey: pair.$3,
    );
    final raw = envelope.ciphertext.codeUnits.reversed.join();
    final tampered = EncryptedEnvelope(
      version: envelope.version,
      messageId: envelope.messageId,
      conversationId: envelope.conversationId,
      senderDeviceId: envelope.senderDeviceId,
      recipientDeviceId: envelope.recipientDeviceId,
      createdAt: envelope.createdAt,
      expiresAt: envelope.expiresAt,
      keyVersion: envelope.keyVersion,
      nonce: envelope.nonce,
      ciphertext: raw == envelope.ciphertext ? '${envelope.ciphertext}AA' : raw,
      signature: envelope.signature,
    );
    expect(
      () => crypto.decryptEnvelope(envelope: tampered, sessionKey: pair.$4),
      throwsA(anything),
    );
  });

  test('invalid signature is rejected', () async {
    final pair = await paired();
    final envelope = await crypto.encryptText(
      sender: pair.$1,
      recipientDeviceId: pair.$2.deviceId,
      conversationId: 'alice:bob',
      plaintext: 'hello',
      sessionKey: pair.$3,
    );
    final ok = await crypto.verifyEnvelopeSignature(
      envelope: envelope,
      senderPublicKeyB64: pair.$2.publicKeyB64,
    );
    expect(ok, isFalse);
    expect(
      await crypto.verifyEnvelopeSignature(
        envelope: envelope,
        senderPublicKeyB64: pair.$1.publicKeyB64,
      ),
      isTrue,
    );
  });
}
