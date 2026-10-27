import 'models.dart';

abstract class Transport {
  Future<TransportCapabilities> capabilities();
  Stream<List<PeerDescriptor>> discoverPeers();
  Future<ConnectionResult> connect(PeerDescriptor peer);
  Future<SendResult> send(PeerDescriptor peer, EncryptedEnvelope envelope);
  Future<void> disconnect(PeerDescriptor peer);
  Stream<TransportLinkState> observeState();
}

class IncomingConnectionRequest {
  const IncomingConnectionRequest({
    required this.endpointId,
    required this.displayName,
  });

  final String endpointId;
  final String displayName;
}

abstract class NearbyAwareTransport extends Transport {
  Stream<IncomingConnectionRequest> get connectionRequests;
  Stream<Map<String, dynamic>> get controlMessages;
  Future<void> accept(String endpointId);
  Future<void> reject(String endpointId);
  Future<SendResult> sendControl(String endpointId, Map<String, dynamic> message);
  Future<void> startDiscovery({required String displayName});
  Future<void> stopDiscovery();
}
