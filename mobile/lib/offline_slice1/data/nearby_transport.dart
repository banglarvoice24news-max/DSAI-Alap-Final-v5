import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/models.dart';
import '../domain/transport.dart';

class NearbyTransport implements NearbyAwareTransport {
  NearbyTransport({
    Nearby? nearby,
    this.serviceId = 'com.nexus.comm.slice1',
  }) : _nearby = nearby ?? Nearby();

  final Nearby _nearby;
  final String serviceId;

  final StreamController<List<PeerDescriptor>> _peers =
      StreamController<List<PeerDescriptor>>.broadcast();
  final StreamController<TransportLinkState> _state =
      StreamController<TransportLinkState>.broadcast();
  final StreamController<IncomingConnectionRequest> _requests =
      StreamController<IncomingConnectionRequest>.broadcast();
  final StreamController<Map<String, dynamic>> _control =
      StreamController<Map<String, dynamic>>.broadcast();

  final Map<String, PeerDescriptor> _known = {};
  final Set<String> _connected = {};
  String _localName = 'Nexus';
  bool _running = false;

  @override
  Stream<IncomingConnectionRequest> get connectionRequests => _requests.stream;

  @override
  Stream<Map<String, dynamic>> get controlMessages => _control.stream;

  @override
  Future<TransportCapabilities> capabilities() async {
    if (!Platform.isAndroid) {
      return const TransportCapabilities(
        ready: false,
        reason: 'Nearby Connections is only available on Android.',
      );
    }
    final missing = await _deniedPermissions();
    if (missing.isNotEmpty) {
      return TransportCapabilities(
        ready: false,
        reason: 'Missing permissions: ${missing.map((p) => p.toString()).join(', ')}',
      );
    }
    return const TransportCapabilities(ready: true);
  }

  Future<List<Permission>> _deniedPermissions() async {
    final required = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ];
    if (Platform.isAndroid) {
      required.add(Permission.locationWhenInUse);
    }
    final statuses = await required.request();
    return statuses.entries
        .where((e) => !e.value.isGranted)
        .map((e) => e.key)
        .toList();
  }

  @override
  Stream<List<PeerDescriptor>> discoverPeers() => _peers.stream;

  @override
  Stream<TransportLinkState> observeState() => _state.stream;

  @override
  Future<void> startDiscovery({required String displayName}) async {
    if (_running) return;
    _localName = displayName;
    final caps = await capabilities();
    if (!caps.ready) {
      _state.add(TransportLinkState.unavailable);
      throw StateError(caps.reason ?? 'Nearby unavailable');
    }
    _running = true;
    _state.add(TransportLinkState.available);
    await _nearby.startAdvertising(
      _localName,
      Strategy.P2P_POINT_TO_POINT,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
      serviceId: serviceId,
    );
    await _nearby.startDiscovery(
      _localName,
      Strategy.P2P_POINT_TO_POINT,
      onEndpointFound: (id, name, service) {
        _known[id] = PeerDescriptor(
          endpointId: id,
          displayName: name,
          state: TransportLinkState.available,
        );
        _emitPeers();
      },
      onEndpointLost: (id) {
        if (id == null) return;
        _known.remove(id);
        _connected.remove(id);
        _emitPeers();
      },
      serviceId: serviceId,
    );
  }

  @override
  Future<void> stopDiscovery() async {
    _running = false;
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    try {
      await _nearby.stopDiscovery();
    } catch (_) {}
    _known.clear();
    _emitPeers();
    _state.add(TransportLinkState.unavailable);
  }

  @override
  Future<ConnectionResult> connect(PeerDescriptor peer) async {
    try {
      _known[peer.endpointId] = peer.copyWith(state: TransportLinkState.available);
      _emitPeers();
      await _nearby.requestConnection(
        _localName,
        peer.endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      return const ConnectionResult(ok: true);
    } catch (err) {
      _state.add(TransportLinkState.error);
      return ConnectionResult(ok: false, message: err.toString());
    }
  }

  @override
  Future<void> accept(String endpointId) async {
    await _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: (id, payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          _onBytes(id, payload.bytes!);
        }
      },
      onPayloadTransferUpdate: (id, update) {},
    );
  }

  @override
  Future<void> reject(String endpointId) async {
    try {
      await _nearby.rejectConnection(endpointId);
    } catch (_) {}
  }

  @override
  Future<SendResult> send(PeerDescriptor peer, EncryptedEnvelope envelope) {
    return sendControl(peer.endpointId, {
      't': 'envelope',
      'envelope': envelope.toJson(),
    });
  }

  @override
  Future<SendResult> sendControl(
    String endpointId,
    Map<String, dynamic> message,
  ) async {
    if (!_connected.contains(endpointId)) {
      return const SendResult(ok: false, message: 'Peer not connected');
    }
    try {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(message)));
      await _nearby.sendBytesPayload(endpointId, bytes);
      return const SendResult(ok: true);
    } catch (err) {
      return SendResult(ok: false, message: err.toString());
    }
  }

  @override
  Future<void> disconnect(PeerDescriptor peer) async {
    try {
      await _nearby.disconnectFromEndpoint(peer.endpointId);
    } catch (_) {}
    _connected.remove(peer.endpointId);
    _emitPeers();
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    _known[endpointId] = PeerDescriptor(
      endpointId: endpointId,
      displayName: info.endpointName,
      state: TransportLinkState.available,
    );
    _emitPeers();
    _requests.add(
      IncomingConnectionRequest(
        endpointId: endpointId,
        displayName: info.endpointName,
      ),
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      _connected.add(endpointId);
      final existing = _known[endpointId];
      if (existing != null) {
        _known[endpointId] = existing.copyWith(state: TransportLinkState.connected);
      }
      _state.add(TransportLinkState.connected);
      _emitPeers();
    } else {
      _state.add(TransportLinkState.error);
    }
  }

  void _onDisconnected(String endpointId) {
    _connected.remove(endpointId);
    final existing = _known[endpointId];
    if (existing != null) {
      _known[endpointId] = existing.copyWith(state: TransportLinkState.unavailable);
    }
    _state.add(TransportLinkState.unavailable);
    _control.add({'t': 'disconnected', 'endpointId': endpointId});
    _emitPeers();
  }

  void _onBytes(String endpointId, Uint8List bytes) {
    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      map['endpointId'] = endpointId;
      _control.add(map);
    } catch (_) {
      _state.add(TransportLinkState.error);
    }
  }

  void _emitPeers() {
    _peers.add(_known.values.toList(growable: false));
  }
}
