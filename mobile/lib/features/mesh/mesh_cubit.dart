import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import '../../services/offline_mesh_service.dart';
import 'mesh_models.dart';

class MeshCubit extends Cubit<MeshState> {
  MeshCubit({OfflineMeshService? service})
      : _service = service ?? OfflineMeshService(),
        super(const MeshState());

  final OfflineMeshService _service;
  StreamSubscription<MeshDiscoveryEvent>? _discSub;
  StreamSubscription<MeshConnectionEvent>? _connSub;

  Future<void> start() async {
    emit(state.copyWith(scanning: true, clearError: true));
    try {
      final perms = await _service.ensurePermissions();
      if (!perms.granted) {
        emit(state.copyWith(
          scanning: false,
          permissionsGranted: false,
          error: 'Missing nearby / bluetooth / location permissions',
        ));
        return;
      }
      _discSub ??= _service.discovery.listen(_onDiscovery);
      _connSub ??= _service.connections.listen(_onConnection);
      await _service.startDiscovery();
      emit(state.copyWith(scanning: true, permissionsGranted: true));
    } catch (err) {
      emit(state.copyWith(scanning: false, error: err.toString()));
    }
  }

  Future<void> stop() async {
    await _service.stopDiscovery();
    emit(state.copyWith(scanning: false, peers: const []));
  }

  Future<void> connect(MeshPeer peer) async {
    final updated = state.peers
        .map((p) => p.id == peer.id ? p.copyWith(status: MeshPeerStatus.connecting) : p)
        .toList();
    emit(state.copyWith(peers: updated, activePeerId: peer.id));
    await _service.connect(peer.endpointId ?? peer.id);
  }

  Future<void> startCall(MeshPeer peer, {required bool asHost}) async {
    await _service.startVoiceCall(asHost: asHost);
    emit(state.copyWith(inCall: true, activePeerId: peer.id));
  }

  Future<void> hangup() async {
    await _service.endVoiceCall();
    await _service.disconnect();
    emit(state.copyWith(inCall: false, clearActive: true));
  }

  void _onDiscovery(MeshDiscoveryEvent event) {
    switch (event.kind) {
      case MeshDiscoveryKind.found:
        final ep = event.endpoint!;
        final peer = MeshPeer(
          id: ep.id,
          name: ep.name,
          rssi: ep.rssi,
          distanceMeters: event.distanceMeters ?? 0,
          endpointId: ep.id,
        );
        final next = [...state.peers.where((p) => p.id != peer.id), peer];
        emit(state.copyWith(peers: next));
      case MeshDiscoveryKind.lost:
        emit(state.copyWith(peers: state.peers.where((p) => p.id != event.lostId).toList()));
      case MeshDiscoveryKind.cleared:
        emit(state.copyWith(peers: const []));
      case MeshDiscoveryKind.permissionDenied:
        emit(state.copyWith(permissionsGranted: false, error: 'Permissions denied'));
    }
  }

  void _onConnection(MeshConnectionEvent event) {
    MeshPeerStatus status;
    switch (event.kind) {
      case MeshConnectionKind.connecting:
        status = MeshPeerStatus.connecting;
      case MeshConnectionKind.connected:
        status = MeshPeerStatus.connected;
      case MeshConnectionKind.dropped:
        status = MeshPeerStatus.dropped;
      case MeshConnectionKind.failed:
        status = MeshPeerStatus.discovered;
    }
    final next = state.peers
        .map((p) => p.id == event.endpointId ? p.copyWith(status: status) : p)
        .toList();
    emit(state.copyWith(
      peers: next,
      inCall: event.kind == MeshConnectionKind.dropped || event.kind == MeshConnectionKind.failed
          ? false
          : state.inCall,
    ));
  }

  @override
  Future<void> close() async {
    await _discSub?.cancel();
    await _connSub?.cancel();
    await _service.dispose();
    return super.close();
  }
}
