import 'dart:convert';

enum OutboxState {
  queued,
  sending,
  sentWaitingAck,
  delivered,
  failedRetryable,
  expired,
}

enum TransportLinkState { available, connected, unavailable, error }

enum IncomingKind { connectionRequest, handshake, envelope, disconnected }

class PeerDescriptor {
  const PeerDescriptor({
    required this.endpointId,
    required this.displayName,
    this.deviceId,
    this.state = TransportLinkState.available,
    this.errorMessage,
  });

  final String endpointId;
  final String displayName;
  final String? deviceId;
  final TransportLinkState state;
  final String? errorMessage;

  PeerDescriptor copyWith({
    String? displayName,
    String? deviceId,
    TransportLinkState? state,
    String? errorMessage,
  }) {
    return PeerDescriptor(
      endpointId: endpointId,
      displayName: displayName ?? this.displayName,
      deviceId: deviceId ?? this.deviceId,
      state: state ?? this.state,
      errorMessage: errorMessage,
    );
  }
}

class TransportCapabilities {
  const TransportCapabilities({
    required this.ready,
    this.reason,
  });

  final bool ready;
  final String? reason;
}

class ConnectionResult {
  const ConnectionResult({required this.ok, this.message});

  final bool ok;
  final String? message;
}

class SendResult {
  const SendResult({required this.ok, this.message});

  final bool ok;
  final String? message;
}

class EncryptedEnvelope {
  const EncryptedEnvelope({
    required this.version,
    required this.messageId,
    required this.conversationId,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.createdAt,
    required this.expiresAt,
    required this.keyVersion,
    required this.nonce,
    required this.ciphertext,
    required this.signature,
  });

  final int version;
  final String messageId;
  final String conversationId;
  final String senderDeviceId;
  final String recipientDeviceId;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int keyVersion;
  final String nonce;
  final String ciphertext;
  final String signature;

  String get aad {
    return [
      version.toString(),
      messageId,
      conversationId,
      senderDeviceId,
      recipientDeviceId,
      createdAt.millisecondsSinceEpoch.toString(),
      expiresAt.millisecondsSinceEpoch.toString(),
      keyVersion.toString(),
    ].join('|');
  }

  String get signedCanonical {
    return '$aad|$nonce|$ciphertext';
  }

  Map<String, Object?> toJson() => {
        'version': version,
        'messageId': messageId,
        'conversationId': conversationId,
        'senderDeviceId': senderDeviceId,
        'recipientDeviceId': recipientDeviceId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'keyVersion': keyVersion,
        'nonce': nonce,
        'ciphertext': ciphertext,
        'signature': signature,
      };

  factory EncryptedEnvelope.fromJson(Map<String, dynamic> json) {
    return EncryptedEnvelope(
      version: json['version'] as int,
      messageId: json['messageId'] as String,
      conversationId: json['conversationId'] as String,
      senderDeviceId: json['senderDeviceId'] as String,
      recipientDeviceId: json['recipientDeviceId'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expiresAt'] as int),
      keyVersion: json['keyVersion'] as int,
      nonce: json['nonce'] as String,
      ciphertext: json['ciphertext'] as String,
      signature: json['signature'] as String,
    );
  }

  String encode() => jsonEncode(toJson());

  factory EncryptedEnvelope.decode(String raw) {
    return EncryptedEnvelope.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

class OutboxRecord {
  const OutboxRecord({
    required this.messageId,
    required this.recipientDeviceId,
    required this.encryptedEnvelope,
    required this.createdAt,
    required this.expiresAt,
    required this.attemptCount,
    required this.state,
    this.lastAttemptAt,
  });

  final String messageId;
  final String recipientDeviceId;
  final EncryptedEnvelope encryptedEnvelope;
  final DateTime createdAt;
  final DateTime expiresAt;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final OutboxState state;

  OutboxRecord copyWith({
    int? attemptCount,
    DateTime? lastAttemptAt,
    OutboxState? state,
  }) {
    return OutboxRecord(
      messageId: messageId,
      recipientDeviceId: recipientDeviceId,
      encryptedEnvelope: encryptedEnvelope,
      createdAt: createdAt,
      expiresAt: expiresAt,
      attemptCount: attemptCount ?? this.attemptCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      state: state ?? this.state,
    );
  }
}

class InboxMessage {
  const InboxMessage({
    required this.messageId,
    required this.conversationId,
    required this.senderDeviceId,
    required this.recipientDeviceId,
    required this.body,
    required this.createdAt,
  });

  final String messageId;
  final String conversationId;
  final String senderDeviceId;
  final String recipientDeviceId;
  final String body;
  final DateTime createdAt;
}

class TrustedContact {
  const TrustedContact({
    required this.deviceId,
    required this.displayName,
    required this.publicKeyB64,
    required this.conversationId,
    required this.verifiedAt,
    required this.keyVersion,
    this.endpointId,
  });

  final String deviceId;
  final String displayName;
  final String publicKeyB64;
  final String conversationId;
  final DateTime verifiedAt;
  final int keyVersion;
  final String? endpointId;
}

class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.publicKeyB64,
    required this.privateKeyB64,
    this.displayName,
    this.linkedAccountHint,
  });

  final String deviceId;
  final String publicKeyB64;
  final String privateKeyB64;
  final String? displayName;
  final String? linkedAccountHint;

  String get shortName =>
      displayName ?? 'Nexus-${deviceId.substring(0, deviceId.length.clamp(0, 8))}';
}

class ChatLine {
  const ChatLine({
    required this.messageId,
    required this.body,
    required this.mine,
    required this.createdAt,
    required this.statusLabel,
  });

  final String messageId;
  final String body;
  final bool mine;
  final DateTime createdAt;
  final String statusLabel;
}

class HandshakeTranscript {
  const HandshakeTranscript({
    required this.localDeviceId,
    required this.remoteDeviceId,
    required this.localIdentityPub,
    required this.remoteIdentityPub,
    required this.localEphPub,
    required this.remoteEphPub,
  });

  final String localDeviceId;
  final String remoteDeviceId;
  final String localIdentityPub;
  final String remoteIdentityPub;
  final String localEphPub;
  final String remoteEphPub;

  List<int> canonicalBytes() {
    final identity = [localIdentityPub, remoteIdentityPub]..sort();
    final eph = [localEphPub, remoteEphPub]..sort();
    final ids = [localDeviceId, remoteDeviceId]..sort();
    return utf8.encode('v1|${ids.join('|')}|${identity.join('|')}|${eph.join('|')}');
  }
}
