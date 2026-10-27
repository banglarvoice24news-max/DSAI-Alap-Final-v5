import 'dart:convert';

import '../crypto/encrypted_envelope.dart';
import '../crypto/slice1_protocol.dart';
import '../identity/device_identity.dart';
import '../storage/offline_store.dart';
import '../transport/p2p_transport.dart';
import 'offline_repository.dart';
import 'pairing.dart';

enum SessionUiPhase {
  idle,
  discovering,
  peerFound,
  connecting,
  verifyCode,
  trusted,
}

enum MessageUiState {
  queued,
  sending,
  waitingAck,
  delivered,
  failed,
  expired,
  received,
}

class OfflineChatMessage {
  const OfflineChatMessage({
    required this.messageId,
    required this.mine,
    required this.body,
    required this.state,
    required this.createdAt,
  });

  final String messageId;
  final bool mine;
  final String body;
  final MessageUiState state;
  final DateTime createdAt;

  OfflineChatMessage copyWith({MessageUiState? state}) => OfflineChatMessage(
        messageId: messageId,
        mine: mine,
        body: body,
        state: state ?? this.state,
        createdAt: createdAt,
      );
}

class OfflineSessionState {
  const OfflineSessionState({
    this.phase = SessionUiPhase.idle,
    this.peers = const [],
    this.activePeer,
    this.safetyCode,
    this.trustedDeviceId,
    this.trustedName,
    this.messages = const [],
    this.error,
    this.incomingRequest,
  });

  final SessionUiPhase phase;
  final List<PeerDescriptor> peers;
  final PeerDescriptor? activePeer;
  final String? safetyCode;
  final String? trustedDeviceId;
  final String? trustedName;
  final List<OfflineChatMessage> messages;
  final String? error;
  final IncomingConnectionRequest? incomingRequest;

  OfflineSessionState copyWith({
    SessionUiPhase? phase,
    List<PeerDescriptor>? peers,
    PeerDescriptor? activePeer,
    bool clearPeer = false,
    String? safetyCode,
    bool clearSafety = false,
    String? trustedDeviceId,
    String? trustedName,
    bool clearTrusted = false,
    List<OfflineChatMessage>? messages,
    String? error,
    bool clearError = false,
    IncomingConnectionRequest? incomingRequest,
    bool clearIncoming = false,
  }) {
    return OfflineSessionState(
      phase: phase ?? this.phase,
      peers: peers ?? this.peers,
      activePeer: clearPeer ? null : (activePeer ?? this.activePeer),
      safetyCode: clearSafety ? null : (safetyCode ?? this.safetyCode),
      trustedDeviceId: clearTrusted ? null : (trustedDeviceId ?? this.trustedDeviceId),
      trustedName: clearTrusted ? null : (trustedName ?? this.trustedName),
      messages: messages ?? this.messages,
      error: clearError ? null : (error ?? this.error),
      incomingRequest: clearIncoming ? null : (incomingRequest ?? this.incomingRequest),
    );
  }
}

typedef SendBytes = Future<SendResult> Function(PeerDescriptor peer, EncryptedEnvelope envelope);
typedef SendControl = Future<SendResult> Function(String endpointId, Map<String, dynamic> json);

class OfflineSessionEngine {
  OfflineSessionEngine({
    required this.identity,
    required this.protocol,
    required this.repo,
    required this.sendEnvelope,
    required this.sendControl,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final DeviceIdentity identity;
  final Slice1Protocol protocol;
  final OfflineRepository repo;
  final SendBytes sendEnvelope;
  final SendControl sendControl;
  final DateTime Function() _clock;

  OfflineSessionState state = const OfflineSessionState();
  PairingSession? pairing;
  HandshakeMaterial? trusted;
  PeerDescriptor? transportPeer;
  final Set<String> _inFlight = {};
  final Set<String> _seenAcks = {};

  Future<void> restore() async {
    await repo.markExpiredIfNeeded(_clock().toUtc());
    final contacts = await repo.contacts();
    if (contacts.isNotEmpty) {
      final c = contacts.first;
      trusted = HandshakeMaterial(
        localEphPub: const [],
        localEphPriv: const [],
        remoteDeviceId: c.deviceId,
        remoteDisplayName: c.displayName,
        remoteIdentityPub: base64Decode(c.publicKeyB64),
        remoteEphPub: const [],
        transcript: const [],
        safetyCode: c.safetyCode,
        sessionKeyBytes: base64Decode(c.sessionKeyB64),
      );
      final inbox = await repo.inboxFor(c.deviceId);
      state = state.copyWith(
        phase: SessionUiPhase.idle,
        trustedDeviceId: c.deviceId,
        trustedName: c.displayName,
        safetyCode: c.safetyCode,
      );
      for (final rec in inbox) {
        state = state.copyWith(messages: [
          ...state.messages,
          OfflineChatMessage(
            messageId: rec.messageId,
            mine: false,
            body: rec.body,
            state: MessageUiState.received,
            createdAt: rec.createdAt,
          ),
        ]);
      }
    }
    final pending = await repo.pending();
    final restored = [...state.messages];
    for (final rec in pending) {
      if (restored.any((m) => m.messageId == rec.messageId)) continue;
      restored.add(OfflineChatMessage(
        messageId: rec.messageId,
        mine: true,
        body: '',
        state: _uiState(rec.state),
        createdAt: rec.createdAt,
      ));
    }
    state = state.copyWith(messages: restored);
  }

  void setPeers(List<PeerDescriptor> peers) {
    state = state.copyWith(
      peers: peers,
      phase: peers.isEmpty ? SessionUiPhase.discovering : SessionUiPhase.peerFound,
    );
  }

  void setIncomingRequest(IncomingConnectionRequest request) {
    state = state.copyWith(
      incomingRequest: request,
      phase: SessionUiPhase.connecting,
    );
  }

  Future<HandshakeOffer> beginPairing() async {
    pairing = await PairingSession.start(local: identity, protocol: protocol);
    return pairing!.localOffer();
  }

  Future<String> onHandshakeOffer(HandshakeOffer remote) async {
    pairing ??= await PairingSession.start(local: identity, protocol: protocol);
    final material = await pairing!.acceptRemote(remote);
    state = state.copyWith(
      phase: SessionUiPhase.verifyCode,
      safetyCode: material.safetyCode,
    );
    return material.safetyCode;
  }

  Future<bool> onHandshakeConfirm(Map<String, dynamic> json) async {
    final session = pairing;
    if (session == null) return false;
    final ok = await session.verifyRemoteConfirm(json);
    if (!ok) {
      state = state.copyWith(phase: SessionUiPhase.idle, error: 'safety-code-mismatch', clearSafety: true);
      return false;
    }
    return true;
  }

  Future<void> confirmLocalAndTrust({PeerDescriptor? peer}) async {
    final session = pairing;
    final material = session?.material;
    if (session == null || material == null) {
      throw StateError('no-pairing');
    }
    session.confirmLocal();
    trusted = material;
    transportPeer = peer ?? transportPeer;
    await repo.upsertContact(TrustedContact(
      deviceId: material.remoteDeviceId,
      displayName: material.remoteDisplayName,
      publicKeyB64: base64Encode(material.remoteIdentityPub),
      safetyCode: material.safetyCode,
      sessionKeyB64: base64Encode(material.sessionKeyBytes),
      confirmedAt: _clock().toUtc(),
    ));
    state = state.copyWith(
      phase: SessionUiPhase.trusted,
      trustedDeviceId: material.remoteDeviceId,
      trustedName: material.remoteDisplayName,
      safetyCode: material.safetyCode,
      activePeer: transportPeer,
    );
  }

  void rejectPairing() {
    pairing?.reject();
    pairing = null;
    trusted = null;
    state = state.copyWith(
      phase: SessionUiPhase.idle,
      clearSafety: true,
      clearTrusted: true,
      error: 'pairing-rejected',
    );
  }

  Future<OfflineChatMessage> sendText(String body) async {
    final material = trusted;
    if (material == null) {
      throw StateError('untrusted-peer');
    }
    final now = _clock().toUtc();
    final envelope = await protocol.encrypt(
      sender: identity,
      recipientDeviceId: material.remoteDeviceId,
      sessionKeyBytes: material.sessionKeyBytes,
      conversationId: _conversationId(identity.deviceId, material.remoteDeviceId),
      payload: DecryptedPayload(kind: 'txt', body: body, ackFor: null),
      now: now,
    );
    final record = EncryptedOutboxRecord(
      messageId: envelope.messageId,
      recipientDeviceId: material.remoteDeviceId,
      envelopeJson: envelope.encode(),
      createdAt: envelope.createdAt,
      expiresAt: envelope.expiresAt,
      attemptCount: 0,
      state: OutboxState.queued,
    );
    await repo.enqueue(record);
    final message = OfflineChatMessage(
      messageId: envelope.messageId,
      mine: true,
      body: body,
      state: MessageUiState.queued,
      createdAt: envelope.createdAt,
    );
    state = state.copyWith(messages: [...state.messages, message]);
    await trySend(envelope.messageId);
    return message;
  }

  Future<void> trySend(String messageId) async {
    if (_inFlight.contains(messageId)) return;
    final rec = await repo.byId(messageId);
    if (rec == null) return;
    if (rec.state == OutboxState.delivered || rec.state == OutboxState.expired) return;
    final now = _clock().toUtc();
    if (!rec.expiresAt.isAfter(now)) {
      await repo.updateState(messageId: messageId, state: OutboxState.expired);
      _patchMessage(messageId, MessageUiState.expired);
      return;
    }
    final peer = transportPeer;
    if (peer == null || trusted == null) {
      await repo.updateState(messageId: messageId, state: OutboxState.queued);
      _patchMessage(messageId, MessageUiState.queued);
      return;
    }
    _inFlight.add(messageId);
    await repo.updateState(
      messageId: messageId,
      state: OutboxState.sending,
      attemptCount: rec.attemptCount + 1,
      lastAttemptAt: now,
    );
    _patchMessage(messageId, MessageUiState.sending);
    try {
      final result = await sendEnvelope(peer, rec.envelope);
      if (result.ok) {
        await repo.updateState(messageId: messageId, state: OutboxState.sentWaitingAck);
        _patchMessage(messageId, MessageUiState.waitingAck);
      } else {
        await repo.updateState(
          messageId: messageId,
          state: OutboxState.failedRetryable,
          lastAttemptAt: now,
        );
        _patchMessage(messageId, MessageUiState.failed);
      }
    } catch (_) {
      await repo.updateState(
        messageId: messageId,
        state: OutboxState.failedRetryable,
        lastAttemptAt: now,
      );
      _patchMessage(messageId, MessageUiState.failed);
      rethrow;
    } finally {
      _inFlight.remove(messageId);
    }
  }

  Future<void> retryPending() async {
    final now = _clock().toUtc();
    await repo.markExpiredIfNeeded(now);
    final recs = await repo.pending();
    for (final rec in recs) {
      if (rec.state == OutboxState.delivered || rec.state == OutboxState.expired) {
        continue;
      }
      if (_inFlight.contains(rec.messageId)) continue;
      if (rec.lastAttemptAt != null) {
        final wait = retryDelay(rec.attemptCount);
        if (now.isBefore(rec.lastAttemptAt!.add(wait))) continue;
      }
      await trySend(rec.messageId);
    }
  }

  Future<EncryptedEnvelope?> onIncomingEnvelope(EncryptedEnvelope envelope) async {
    final material = trusted;
    if (material == null) return null;
    if (envelope.senderDeviceId != material.remoteDeviceId) {
      throw CryptoException('untrusted-sender');
    }
    final seen = await repo.seenIds();
    DecryptedPayload payload;
    try {
      payload = await protocol.decrypt(
        envelope: envelope,
        local: identity,
        senderIdentityPub: material.remoteIdentityPub,
        sessionKeyBytes: material.sessionKeyBytes,
        seenMessageIds: seen,
        now: _clock().toUtc(),
      );
    } on CryptoException catch (err) {
      if (err.code == 'duplicate') {
        if (envelope.messageId.startsWith('ack:')) return null;
        return protocol.encrypt(
          sender: identity,
          recipientDeviceId: material.remoteDeviceId,
          sessionKeyBytes: material.sessionKeyBytes,
          conversationId: envelope.conversationId,
          payload: DecryptedPayload(kind: 'ack', body: '', ackFor: envelope.messageId),
          now: _clock().toUtc(),
          messageId: 'ack:${envelope.messageId}',
        );
      }
      rethrow;
    }
    if (payload.kind == 'ack') {
      final target = payload.ackFor;
      if (target == null) return null;
      if (_seenAcks.contains(target)) return null;
      _seenAcks.add(target);
      await repo.markSeen(envelope.messageId);
      await repo.updateState(messageId: target, state: OutboxState.delivered);
      _patchMessage(target, MessageUiState.delivered);
      return null;
    }
    final inserted = await repo.insertInbox(InboxRecord(
      messageId: envelope.messageId,
      senderDeviceId: envelope.senderDeviceId,
      body: payload.body,
      createdAt: envelope.createdAt,
      kind: payload.kind,
    ));
    if (!inserted) {
      return protocol.encrypt(
        sender: identity,
        recipientDeviceId: material.remoteDeviceId,
        sessionKeyBytes: material.sessionKeyBytes,
        conversationId: envelope.conversationId,
        payload: DecryptedPayload(kind: 'ack', body: '', ackFor: envelope.messageId),
        now: _clock().toUtc(),
        messageId: 'ack:${envelope.messageId}',
      );
    }
    state = state.copyWith(messages: [
      ...state.messages.where((m) => m.messageId != envelope.messageId),
      OfflineChatMessage(
        messageId: envelope.messageId,
        mine: false,
        body: payload.body,
        state: MessageUiState.received,
        createdAt: envelope.createdAt,
      ),
    ]);
    return protocol.encrypt(
      sender: identity,
      recipientDeviceId: material.remoteDeviceId,
      sessionKeyBytes: material.sessionKeyBytes,
      conversationId: envelope.conversationId,
      payload: DecryptedPayload(kind: 'ack', body: '', ackFor: envelope.messageId),
      now: _clock().toUtc(),
      messageId: 'ack:${envelope.messageId}',
    );
  }

  static String conversationId(String a, String b) => _conversationId(a, b);

  static String _conversationId(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids[0]}:${ids[1]}';
  }

  static MessageUiState _uiState(OutboxState state) {
    return switch (state) {
      OutboxState.queued => MessageUiState.queued,
      OutboxState.sending => MessageUiState.sending,
      OutboxState.sentWaitingAck => MessageUiState.waitingAck,
      OutboxState.delivered => MessageUiState.delivered,
      OutboxState.failedRetryable => MessageUiState.failed,
      OutboxState.expired => MessageUiState.expired,
    };
  }

  void _patchMessage(String id, MessageUiState next) {
    state = state.copyWith(
      messages: [
        for (final m in state.messages)
          if (m.messageId == id) m.copyWith(state: next) else m,
      ],
    );
  }
}
