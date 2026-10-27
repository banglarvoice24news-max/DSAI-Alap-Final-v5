import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_comm/core/transport/transport_status.dart';
import 'package:nexus_comm/features/calls/calls_cubit.dart';
import 'package:nexus_comm/features/calls/calls_repository.dart';
import 'package:nexus_comm/features/hybrid/hybrid_models.dart';

class _FakeCallLogRepository implements CallLogRepository {
  _FakeCallLogRepository(this._calls);

  final List<CallRecord> _calls;

  @override
  Future<List<CallRecord>> loadCalls({int limit = 50}) async => _calls;
}

class _ThrowingCallLogRepository implements CallLogRepository {
  @override
  Future<List<CallRecord>> loadCalls({int limit = 50}) async => throw Exception('offline');
}

CallRecord _record() => CallRecord(
      id: 'c1',
      name: '+8801700000000',
      number: '+8801700000000',
      transport: CallTransport.voip,
      startedAt: DateTime(2026, 9, 11, 10, 0),
      durationSec: 42,
    );

void main() {
  group('callRecordFromCdr', () {
    test('maps an outbound GSM completion', () {
      final record = callRecordFromCdr(const {
        'callSid': 'sid-1',
        'direction': 'OUTBOUND',
        'fromNumber': '+8801000000000',
        'toNumber': '+8801700000000',
        'gatewayType': 'GSM',
        'status': 'COMPLETED',
        'durationSec': 95,
        'createdAt': '2026-09-11T10:00:00.000Z',
      });

      expect(record.id, 'sid-1');
      expect(record.number, '+8801700000000');
      expect(record.transport, CallTransport.gsm);
      expect(record.durationSec, 95);
      expect(record.missed, isFalse);
    });

    test('maps an inbound MESH missed call with no duration', () {
      final record = callRecordFromCdr(const {
        'callSid': 'sid-2',
        'direction': 'INBOUND',
        'fromNumber': '+8801800000000',
        'toNumber': '+8801700000000',
        'gatewayType': 'MESH',
        'status': 'NO_ANSWER',
        'durationSec': 0,
        'createdAt': '2026-09-11T09:30:00.000Z',
      });

      expect(record.number, '+8801800000000');
      expect(record.transport, CallTransport.mesh);
      expect(record.durationSec, isNull);
      expect(record.missed, isTrue);
    });

    test('treats licensed providers as VoIP', () {
      expect(callRecordFromCdr(const {'gatewayType': 'JAMBONZ'}).transport, CallTransport.voip);
      expect(callRecordFromCdr(const {'gatewayType': 'JASMIN'}).transport, CallTransport.voip);
    });
  });

  group('CallsCubit', () {
    test('loads records from the repository', () async {
      final calls = [_record()];
      final cubit = CallsCubit(repository: _FakeCallLogRepository(calls));

      await cubit.load();

      expect(cubit.state.calls, calls);
      expect(cubit.state.loading, isFalse);
    });

    test('falls back to an empty history when the repository throws', () async {
      final cubit = CallsCubit(repository: _ThrowingCallLogRepository());

      await cubit.load();

      expect(cubit.state.calls, isEmpty);
      expect(cubit.state.loading, isFalse);
    });
  });
}
