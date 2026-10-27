// Onboarding — plain-language Bengali default, one screen.
//
// Explains the three automatic transport layers and the one-time internet
// requirement. Honest about the GSM layer being Android-only (iOS never gets a
// dead control — platform asymmetry from core/transport/transport_status.dart).
// "Seen" state is persisted to SharedPreferences so it shows once.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/transport/transport_status.dart';

class HybridOnboardingScreen extends StatefulWidget {
  const HybridOnboardingScreen({super.key});

  static const String seenKey = 'onboarding_seen_v1';

  @override
  State<HybridOnboardingScreen> createState() => _HybridOnboardingScreenState();
}

class _HybridOnboardingScreenState extends State<HybridOnboardingScreen> {
  Future<void> _continue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(HybridOnboardingScreen.seenKey, true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final gsmOk = TransportCapabilities.forPlatform().supports(CallTransport.gsm);
    return Scaffold(
      backgroundColor: AppTokens.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            const Icon(Icons.wifi_tethering, color: AppTokens.primaryBright, size: 48),
            const SizedBox(height: 8),
            Text(
              'dsaialap',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 1.4),
            ),
            const SizedBox(height: 6),
            const Text(
              'ইন্টারনেট না থাকলেও আপনি সংযুক্ত থাকবেন',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, color: AppTokens.textSecondary),
            ),
            const SizedBox(height: 24),
            const _LayerStep(
              color: AppTokens.mesh,
              title: '১. মেশ নেটওয়ার্ক',
              body: 'কাছাকাছি ডিভাইসের সঙ্গে সরাসরি সংযোগ, কোনো ইন্টারনেট লাগে না। '
                  'সবচেয়ে কম শক্তি খরচ — যখনই সম্ভব এই পথ ব্যবহার হয়।',
            ),
            const SizedBox(height: 12),
            const _LayerStep(
              color: AppTokens.voip,
              title: '২. ভিওআইপি (ইন্টারনেট)',
              body: 'মেশ পাওয়া না গেলে ইন্টারনেট দিয়ে কল ও বার্তা। একবার সংযোগ দরকার '
                  'যাতে আপনার ডিভাইস শনাক্ত হতে পারে।',
            ),
            const SizedBox(height: 12),
            _LayerStep(
              color: AppTokens.gsm,
              title: gsmOk ? '৩. জিএসএম (সিম) — শেষ বিকল্প' : '৩. জিএসএম (সিম)',
              body: gsmOk
                  ? 'মেশ আর ইন্টারনেট দুটোই না থাকলে স্বাভাবিক সিম কল ব্যবহার হয় — '
                      'যোগাযোগ যেন কখনো থেমে না থাকে।'
                  : 'এই ডিভাইসে (iOS) স্বাভাবিক সিম ফলব্যাক নেই; মেশ আর ভিওআইপিই পথ।',
            ),
            const SizedBox(height: 20),
            const _LayerStep(
              color: AppTokens.textSecondary,
              title: 'সব সময় স্বচ্ছ',
              body: 'প্রতিটি বার্তা ও কল কোন পথে গেল, তা সব সময় দেখা যায় — '
                  'কোনো লুকানো ব্যর্থতা নেই।',
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 56,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTokens.primaryBright,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                ),
                onPressed: _continue,
                child: const Text('চলুন শুরু করি', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LayerStep extends StatelessWidget {
  const _LayerStep({required this.color, required this.title, required this.body});

  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: color)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppTokens.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
