import 'dart:convert';

import '../crypto/slice1_protocol.dart';
import '../identity/device_identity.dart';

enum PairingPhase { idle, exchanging, verifyCode, confirmed, rejected }

class HandshakeOffer {
  const HandshakeOffer({
    required this.deviceId,
    required this.displayName,
    required this.identityPubB64,
    required this.ephPubB64,
    required this.identityBindSigB64,
  });

  final String deviceId;
  final String displayName;
  final String identityPubB64;
  final String ephPubB64;
  final String identityBindSigB64;

  Map<String, dynamic> toJson() => {
        't': 'hs1',
        'deviceId': deviceId,
        'displayName': displayName,
        'identityPub': identityPubB64,
        'ephPub': ephPubB64,
        'sig': identityBindSigB64,
      };

  factory HandshakeOffer.fromJson(Map<String, dynamic> json) {
    return HandshakeOffer(
      deviceId: json['deviceId'] as String,
      displayName: json['displayName'] as String,
      identityPubB64: json['identityPub'] as String,
      ephPubB64: json['ephPub'] as String,
      identityBindSigB64: json['sig'] as String,
    );
  }
}

class PairingSession {
  PairingSession({
    required this.local,
    required this.protocol,
    required this.localEphPub,
    required this.localEphPriv,
  });

  final DeviceIdentity local;
  final Slice1Protocol protocol;
  final List<int> localEphPub;
  final List<int> localEphPriv;

  HandshakeMaterial? material;
  PairingPhase phase = PairingPhase.exchanging;

  static Future<PairingSession> start({
    required DeviceIdentity local,
    required Slice1Protocol protocol,
  }) async {
    final eph = await protocol.newEphemeral();
    return PairingSession(
      local: local,
      protocol: protocol,
      localEphPub: eph.$1,
      localEphPriv: eph.$2,
    );
  }

  static List<int> bindMessage({required String deviceId, required List<int> ephPub}) {
    return utf8.encode('slice1-hs1|$deviceId|${base64Encode(ephPub)}');
  }

  Future<HandshakeOffer> localOffer() async {
    final sig = await protocol.signTranscript(bindMessage(
      deviceId: local.deviceId,
      ephPub: localEphPub,
    ));
    return HandshakeOffer(
      deviceId: local.deviceId,
      displayName: local.displayName,
      identityPubB64: local.publicKeyB64,
      ephPubB64: base64Encode(localEphPub),
      identityBindSigB64: base64Encode(sig),
    );
  }

  Future<HandshakeMaterial> acceptRemote(HandshakeOffer remote) async {
    final remoteIdPub = base64Decode(remote.identityPubB64);
    final remoteEph = base64Decode(remote.ephPubB64);
    final bindOk = await protocol.verifyTranscript(
      transcript: bindMessage(deviceId: remote.deviceId, ephPub: remoteEph),
      signature: base64Decode(remote.identityBindSigB64),
      publicKey: remoteIdPub,
    );
    if (!bindOk) {
      phase = PairingPhase.rejected;
      throw CryptoHandshakeRejected('invalid-identity-signature');
    }
    material = await protocol.completeHandshake(
      local: local,
      localEphPub: localEphPub,
      localEphPriv: localEphPriv,
      remoteDeviceId: remote.deviceId,
      remoteDisplayName: remote.displayName,
      remoteIdentityPub: remoteIdPub,
      remoteEphPub: remoteEph,
    );
    phase = PairingPhase.verifyCode;
    return material!;
  }

  Future<Map<String, dynamic>> confirmFrame() async {
    final m = material;
    if (m == null) throw StateError('no-handshake');
    final sig = await protocol.signTranscript(m.transcript);
    return {
      't': 'hs2',
      'deviceId': local.deviceId,
      'sig': base64Encode(sig),
      'code': m.safetyCode,
    };
  }

  Future<bool> verifyRemoteConfirm(Map<String, dynamic> json) async {
    final m = material;
    if (m == null) return false;
    final remoteCode = json['code'] as String?;
    if (remoteCode != m.safetyCode) {
      phase = PairingPhase.rejected;
      return false;
    }
    final ok = await protocol.verifyTranscript(
      transcript: m.transcript,
      signature: base64Decode(json['sig'] as String),
      publicKey: m.remoteIdentityPub,
    );
    if (!ok) {
      phase = PairingPhase.rejected;
      return false;
    }
    return true;
  }

  void confirmLocal() {
    if (phase == PairingPhase.verifyCode) {
      phase = PairingPhase.confirmed;
    }
  }

  void reject() {
    phase = PairingPhase.rejected;
  }
}

class CryptoHandshakeRejected implements Exception {
  CryptoHandshakeRejected(this.code);
  final String code;

  @override
  String toString() => 'CryptoHandshakeRejected($code)';
}
