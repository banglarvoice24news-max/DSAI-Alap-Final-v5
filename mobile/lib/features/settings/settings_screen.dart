import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nexus_comm/l10n/app_localizations.dart';
import '../locale/locale_cubit.dart';
import '../locale/locale_state.dart';
import 'connection_priority.dart';
import 'settings_cubit.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          _Section(
            title: l10n.settingsLanguage,
            child: BlocBuilder<LocaleCubit, LocaleState>(
              builder: (context, state) {
                return SegmentedButton<String>(
                  segments: [
                    ButtonSegment(value: 'en', label: Text(l10n.settingsEnglish)),
                    ButtonSegment(value: 'bn', label: Text(l10n.settingsBengali)),
                  ],
                  selected: {state.locale.languageCode},
                  onSelectionChanged: (s) {
                    context.read<LocaleCubit>().setLocale(Locale(s.first));
                  },
                );
              },
            ),
          ),
          _Section(
            title: l10n.settingsConnection,
            child: BlocBuilder<SettingsCubit, SettingsSnapshot>(
              builder: (context, state) {
                final labels = {
                  ConnectionPriority.auto: l10n.settingsPriorityAuto,
                  ConnectionPriority.internetOnly: l10n.settingsPriorityInternet,
                  ConnectionPriority.meshOnly: l10n.settingsPriorityMesh,
                  ConnectionPriority.simOnly: l10n.settingsPrioritySim,
                };
                return Column(
                  children: ConnectionPriority.values.map((p) {
                    return ListTile(
                      title: Text(labels[p]!),
                      leading: Icon(
                        state.priority == p ? Icons.radio_button_checked : Icons.radio_button_off,
                      ),
                      onTap: () => context.read<SettingsCubit>().setPriority(p),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          _Section(
            title: l10n.settingsSecurity,
            child: BlocBuilder<SettingsCubit, SettingsSnapshot>(
              builder: (context, state) {
                return Column(
                  children: [
                    SwitchListTile(
                      title: Text(l10n.settingsAppLock),
                      subtitle: Text(l10n.settingsBiometric),
                      value: state.appLockEnabled,
                      onChanged: (v) => context.read<SettingsCubit>().setAppLock(v),
                    ),
                    SwitchListTile(
                      title: Text(l10n.settingsScreenSecurity),
                      subtitle: Text(l10n.settingsScreenSecuritySub),
                      value: state.screenSecurityEnabled,
                      onChanged: (v) =>
                          context.read<SettingsCubit>().setScreenSecurity(v),
                    ),
                    ListTile(
                      leading: const Icon(Icons.verified_user_outlined),
                      title: Text(l10n.settingsE2eeVerify),
                      onTap: () {},
                    ),
                    ListTile(
                      leading: const Icon(Icons.block),
                      title: Text(l10n.settingsBlocked),
                      onTap: () {},
                    ),
                    ListTile(
                      leading: const Icon(Icons.cleaning_services_outlined),
                      title: Text(l10n.settingsClearCache),
                      onTap: () => context.read<SettingsCubit>().clearCache(),
                    ),
                  ],
                );
              },
            ),
          ),
          _Section(
            title: l10n.settingsNetwork,
            child: BlocBuilder<SettingsCubit, SettingsSnapshot>(
              builder: (context, state) {
                return Column(
                  children: [
                    SwitchListTile(
                      title: Text(l10n.settingsDataSaver),
                      value: state.dataSaver,
                      onChanged: (v) => context.read<SettingsCubit>().setDataSaver(v),
                    ),
                    SwitchListTile(
                      title: Text(l10n.settingsBatterySaver),
                      subtitle: Text(l10n.settingsMeshFreq),
                      value: state.batterySaver,
                      onChanged: (v) => context.read<SettingsCubit>().setBatterySaver(v),
                    ),
                  ],
                );
              },
            ),
          ),
          _Section(
            title: l10n.settingsNotifications,
            child: BlocBuilder<SettingsCubit, SettingsSnapshot>(
              builder: (context, state) {
                return Column(
                  children: [
                    ListTile(
                      title: Text(l10n.settingsRingtone),
                      subtitle: Text(state.ringtone),
                      onTap: () => context.read<SettingsCubit>().setRingtone('nexus_default'),
                    ),
                    ListTile(
                      title: Text(l10n.settingsVibrate),
                      subtitle: Text(state.vibrate.name),
                      onTap: () => context.read<SettingsCubit>().setVibrate(VibratePattern.short),
                    ),
                    ListTile(
                      title: Text(l10n.settingsNotifPriority),
                      subtitle: Text(state.notificationPriority.name),
                      onTap: () => context
                          .read<SettingsCubit>()
                          .setNotificationPriority(NotificationPriority.high),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
