// Reusable honest-transport UI atoms for the hybrid prototype.
//
// GAP NOTE: these widgets only RENDER state. Real "current transport" changes
// come from a TransportStatusController fed by the future router / platform
// channels; nothing writes to it yet outside in-call and thread demos.

import 'package:flutter/material.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/transport/transport_status.dart';
import '../hybrid_models.dart';

Color transportColor(CallTransport transport) {
  return switch (transport) {
    CallTransport.mesh => AppTokens.mesh,
    CallTransport.voip => AppTokens.voip,
    CallTransport.gsm => AppTokens.gsm,
  };
}

String transportLabel(CallTransport transport) {
  return switch (transport) {
    CallTransport.mesh => AppStrings.transportMesh,
    CallTransport.voip => AppStrings.transportVoip,
    CallTransport.gsm => AppStrings.transportGsm,
  };
}

/// Small transport pill, e.g. "মেশ", "ভিওআইপি", "জিএসএম".
class TransportChip extends StatelessWidget {
  const TransportChip({super.key, required this.transport, this.dim = false});

  final CallTransport transport;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final color = transportColor(transport);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dim ? 0.10 : 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: dim ? 0.4 : 0.75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors, size: 11, color: color.withValues(alpha: dim ? 0.7 : 1)),
          const SizedBox(width: 4),
          Text(
            transportLabel(transport),
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Honest delivery ticks for an outgoing message.
///
/// Never a generic clock: [pending] renders the transport reason inline next to
/// the bubble instead of pretending to be "sent".
class DeliveryTicks extends StatelessWidget {
  const DeliveryTicks({super.key, required this.state});

  final DeliveryState state;

  @override
  Widget build(BuildContext context) {
    return switch (state) {
      DeliveryState.pending => SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 1.6, valueColor: const AlwaysStoppedAnimation(AppTokens.warn)),
        ),
      DeliveryState.sent => const Icon(Icons.check, size: 14, color: AppTokens.textSecondary),
      DeliveryState.delivered => const Icon(Icons.done_all, size: 14, color: AppTokens.textSecondary),
      DeliveryState.read => const Icon(Icons.done_all, size: 14, color: AppTokens.mint),
    };
  }
}

String deliveredCaption(HybridMessage message) {
  if (message.state == DeliveryState.pending) {
    return message.pendingReason ?? AppStrings.deliveredPending;
  }
  return switch (message.state) {
    DeliveryState.read => AppStrings.readBadge,
    DeliveryState.delivered => switch (message.transport) {
        CallTransport.mesh => AppStrings.deliveredViaMesh,
        CallTransport.voip => AppStrings.deliveredViaVoip,
        CallTransport.gsm => AppStrings.deliveredViaGsm,
        null => AppStrings.deliveredSent,
      },
    _ => AppStrings.deliveredSent,
  };
}

/// Live strip shown while a leg is active. Subscribes to the injected
/// TransportStatusController and paints the visible "falling back" moment.
class LiveTransportStrip extends StatelessWidget {
  const LiveTransportStrip({super.key, required this.controller, this.trailing});

  final TransportStatusController controller;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TransportSnapshot>(
      valueListenable: controller,
      builder: (context, snapshot, _) {
        final active = snapshot.activeTransport;
        if (active == null || snapshot.activity == TransportActivity.idle) {
          return const SizedBox.shrink();
        }
        final color = transportColor(active);
        final falling = snapshot.activity == TransportActivity.fallbackInProgress;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: [
              if (falling)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, valueColor: const AlwaysStoppedAnimation(AppTokens.warn)),
                )
              else
                Icon(Icons.wifi_tethering, size: 14, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  falling ? AppStrings.inCallFallback : '${transportLabel(active)} • ${AppStrings.inCallHops} ${snapshot.hops}',
                  style: TextStyle(
                    color: falling ? AppTokens.warn : color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        );
      },
    );
  }
}
