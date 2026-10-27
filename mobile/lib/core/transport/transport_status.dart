// Active-transport status — the small, additive stream abstraction the hybrid
// UI depends on.
//
// GAP NOTE (real-code check, §5 of the App UX brief): there is currently NO
// fallback_router_service.dart in this app. The only transport-ish state today
// is a synchronous heuristic in features/shell/connection_status_badge.dart
// (Cloud/Mesh/SIM decided from SettingsCubit.priority + MeshCubit.scanning)
// plus the manual SIM dialog in DialerCubit. Nothing exposes a live stream of
// "which transport is carrying this conversation right now".
//
// TransportStatusController is that missing stream. It is intentionally just a
// ValueNotifier<TransportSnapshot> so it needs no BLoC wiring and can be fed by
// whichever object later owns routing (the future fallback_router_service, a
// FreeSWITCH/GSM platform channel, or the mesh service). Screens only ever read
// snapshot.activeTransport / activity and animate on change.

import 'package:flutter/foundation.dart';

/// The three simultaneous transport layers dsaialap can carry a leg over.
enum CallTransport { mesh, voip, gsm }

/// What the router is doing with the current leg.
enum TransportActivity {
  /// No call in progress.
  idle,

  /// A leg is being set up over one transport.
  acquiring,

  /// A leg is live over `activeTransport`.
  active,

  /// A live leg just switched transports (Mesh -> VoIP -> GSM).
  fallbackInProgress,
}

/// Immutable view of the current leg that screens subscribe to.
@immutable
class TransportSnapshot {
  const TransportSnapshot({
    this.activeTransport,
    this.activity = TransportActivity.idle,
    this.available = const <CallTransport>{},
    this.hops = 0,
  });

  /// The transport currently carrying the conversation, or null when idle.
  final CallTransport? activeTransport;

  final TransportActivity activity;

  /// Transports that can currently be attempted (mesh needs peers, gsm is
  /// Android-only, voip needs a route). Shown honestly, never assumed.
  final Set<CallTransport> available;

  /// Hop count for the active mesh path (0 for direct VoIP/GSM).
  final int hops;

  bool get hasActiveLeg => activeTransport != null && activity != TransportActivity.idle;

  TransportSnapshot copyWith({
    CallTransport? activeTransport,
    bool clearActive = false,
    TransportActivity? activity,
    Set<CallTransport>? available,
    int? hops,
  }) {
    return TransportSnapshot(
      activeTransport: clearActive ? null : (activeTransport ?? this.activeTransport),
      activity: activity ?? this.activity,
      available: available ?? this.available,
      hops: hops ?? this.hops,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is TransportSnapshot &&
        other.activeTransport == activeTransport &&
        other.activity == activity &&
        other.hops == hops &&
        setEquals(other.available, available);
  }

  @override
  int get hashCode => Object.hash(activeTransport, activity, hops, Object.hashAll(available));
}

/// Honest per-platform capability gate.
///
/// GAP NOTE (platform asymmetry, §4 of the brief): native GSM fallback only
/// works through the Android Telecom API. iOS exposes no equivalent, so the UI
/// must not offer a GSM control there. Mesh (MultipeerConnectivity) and VoIP
/// are cross-platform. Voice-over-IP support is assumed true here because the
/// app's dialer is VoIP-first; flag this from real connectivity when binding.
class TransportCapabilities {
  const TransportCapabilities({required this.gsmNativeCalls, required this.voiceOverIp});

  final bool gsmNativeCalls;
  final bool voiceOverIp;

  bool supports(CallTransport transport) {
    return switch (transport) {
      CallTransport.mesh => true,
      CallTransport.voip => voiceOverIp,
      CallTransport.gsm => gsmNativeCalls,
    };
  }

  static TransportCapabilities forPlatform() {
    if (kIsWeb) return const TransportCapabilities(gsmNativeCalls: false, voiceOverIp: true);
    return switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        const TransportCapabilities(gsmNativeCalls: true, voiceOverIp: true),
      TargetPlatform.iOS =>
        const TransportCapabilities(gsmNativeCalls: false, voiceOverIp: true),
      _ => const TransportCapabilities(gsmNativeCalls: false, voiceOverIp: true),
    };
  }
}

/// Publish transport changes. Feed it from the real router once one exists.
class TransportStatusController extends ValueNotifier<TransportSnapshot> {
  TransportStatusController([TransportSnapshot initial = const TransportSnapshot()])
      : super(initial);

  /// A leg is now live (or acquiring/falling back) over [transport].
  void publish(CallTransport transport, {TransportActivity activity = TransportActivity.active}) {
    value = value.copyWith(activeTransport: transport, activity: activity);
  }

  /// Called right before/while the router swaps the active leg. The UI treats
  /// this as the visible "falling back" moment, not as instant reconnection.
  void beginFallback(CallTransport next) {
    value = value.copyWith(activeTransport: next, activity: TransportActivity.fallbackInProgress);
  }

  void endFallback() {
    value = value.copyWith(activity: TransportActivity.active);
  }

  void setAvailable(Set<CallTransport> available) {
    value = value.copyWith(available: available);
  }

  void clear() {
    value = const TransportSnapshot();
  }
}
