// Transparency screen — "what we store and why" in plain Bengali.
//
// Mirrors the backend's CDR truth (backend/CPAAS.md): records exist for
// delivery + billing + abuse protection; call CONTENT is never recorded. v1
// screen is static explainer; the CDR retention switch will bind to the real
// consent service once the consent API is reachable from the app.

import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_tokens.dart';

class HybridTransparencyScreen extends StatelessWidget {
  const HybridTransparencyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.canvas,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text(AppStrings.transparencyTitle, style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(AppStrings.transparencyIntro, style: const TextStyle(fontSize: 14.5, height: 1.5)),
            const SizedBox(height: 14),
            const _TtlBadge(),
            const SizedBox(height: 14),
            const _Block(
              icon: Icons.receipt_long_outlined,
              title: AppStrings.transparencyCdrTitle,
              body: AppStrings.transparencyCdrBody,
            ),
            const SizedBox(height: 10),
            const _Block(
              icon: Icons.lock_outline,
              title: AppStrings.transparencyContentTitle,
              body: AppStrings.transparencyContentBody,
            ),
            const SizedBox(height: 10),
            const _Block(
              icon: Icons.admin_panel_settings_outlined,
              title: AppStrings.transparencyConsentTitle,
              body: AppStrings.transparencyConsentBody,
            ),
          ],
        ),
      ),
    );
  }
}

class _TtlBadge extends StatelessWidget {
  const _TtlBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTokens.success.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTokens.success.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timelapse, color: AppTokens.success, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppStrings.transparencyTtl,
              style: const TextStyle(fontSize: 13, color: AppTokens.success, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTokens.glassStroke),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTokens.primaryBright, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                const SizedBox(height: 5),
                Text(body, style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppTokens.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
