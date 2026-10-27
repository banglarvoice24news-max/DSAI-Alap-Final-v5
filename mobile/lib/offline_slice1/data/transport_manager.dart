import '../domain/models.dart';
import '../domain/transport.dart';
import 'nearby_transport.dart';

class TransportManager {
  TransportManager({NearbyAwareTransport? transport})
      : transport = transport ?? NearbyTransport();

  final NearbyAwareTransport transport;

  Future<TransportCapabilities> capabilities() => transport.capabilities();
}
