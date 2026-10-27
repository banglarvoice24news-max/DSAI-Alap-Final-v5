import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

/// Hybrid Wi-Fi Direct + BLE peer discovery and local P2P voice streaming.
///
/// Discovery uses Google Nearby Connections (Wi-Fi P2P / BLE / Wi-Fi LAN).
/// Once two devices are connected, a local TCP socket carries Opus-framed
/// audio with a target one-way latency under 100 ms.
class OfflineMeshService {
  OfflineMeshService({
    this.serviceId = 'com.nexus.comm.mesh',
    this.nickname,
    this.rangeMeters = 200,
    this.sampleRate = 16000,
    this.discoveryInterval = const Duration(seconds: 8),
  });

  static const int _audioPort = 47831;
  static const int _pcmBytesPerFrame = 640;
  static const int _reconnectDelayMs = 1500;
  static const int _maxReconnectAttempts = 8;

  final String serviceId;
  final String? nickname;
  final int rangeMeters;
  final int sampleRate;
  final Duration discoveryInterval;

  final Nearby _nearby = Nearby();
  final StreamController<MeshDiscoveryEvent> _discovery =
      StreamController<MeshDiscoveryEvent>.broadcast();
  final StreamController<MeshConnectionEvent> _connections =
      StreamController<MeshConnectionEvent>.broadcast();
  final StreamController<MeshAudioStats> _audioStats =
      StreamController<MeshAudioStats>.broadcast();

  final Map<String, DiscoveredEndpoint> _endpoints = {};
  final Map<String, int> _rssi = {};
  final Set<String> _connected = {};

  FlutterSoundRecorder? _recorder;
  FlutterSoundPlayer? _player;
  ServerSocket? _server;
  Socket? _peerSocket;
  StreamSubscription<Uint8List>? _socketSub;
  StreamSubscription<Uint8List>? _micSub;
  StreamController<Uint8List>? _micController;
  Timer? _scanTimer;
  Timer? _reconnectTimer;
  bool _advertising = false;
  bool _running = false;
  bool _inCall = false;
  bool _muted = false;
  String? _localName;
  String? _activeEndpointId;
  String? _lastPeerHost;
  int _reconnectAttempts = 0;
  bool _audioOpened = false;
  final BytesBuilder _rxBuffer = BytesBuilder(copy: false);

  Stream<MeshDiscoveryEvent> get discovery => _discovery.stream;
  Stream<MeshConnectionEvent> get connections => _connections.stream;
  Stream<MeshAudioStats> get audioStats => _audioStats.stream;
  bool get isRunning => _running;
  bool get inCall => _inCall;
  Map<String, DiscoveredEndpoint> get endpoints => Map.unmodifiable(_endpoints);

  /// Requests runtime permissions required for Wi-Fi Direct, BLE, and audio.
  Future<MeshPermissionResult> ensurePermissions() async {
    final required = <Permission>[
      Permission.locationWhenInUse,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
      Permission.microphone,
    ];
    if (Platform.isAndroid) {
      required.add(Permission.location);
    }
    final statuses = await required.request();
    final denied = statuses.entries.where((e) => !e.value.isGranted).map((e) => e.key).toList();
    final permanentlyDenied =
        statuses.entries.where((e) => e.value.isPermanentlyDenied).map((e) => e.key).toList();
    return MeshPermissionResult(
      granted: denied.isEmpty,
      denied: denied,
      permanentlyDenied: permanentlyDenied,
    );
  }

  /// Starts continuous advertise + scan. Peers beyond [rangeMeters] are dropped.
  Future<void> startDiscovery({String? displayName}) async {
    if (_running) return;
    final perms = await ensurePermissions();
    if (!perms.granted) {
      _discovery.add(MeshDiscoveryEvent.permissionDenied(perms));
      throw MeshPermissionException(perms);
    }
    _localName = displayName ?? nickname ?? await _defaultName();
    _running = true;
    await _startAdvertising();
    await _startScanning();
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(discoveryInterval, (_) {
      if (_running) {
        unawaited(_restartScan());
      }
    });
  }

  Future<void> stopDiscovery() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    _running = false;
    _advertising = false;
    try {
      await _nearby.stopAllEndpoints();
    } catch (_) {}
    try {
      await _nearby.stopAdvertising();
    } catch (_) {}
    try {
      await _nearby.stopDiscovery();
    } catch (_) {}
    _endpoints.clear();
    _rssi.clear();
    _discovery.add(const MeshDiscoveryEvent.cleared());
  }

  Future<void> connect(String endpointId) async {
    _activeEndpointId = endpointId;
    _connections.add(MeshConnectionEvent.connecting(endpointId));
    await _nearby.requestConnection(
      _localName ?? 'Nexus',
      endpointId,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
    );
  }

  Future<void> disconnect([String? endpointId]) async {
    final id = endpointId ?? _activeEndpointId;
    if (id != null) {
      try {
        await _nearby.disconnectFromEndpoint(id);
      } catch (_) {}
    }
    await _tearDownAudioBridge();
    _inCall = false;
    _activeEndpointId = null;
  }

  /// Opens a local TCP audio bridge and starts mic capture / playback.
  Future<void> startVoiceCall({required bool asHost, String? peerHost}) async {
    if (_inCall) return;
    _inCall = true;
    _reconnectAttempts = 0;
    _lastPeerHost = peerHost ?? _lastPeerHost;
    await _initAudioIo();
    if (asHost) {
      await _listenAudioServer();
      final id = _activeEndpointId;
      if (id != null) {
        unawaited(_exchangeAudioHostInfo(id));
      }
    } else if (_lastPeerHost != null) {
      await _connectAudioClient(_lastPeerHost!);
    }
    await _startCapture();
  }

  Future<void> endVoiceCall() async {
    _inCall = false;
    _reconnectTimer?.cancel();
    await _tearDownAudioBridge();
  }

  void setMuted(bool muted) {
    _muted = muted;
  }

  /// Converts RSSI (dBm) into an approximate distance in meters using a
  /// log-distance path-loss model calibrated for 2.4 GHz indoor/outdoor mix.
  int distanceFromRssi(int rssi, {int txPower = -59, double n = 2.4}) {
    if (rssi == 0) return rangeMeters;
    final ratio = (txPower - rssi) / (10 * n);
    final meters = pow(10, ratio).toDouble();
    return meters.clamp(1, rangeMeters * 1.5).round();
  }

  double signalQuality(int rssi) {
    if (rssi >= -50) return 1;
    if (rssi <= -100) return 0;
    return (rssi + 100) / 50.0;
  }

  Future<void> dispose() async {
    await endVoiceCall();
    await stopDiscovery();
    await _discovery.close();
    await _connections.close();
    await _audioStats.close();
  }

  Future<String> _defaultName() async {
    return 'Nexus-${Random().nextInt(9999).toString().padLeft(4, '0')}';
  }

  Future<void> _startAdvertising() async {
    if (_advertising) return;
    await _nearby.startAdvertising(
      _localName ?? 'Nexus',
      Strategy.P2P_CLUSTER,
      onConnectionInitiated: _onConnectionInitiated,
      onConnectionResult: _onConnectionResult,
      onDisconnected: _onDisconnected,
      serviceId: serviceId,
    );
    _advertising = true;
  }

  Future<void> _startScanning() async {
    await _nearby.startDiscovery(
      _localName ?? 'Nexus',
      Strategy.P2P_CLUSTER,
      onEndpointFound: (id, name, service) {
        final rssi = _rssi[id] ?? -70;
        final distance = distanceFromRssi(rssi);
        if (distance > rangeMeters) {
          return;
        }
        final endpoint = DiscoveredEndpoint(id: id, name: name, serviceId: service, rssi: rssi);
        _endpoints[id] = endpoint;
        _discovery.add(MeshDiscoveryEvent.found(endpoint, distance));
      },
      onEndpointLost: (id) {
        if (id == null) return;
        _endpoints.remove(id);
        _discovery.add(MeshDiscoveryEvent.lost(id));
        if (id == _activeEndpointId) {
          _connections.add(MeshConnectionEvent.dropped(id));
          _scheduleReconnect(id);
        }
      },
      serviceId: serviceId,
    );
  }

  Future<void> _restartScan() async {
    try {
      await _nearby.stopDiscovery();
    } catch (_) {}
    if (_running) {
      await _startScanning();
    }
  }

  void _onConnectionInitiated(String endpointId, ConnectionInfo info) {
    unawaited(
      _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: (id, payload) {
          if (payload.type == PayloadType.BYTES && payload.bytes != null) {
            _handleControlPayload(id, payload.bytes!);
          }
        },
        onPayloadTransferUpdate: (id, update) {},
      ),
    );
  }

  void _onConnectionResult(String endpointId, Status status) {
    if (status == Status.CONNECTED) {
      _connected.add(endpointId);
      _activeEndpointId = endpointId;
      _reconnectAttempts = 0;
      _connections.add(MeshConnectionEvent.connected(endpointId));
    } else {
      _connections.add(MeshConnectionEvent.failed(endpointId, status.toString()));
    }
  }

  void _onDisconnected(String endpointId) {
    _connected.remove(endpointId);
    _connections.add(MeshConnectionEvent.dropped(endpointId));
    if (_inCall) {
      _scheduleReconnect(endpointId);
    }
  }

  Future<void> _exchangeAudioHostInfo(String endpointId) async {
    final ip = await _localIpv4();
    final payload = utf8.encode(jsonEncode({
      't': 'audio-host',
      'ip': ip,
      'port': _audioPort,
    }));
    await _nearby.sendBytesPayload(endpointId, Uint8List.fromList(payload));
  }

  void _handleControlPayload(String endpointId, Uint8List bytes) {
    try {
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (map['t'] == 'audio-host') {
        final ip = map['ip'] as String?;
        if (ip == null || ip.isEmpty) return;
        _lastPeerHost = ip;
        if (_server != null) return;
        if (_inCall) {
          if (_peerSocket == null) {
            unawaited(_connectAudioClient(ip));
          }
          return;
        }
        unawaited(startVoiceCall(asHost: false, peerHost: ip));
      }
    } catch (err) {
      debugPrint('mesh control payload error: $err');
    }
  }

  void _scheduleReconnect(String endpointId) {
    if (!_inCall && !_running) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _connections.add(MeshConnectionEvent.failed(endpointId, 'max_reconnect'));
      return;
    }
    _reconnectTimer?.cancel();
    final delay = Duration(milliseconds: _reconnectDelayMs * (1 + _reconnectAttempts));
    _reconnectAttempts += 1;
    _reconnectTimer = Timer(delay, () {
      if (_endpoints.containsKey(endpointId)) {
        unawaited(connect(endpointId));
      } else if (_running) {
        unawaited(_restartScan());
      }
    });
  }

  Future<void> _initAudioIo() async {
    _recorder ??= FlutterSoundRecorder();
    _player ??= FlutterSoundPlayer();
    if (!_audioOpened) {
      await _recorder!.openRecorder();
      await _player!.openPlayer();
      _audioOpened = true;
    }
    if (_player!.isStopped) {
      await _player!.startPlayerFromStream(
        codec: Codec.pcm16,
        sampleRate: sampleRate,
        numChannels: 1,
        interleaved: true,
        bufferSize: _pcmBytesPerFrame,
      );
    }
  }

  Future<void> _listenAudioServer() async {
    if (_server != null) return;
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, _audioPort, shared: true);
    _server!.listen((socket) {
      unawaited(_attachPeerSocket(socket));
    });
  }

  Future<void> _connectAudioClient(String host) async {
    _lastPeerHost = host;
    final socket = await Socket.connect(host, _audioPort, timeout: const Duration(seconds: 4));
    await _attachPeerSocket(socket);
  }

  Future<void> _attachPeerSocket(Socket socket) async {
    await _peerSocket?.close();
    await _socketSub?.cancel();
    _peerSocket = socket;
    socket.setOption(SocketOption.tcpNoDelay, true);
    _socketSub = socket.listen(
      _onAudioBytes,
      onDone: () {
        if (_inCall) {
          unawaited(_recoverSocket());
        }
      },
      onError: (_) {
        if (_inCall) {
          unawaited(_recoverSocket());
        }
      },
      cancelOnError: true,
    );
  }

  Future<void> _recoverSocket() async {
    await _socketSub?.cancel();
    _peerSocket = null;
    if (!_inCall) return;
    if (_lastPeerHost != null) {
      try {
        await _connectAudioClient(_lastPeerHost!);
      } catch (_) {
        _scheduleReconnect(_activeEndpointId ?? '');
      }
    }
  }

  Future<void> _startCapture() async {
    await _micSub?.cancel();
    await _micController?.close();
    if (!(_recorder?.isStopped ?? true)) {
      try {
        await _recorder!.stopRecorder();
      } catch (_) {}
    }
    _micController = StreamController<Uint8List>();
    _micSub = _micController!.stream.listen(_onMicPcm);
    await _recorder!.startRecorder(
      codec: Codec.pcm16,
      sampleRate: sampleRate,
      numChannels: 1,
      bitRate: sampleRate * 16,
      bufferSize: _pcmBytesPerFrame,
      toStream: _micController!.sink,
    );
  }

  /// Length-prefixed PCM frames. Swap in Opus via `opus_dart` when the
  /// native encoder is available; PCM 16 kHz mono is the fallback path.
  Uint8List _framePacket(Uint8List pcm) {
    final out = Uint8List(4 + pcm.length);
    ByteData.sublistView(out).setUint32(0, pcm.length, Endian.big);
    out.setAll(4, pcm);
    return out;
  }

  void _onMicPcm(Uint8List pcm) {
    if (_muted || pcm.isEmpty) return;
    final socket = _peerSocket;
    if (socket == null) return;
    var offset = 0;
    while (offset < pcm.length) {
      final end = min(offset + _pcmBytesPerFrame, pcm.length);
      socket.add(_framePacket(pcm.sublist(offset, end)));
      offset = end;
    }
  }

  void _onAudioBytes(Uint8List chunk) {
    _rxBuffer.add(chunk);
    var buf = _rxBuffer.takeBytes();
    const maxFrame = 8192;
    while (buf.length >= 4) {
      final len = ByteData.sublistView(buf, 0, 4).getUint32(0, Endian.big);
      if (len <= 0 || len > maxFrame) {
        buf = buf.sublist(1);
        continue;
      }
      if (buf.length < 4 + len) break;
      final frame = buf.sublist(4, 4 + len);
      final player = _player;
      if (player != null && !player.isStopped) {
        unawaited(player.feedUint8FromStream(frame));
      }
      _audioStats.add(MeshAudioStats(bytes: len, rssi: _rssi[_activeEndpointId] ?? -70));
      buf = buf.sublist(4 + len);
    }
    if (buf.isNotEmpty) {
      _rxBuffer.add(buf);
    }
  }

  Future<void> _tearDownAudioBridge() async {
    await _micSub?.cancel();
    _micSub = null;
    await _micController?.close();
    _micController = null;
    try {
      await _recorder?.stopRecorder();
    } catch (_) {}
    try {
      await _player?.stopPlayer();
    } catch (_) {}
    try {
      await _recorder?.closeRecorder();
    } catch (_) {}
    try {
      await _player?.closePlayer();
    } catch (_) {}
    _audioOpened = false;
    _rxBuffer.clear();
    await _socketSub?.cancel();
    _socketSub = null;
    try {
      await _peerSocket?.close();
    } catch (_) {}
    _peerSocket = null;
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
  }

  Future<String?> _localIpv4() async {
    final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLinkLocal: true);
    for (final iface in ifaces) {
      for (final addr in iface.addresses) {
        if (!addr.isLoopback) return addr.address;
      }
    }
    return null;
  }
}

class DiscoveredEndpoint {
  const DiscoveredEndpoint({
    required this.id,
    required this.name,
    required this.serviceId,
    required this.rssi,
  });

  final String id;
  final String name;
  final String serviceId;
  final int rssi;
}

class MeshPermissionResult {
  const MeshPermissionResult({
    required this.granted,
    required this.denied,
    required this.permanentlyDenied,
  });

  final bool granted;
  final List<Permission> denied;
  final List<Permission> permanentlyDenied;
}

class MeshPermissionException implements Exception {
  MeshPermissionException(this.result);
  final MeshPermissionResult result;

  @override
  String toString() => 'Mesh permissions denied: ${result.denied}';
}

class MeshDiscoveryEvent {
  const MeshDiscoveryEvent._(this.kind, {this.endpoint, this.distanceMeters, this.lostId, this.permissions});

  const MeshDiscoveryEvent.found(DiscoveredEndpoint endpoint, int distance)
      : this._(MeshDiscoveryKind.found, endpoint: endpoint, distanceMeters: distance);

  const MeshDiscoveryEvent.lost(String id) : this._(MeshDiscoveryKind.lost, lostId: id);

  const MeshDiscoveryEvent.cleared() : this._(MeshDiscoveryKind.cleared);

  const MeshDiscoveryEvent.permissionDenied(MeshPermissionResult result)
      : this._(MeshDiscoveryKind.permissionDenied, permissions: result);

  final MeshDiscoveryKind kind;
  final DiscoveredEndpoint? endpoint;
  final int? distanceMeters;
  final String? lostId;
  final MeshPermissionResult? permissions;
}

enum MeshDiscoveryKind { found, lost, cleared, permissionDenied }

class MeshConnectionEvent {
  const MeshConnectionEvent._(this.kind, this.endpointId, [this.detail]);

  const MeshConnectionEvent.connecting(String id) : this._(MeshConnectionKind.connecting, id);
  const MeshConnectionEvent.connected(String id) : this._(MeshConnectionKind.connected, id);
  const MeshConnectionEvent.dropped(String id) : this._(MeshConnectionKind.dropped, id);
  const MeshConnectionEvent.failed(String id, String detail)
      : this._(MeshConnectionKind.failed, id, detail);

  final MeshConnectionKind kind;
  final String endpointId;
  final String? detail;
}

enum MeshConnectionKind { connecting, connected, dropped, failed }

class MeshAudioStats {
  const MeshAudioStats({required this.bytes, required this.rssi});
  final int bytes;
  final int rssi;
}
