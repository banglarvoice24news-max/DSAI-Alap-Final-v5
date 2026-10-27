// Settings tab — routing preference, Data Saver, transparency (first-pass).
//
// Route preference maps onto the existing ConnectionPriority store so the
// dialer's low-bitrate / SIM behaviour stays consistent. Data Saver is the
// same switch the backend's `lowBitrate` Opus/SILK flag will honour. Platform
// honesty: on iOS, native GSM fallback does not exist, so the "only GSM" row
// is shown disabled rather than leading the user to a dead control.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/transport/transport_status.dart';
import '../../offline_slice1/data/session_engine.dart';
import '../../offline_slice1/presentation/offline_nearby_screen.dart';
import '../../offline_slice1/presentation/offline_slice_cubit.dart';
import '../locale/locale_cubit.dart';
import '../locale/locale_state.dart';
import '../settings/connection_priority.dart';
import '../settings/settings_cubit.dart';
import 'hybrid_onboarding_screen.dart';
import 'hybrid_transparency_screen.dart';

class HybridSettingsScreen extends StatelessWidget {
  const HybridSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.canvas,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            const _LocalIdentityCard(),
            const SizedBox(height: 12),
            _LanguageCard(),
            const SizedBox(height: 12),
            _RoutingCard(),
            const SizedBox(height: 12),
            _NetworkCard(),
            const SizedBox(height: 12),
            _LinkCard(
              icon: Icons.privacy_tip_outlined,
              title: AppStrings.settingsTransparency,
              subtitle: AppStrings.settingsTransparencySub,
              onTap: () => _push(context, const HybridTransparencyScreen()),
            ),
            const SizedBox(height: 8),
            _LinkCard(
              icon: Icons.waving_hand_outlined,
              title: AppStrings.settingsOnboarding,
              subtitle: AppStrings.settingsAutoSub,
              onTap: () => _push(context, const HybridOnboardingScreen()),
            ),
            const SizedBox(height: 8),
            _LinkCard(
              icon: Icons.lock_outline,
              title: 'Offline nearby chat',
              subtitle: 'No OTP, SIM, or internet required',
              onTap: () => _push(context, const OfflineNearbyScreen()),
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTokens.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTokens.glassStroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _LocalIdentityCard extends StatefulWidget {
  const _LocalIdentityCard();

  @override
  State<_LocalIdentityCard> createState() => _LocalIdentityCardState();
}

class _LocalIdentityCardState extends State<_LocalIdentityCard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OfflineSliceCubit>().bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Local identity',
      child: BlocBuilder<OfflineSliceCubit, OfflineSessionState>(
        builder: (context, _) {
          final identity = context.read<OfflineSliceCubit>().identity;
          if (identity == null) {
            return const Text(
              'Creating local identity…',
              style: TextStyle(fontSize: 12, color: AppTokens.textSecondary),
            );
          }
          final pub = identity.publicKeyB64;
          final pubShort = pub.length <= 20 ? pub : '${pub.substring(0, 20)}…';
          final hint = identity.linkedAccountHint;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(identity.shortName, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Device ${identity.deviceId}',
                style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                'Public key $pubShort',
                style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                hint == null || hint.isEmpty
                    ? 'Not linked to an online account'
                    : 'Linked account $hint',
                style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Card(
      title: AppStrings.settingsLanguage,
      child: BlocBuilder<LocaleCubit, LocaleState>(
        builder: (context, state) {
          return SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'bn', label: Text('বাংলা')),
            ],
            selected: {state.locale.languageCode},
            onSelectionChanged: (s) => context.read<LocaleCubit>().setLocale(Locale(s.first)),
          );
        },
      ),
    );
  }
}

class _RoutingCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final gsmOk = TransportCapabilities.forPlatform().supports(CallTransport.gsm);
    return _Card(
      title: AppStrings.settingsRoutePref,
      child: BlocBuilder<SettingsCubit, SettingsSnapshot>(
        builder: (context, state) {
          final rows = <(ConnectionPriority, String, String, bool)>[
            (ConnectionPriority.auto, AppStrings.settingsAuto, AppStrings.settingsAutoSub, true),
            (ConnectionPriority.meshOnly, AppStrings.settingsMeshOnly, AppStrings.settingsMeshOnlySub, true),
            (ConnectionPriority.internetOnly, AppStrings.settingsInternetOnly, AppStrings.settingsInternetOnlySub, true),
            (ConnectionPriority.simOnly, AppStrings.settingsGsmOnly, AppStrings.settingsGsmOnlySub, gsmOk),
          ];
          return Column(
            children: [
              for (final (p, label, sub, enabled) in rows)
                ListTile(
                  dense: true,
                  enabled: enabled,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    state.priority == p ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: enabled ? AppTokens.primaryBright : AppTokens.textSecondary,
                  ),
                  title: Text(label, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  subtitle: Text(sub, style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
                  onTap: enabled ? () => context.read<SettingsCubit>().setPriority(p) : null,
                ),
              if (!gsmOk)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'iOS: native GSM fallback উপলব্ধ নয়।',
                    style: TextStyle(fontSize: 11.5, color: AppTokens.warn),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _NetworkCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _Card(
      title: AppStrings.settingsNetwork,
      child: BlocBuilder<SettingsCubit, SettingsSnapshot>(
        builder: (context, state) {
          return Column(
            children: [
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(AppStrings.settingsDataSaver, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                subtitle: const Text(AppStrings.settingsDataSaverSub, style: TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
                activeColor: AppTokens.primaryBright,
                value: state.dataSaver,
                onChanged: (v) => context.read<SettingsCubit>().setDataSaver(v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(AppStrings.settingsBatterySaver, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                subtitle: Text('Mesh স্ক্যান ${state.meshDiscoverySeconds}s', style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
                activeColor: AppTokens.primaryBright,
                value: state.batterySaver,
                onChanged: (v) => context.read<SettingsCubit>().setBatterySaver(v),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.surface.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: AppTokens.primaryBright),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTokens.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTokens.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
