// Call history bound to the backend CPaaS /logs (CDR) endpoint.
//
// CDR rows are the canonical, immutable call audit trail (callSid, direction,
// numbers, gatewayType, status, durationSec, createdAt). This is the correct
// source for the Calls tab: unlike chat content there is no decryption step.
//
// GAP NOTE: favorites are local-only; the CDR has no favorite field, so every
// record comes back with favorite=false until a device-local store exists
// (TODO(P2-CALLS-FAVORITES)).

import '../../core/constants.dart';
import '../../core/network/api_client.dart';
import '../../core/transport/transport_status.dart';
import '../hybrid/hybrid_models.dart';

abstract class CallLogRepository {
  Future<List<CallRecord>> loadCalls({int limit});
}

class CpaasCallLogRepository implements CallLogRepository {
  CpaasCallLogRepository({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  Map<String, String> get _authHeaders => {'x-dsaialap-key': AppConstants.b2bApiKey};

  @override
  Future<List<CallRecord>> loadCalls({int limit = 50}) async {
    final res = await _api.get('/api/cpaas/logs', headers: _authHeaders, query: {'limit': limit});
    final data = res['data'] as Map?;
    final logs = (data?['logs'] as List?)?.cast<Map>() ?? const [];
    return logs.map((raw) => callRecordFromCdr(raw)).toList();
  }
}

/// Maps one CDR row into the presentation record the Calls tab renders.
CallRecord callRecordFromCdr(Map raw) {
  final direction = raw['direction'] as String?;
  final number = ((direction == 'OUTBOUND' ? raw['toNumber'] : raw['fromNumber']) as String?) ?? '';
  final status = (raw['status'] as String?) ?? 'UNKNOWN';
  final duration = raw['durationSec'] as int?;
  return CallRecord(
    id: (raw['callSid'] as String?) ?? number,
    name: number,
    number: number,
    transport: _transportFromGateway(raw['gatewayType'] as String?),
    startedAt: DateTime.tryParse((raw['createdAt'] as String?) ?? '')?.toLocal() ?? DateTime.now(),
    durationSec: (duration != null && duration > 0) ? duration : null,
    missed: _missed(status),
  );
}

CallTransport _transportFromGateway(String? gateway) {
  return switch (gateway) {
    'MESH' => CallTransport.mesh,
    'GSM' => CallTransport.gsm,
    // VOIP/JASMIN/JAMBONZ are all licensed IP termination.
    _ => CallTransport.voip,
  };
}

bool _missed(String status) {
  return status == 'NO_ANSWER' || status == 'BUSY' || status == 'FAILED' || status == 'CANCELED';
}
