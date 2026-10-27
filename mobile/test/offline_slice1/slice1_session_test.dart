import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_comm/offline_slice1/data/session_engine.dart';
import 'package:nexus_comm/offline_slice1/data/slice1_repository.dart';
import 'package:nexus_comm/offline_slice1/domain/crypto_protocol.dart';
import 'package:nexus_comm/offline_slice1/domain/models.dart';
import 'package:nexus_comm/offline_slice1/domain/transport.dart';

class FakeNearbyTransport implements NearbyAwareTransport {
  FakeNearbyTransport(this.localId);

  final String localId;
  FakeNearbyTransport? peer;

  final _peers = StreamController<List<PeerDescriptor>>.broadcast();
  final _state = StreamController<TransportLinkState>.broadcast();
  final _requests = StreamController<IncomingConnectionRequest>.broadcast();
  final _control = StreamController<Map<String, dynamic>>.broadcast();
  bool connected = false;

  @override
  Stream<IncomingConnectionRequest> get connectionRequests => _requests.stream;

  @override
  Stream<Map<String, dynamic>> get controlMessages => _control.stream;

  @override
  Future<TransportCapabilities> capabilities() async =>
      const TransportCapabilities(ready: true);

  @override
  Stream<List<PeerDescriptor>> discoverPeers() => _peers.stream;

  @override
  Stream<TransportLinkState> observeState() => _state.stream;

  @override
  Future<void> startDiscovery({required String displayName}) async {
    _peers.add([
      PeerDescriptor(endpointId: peer!.localId, displayName: displayName),
    ]);
  }

  @override
  Future<void> stopDiscovery() async {}

  bool accepted = false;

  @override
  Future<ConnectionResult> connect(PeerDescriptor target) async {
    peer?._requests.add(
      IncomingConnectionRequest(endpointId: localId, displayName: localId),
    );
    _requests.add(
      IncomingConnectionRequest(
        endpointId: target.endpointId,
        displayName: target.displayName,
      ),
    );
    return const ConnectionResult(ok: true);
  }

  @override
  Future<void> accept(String endpointId) async {
    accepted = true;
    if (peer?.accepted == true) {
      connected = true;
      peer?.connected = true;
      _state.add(TransportLinkState.connected);
      peer?._state.add(TransportLinkState.connected);
    }
  }

  @override
  Future<void> reject(String endpointId) async {
    accepted = false;
    connected = false;
    peer?.accepted = false;
    peer?.connected = false;
    peer?._control.add({
      't': 'handshake',
      'stage': 'reject',
      'endpointId': localId,
    });
    _state.add(TransportLinkState.unavailable);
    peer?._state.add(TransportLinkState.unavailable);
  }

  @override
  Future<SendResult> send(PeerDescriptor target, EncryptedEnvelope envelope) {
    return sendControl(target.endpointId, {
      't': 'envelope',
      'envelope': envelope.toJson(),
    });
  }

  @override
  Future<SendResult> sendControl(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    if (!connected) {
      return const SendResult(ok: false, message: 'Peer not connected');
    }
    final copy = Map<String, dynamic>.from(message);
    copy['endpointId'] = localId;
    peer?._control.add(copy);
    return const SendResult(ok: true);
  }

  @override
  Future<void> disconnect(PeerDescriptor target) async {
    connected = false;
    accepted = false;
    peer?.connected = false;
    peer?.accepted = false;
    _state.add(TransportLinkState.unavailable);
    peer?._state.add(TransportLinkState.unavailable);
  }

  void emitConnected() {
    connected = true;
    accepted = true;
    _state.add(TransportLinkState.connected);
  }

  void injectControl(Map<String, dynamic> message) {
    _control.add(Map<String, dynamic>.from(message));
  }
}

void main() {
  late Slice1Crypto crypto;
  late DeviceIdentity alice;
  late DeviceIdentity bob;
  late MemorySlice1Repository aliceRepo;
  late MemorySlice1Repository bobRepo;
  late FakeNearbyTransport aliceNet;
  late FakeNearbyTransport bobNet;
  late OfflineSessionEngine aliceEngine;
  late OfflineSessionEngine bobEngine;
  late DateTime now;

  setUp(() async {
    crypto = Slice1Crypto();
    now = DateTime.utc(2026, 1, 1, 12);
    alice = await crypto.createIdentity(deviceId: 'alice');
    bob = await crypto.createIdentity(deviceId: 'bob');
    aliceRepo = MemorySlice1Repository();
    bobRepo = MemorySlice1Repository();
    aliceNet = FakeNearbyTransport('alice-ep');
    bobNet = FakeNearbyTransport('bob-ep');
    aliceNet.peer = bobNet;
    bobNet.peer = aliceNet;
    aliceEngine = OfflineSessionEngine(
      identity: alice,
      transport: aliceNet,
      repository: aliceRepo,
      crypto: crypto,
      clock: () => now,
    );
    bobEngine = OfflineSessionEngine(
      identity: bob,
      transport: bobNet,
      repository: bobRepo,
      crypto: crypto,
      clock: () => now,
    );
    await aliceEngine.start();
    await bobEngine.start();
  });

  tearDown(() async {
    await aliceEngine.dispose();
    await bobEngine.dispose();
  });

  Future<void> _waitUntil(bool Function() pred) async {
    for (var i = 0; i < 80; i++) {
      if (pred()) return;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    fail('condition not met');
  }

  Future<List<int>> trustBoth() async {
    final aliceEph = await crypto.newEphemeral();
    final bobEph = await crypto.newEphemeral();
    final aliceTranscript = HandshakeTranscript(
      localDeviceId: alice.deviceId,
      remoteDeviceId: bob.deviceId,
      localIdentityPub: alice.publicKeyB64,
      remoteIdentityPub: bob.publicKeyB64,
      localEphPub: await crypto.publicB64(aliceEph),
      remoteEphPub: await crypto.publicB64(bobEph),
    );
    final bobTranscript = HandshakeTranscript(
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
      transcript: aliceTranscript,
    );
    final bobKey = await crypto.deriveSessionKey(
      localEph: bobEph,
      remoteEphPubB64: await crypto.publicB64(aliceEph),
      transcript: bobTranscript,
    );
    expect(aliceKey, bobKey);
    final conversationId = crypto.conversationId(alice.deviceId, bob.deviceId);
    final nowTs = DateTime.utc(2026, 1, 1, 12);
    await aliceRepo.saveTrusted(
      TrustedContact(
        deviceId: bob.deviceId,
        displayName: 'bob',
        publicKeyB64: bob.publicKeyB64,
        conversationId: conversationId,
        verifiedAt: nowTs,
        keyVersion: 1,
        endpointId: 'bob-ep',
      ),
    );
    await bobRepo.saveTrusted(
      TrustedContact(
        deviceId: alice.deviceId,
        displayName: 'alice',
        publicKeyB64: alice.publicKeyB64,
        conversationId: conversationId,
        verifiedAt: nowTs,
        keyVersion: 1,
        endpointId: 'alice-ep',
      ),
    );
    await aliceRepo.saveSessionKey(bob.deviceId, aliceKey);
    await bobRepo.saveSessionKey(alice.deviceId, bobKey);
    aliceEngine.installSessionForTest(
      trusted: (await aliceRepo.trustedByDeviceId(bob.deviceId))!,
      sessionKey: aliceKey,
      endpointId: 'bob-ep',
    );
    bobEngine.installSessionForTest(
      trusted: (await bobRepo.trustedByDeviceId(alice.deviceId))!,
      sessionKey: bobKey,
      endpointId: 'alice-ep',
    );
    aliceNet.emitConnected();
    bobNet.emitConnected();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return aliceKey;
  }

  Future<void> exchangeUntilSafetyCodes() async {
    await aliceEngine.connect(
      const PeerDescriptor(endpointId: 'bob-ep', displayName: 'bob'),
    );
    await _waitUntil(() =>
        aliceEngine.current.pendingRequest != null &&
        bobEngine.current.pendingRequest != null);
    await aliceEngine.acceptIncoming();
    await bobEngine.acceptIncoming();
    await _waitUntil(() =>
        aliceEngine.current.safetyCode != null &&
        bobEngine.current.safetyCode != null);
    expect(aliceEngine.current.safetyCode, bobEngine.current.safetyCode);
    expect(aliceEngine.current.safetyCode!.length, 6);
  }

  Future<void> pair() async {
    await exchangeUntilSafetyCodes();
    await aliceEngine.confirmSafetyCode();
    await bobEngine.confirmSafetyCode();
    await _waitUntil(() =>
        aliceEngine.current.trusted != null && bobEngine.current.trusted != null);
  }

  test('mutual pairing produces the same 6-digit safety code', () async {
    await pair();
    expect(aliceEngine.current.safetyCode!.length, 6);
    expect(aliceEngine.current.phase, OfflineUiPhase.trusted);
    expect(bobEngine.current.phase, OfflineUiPhase.trusted);
  });

  test('one-sided accept does not connect or auto-trust', () async {
    await aliceEngine.connect(
      const PeerDescriptor(endpointId: 'bob-ep', displayName: 'bob'),
    );
    await _waitUntil(() => bobEngine.current.pendingRequest != null);
    await bobEngine.acceptIncoming();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(aliceNet.connected, isFalse);
    expect(bobNet.connected, isFalse);
    expect(aliceEngine.current.trusted, isNull);
    expect(bobEngine.current.trusted, isNull);
    expect(aliceEngine.current.phase, isNot(OfflineUiPhase.trusted));
    expect(bobEngine.current.phase, isNot(OfflineUiPhase.trusted));
  });

  test('one-sided safety confirm does not trust', () async {
    await exchangeUntilSafetyCodes();
    await aliceEngine.confirmSafetyCode();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(aliceEngine.current.trusted, isNull);
    expect(bobEngine.current.trusted, isNull);
    expect(aliceEngine.current.phase, OfflineUiPhase.verifyCode);
    expect(bobEngine.current.phase, OfflineUiPhase.verifyCode);
  });

  test('reject safety code cancels pairing on both sides', () async {
    await exchangeUntilSafetyCodes();
    await bobEngine.rejectSafetyCode();
    await _waitUntil(() =>
        aliceEngine.current.error != null && bobEngine.current.error != null);
    expect(aliceEngine.current.trusted, isNull);
    expect(bobEngine.current.trusted, isNull);
    expect(aliceEngine.current.phase, isNot(OfflineUiPhase.trusted));
    expect(bobEngine.current.phase, isNot(OfflineUiPhase.trusted));
  });

  test('safety code mismatch rejects pairing', () async {
    await exchangeUntilSafetyCodes();
    aliceNet.injectControl({
      't': 'handshake',
      'stage': 'confirm',
      'endpointId': 'bob-ep',
      'deviceId': bob.deviceId,
      'displayName': 'bob',
      'identityPub': bob.publicKeyB64,
      'code': '000000',
    });
    await _waitUntil(() => aliceEngine.current.error == 'safety code mismatch');
    expect(aliceEngine.current.trusted, isNull);
    expect(aliceEngine.current.phase, isNot(OfflineUiPhase.trusted));
  });

  test('unknown peer cannot send', () async {
    await aliceEngine.sendText('nope');
    expect(aliceEngine.current.error, 'Unknown peer. Verify safety code first.');
    expect(aliceRepo.outbox, isEmpty);
    expect(aliceEngine.current.trusted, isNull);
  });

  test('wrong recipient is rejected', () async {
    await trustBoth();
    final key = aliceEngine.current.trusted!;
    expect(key.deviceId, 'bob');
    final foreign = await crypto.createIdentity(deviceId: 'mallory');
    final envelope = await crypto.encryptText(
      sender: alice,
      recipientDeviceId: foreign.deviceId,
      conversationId: 'alice:mallory',
      plaintext: 'nope',
      sessionKey: List<int>.filled(32, 7),
    );
    await bobEngine.handleIncomingEnvelope(envelope);
    expect(bobRepo.inbox, isEmpty);
  });

  test('duplicate message is stored once', () async {
    await trustBoth();
    await aliceEngine.sendText('hello');
    await _waitUntil(() => bobRepo.inbox.length == 1);
    final first = bobRepo.inbox.values.single;
    final envelope = aliceRepo.outbox.values.single.encryptedEnvelope;
    await bobEngine.handleIncomingEnvelope(envelope);
    expect(bobRepo.inbox.length, 1);
    expect(bobRepo.inbox.values.single.messageId, first.messageId);
  });

  test('duplicate ACK is idempotent', () async {
    await trustBoth();
    await aliceEngine.sendText('hello');
    await _waitUntil(
      () => aliceRepo.outbox.values.single.state == OutboxState.delivered,
    );
    final ackAgain = await crypto.encryptAck(
      sender: bob,
      recipientDeviceId: alice.deviceId,
      conversationId: crypto.conversationId(alice.deviceId, bob.deviceId),
      ackMessageId: aliceRepo.outbox.values.single.messageId,
      sessionKey: bobEngine.debugSessionKey!,
    );
    await aliceEngine.handleIncomingEnvelope(ackAgain);
    await aliceEngine.handleIncomingEnvelope(ackAgain);
    expect(aliceRepo.outbox.values.single.state, OutboxState.delivered);
  });

  test('outbox queues when disconnected and retries after reconnect', () async {
    await trustBoth();
    await aliceNet.disconnect(
      const PeerDescriptor(endpointId: 'bob-ep', displayName: 'bob'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await aliceEngine.sendText('queued-hello');
    expect(aliceRepo.outbox.values.single.state, OutboxState.queued);
    aliceNet.emitConnected();
    bobNet.emitConnected();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await aliceEngine.retryPending();
    await _waitUntil(() =>
        aliceRepo.outbox.values.single.state == OutboxState.sentWaitingAck ||
        aliceRepo.outbox.values.single.state == OutboxState.delivered);
    expect(
      aliceRepo.outbox.values.single.state,
      anyOf(OutboxState.sentWaitingAck, OutboxState.delivered),
    );
  });

  test('expired outbox is not resent', () async {
    await trustBoth();
    await aliceNet.disconnect(
      const PeerDescriptor(endpointId: 'bob-ep', displayName: 'bob'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await aliceEngine.sendText('old');
    now = now.add(const Duration(hours: 25));
    aliceNet.connected = true;
    await aliceEngine.retryPending();
    expect(aliceRepo.outbox.values.single.state, OutboxState.expired);
  });

  test('restart recovery reloads pending outbox', () async {
    await trustBoth();
    await aliceNet.disconnect(
      const PeerDescriptor(endpointId: 'bob-ep', displayName: 'bob'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await aliceEngine.sendText('persist-me');
    final restarted = OfflineSessionEngine(
      identity: alice,
      transport: aliceNet,
      repository: aliceRepo,
      crypto: crypto,
      clock: () => now,
    );
    await restarted.start();
    expect(aliceRepo.outbox.values.single.state, OutboxState.queued);
    expect(restarted.current.trusted, isNotNull);
    await restarted.dispose();
  });

  test('replay of a seen message id is ignored', () async {
    await trustBoth();
    await aliceEngine.sendText('once');
    await _waitUntil(() => bobRepo.inbox.length == 1);
    final envelope = aliceRepo.outbox.values.single.encryptedEnvelope;
    await bobEngine.handleIncomingEnvelope(envelope);
    expect(bobRepo.inbox.length, 1);
  });
}
