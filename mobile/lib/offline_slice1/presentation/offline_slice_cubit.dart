import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/identity_service.dart';
import '../data/session_engine.dart';
import '../data/slice1_repository.dart';
import '../data/sql_slice1_repository.dart';
import '../data/transport_manager.dart';
import '../domain/models.dart';
import '../domain/transport.dart';

class OfflineSliceCubit extends Cubit<OfflineSessionState> {
  OfflineSliceCubit({
    IdentityService? identityService,
    NearbyAwareTransport? transport,
    Slice1Repository? repository,
    OfflineSessionEngine? engine,
  })  : _identityService = identityService ?? IdentityService(),
        _transport = transport ?? TransportManager().transport,
        _repository = repository ?? SqlSlice1Repository(),
        _injectedEngine = engine,
        super(const OfflineSessionState());

  final IdentityService _identityService;
  final NearbyAwareTransport _transport;
  final Slice1Repository _repository;
  final OfflineSessionEngine? _injectedEngine;
  OfflineSessionEngine? _engine;
  StreamSubscription<OfflineSessionState>? _sub;
  Future<void>? _bootstrap;
  DeviceIdentity? identity;

  Future<void> bootstrap({String? linkedAccountHint}) async {
    if (_bootstrap != null) {
      await _bootstrap;
      await _engine?.retryPending();
      if (_engine != null) emit(_engine!.current);
      return;
    }
    _bootstrap = _doBootstrap(linkedAccountHint);
    await _bootstrap;
  }

  Future<void> _doBootstrap(String? linkedAccountHint) async {
    identity = await _identityService.loadOrCreate(
      linkedAccountHint: linkedAccountHint,
    );
    _engine = _injectedEngine ??
        OfflineSessionEngine(
          identity: identity!,
          transport: _transport,
          repository: _repository,
        );
    await _sub?.cancel();
    _sub = _engine!.states.listen(emit);
    await _engine!.start();
    emit(_engine!.current);
  }

  Future<void> startDiscovery() async {
    await _engine?.startDiscovery();
  }

  Future<void> stopDiscovery() async {
    await _engine?.stopDiscovery();
  }

  Future<void> connect(PeerDescriptor peer) async {
    await _engine?.connect(peer);
  }

  Future<void> acceptIncoming() async {
    await _engine?.acceptIncoming();
  }

  Future<void> rejectIncoming() async {
    await _engine?.rejectIncoming();
  }

  Future<void> confirmSafetyCode() async {
    await _engine?.confirmSafetyCode();
  }

  Future<void> rejectSafetyCode() async {
    await _engine?.rejectSafetyCode();
  }

  Future<void> sendText(String text) async {
    await _engine?.sendText(text);
  }

  Future<void> retryPending() async {
    await _engine?.retryPending();
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _engine?.dispose();
    return super.close();
  }
}
