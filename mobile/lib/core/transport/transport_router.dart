// Real transport router: decides which leg carries a call, in the fixed
// order Mesh -> VoIP -> GSM, subject to the caller's routing preference and
// the transports the platform/network actually make available.
//
// This is pure decision logic (no Flutter, no I/O) so it is unit-testable and
// so callers must supply the available set explicitly — the router never
// assumes a transport works. Mesh availability comes from MeshCubit and is not
// wired into the dialer yet: see TODO(P2-ROUTER-MESH) in dialer_cubit.dart.

import 'transport_status.dart';

/// Caller routing preference. Mirrors ConnectionPriority at the boundary so
/// this core file does not depend on the settings feature.
enum TransportPreference { auto, meshOnly, voipOnly, gsmOnly }

class TransportDecision {
  const TransportDecision({required this.ordered, required this.chosen, required this.reason});

  /// The fallback order that was evaluated (may be filtered by preference).
  final List<CallTransport> ordered;

  /// The transport that should carry the leg, or null when nothing is usable.
  final CallTransport? chosen;

  /// Machine-readable reason code (never shown to users directly).
  final String reason;

  bool get hasRoute => chosen != null;
}

class TransportRouter {
  const TransportRouter();

  static const List<CallTransport> _autoOrder = [
    CallTransport.mesh,
    CallTransport.voip,
    CallTransport.gsm,
  ];

  TransportDecision decide({
    required Set<CallTransport> available,
    TransportPreference preference = TransportPreference.auto,
  }) {
    final order = switch (preference) {
      TransportPreference.auto => _autoOrder,
      TransportPreference.meshOnly => const [CallTransport.mesh],
      TransportPreference.voipOnly => const [CallTransport.voip],
      TransportPreference.gsmOnly => const [CallTransport.gsm],
    };
    for (final transport in order) {
      if (available.contains(transport)) {
        return TransportDecision(
          ordered: order,
          chosen: transport,
          reason: 'first-available:${transport.name}',
        );
      }
    }
    return TransportDecision(ordered: order, chosen: null, reason: 'no-available-transport');
  }
}
