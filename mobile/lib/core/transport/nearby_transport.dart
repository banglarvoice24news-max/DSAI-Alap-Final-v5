import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

import '../crypto/encrypted_envelope.dart';
import 'p2p_transport.dart';

class NearbyTransport implements Transport {
  NearbyTransport({
    Nearby? nearby,
    this.serviceId = 'com.nexus.comm.slice1',
    this.localName = 'Nexus',
  }) : _nearby = nearby ?? Nearby();

  final Nearby _nearby;
  final String serviceId;
  String localName;

  final StreamController<List<PeerDescriptor>> _peers =
      StreamController<List<PeerDescriptor>>.broadcast();
  final StreamController<ConnectionState> _state =
      StreamController<ConnectionState>.broadcast();
  final StreamController<IncomingBytes> _incoming =
      StreamController<IncomingBytes>.broadcast();
  final StreamController<IncomingConnectionRequest> _incomingRequests =
      StreamController<IncomingConnectionRequest>.broadcast();

  final Map<String, PeerDescriptor> _discovered = {};
  final Set<String> _connected = {};
  bool _running = false;
  Completer<ConnectionResult>? _pendingConnect;

  Stream<IncomingBytes> get incoming => _incoming.stream;
  Stream<IncomingConnectionRequest> get connectionRequests => _incomingRequests.stream;
  Set<String> get connectedIds => Set.unmodifiable(_connected);

  @override
  Future<P2pCapabilities> capabilities() async {
    try {
      final denied = <Permission>[];
      for (final p in const [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.nearbyWifiDevices,
        Permission.locationWhenInUse,
      ]) {
        final status = await p.status;
        if (!status.isGranted) denied.add(p);
      }
      if (denied.isNotEmpty) {
        return const P2pCapabilities(
          name: 'nearby',
          availability: TransportAvailability.unavailable,
          detail: 'permission-needed',
        );
      }
      return const P2pCapabilities(
        name: 'nearby',
        availability: TransportAvailability.available,
      );
    } catch (err) {
      return P2pCapabilities(
        name: 'nearby',
        availability: TransportAvailability.error,
        detail: err.toString(),
      );
    }
  }

  Future<bool> requestPermissions() async {
    final required = <Permission>[
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ];
    final statuses = await required.request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> startDiscovery() async {
    if (_running) return;
    final granted = await requestPermissions();
    if (!granted) {
      _state.add(const ConnectionState(
        kind: ConnectionStateKind.error,
        detail: 'permission-denied',
      ));
      return;
    }
    _running = true;
    _state.add(const ConnectionState(kind: ConnectionStateKind.discovering));
    await _nearby.startAdvertising(
      localName,
      Strategy.P2P_CLUSTER,
      serviceId: serviceId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
    await _nearby.startDiscovery(
      localName,
      Strategy.P2P_CLUSTER,
      serviceId: serviceId,
      onEndpointFound: (id, name, service) {
        _discovered[id] = PeerDescriptor(endpointId: id, displayName: name);
        _peers.add(_discovered.values.toList(growable: false));
      },
      onEndpointLost: (id) {
        if (id == null) return;
        _discovered.remove(id);
        _peers.add(_discovered.values.toList(growable: false));
      },
    );
  }

  Future<void> stopDiscovery() async {
    _running = false;
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    try {
      await _nearby.stopDiscovery();
    } catch (_) {}
    _discovered.clear();
    _peers.add(const []);
    _state.add(const ConnectionState(kind: ConnectionStateKind.idle));
  }

  @override
  Stream<List<PeerDescriptor>> discoverPeers() => _peers.stream;

  @override
  Future<ConnectionResult> connect(PeerDescriptor peer) async {
    _state.add(ConnectionState(
      kind: ConnectionStateKind.connecting,
      endpointId: peer.endpointId,
    ));
    _pendingConnect = Completer<ConnectionResult>();
    await _nearby.requestConnection(
      localName,
      peer.endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
    return _pendingConnect!.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () => const ConnectionResult(ok: false, error: 'timeout'),
    );
  }

  Future<void> accept(String endpointId) async {
    await _nearby.acceptConnection(
      endpointId,
      onPayLoadRecieved: (id, payload) {
        if (payload.type == PayloadType.BYTES && payload.bytes != null) {
          _incoming.add(IncomingBytes(endpointId: id, bytes: payload.bytes!));
        }
      },
      onPayloadTransferUpdate: (_, __) {},
    );
  }

  Future<void> reject(String endpointId) async {
    await _nearby.rejectConnection(endpointId);
  }

  @override
  Future<SendResult> send(PeerDescriptor peer, EncryptedEnvelope envelope) async {
    if (!_connected.contains(peer.endpointId)) {
      return const SendResult(ok: false, error: 'not-connected');
    }
    try {
      final frame = utf8.encode(jsonEncode({'t': 'env', 'e': envelope.toJson()}));
      await _nearby.sendBytesPayload(peer.endpointId, Uint8List.fromList(frame));
      return const SendResult(ok: true);
    } catch (err) {
      return SendResult(ok: false, error: err.toString());
    }
  }

  Future<SendResult> sendControl(String endpointId, Map<String, dynamic> json) async {
    try {
      final frame = utf8.encode(jsonEncode(json));
      await _nearby.sendBytesPayload(endpointId, Uint8List.fromList(frame));
      return const SendResult(ok: true);
    } catch (err) {
      return SendResult(ok: false, error: err.toString());
    }
  }

  @override
  Future<void> disconnect(PeerDescriptor peer) async {
    try {
      await _nearby.disconnectFromEndpoint(peer.endpointId);
    } catch (_) {}
    _connected.remove(peer.endpointId);
    _state.add(ConnectionState(
      kind: ConnectionStateKind.disconnected,
      endpointId: peer.endpointId,
    ));
  }

  @override
  Stream<ConnectionState> observeState() => _state.stream;

  Future<void> dispose() async {
    await stopDiscovery();
    try {
      await _nearby.stopAllEndpoints();
    } catch (_) {}
    await _peers.close();
    await _state.close();
    await _incoming.close();
    await _incomingRequests.close();
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    _incomingRequests.add(IncomingConnectionRequest(
      endpointId: endpointId,
      displayName: info.endpointName,
      authenticationToken: info.authenticationToken,
    ));
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      _connected.add(endpointId);
      _state.add(ConnectionState(
        kind: ConnectionStateKind.connected,
        endpointId: endpointId,
      ));
      if (_pendingConnect != null && !(_pendingConnect!.isCompleted)) {
        _pendingConnect!.complete(const ConnectionResult(ok: true));
      }
    } else {
      _state.add(ConnectionState(
        kind: ConnectionStateKind.error,
        endpointId: endpointId,
        detail: status.toString(),
      ));
      if (_pendingConnect != null && !(_pendingConnect!.isCompleted)) {
        _pendingConnect!.complete(ConnectionResult(ok: false, error: status.toString()));
      }
    }
  }

  void _onDisconnected(String endpointId) {
    _connected.remove(endpointId);
    _state.add(ConnectionState(
      kind: ConnectionStateKind.disconnected,
      endpointId: endpointId,
    ));
  }
}
