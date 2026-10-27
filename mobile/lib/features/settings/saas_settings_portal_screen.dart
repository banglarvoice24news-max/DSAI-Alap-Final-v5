import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/constants.dart';
import '../../core/theme/dsaialap_glass.dart';
import '../locale/locale_cubit.dart';
import '../locale/locale_state.dart';
import 'connection_priority.dart';
import 'settings_cubit.dart';

class SaasSettingsPortalScreen extends StatelessWidget {
  const SaasSettingsPortalScreen({super.key});

  static const b2bKeyHint = 'x-dsaialap-key  •  set via DSAIALAP_B2B_KEYS';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        GlassCard(
          child: BlocBuilder<LocaleCubit, LocaleState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Language', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'en', label: Text('EN')),
                      ButtonSegment(value: 'bn', label: Text('বাংলা')),
                    ],
                    selected: {state.locale.languageCode},
                    onSelectionChanged: (s) => context.read<LocaleCubit>().setLocale(Locale(s.first)),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: BlocBuilder<SettingsCubit, SettingsSnapshot>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Network engine', style: TextStyle(fontWeight: FontWeight.w700)),
                  for (final p in ConnectionPriority.values)
                    ListTile(
                      dense: true,
                      title: Text(p.name),
                      leading: Icon(
                        state.priority == p ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: DsaialapTokens.neonCyan,
                      ),
                      onTap: () => context.read<SettingsCubit>().setPriority(p),
                    ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          glow: DsaialapTokens.neonOrange,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const NeonBadge(label: 'B2B SaaS', color: DsaialapTokens.neonOrange),
              const SizedBox(height: 8),
              const Text('Enterprise API key header'),
              const SizedBox(height: 6),
              if (AppConstants.b2bApiKey.isEmpty)
                const SelectableText(b2bKeyHint, style: TextStyle(fontFamily: 'monospace'))
              else
                SelectableText(
                  AppConstants.b2bApiKey,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    color: DsaialapTokens.neonLime,
                  ),
                ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(
                      text: AppConstants.b2bApiKey.isEmpty
                          ? 'x-dsaialap-key'
                          : AppConstants.b2bApiKey,
                    ),
                  );
                },
                icon: const Icon(Icons.copy),
                label: Text(AppConstants.b2bApiKey.isEmpty ? 'Copy header name' : 'Copy API key'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
