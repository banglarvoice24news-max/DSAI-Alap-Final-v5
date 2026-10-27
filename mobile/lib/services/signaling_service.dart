import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;
import '../core/constants.dart';
import '../core/storage/secure_store.dart';

class SignalingService {
  SignalingService({SecureStore? store}) : _store = store ?? SecureStore();

  final SecureStore _store;
  io.Socket? _socket;

  final _incomingMessages = StreamController<Map<String, dynamic>>.broadcast();
  final _receipts = StreamController<Map<String, dynamic>>.broadcast();
  final _callEvents = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get incomingMessages => _incomingMessages.stream;
  Stream<Map<String, dynamic>> get receipts => _receipts.stream;
  Stream<Map<String, dynamic>> get callEvents => _callEvents.stream;

  Future<void> connect() async {
    final token = await _store.read(SecureStore.accessToken);
    if (token == null) return;
    await disconnect();
    final socket = io.io(
      AppConstants.apiBaseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );
    socket.on('message:incoming', (data) {
      if (data is Map) _incomingMessages.add(Map<String, dynamic>.from(data));
    });
    socket.on('message:receipt', (data) {
      if (data is Map) _receipts.add(Map<String, dynamic>.from(data));
    });
    for (final event in ['call:offer', 'call:answer', 'call:ice', 'call:hangup']) {
      socket.on(event, (data) {
        if (data is Map) {
          _callEvents.add({'event': event, ...Map<String, dynamic>.from(data)});
        }
      });
    }
    _socket = socket;
  }

  void sendMessage({
    required String to,
    required String ciphertext,
    String? nonce,
    String? header,
    String? clientId,
  }) {
    _socket?.emit('message:send', {
      'to': to,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'header': header,
      'clientId': clientId,
    });
  }

  void ackDelivered({required String id, required String to}) {
    _socket?.emit('message:delivered', {'id': id, 'to': to});
  }

  void ackRead({required List<String> ids, required String to}) {
    _socket?.emit('message:read', {'ids': ids, 'to': to});
  }

  void sendOffer({required String to, required String sdp, required String type}) {
    _socket?.emit('call:offer', {'to': to, 'sdp': sdp, 'type': type});
  }

  void sendAnswer({required String callId, required String to, required String sdp}) {
    _socket?.emit('call:answer', {'callId': callId, 'to': to, 'sdp': sdp});
  }

  void sendIce({required String callId, required String to, required Object candidate}) {
    _socket?.emit('call:ice', {'callId': callId, 'to': to, 'candidate': candidate});
  }

  void hangup({required String callId, required String to, String? reason}) {
    _socket?.emit('call:hangup', {'callId': callId, 'to': to, 'reason': reason});
  }

  Future<void> disconnect() async {
    _socket?.dispose();
    _socket = null;
  }

  Future<void> dispose() async {
    await disconnect();
    await _incomingMessages.close();
    await _receipts.close();
    await _callEvents.close();
  }
}
