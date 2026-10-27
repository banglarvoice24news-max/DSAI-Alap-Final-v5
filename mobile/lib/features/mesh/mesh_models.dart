import 'package:equatable/equatable.dart';

enum MeshPeerStatus { discovered, connecting, connected, dropped }

class MeshPeer extends Equatable {
  const MeshPeer({
    required this.id,
    required this.name,
    required this.rssi,
    required this.distanceMeters,
    this.status = MeshPeerStatus.discovered,
    this.endpointId,
  });

  final String id;
  final String name;
  final int rssi;
  final int distanceMeters;
  final MeshPeerStatus status;
  final String? endpointId;

  double get signalQuality {
    if (rssi >= -50) return 1;
    if (rssi <= -100) return 0;
    return (rssi + 100) / 50.0;
  }

  MeshPeer copyWith({
    int? rssi,
    int? distanceMeters,
    MeshPeerStatus? status,
    String? endpointId,
  }) {
    return MeshPeer(
      id: id,
      name: name,
      rssi: rssi ?? this.rssi,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      status: status ?? this.status,
      endpointId: endpointId ?? this.endpointId,
    );
  }

  @override
  List<Object?> get props => [id, name, rssi, distanceMeters, status, endpointId];
}

class MeshState extends Equatable {
  const MeshState({
    this.scanning = false,
    this.peers = const [],
    this.activePeerId,
    this.inCall = false,
    this.error,
    this.permissionsGranted = false,
  });

  final bool scanning;
  final List<MeshPeer> peers;
  final String? activePeerId;
  final bool inCall;
  final String? error;
  final bool permissionsGranted;

  MeshState copyWith({
    bool? scanning,
    List<MeshPeer>? peers,
    String? activePeerId,
    bool? inCall,
    String? error,
    bool? permissionsGranted,
    bool clearError = false,
    bool clearActive = false,
  }) {
    return MeshState(
      scanning: scanning ?? this.scanning,
      peers: peers ?? this.peers,
      activePeerId: clearActive ? null : (activePeerId ?? this.activePeerId),
      inCall: inCall ?? this.inCall,
      error: clearError ? null : (error ?? this.error),
      permissionsGranted: permissionsGranted ?? this.permissionsGranted,
    );
  }

  @override
  List<Object?> get props => [scanning, peers, activePeerId, inCall, error, permissionsGranted];
}
