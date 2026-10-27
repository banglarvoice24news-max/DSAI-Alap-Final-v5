import '../crypto/encrypted_envelope.dart';

enum TransportAvailability { available, connected, unavailable, error }

class P2pCapabilities {
  const P2pCapabilities({
    required this.name,
    required this.availability,
    this.detail = '',
  });

  final String name;
  final TransportAvailability availability;
  final String detail;
}

class PeerDescriptor {
  const PeerDescriptor({
    required this.endpointId,
    required this.displayName,
    this.rssi,
  });

  final String endpointId;
  final String displayName;
  final int? rssi;
}

class ConnectionResult {
  const ConnectionResult({required this.ok, this.error});

  final bool ok;
  final String? error;
}

class SendResult {
  const SendResult({required this.ok, this.error});

  final bool ok;
  final String? error;
}

enum ConnectionStateKind { idle, discovering, connecting, connected, disconnected, error }

class ConnectionState {
  const ConnectionState({
    required this.kind,
    this.endpointId,
    this.detail,
  });

  final ConnectionStateKind kind;
  final String? endpointId;
  final String? detail;
}

class IncomingBytes {
  const IncomingBytes({required this.endpointId, required this.bytes});

  final String endpointId;
  final List<int> bytes;
}

class IncomingConnectionRequest {
  const IncomingConnectionRequest({
    required this.endpointId,
    required this.displayName,
    this.authenticationToken,
  });

  final String endpointId;
  final String displayName;
  final String? authenticationToken;
}

abstract class Transport {
  Future<P2pCapabilities> capabilities();
  Stream<List<PeerDescriptor>> discoverPeers();
  Future<ConnectionResult> connect(PeerDescriptor peer);
  Future<SendResult> send(PeerDescriptor peer, EncryptedEnvelope envelope);
  Future<void> disconnect(PeerDescriptor peer);
  Stream<ConnectionState> observeState();
}
