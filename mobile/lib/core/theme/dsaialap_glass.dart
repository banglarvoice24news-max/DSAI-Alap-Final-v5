import 'dart:ui';

import 'package:flutter/material.dart';
import 'app_tokens.dart';

/// Legacy token aliases. Canonical Direction A tokens live in app_tokens.dart;
/// these names are kept so older widgets keep compiling while they migrate to
/// AppTokens. Values now map onto the Nilkantha palette.
class DsaialapTokens {
  static const Color oled = AppTokens.canvas;
  static const Color neonCyan = AppTokens.mesh;
  static const Color neonLime = AppTokens.success;
  static const Color neonOrange = AppTokens.gsm;
  static const Color glassFill = AppTokens.glassFill;
  static const Color glassStroke = AppTokens.glassStroke;
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.glow,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: (glow ?? DsaialapTokens.neonCyan).withValues(alpha: 0.18),
            blurRadius: 24,
            spreadRadius: 1,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: DsaialapTokens.glassFill,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: DsaialapTokens.glassStroke),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class NeonBadge extends StatelessWidget {
  const NeonBadge({super.key, required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.4),
      ),
    );
  }
}
