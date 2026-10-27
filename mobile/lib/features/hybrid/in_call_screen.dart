// In-call screen prototype — the visible Mesh -> VoIP -> GSM fallback moment.
//
// GAP NOTE: there is no live call leg yet. This screen drives its own
// TransportStatusController through a simulated route so the UI's behaviour
// under a real handoff is visible: transport strip flips to "সংযোগ পড়ছে…"
// during a fallback, then lands on the next transport. When the real router
// (future fallback_router_service / FreeSWITCH / Telecom) publishes to a
// shared controller, this screen must adopt that controller instead of the
// local simulation. GSM is only offered when the platform supports native SIM
// calls (Android), so iOS never sees a dead GSM control.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/transport/transport_status.dart';
import 'widgets/transport_ui.dart';

class InCallScreen extends StatefulWidget {
  const InCallScreen({super.key, required this.contactName, required this.number});

  final String contactName;
  final String number;

  @override
  State<InCallScreen> createState() => _InCallScreenState();
}

class _InCallScreenState extends State<InCallScreen> {
  final TransportStatusController _leg = TransportStatusController(
    TransportSnapshot(
      available: TransportCapabilities.forPlatform().supports(CallTransport.gsm)
          ? const {CallTransport.mesh, CallTransport.voip, CallTransport.gsm}
          : const {CallTransport.mesh, CallTransport.voip},
    ),
  );

  Timer? _advancer;
  Timer? _fallbackTimer;
  late final List<CallTransport> _stages;
  int _stage = 0;
  bool _muted = false;
  bool _speaker = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final caps = TransportCapabilities.forPlatform();
    _stages = CallTransport.values.where(caps.supports).toList();
    // Land on the first transport immediately.
    _leg.publish(_stages.first);
    _leg.setAvailable({for (final t in _stages) t});
    _startTicker();
    _startFallbackCycle();
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  /// Simulated handoff: every 6s, fall back to the next supported transport.
  void _startFallbackCycle() {
    _advancer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_fallbackTimer?.isActive ?? false) return;
      final next = _stages[(_stage + 1) % _stages.length];
      if (next == _stages.first) return;
      setState(() {
        _stage = _stages.indexOf(next);
        _leg.beginFallback(next);
      });
      _fallbackTimer = Timer(const Duration(milliseconds: 1600), () {
        if (!mounted) return;
        setState(() {
          _leg.endFallback();
          _leg.publish(next);
        });
      });
    });
  }

  @override
  void dispose() {
    _advancer?.cancel();
    _fallbackTimer?.cancel();
    _ticker?.cancel();
    _leg.dispose();
    super.dispose();
  }

  String get _clock {
    final m = (_elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: const SizedBox(),
        actions: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Text(AppStrings.prototypeBanner, style: const TextStyle(fontSize: 11, color: AppTokens.warn)),
            const Spacer(),
            CircleAvatar(
              radius: 54,
              backgroundColor: AppTokens.primary.withValues(alpha: 0.3),
              child: Text(
                widget.contactName.isEmpty ? '?' : widget.contactName[0].toUpperCase(),
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: AppTokens.textPrimary),
              ),
            ),
            const SizedBox(height: 18),
            Text(widget.contactName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(widget.number, style: const TextStyle(color: AppTokens.textSecondary)),
            const SizedBox(height: 8),
            Text(_clock, style: const TextStyle(fontSize: 18, color: AppTokens.textSecondary, fontFeatures: [FontFeature.tabularFigures()])),
            const Spacer(),
            LiveTransportStrip(controller: _leg, trailing: const Icon(Icons.swap_horiz, size: 16, color: AppTokens.textSecondary)),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _BigControl(
                  icon: _muted ? Icons.mic_off : Icons.mic,
                  label: AppStrings.inCallMute,
                  active: _muted,
                  onTap: () => setState(() => _muted = !_muted),
                ),
                _BigControl(
                  icon: _speaker ? Icons.volume_up : Icons.volume_down,
                  label: AppStrings.inCallSpeaker,
                  active: _speaker,
                  onTap: () => setState(() => _speaker = !_speaker),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTokens.danger,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(180, 58),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                child: const Text(AppStrings.inCallEnd, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BigControl extends StatelessWidget {
  const _BigControl({required this.icon, required this.label, required this.active, required this.onTap});

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? Colors.black : AppTokens.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: (active ? AppTokens.primaryBright : AppTokens.surface).withValues(alpha: active ? 1 : 0.8),
                shape: BoxShape.circle,
                border: Border.all(color: AppTokens.glassStroke),
              ),
              child: Icon(icon, size: 30, color: color),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
          ],
        ),
      ),
    );
  }
}
