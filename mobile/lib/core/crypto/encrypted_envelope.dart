import 'dart:convert';

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
  final List<int> nonce;
  final List<int> ciphertext;
  final List<int> signature;

  Map<String, Object?> toJson() => {
        'version': version,
        'messageId': messageId,
        'conversationId': conversationId,
        'senderDeviceId': senderDeviceId,
        'recipientDeviceId': recipientDeviceId,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'keyVersion': keyVersion,
        'nonce': base64Encode(nonce),
        'ciphertext': base64Encode(ciphertext),
        'signature': base64Encode(signature),
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
      nonce: base64Decode(json['nonce'] as String),
      ciphertext: base64Decode(json['ciphertext'] as String),
      signature: base64Decode(json['signature'] as String),
    );
  }

  String encode() => jsonEncode(toJson());

  static EncryptedEnvelope decode(String raw) =>
      EncryptedEnvelope.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  List<int> aadBytes() {
    final canonical = [
      'v=$version',
      'mid=$messageId',
      'cid=$conversationId',
      'sid=$senderDeviceId',
      'rid=$recipientDeviceId',
      'ts=${createdAt.millisecondsSinceEpoch}',
      'exp=${expiresAt.millisecondsSinceEpoch}',
      'kv=$keyVersion',
    ].join('\n');
    return utf8.encode(canonical);
  }

  List<int> signaturePayload() {
    final canonical = [
      utf8.decode(aadBytes()),
      'nonce=${base64Encode(nonce)}',
      'ct=${base64Encode(ciphertext)}',
    ].join('\n');
    return utf8.encode(canonical);
  }
}

class CryptoException implements Exception {
  CryptoException(this.code);
  final String code;

  @override
  String toString() => 'CryptoException($code)';
}
