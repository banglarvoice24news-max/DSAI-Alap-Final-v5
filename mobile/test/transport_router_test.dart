import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_comm/core/transport/transport_router.dart';
import 'package:nexus_comm/core/transport/transport_status.dart';

void main() {
  const router = TransportRouter();
  const all = {CallTransport.mesh, CallTransport.voip, CallTransport.gsm};

  group('TransportRouter fallback order', () {
    test('auto prefers mesh, then voip, then gsm', () {
      expect(router.decide(available: all).chosen, CallTransport.mesh);
      expect(router.decide(available: {CallTransport.voip, CallTransport.gsm}).chosen, CallTransport.voip);
      expect(router.decide(available: {CallTransport.gsm}).chosen, CallTransport.gsm);
    });

    test('auto reports no route when nothing is available', () {
      final decision = router.decide(available: const {});
      expect(decision.hasRoute, isFalse);
      expect(decision.chosen, isNull);
      expect(decision.reason, 'no-available-transport');
    });

    test('voipOnly never falls back to gsm', () {
      final decision = router.decide(available: all, preference: TransportPreference.voipOnly);
      expect(decision.chosen, CallTransport.voip);
      expect(router.decide(available: {CallTransport.gsm}, preference: TransportPreference.voipOnly).chosen, isNull);
    });

    test('gsmOnly picks gsm even when mesh/voip are available', () {
      final decision = router.decide(available: all, preference: TransportPreference.gsmOnly);
      expect(decision.chosen, CallTransport.gsm);
    });

    test('meshOnly requires an available mesh peer', () {
      expect(router.decide(available: all, preference: TransportPreference.meshOnly).chosen, CallTransport.mesh);
      expect(router.decide(available: {CallTransport.voip}, preference: TransportPreference.meshOnly).chosen, isNull);
    });
  });

  group('TransportCapabilities platform gate', () {
    test('gsm is not advertised when the platform has no native calls', () {
      const capped = TransportCapabilities(gsmNativeCalls: false, voiceOverIp: true);
      expect(capped.supports(CallTransport.gsm), isFalse);
      expect(capped.supports(CallTransport.voip), isTrue);
      expect(capped.supports(CallTransport.mesh), isTrue);
    });
  });
}
