import 'dart:async';

import 'package:cryptography/cryptography.dart';

import '../domain/crypto_protocol.dart';
import '../domain/models.dart';
import '../domain/transport.dart';
import 'slice1_repository.dart';

enum OfflineUiPhase {
  idle,
  discovering,
  peerFound,
  connecting,
  verifyCode,
  trusted,
}

class OfflineSessionState {
  const OfflineSessionState({
    this.phase = OfflineUiPhase.idle,
    this.peers = const [],
    this.pendingRequest,
    this.safetyCode,
    this.trusted,
    this.lines = const [],
    this.status = 'Idle',
    this.error,
    this.transportState = TransportLinkState.unavailable,
    this.localDeviceId,
  });

  final OfflineUiPhase phase;
  final List<PeerDescriptor> peers;
  final IncomingConnectionRequest? pendingRequest;
  final String? safetyCode;
  final TrustedContact? trusted;
  final List<ChatLine> lines;
  final String status;
  final String? error;
  final TransportLinkState transportState;
  final String? localDeviceId;

  OfflineSessionState copyWith({
    OfflineUiPhase? phase,
    List<PeerDescriptor>? peers,
    IncomingConnectionRequest? pendingRequest,
    bool clearPending = false,
    String? safetyCode,
    bool clearSafety = false,
    TrustedContact? trusted,
    List<ChatLine>? lines,
    String? status,
    String? error,
    bool clearError = false,
    TransportLinkState? transportState,
    String? localDeviceId,
  }) {
    return OfflineSessionState(
      phase: phase ?? this.phase,
      peers: peers ?? this.peers,
      pendingRequest: clearPending ? null : (pendingRequest ?? this.pendingRequest),
      safetyCode: clearSafety ? null : (safetyCode ?? this.safetyCode),
      trusted: trusted ?? this.trusted,
      lines: lines ?? this.lines,
      status: status ?? this.status,
      error: clearError ? null : (error ?? this.error),
      transportState: transportState ?? this.transportState,
      localDeviceId: localDeviceId ?? this.localDeviceId,
    );
  }
}

class OfflineSessionEngine {
  OfflineSessionEngine({
    required this.identity,
    required NearbyAwareTransport transport,
    required Slice1Repository repository,
    Slice1Crypto? crypto,
    DateTime Function()? clock,
  })  : _transport = transport,
        _repo = repository,
        _crypto = crypto ?? Slice1Crypto(),
        _clock = clock ?? DateTime.now;

  final DeviceIdentity identity;
  final NearbyAwareTransport _transport;
  final Slice1Repository _repo;
  final Slice1Crypto _crypto;
  final DateTime Function() _clock;

  final StreamController<OfflineSessionState> _states =
      StreamController<OfflineSessionState>.broadcast();

  OfflineSessionState _state = const OfflineSessionState();
  SimpleKeyPair? _localEph;
  String? _remoteEphPub;
  String? _remoteIdentityPub;
  String? _remoteDeviceId;
  String? _remoteName;
  String? _activeEndpointId;
  List<int>? _sessionKey;
  bool _localConfirmed = false;
  bool _remoteConfirmed = false;
  bool _linkConnected = false;
  final Set<String> _inFlight = {};
  Timer? _retryTimer;
  StreamSubscription<List<PeerDescriptor>>? _peerSub;
  StreamSubscription<IncomingConnectionRequest>? _reqSub;
  StreamSubscription<Map<String, dynamic>>? _msgSub;
  StreamSubscription<TransportLinkState>? _stateSub;

  Stream<OfflineSessionState> get states => _states.stream;
  OfflineSessionState get current => _state;
  List<int>? get debugSessionKey => _sessionKey;

  Future<void> start() async {
    _peerSub ??= _transport.discoverPeers().listen((peers) {
      _emit(_state.copyWith(
        peers: peers,
        phase: peers.isEmpty ? OfflineUiPhase.discovering : OfflineUiPhase.peerFound,
        status: peers.isEmpty ? 'Discovering' : 'Peer Found',
      ));
    });
    _reqSub ??= _transport.connectionRequests.listen((req) {
      _emit(_state.copyWith(
        pendingRequest: req,
        phase: OfflineUiPhase.connecting,
        status: 'Connecting',
      ));
    });
    _msgSub ??= _transport.controlMessages.listen(_onControl);
    _stateSub ??= _transport.observeState().listen((link) {
      _linkConnected = link == TransportLinkState.connected;
      _emit(_state.copyWith(transportState: link));
      if (link == TransportLinkState.connected) {
        unawaited(_kickHandshake());
        unawaited(retryPending());
      }
    });
    final contacts = await _repo.trustedContacts();
    if (contacts.isNotEmpty) {
      final contact = contacts.first;
      _remoteDeviceId = contact.deviceId;
      _remoteIdentityPub = contact.publicKeyB64;
      _remoteName = contact.displayName;
      _activeEndpointId = contact.endpointId;
      _sessionKey = await _repo.sessionKeyFor(contact.deviceId);
      _emit(_state.copyWith(
        trusted: contact,
        localDeviceId: identity.deviceId,
        status: 'Queued',
      ));
      await _refreshLines();
    } else {
      _emit(_state.copyWith(localDeviceId: identity.deviceId));
    }
    await retryPending();
  }

  Future<void> _kickHandshake() async {
    _localEph ??= await _crypto.newEphemeral();
    await _sendHandshake(stage: 'hello');
  }

  void installSessionForTest({
    required TrustedContact trusted,
    required List<int> sessionKey,
    String? endpointId,
  }) {
    _sessionKey = sessionKey;
    _activeEndpointId = endpointId ?? trusted.endpointId;
    _remoteDeviceId = trusted.deviceId;
    _remoteIdentityPub = trusted.publicKeyB64;
    _remoteName = trusted.displayName;
    _localConfirmed = true;
    _remoteConfirmed = true;
    _linkConnected = true;
    _emit(_state.copyWith(
      trusted: trusted,
      phase: OfflineUiPhase.trusted,
      status: 'Trusted',
    ));
  }

  Future<void> handleIncomingEnvelope(EncryptedEnvelope envelope) {
    return _onEnvelope({
      't': 'envelope',
      'envelope': envelope.toJson(),
    });
  }

  Future<void> startDiscovery() async {
    try {
      await _transport.startDiscovery(displayName: identity.shortName);
      _emit(_state.copyWith(
        phase: OfflineUiPhase.discovering,
        status: 'Discovering',
        localDeviceId: identity.deviceId,
        clearError: true,
      ));
    } catch (err) {
      _emit(_state.copyWith(
        phase: OfflineUiPhase.idle,
        status: 'Failed',
        error: _readable(err),
        transportState: TransportLinkState.unavailable,
      ));
    }
  }

  Future<void> stopDiscovery() async {
    await _transport.stopDiscovery();
    _emit(_state.copyWith(phase: OfflineUiPhase.idle, status: 'Idle', peers: const []));
  }

  Future<void> connect(PeerDescriptor peer) async {
    _activeEndpointId = peer.endpointId;
    _remoteName = peer.displayName;
    _emit(_state.copyWith(phase: OfflineUiPhase.connecting, status: 'Connecting', clearError: true));
    final result = await _transport.connect(peer);
    if (!result.ok) {
      _emit(_state.copyWith(status: 'Failed', error: result.message ?? 'Connect failed'));
    }
  }

  Future<void> acceptIncoming() async {
    final req = _state.pendingRequest;
    if (req == null) return;
    _activeEndpointId = req.endpointId;
    _remoteName = req.displayName;
    await _transport.accept(req.endpointId);
    _emit(_state.copyWith(clearPending: true, status: 'Connecting'));
  }

  Future<void> rejectIncoming() async {
    final req = _state.pendingRequest;
    if (req == null) return;
    await _transport.reject(req.endpointId);
    await _resetPairing('pairing cancelled');
  }

  Future<void> confirmSafetyCode() async {
    if (_state.phase != OfflineUiPhase.verifyCode || _state.safetyCode == null) {
      return;
    }
    _localConfirmed = true;
    await _sendHandshake(stage: 'confirm');
    await _maybeTrust();
  }

  Future<void> rejectSafetyCode() async {
    await _sendHandshake(stage: 'reject');
    await _resetPairing('pairing cancelled');
  }

  Future<void> sendText(String plaintext) async {
    final trusted = _state.trusted;
    final key = _sessionKey;
    final endpoint = _activeEndpointId;
    if (trusted == null || key == null) {
      _emit(_state.copyWith(error: 'Unknown peer. Verify safety code first.'));
      return;
    }
    final now = _clock().toUtc();
    final envelope = await _crypto.encryptText(
      sender: identity,
      recipientDeviceId: trusted.deviceId,
      conversationId: trusted.conversationId,
      plaintext: plaintext,
      sessionKey: key,
      now: now,
    );
    final record = OutboxRecord(
      messageId: envelope.messageId,
      recipientDeviceId: trusted.deviceId,
      encryptedEnvelope: envelope,
      createdAt: envelope.createdAt,
      expiresAt: envelope.expiresAt,
      attemptCount: 0,
      state: OutboxState.queued,
    );
    await _repo.upsertOutbox(record);
    await _repo.saveLocalLine(
      ChatLine(
        messageId: envelope.messageId,
        body: plaintext,
        mine: true,
        createdAt: envelope.createdAt,
        statusLabel: 'Queued',
      ),
      trusted.conversationId,
    );
    await _refreshLines();
    if (endpoint == null || !_linkConnected) {
      _emit(_state.copyWith(status: 'Queued'));
      return;
    }
    await _attemptSend(record, endpoint);
  }

  Future<void> retryPending() async {
    final endpoint = _activeEndpointId;
    final pending = await _repo.pendingOutbox();
    for (final record in pending) {
      if (_clock().toUtc().isAfter(record.expiresAt)) {
        await _repo.upsertOutbox(record.copyWith(state: OutboxState.expired));
        await _updateLineStatus(record.messageId, record.encryptedEnvelope.conversationId, 'Expired');
        continue;
      }
      if (endpoint == null || !_linkConnected) continue;
      if (!_canRetry(record)) continue;
      await _attemptSend(record, endpoint);
    }
    await _refreshLines();
  }

  bool _canRetry(OutboxRecord record) {
    if (record.state == OutboxState.delivered || record.state == OutboxState.expired) {
      return false;
    }
    if (_inFlight.contains(record.messageId)) return false;
    final last = record.lastAttemptAt;
    if (last == null) return true;
    final delayMs = 1000 * (1 << record.attemptCount.clamp(0, 6));
    return _clock().toUtc().difference(last).inMilliseconds >= delayMs;
  }

  Future<void> _attemptSend(OutboxRecord record, String endpoint) async {
    if (_inFlight.contains(record.messageId)) return;
    _inFlight.add(record.messageId);
    final sending = record.copyWith(
      attemptCount: record.attemptCount + 1,
      lastAttemptAt: _clock().toUtc(),
      state: OutboxState.sending,
    );
    await _repo.upsertOutbox(sending);
    await _updateLineStatus(record.messageId, record.encryptedEnvelope.conversationId, 'Sending');
    final result = await _transport.send(
      PeerDescriptor(endpointId: endpoint, displayName: _remoteName ?? 'peer'),
      record.encryptedEnvelope,
    );
    if (result.ok) {
      await _repo.upsertOutbox(sending.copyWith(state: OutboxState.sentWaitingAck));
      await _updateLineStatus(record.messageId, record.encryptedEnvelope.conversationId, 'Waiting for ACK');
      _emit(_state.copyWith(status: 'Waiting for ACK'));
    } else {
      await _repo.upsertOutbox(sending.copyWith(state: OutboxState.failedRetryable));
      await _updateLineStatus(record.messageId, record.encryptedEnvelope.conversationId, 'Failed');
      _emit(_state.copyWith(status: 'Failed', error: result.message));
      _scheduleRetry();
    }
    _inFlight.remove(record.messageId);
    await _refreshLines();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 2), () {
      unawaited(retryPending());
    });
  }

  Future<void> _onControl(Map<String, dynamic> msg) async {
    final type = msg['t'] as String?;
    final endpointId = msg['endpointId'] as String?;
    if (endpointId != null) {
      _activeEndpointId = endpointId;
    }
    switch (type) {
      case 'handshake':
        await _onHandshake(msg);
      case 'envelope':
        await _onEnvelope(msg);
      case 'disconnected':
        _linkConnected = false;
        _emit(_state.copyWith(
          transportState: TransportLinkState.unavailable,
          status: 'Queued',
        ));
      default:
        break;
    }
  }

  Future<void> _onHandshake(Map<String, dynamic> msg) async {
    final stage = msg['stage'] as String? ?? 'hello';
    if (stage == 'reject') {
      await _resetPairing('peer rejected pairing');
      return;
    }
    if (stage == 'confirm') {
      final remoteCode = msg['code'] as String?;
      final localCode = _state.safetyCode;
      final remoteSig = msg['transcriptSig'] as String?;
      if (_remoteIdentityPub == null ||
          _remoteEphPub == null ||
          _remoteDeviceId == null ||
          localCode == null ||
          remoteCode != localCode) {
        await _sendHandshake(stage: 'reject');
        await _resetPairing('safety code mismatch');
        return;
      }
      if (remoteSig != null) {
        final ok = await _crypto.verifyTranscript(
          publicKeyB64: _remoteIdentityPub!,
          transcript: await _transcript(),
          signatureB64: remoteSig,
        );
        if (!ok) {
          await _sendHandshake(stage: 'reject');
          await _resetPairing('safety code mismatch');
          return;
        }
      }
      _remoteConfirmed = true;
      await _maybeTrust();
      return;
    }
    _remoteDeviceId = msg['deviceId'] as String? ?? _remoteDeviceId;
    _remoteIdentityPub = msg['identityPub'] as String? ?? _remoteIdentityPub;
    _remoteEphPub = msg['ephPub'] as String? ?? _remoteEphPub;
    _remoteName = msg['displayName'] as String? ?? _remoteName;
    final remoteSig = msg['transcriptSig'] as String?;
    if (_localEph == null) {
      _localEph = await _crypto.newEphemeral();
    }
    if (_remoteDeviceId == null || _remoteIdentityPub == null || _remoteEphPub == null) {
      return;
    }
    final existing = await _repo.trustedByDeviceId(_remoteDeviceId!);
    if (existing != null && existing.publicKeyB64 != _remoteIdentityPub) {
      await _resetPairing('safety code mismatch');
      return;
    }
    if (existing != null && existing.publicKeyB64 == _remoteIdentityPub) {
      _sessionKey = await _repo.sessionKeyFor(_remoteDeviceId!) ?? _sessionKey;
      _localConfirmed = true;
      _remoteConfirmed = true;
      if (stage == 'hello') {
        await _sendHandshake(stage: 'hello-ack');
      }
      await _maybeTrust();
      return;
    }
    final transcript = await _transcript();
    if (remoteSig != null) {
      final ok = await _crypto.verifyTranscript(
        publicKeyB64: _remoteIdentityPub!,
        transcript: transcript,
        signatureB64: remoteSig,
      );
      if (!ok) {
        await _resetPairing('safety code mismatch');
        return;
      }
    }
    _sessionKey = await _crypto.deriveSessionKey(
      localEph: _localEph!,
      remoteEphPubB64: _remoteEphPub!,
      transcript: transcript,
    );
    final code = await _crypto.safetyCode(transcript);
    _emit(_state.copyWith(
      phase: OfflineUiPhase.verifyCode,
      status: 'Verify Code',
      safetyCode: code,
    ));
    if (stage == 'hello') {
      await _sendHandshake(stage: 'hello-ack');
    }
  }

  Future<void> _sendHandshake({required String stage}) async {
    final endpoint = _activeEndpointId;
    if (endpoint == null) return;
    _localEph ??= await _crypto.newEphemeral();
    final payload = <String, dynamic>{
      't': 'handshake',
      'stage': stage,
      'deviceId': identity.deviceId,
      'displayName': identity.shortName,
      'identityPub': identity.publicKeyB64,
      'ephPub': await _crypto.publicB64(_localEph!),
    };
    if (stage == 'confirm') {
      final code = _state.safetyCode;
      if (code == null) return;
      payload['code'] = code;
    }
    if (_remoteDeviceId == null || _remoteIdentityPub == null || _remoteEphPub == null) {
      await _transport.sendControl(endpoint, payload);
      return;
    }
    final transcript = await _transcript();
    payload['transcriptSig'] =
        await _crypto.signTranscript(identity: identity, transcript: transcript);
    await _transport.sendControl(endpoint, payload);
  }

  Future<HandshakeTranscript> _transcript() async {
    return HandshakeTranscript(
      localDeviceId: identity.deviceId,
      remoteDeviceId: _remoteDeviceId!,
      localIdentityPub: identity.publicKeyB64,
      remoteIdentityPub: _remoteIdentityPub!,
      localEphPub: await _crypto.publicB64(_localEph!),
      remoteEphPub: _remoteEphPub!,
    );
  }

  Future<void> _maybeTrust() async {
    if (!_localConfirmed || !_remoteConfirmed) return;
    if (_remoteDeviceId == null || _remoteIdentityPub == null) return;
    final conversationId = _crypto.conversationId(identity.deviceId, _remoteDeviceId!);
    final contact = TrustedContact(
      deviceId: _remoteDeviceId!,
      displayName: _remoteName ?? _remoteDeviceId!,
      publicKeyB64: _remoteIdentityPub!,
      conversationId: conversationId,
      verifiedAt: _clock().toUtc(),
      keyVersion: Slice1Crypto.keyVersion,
      endpointId: _activeEndpointId,
    );
    await _repo.saveTrusted(contact);
    if (_sessionKey != null) {
      await _repo.saveSessionKey(contact.deviceId, _sessionKey!);
    }
    _emit(_state.copyWith(
      phase: OfflineUiPhase.trusted,
      status: 'Trusted',
      trusted: contact,
    ));
    await retryPending();
  }

  Future<void> _onEnvelope(Map<String, dynamic> msg) async {
    final raw = msg['envelope'];
    if (raw is! Map) return;
    final envelope = EncryptedEnvelope.fromJson(Map<String, dynamic>.from(raw));
    final now = _clock().toUtc();
    if (now.isAfter(envelope.expiresAt)) return;
    if (envelope.recipientDeviceId != identity.deviceId) return;
    if (await _repo.hasSeen(envelope.messageId)) {
      if (_looksLikeAck(envelope)) {
        return;
      }
      return;
    }
    final trusted = await _repo.trustedByDeviceId(envelope.senderDeviceId);
    if (trusted == null || _sessionKey == null) {
      _emit(_state.copyWith(error: 'Unknown peer. Message rejected.'));
      return;
    }
    final sigOk = await _crypto.verifyEnvelopeSignature(
      envelope: envelope,
      senderPublicKeyB64: trusted.publicKeyB64,
    );
    if (!sigOk) return;
    Map<String, dynamic> payload;
    try {
      payload = await _crypto.decryptEnvelope(
        envelope: envelope,
        sessionKey: _sessionKey!,
      );
    } catch (_) {
      return;
    }
    await _repo.markSeen(envelope.messageId);
    final type = payload['type'] as String?;
    if (type == 'ack') {
      final ackId = payload['messageId'] as String?;
      if (ackId == null) return;
      final existing = await _repo.outboxById(ackId);
      if (existing != null) {
        await _repo.upsertOutbox(existing.copyWith(state: OutboxState.delivered));
        await _updateLineStatus(ackId, existing.encryptedEnvelope.conversationId, 'Delivered');
        _emit(_state.copyWith(status: 'Delivered'));
      }
      return;
    }
    if (type != 'text') return;
    final body = payload['body'] as String? ?? '';
    await _repo.saveInbox(
      InboxMessage(
        messageId: envelope.messageId,
        conversationId: envelope.conversationId,
        senderDeviceId: envelope.senderDeviceId,
        recipientDeviceId: envelope.recipientDeviceId,
        body: body,
        createdAt: envelope.createdAt,
      ),
    );
    await _repo.saveLocalLine(
      ChatLine(
        messageId: envelope.messageId,
        body: body,
        mine: false,
        createdAt: envelope.createdAt,
        statusLabel: 'Delivered',
      ),
      envelope.conversationId,
    );
    await _refreshLines();
    final ack = await _crypto.encryptAck(
      sender: identity,
      recipientDeviceId: envelope.senderDeviceId,
      conversationId: envelope.conversationId,
      ackMessageId: envelope.messageId,
      sessionKey: _sessionKey!,
      now: now,
    );
    final endpoint = _activeEndpointId;
    if (endpoint != null) {
      await _transport.send(
        PeerDescriptor(endpointId: endpoint, displayName: trusted.displayName),
        ack,
      );
    }
  }

  bool _looksLikeAck(EncryptedEnvelope envelope) => envelope.messageId.isNotEmpty;

  Future<void> _updateLineStatus(
    String messageId,
    String conversationId,
    String status,
  ) async {
    final lines = await _repo.linesFor(conversationId);
    for (final line in lines) {
      if (line.messageId == messageId) {
        await _repo.saveLocalLine(
          ChatLine(
            messageId: line.messageId,
            body: line.body,
            mine: line.mine,
            createdAt: line.createdAt,
            statusLabel: status,
          ),
          conversationId,
        );
      }
    }
  }

  Future<void> _refreshLines() async {
    final trusted = _state.trusted;
    if (trusted == null) return;
    final lines = await _repo.linesFor(trusted.conversationId);
    _emit(_state.copyWith(lines: lines));
  }

  Future<void> _resetPairing(String reason) async {
    _localConfirmed = false;
    _remoteConfirmed = false;
    _sessionKey = null;
    _localEph = null;
    _remoteEphPub = null;
    _remoteIdentityPub = null;
    _remoteDeviceId = null;
    _emit(_state.copyWith(
      phase: OfflineUiPhase.peerFound,
      status: 'Failed',
      error: reason,
      clearSafety: true,
      clearPending: true,
    ));
  }

  String _readable(Object err) {
    final text = err.toString();
    if (text.contains('Missing permissions')) {
      return 'Nearby permissions were denied. Other app features still work.';
    }
    if (text.contains('only available on Android')) {
      return 'Offline nearby messaging is available on Android devices.';
    }
    return 'Nearby service is unavailable.';
  }

  void _emit(OfflineSessionState next) {
    _state = next;
    _states.add(next);
  }

  Future<void> dispose() async {
    _retryTimer?.cancel();
    await _peerSub?.cancel();
    await _reqSub?.cancel();
    await _msgSub?.cancel();
    await _stateSub?.cancel();
    await _states.close();
  }
}
