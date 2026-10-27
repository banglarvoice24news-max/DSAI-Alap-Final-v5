import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_comm/core/crypto/encrypted_envelope.dart';
import 'package:nexus_comm/core/crypto/slice1_protocol.dart';
import 'package:nexus_comm/core/identity/device_identity.dart';
import 'package:nexus_comm/core/offline/offline_repository.dart';
import 'package:nexus_comm/core/offline/offline_session.dart';
import 'package:nexus_comm/core/offline/pairing.dart';
import 'package:nexus_comm/core/storage/offline_store.dart';
import 'package:nexus_comm/core/storage/secret_store.dart';
import 'package:nexus_comm/core/transport/p2p_transport.dart';

Future<(DeviceIdentityService, DeviceIdentity)> _identity(String deviceId) async {
  final store = MemoryIdentityKeyStore(
    store: MemorySecretStore({'device_id': deviceId}),
  );
  final service = DeviceIdentityService(store: store);
  return (service, await service.loadOrCreate());
}

Future<(OfflineSessionEngine, OfflineSessionEngine, MemoryOfflineRepository, MemoryOfflineRepository)>
    _paired({
  EncryptedEnvelope? Function(EncryptedEnvelope envelope)? interceptSendA,
}) async {
  final aId = await _identity('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
  final bId = await _identity('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
  final aProto = Slice1Protocol(identity: aId.$1);
  final bProto = Slice1Protocol(identity: bId.$1);
  final aRepo = MemoryOfflineRepository();
  final bRepo = MemoryOfflineRepository();
  late OfflineSessionEngine a;
  late OfflineSessionEngine b;
  a = OfflineSessionEngine(
    identity: aId.$2,
    protocol: aProto,
    repo: aRepo,
    sendEnvelope: (peer, envelope) async {
      final hijack = interceptSendA?.call(envelope);
      final delivered = hijack ?? envelope;
      final ack = await b.onIncomingEnvelope(delivered);
      if (ack != null) {
        await a.onIncomingEnvelope(ack);
      }
      return const SendResult(ok: true);
    },
    sendControl: (_, __) async => const SendResult(ok: true),
  );
  b = OfflineSessionEngine(
    identity: bId.$2,
    protocol: bProto,
    repo: bRepo,
    sendEnvelope: (peer, envelope) async {
      final ack = await a.onIncomingEnvelope(envelope);
      if (ack != null) {
        await b.onIncomingEnvelope(ack);
      }
      return const SendResult(ok: true);
    },
    sendControl: (_, __) async => const SendResult(ok: true),
  );
  final aPair = await PairingSession.start(local: aId.$2, protocol: aProto);
  final bPair = await PairingSession.start(local: bId.$2, protocol: bProto);
  final aOffer = await aPair.localOffer();
  final bOffer = await bPair.localOffer();
  await aPair.acceptRemote(bOffer);
  await bPair.acceptRemote(aOffer);
  expect(aPair.material!.safetyCode, bPair.material!.safetyCode);
  a.pairing = aPair;
  b.pairing = bPair;
  a.transportPeer = const PeerDescriptor(endpointId: 'b', displayName: 'B');
  b.transportPeer = const PeerDescriptor(endpointId: 'a', displayName: 'A');
  await a.confirmLocalAndTrust();
  await b.confirmLocalAndTrust();
  return (a, b, aRepo, bRepo);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('identity', () {
    test('creates a local identity without OTP', () async {
      final created = await _identity('11111111-1111-1111-1111-111111111111');
      expect(created.$2.deviceId, '11111111-1111-1111-1111-111111111111');
      expect(created.$2.publicKeyBytes, isNotEmpty);
      expect(created.$2.linkedAccount, isFalse);
    });

    test('reloads the same public key from secure storage', () async {
      final mem = MemorySecretStore({'device_id': '22222222-2222-2222-2222-222222222222'});
      final store = MemoryIdentityKeyStore(store: mem);
      final first = DeviceIdentityService(store: store);
      final a = await first.loadOrCreate();
      final second = DeviceIdentityService(store: MemoryIdentityKeyStore(store: mem));
      final b = await second.loadOrCreate();
      expect(b.publicKeyB64, a.publicKeyB64);
      expect(b.deviceId, a.deviceId);
    });

    test('optional account hint is stored without replacing keys', () async {
      final mem = MemorySecretStore({'device_id': '33333333-3333-3333-3333-333333333333'});
      final store = MemoryIdentityKeyStore(store: mem);
      final first = await DeviceIdentityService(store: store).loadOrCreate();
      final linked = await DeviceIdentityService(store: store).loadOrCreate(
        linkedAccountHint: '+8801999999999',
      );
      expect(linked.deviceId, first.deviceId);
      expect(linked.publicKeyB64, first.publicKeyB64);
      expect(linked.linkedAccount, isTrue);
      expect(linked.linkedAccountHint, '+8801999999999');
    });
  });

  group('safety code', () {
    test('is deterministic across both peers', () async {
      final pair = await _paired();
      expect(pair.$1.trusted!.safetyCode.length, 6);
      expect(pair.$1.trusted!.safetyCode, pair.$2.trusted!.safetyCode);
    });

    test('mismatch rejects confirmation', () async {
      final aId = await _identity('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final bId = await _identity('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
      final aProto = Slice1Protocol(identity: aId.$1);
      final bProto = Slice1Protocol(identity: bId.$1);
      final aPair = await PairingSession.start(local: aId.$2, protocol: aProto);
      final bPair = await PairingSession.start(local: bId.$2, protocol: bProto);
      await aPair.acceptRemote(await bPair.localOffer());
      await bPair.acceptRemote(await aPair.localOffer());
      final frame = await bPair.confirmFrame();
      frame['code'] = '000000';
      expect(await aPair.verifyRemoteConfirm(frame), isFalse);
      expect(aPair.phase, PairingPhase.rejected);
    });
  });

  group('envelope crypto', () {
    test('encrypt then decrypt round-trips', () async {
      final pair = await _paired();
      await pair.$1.sendText('hello');
      expect(pair.$2.state.messages.where((m) => !m.mine).map((m) => m.body), contains('hello'));
      expect(pair.$1.state.messages.single.state, MessageUiState.delivered);
    });

    test('tampered ciphertext is rejected', () async {
      EncryptedEnvelope? captured;
      final pair = await _paired(interceptSendA: (env) {
        captured = EncryptedEnvelope(
          version: env.version,
          messageId: env.messageId,
          conversationId: env.conversationId,
          senderDeviceId: env.senderDeviceId,
          recipientDeviceId: env.recipientDeviceId,
          createdAt: env.createdAt,
          expiresAt: env.expiresAt,
          keyVersion: env.keyVersion,
          nonce: env.nonce,
          ciphertext: [...env.ciphertext]..[0] = env.ciphertext[0] ^ 0xff,
          signature: env.signature,
        );
        return captured;
      });
      await expectLater(pair.$1.sendText('secret'), throwsA(isA<CryptoException>()));
    });

    test('invalid signature is rejected', () async {
      await _paired(interceptSendA: (env) {
        return EncryptedEnvelope(
          version: env.version,
          messageId: env.messageId,
          conversationId: env.conversationId,
          senderDeviceId: env.senderDeviceId,
          recipientDeviceId: env.recipientDeviceId,
          createdAt: env.createdAt,
          expiresAt: env.expiresAt,
          keyVersion: env.keyVersion,
          nonce: env.nonce,
          ciphertext: env.ciphertext,
          signature: List<int>.filled(env.signature.length, 1),
        );
      });
      final broken = await _paired(interceptSendA: (env) {
        return EncryptedEnvelope(
          version: env.version,
          messageId: env.messageId,
          conversationId: env.conversationId,
          senderDeviceId: env.senderDeviceId,
          recipientDeviceId: env.recipientDeviceId,
          createdAt: env.createdAt,
          expiresAt: env.expiresAt,
          keyVersion: env.keyVersion,
          nonce: env.nonce,
          ciphertext: env.ciphertext,
          signature: List<int>.filled(env.signature.length, 3),
        );
      });
      await expectLater(broken.$1.sendText('nope'), throwsA(isA<CryptoException>()));
    });

    test('wrong recipient is rejected', () async {
      final pair = await _paired(interceptSendA: (env) {
        return EncryptedEnvelope(
          version: env.version,
          messageId: env.messageId,
          conversationId: env.conversationId,
          senderDeviceId: env.senderDeviceId,
          recipientDeviceId: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
          createdAt: env.createdAt,
          expiresAt: env.expiresAt,
          keyVersion: env.keyVersion,
          nonce: env.nonce,
          ciphertext: env.ciphertext,
          signature: env.signature,
        );
      });
      await expectLater(pair.$1.sendText('nope'), throwsA(isA<CryptoException>()));
    });

    test('replay of the same messageId is rejected from inbox duplication', () async {
      EncryptedEnvelope? first;
      final pair = await _paired(interceptSendA: (env) {
        first ??= env;
        return env;
      });
      await pair.$1.sendText('once');
      expect(pair.$2.state.messages.where((m) => !m.mine).length, 1);
      final ack = await pair.$2.onIncomingEnvelope(first!);
      expect(ack, isNotNull);
      expect(pair.$2.state.messages.where((m) => !m.mine).length, 1);
    });
  });

  group('ack and outbox', () {
    test('duplicate ACK is idempotent', () async {
      EncryptedEnvelope? ackCopy;
      final aId = await _identity('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final bId = await _identity('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
      final aProto = Slice1Protocol(identity: aId.$1);
      final bProto = Slice1Protocol(identity: bId.$1);
      final aRepo = MemoryOfflineRepository();
      final bRepo = MemoryOfflineRepository();
      late OfflineSessionEngine a;
      late OfflineSessionEngine b;
      a = OfflineSessionEngine(
        identity: aId.$2,
        protocol: aProto,
        repo: aRepo,
        sendEnvelope: (peer, envelope) async {
          final ack = await b.onIncomingEnvelope(envelope);
          if (ack != null) {
            ackCopy = ack;
            await a.onIncomingEnvelope(ack);
          }
          return const SendResult(ok: true);
        },
        sendControl: (_, __) async => const SendResult(ok: true),
      );
      b = OfflineSessionEngine(
        identity: bId.$2,
        protocol: bProto,
        repo: bRepo,
        sendEnvelope: (peer, envelope) async => const SendResult(ok: true),
        sendControl: (_, __) async => const SendResult(ok: true),
      );
      final aPair = await PairingSession.start(local: aId.$2, protocol: aProto);
      final bPair = await PairingSession.start(local: bId.$2, protocol: bProto);
      await aPair.acceptRemote(await bPair.localOffer());
      await bPair.acceptRemote(await aPair.localOffer());
      a.pairing = aPair;
      b.pairing = bPair;
      a.transportPeer = const PeerDescriptor(endpointId: 'b', displayName: 'B');
      b.transportPeer = const PeerDescriptor(endpointId: 'a', displayName: 'A');
      await a.confirmLocalAndTrust();
      await b.confirmLocalAndTrust();
      await a.sendText('ping');
      expect(a.state.messages.single.state, MessageUiState.delivered);
      await a.onIncomingEnvelope(ackCopy!);
      expect(a.state.messages.single.state, MessageUiState.delivered);
    });

    test('outbox queues when disconnected and retries later', () async {
      final aId = await _identity('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final proto = Slice1Protocol(identity: aId.$1);
      final repo = MemoryOfflineRepository();
      var connected = false;
      EncryptedEnvelope? last;
      final engine = OfflineSessionEngine(
        identity: aId.$2,
        protocol: proto,
        repo: repo,
        sendEnvelope: (peer, envelope) async {
          if (!connected) return const SendResult(ok: false, error: 'offline');
          last = envelope;
          return const SendResult(ok: true);
        },
        sendControl: (_, __) async => const SendResult(ok: true),
      );
      final other = await _identity('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
      final otherProto = Slice1Protocol(identity: other.$1);
      final aPair = await PairingSession.start(local: aId.$2, protocol: proto);
      final bPair = await PairingSession.start(local: other.$2, protocol: otherProto);
      await aPair.acceptRemote(await bPair.localOffer());
      engine.pairing = aPair;
      engine.transportPeer = const PeerDescriptor(endpointId: 'b', displayName: 'B');
      await engine.confirmLocalAndTrust();
      await engine.sendText('queued-hello');
      expect(engine.state.messages.single.state, MessageUiState.failed);
      expect((await repo.byId(engine.state.messages.single.messageId))!.state, OutboxState.failedRetryable);
      connected = true;
      await engine.trySend(engine.state.messages.single.messageId);
      expect(engine.state.messages.single.state, MessageUiState.waitingAck);
      expect(last, isNotNull);
      expect(last!.encode().contains('queued-hello'), isFalse);
      expect(String.fromCharCodes(last!.ciphertext).contains('queued-hello'), isFalse);
    });

    test('expired messages are not retried', () async {
      var now = DateTime.utc(2026, 1, 1);
      final aId = await _identity('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final proto = Slice1Protocol(identity: aId.$1);
      final repo = MemoryOfflineRepository();
      final engine = OfflineSessionEngine(
        identity: aId.$2,
        protocol: proto,
        repo: repo,
        sendEnvelope: (peer, envelope) async => const SendResult(ok: true),
        sendControl: (_, __) async => const SendResult(ok: true),
        clock: () => now,
      );
      final other = await _identity('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
      final otherProto = Slice1Protocol(identity: other.$1);
      final aPair = await PairingSession.start(local: aId.$2, protocol: proto);
      final bPair = await PairingSession.start(local: other.$2, protocol: otherProto);
      await aPair.acceptRemote(await bPair.localOffer());
      engine.pairing = aPair;
      engine.transportPeer = const PeerDescriptor(endpointId: 'b', displayName: 'B');
      await engine.confirmLocalAndTrust();
      await engine.sendText('old');
      now = now.add(const Duration(hours: 25));
      await engine.retryPending();
      expect(engine.state.messages.single.state, MessageUiState.expired);
    });

    test('restart recovers pending outbox', () async {
      final aId = await _identity('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final proto = Slice1Protocol(identity: aId.$1);
      final repo = MemoryOfflineRepository();
      final engine = OfflineSessionEngine(
        identity: aId.$2,
        protocol: proto,
        repo: repo,
        sendEnvelope: (peer, envelope) async => const SendResult(ok: false, error: 'down'),
        sendControl: (_, __) async => const SendResult(ok: true),
      );
      final other = await _identity('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
      final otherProto = Slice1Protocol(identity: other.$1);
      final aPair = await PairingSession.start(local: aId.$2, protocol: proto);
      final bPair = await PairingSession.start(local: other.$2, protocol: otherProto);
      await aPair.acceptRemote(await bPair.localOffer());
      engine.pairing = aPair;
      engine.transportPeer = const PeerDescriptor(endpointId: 'b', displayName: 'B');
      await engine.confirmLocalAndTrust();
      await engine.sendText('persist-me');
      final restarted = OfflineSessionEngine(
        identity: aId.$2,
        protocol: proto,
        repo: repo,
        sendEnvelope: (peer, envelope) async => const SendResult(ok: true),
        sendControl: (_, __) async => const SendResult(ok: true),
      );
      await restarted.restore();
      expect(restarted.state.messages, isNotEmpty);
      expect(restarted.state.messages.first.messageId, engine.state.messages.single.messageId);
      expect(restarted.trusted?.remoteDeviceId, isNotNull);
    });

    test('retryDelay grows exponentially', () {
      expect(retryDelay(0), const Duration(seconds: 1));
      expect(retryDelay(1), const Duration(seconds: 2));
      expect(retryDelay(2), const Duration(seconds: 4));
    });

    test('unknown peer cannot send', () async {
      final aId = await _identity('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      final engine = OfflineSessionEngine(
        identity: aId.$2,
        protocol: Slice1Protocol(identity: aId.$1),
        repo: MemoryOfflineRepository(),
        sendEnvelope: (peer, envelope) async => const SendResult(ok: true),
        sendControl: (_, __) async => const SendResult(ok: true),
      );
      expect(engine.sendText('no'), throwsA(isA<StateError>()));
    });
  });
}
