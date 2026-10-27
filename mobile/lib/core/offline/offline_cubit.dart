import 'dart:async';
import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../crypto/encrypted_envelope.dart';
import '../crypto/slice1_protocol.dart';
import '../identity/device_identity.dart';
import '../transport/nearby_transport.dart';
import '../transport/p2p_transport.dart';
import 'offline_repository.dart';
import 'offline_session.dart';
import 'pairing.dart';

class OfflineCubit extends Cubit<OfflineSessionState> {
  OfflineCubit({
    NearbyTransport? transport,
    DeviceIdentityService? identityService,
    OfflineRepository? repository,
    Slice1Protocol? protocol,
  })  : _transport = transport ?? NearbyTransport(),
        _identityService = identityService ?? DeviceIdentityService(),
        _repo = repository ?? SqlOfflineRepository(),
        _protocol = protocol ?? Slice1Protocol(),
        super(const OfflineSessionState());

  final NearbyTransport _transport;
  final DeviceIdentityService _identityService;
  final OfflineRepository _repo;
  final Slice1Protocol _protocol;

  OfflineSessionEngine? _engine;
  StreamSubscription<List<PeerDescriptor>>? _peerSub;
  StreamSubscription<IncomingBytes>? _bytesSub;
  StreamSubscription<IncomingConnectionRequest>? _reqSub;
  StreamSubscription<ConnectionState>? _stateSub;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final identity = await _identityService.loadOrCreate();
    _transport.localName = identity.displayName;
    final engine = OfflineSessionEngine(
      identity: identity,
      protocol: _protocol,
      repo: _repo,
      sendEnvelope: _transport.send,
      sendControl: _transport.sendControl,
    );
    _engine = engine;
    await engine.restore();
    emit(engine.state.copyWith(phase: SessionUiPhase.discovering));
    _peerSub = _transport.discoverPeers().listen((peers) {
      engine.setPeers(peers);
      emit(engine.state);
    });
    _reqSub = _transport.connectionRequests.listen((req) {
      engine.setIncomingRequest(req);
      emit(engine.state.copyWith(incomingRequest: req, phase: SessionUiPhase.connecting));
    });
    _stateSub = _transport.observeState().listen((s) {
      if (s.kind == ConnectionStateKind.connected) {
        unawaited(_onConnected(s.endpointId));
      } else if (s.kind == ConnectionStateKind.disconnected) {
        emit(engine.state.copyWith(error: 'peer-disconnected'));
      } else if (s.kind == ConnectionStateKind.error) {
        emit(engine.state.copyWith(error: s.detail ?? 'transport-error'));
      }
    });
    _bytesSub = _transport.incoming.listen(_onBytes);
    await _transport.startDiscovery();
  }

  Future<void> stop() async {
    _started = false;
    await _transport.stopDiscovery();
    emit(const OfflineSessionState());
  }

  Future<void> connect(PeerDescriptor peer) async {
    final engine = _engine;
    if (engine == null) return;
    engine.transportPeer = peer;
    engine.state = engine.state.copyWith(
      phase: SessionUiPhase.connecting,
      activePeer: peer,
      clearError: true,
    );
    emit(engine.state);
    await _transport.connect(peer);
  }

  Future<void> acceptIncoming() async {
    final engine = _engine;
    final req = engine?.state.incomingRequest;
    if (engine == null || req == null) return;
    engine.transportPeer = PeerDescriptor(
      endpointId: req.endpointId,
      displayName: req.displayName,
    );
    await _transport.accept(req.endpointId);
    engine.state = engine.state.copyWith(clearIncoming: true);
    emit(engine.state);
  }

  Future<void> rejectIncoming() async {
    final engine = _engine;
    final req = engine?.state.incomingRequest;
    if (engine == null || req == null) return;
    await _transport.reject(req.endpointId);
    engine.rejectPairing();
    emit(engine.state.copyWith(clearIncoming: true));
  }

  Future<void> confirmSafety() async {
    final engine = _engine;
    final peer = engine?.transportPeer;
    if (engine == null || peer == null) return;
    if (engine.pairing?.material == null) {
      emit(engine.state.copyWith(error: 'handshake-incomplete'));
      return;
    }
    final frame = await engine.pairing!.confirmFrame();
    await _transport.sendControl(peer.endpointId, frame);
    await engine.confirmLocalAndTrust(peer: peer);
    emit(engine.state);
    await engine.retryPending();
    emit(engine.state);
  }

  Future<void> rejectSafety() async {
    final engine = _engine;
    final peer = engine?.transportPeer;
    if (engine == null) return;
    engine.rejectPairing();
    if (peer != null) {
      await _transport.disconnect(peer);
    }
    emit(engine.state);
  }

  Future<void> sendText(String body) async {
    final engine = _engine;
    if (engine == null) return;
    if (engine.trusted == null) {
      emit(engine.state.copyWith(error: 'untrusted-peer'));
      return;
    }
    await engine.sendText(body);
    emit(engine.state);
  }

  Future<void> onResume() async {
    final engine = _engine;
    if (engine == null) return;
    await engine.retryPending();
    emit(engine.state);
  }

  Future<void> _onConnected(String? endpointId) async {
    final engine = _engine;
    if (engine == null || endpointId == null) return;
    engine.transportPeer ??= PeerDescriptor(endpointId: endpointId, displayName: endpointId);
    if (engine.trusted != null) {
      engine.state = engine.state.copyWith(
        phase: SessionUiPhase.trusted,
        activePeer: engine.transportPeer,
      );
      emit(engine.state);
      await engine.retryPending();
      emit(engine.state);
      return;
    }
    final offer = await engine.beginPairing();
    await _transport.sendControl(endpointId, offer.toJson());
    emit(engine.state.copyWith(phase: SessionUiPhase.connecting));
  }

  Future<void> _onBytes(IncomingBytes event) async {
    final engine = _engine;
    if (engine == null) return;
    Map<String, dynamic> map;
    try {
      map = jsonDecode(utf8.decode(event.bytes)) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = map['t'] as String?;
    if (type == 'hs1') {
      try {
        final offer = HandshakeOffer.fromJson(map);
        await engine.onHandshakeOffer(offer);
        emit(engine.state);
      } catch (err) {
        engine.rejectPairing();
        emit(engine.state.copyWith(error: 'handshake-failed'));
      }
      return;
    }
    if (type == 'hs2') {
      final ok = await engine.onHandshakeConfirm(map);
      if (!ok) {
        emit(engine.state);
        return;
      }
      emit(engine.state.copyWith(phase: SessionUiPhase.verifyCode));
      return;
    }
    if (type == 'env') {
      try {
        final envelope = EncryptedEnvelope.fromJson(map['e'] as Map<String, dynamic>);
        final ack = await engine.onIncomingEnvelope(envelope);
        emit(engine.state);
        if (ack != null && engine.transportPeer != null) {
          await _transport.send(engine.transportPeer!, ack);
        }
      } on CryptoException catch (err) {
        emit(engine.state.copyWith(error: err.code));
      } catch (_) {
        emit(engine.state.copyWith(error: 'transport-error'));
      }
      return;
    }
  }

  @override
  Future<void> close() async {
    await _peerSub?.cancel();
    await _bytesSub?.cancel();
    await _reqSub?.cancel();
    await _stateSub?.cancel();
    await _transport.dispose();
    return super.close();
  }
}
