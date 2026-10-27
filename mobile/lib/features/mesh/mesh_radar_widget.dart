import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../core/theme/dsaialap_glass.dart';
import 'mesh_models.dart';

class MeshRadarWidget extends StatefulWidget {
  const MeshRadarWidget({
    super.key,
    required this.peers,
    required this.rangeMeters,
    this.scanning = false,
    this.onPeerTap,
  });

  final List<MeshPeer> peers;
  final int rangeMeters;
  final bool scanning;
  final ValueChanged<MeshPeer>? onPeerTap;

  @override
  State<MeshRadarWidget> createState() => _MeshRadarWidgetState();
}

class _MeshRadarWidgetState extends State<MeshRadarWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Offset _peerOffset(MeshPeer peer, Size size) {
    final rng = math.Random(peer.id.hashCode);
    final angle = rng.nextDouble() * math.pi * 2;
    final dist = (peer.distanceMeters.clamp(1, widget.rangeMeters) / widget.rangeMeters);
    final radius = (math.min(size.width, size.height) / 2 - 28) * dist;
    return Offset(size.width / 2 + math.cos(angle) * radius, size.height / 2 + math.sin(angle) * radius);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight);
        return SizedBox(
          width: side,
          height: side,
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              return CustomPaint(
                painter: _RadarPainter(progress: _pulse.value, scanning: widget.scanning),
                child: Stack(
                  children: [
                    for (final peer in widget.peers)
                      _PeerBlip(
                        peer: peer,
                        offset: _peerOffset(peer, Size(side, side)),
                        onTap: widget.onPeerTap,
                      ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

Color _signalColor(MeshPeer peer) {
  final quality = peer.signalQuality;
  if (quality >= 0.7) return DsaialapTokens.neonLime;
  if (quality >= 0.4) return DsaialapTokens.neonCyan;
  return DsaialapTokens.neonOrange;
}

class _PeerBlip extends StatelessWidget {
  const _PeerBlip({required this.peer, required this.offset, this.onTap});
  final MeshPeer peer;
  final Offset offset;
  final ValueChanged<MeshPeer>? onTap;

  @override
  Widget build(BuildContext context) {
    final connected = peer.status == MeshPeerStatus.connected;
    return Positioned(
      left: offset.dx - 18,
      top: offset.dy - 18,
      child: GestureDetector(
        onTap: onTap == null ? null : () => onTap!(peer),
        child: Column(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? DsaialapTokens.neonLime : DsaialapTokens.neonCyan,
                boxShadow: [
                  BoxShadow(
                    color: (connected ? DsaialapTokens.neonLime : DsaialapTokens.neonCyan).withValues(alpha: 0.7),
                    blurRadius: 10,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${peer.distanceMeters}m',
              style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w600),
            ),
            Text(
              '${peer.rssi} dBm',
              style: TextStyle(
                color: _signalColor(peer),
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.progress, required this.scanning});
  final double progress;
  final bool scanning;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) / 2 - 8;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = DsaialapTokens.neonCyan.withValues(alpha: 0.28);
    for (final f in [0.25, 0.5, 0.75, 1.0]) {
      canvas.drawCircle(center, maxR * f, ring);
    }
    canvas.drawLine(Offset(center.dx, 8), Offset(center.dx, size.height - 8), ring);
    canvas.drawLine(Offset(8, center.dy), Offset(size.width - 8, center.dy), ring);

    if (scanning) {
      final sweep = Paint()
        ..shader = SweepGradient(
          startAngle: 0,
          endAngle: math.pi / 3,
          colors: [
            DsaialapTokens.neonCyan.withValues(alpha: 0),
            DsaialapTokens.neonCyan.withValues(alpha: 0.35),
          ],
          transform: GradientRotation(progress * math.pi * 2),
        ).createShader(Rect.fromCircle(center: center, radius: maxR));
      canvas.drawCircle(center, maxR, sweep);
    }

    final pulseR = maxR * (0.2 + progress * 0.8);
    canvas.drawCircle(
      center,
      pulseR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = DsaialapTokens.neonCyan.withValues(alpha: 1 - progress),
    );
    canvas.drawCircle(center, 6, Paint()..color = DsaialapTokens.neonLime);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.scanning != scanning;
}
