import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/security/screen_guard.dart';
import 'connection_priority.dart';

class SettingsCubit extends Cubit<SettingsSnapshot> {
  SettingsCubit({LocalAuthentication? auth, ScreenGuard? screenGuard})
      : _auth = auth ?? LocalAuthentication(),
        _screenGuard = screenGuard ?? ScreenGuard(),
        super(const SettingsSnapshot());

  final LocalAuthentication _auth;
  final ScreenGuard _screenGuard;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final screenSecurity = prefs.getBool('screen_security') ?? true;
    await _screenGuard.setEnabled(screenSecurity);
    emit(
      SettingsSnapshot(
        priority: ConnectionPriority.values[prefs.getInt('prio') ?? 0],
        appLockEnabled: prefs.getBool('app_lock') ?? false,
        screenSecurityEnabled: screenSecurity,
        dataSaver: prefs.getBool('data_saver') ?? false,
        batterySaver: prefs.getBool('battery_saver') ?? false,
        ringtone: prefs.getString('ringtone') ?? 'default',
        vibrate: VibratePattern.values[prefs.getInt('vibrate') ?? 2],
        notificationPriority:
            NotificationPriority.values[prefs.getInt('notif_prio') ?? 2],
        meshDiscoverySeconds: prefs.getBool('battery_saver') == true ? 20 : 8,
      ),
    );
  }

  Future<void> setPriority(ConnectionPriority priority) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('prio', priority.index);
    emit(state.copyWith(priority: priority));
  }

  Future<void> setAppLock(bool enabled) async {
    if (enabled) {
      final ok = await _auth.authenticate(
        localizedReason: 'Enable Nexus app lock',
        options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
      );
      if (!ok) return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('app_lock', enabled);
    emit(state.copyWith(appLockEnabled: enabled));
  }

  Future<bool> unlock() async {
    if (!state.appLockEnabled) return true;
    return _auth.authenticate(
      localizedReason: 'Unlock Nexus',
      options: const AuthenticationOptions(biometricOnly: false, stickyAuth: true),
    );
  }

  Future<void> setScreenSecurity(bool enabled) async {
    final effective = await _screenGuard.setEnabled(enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('screen_security', effective);
    emit(state.copyWith(screenSecurityEnabled: effective));
  }

  Future<void> setDataSaver(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('data_saver', value);
    emit(state.copyWith(dataSaver: value));
  }

  Future<void> setBatterySaver(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('battery_saver', value);
    emit(state.copyWith(
      batterySaver: value,
      meshDiscoverySeconds: value ? 20 : 8,
    ));
  }

  Future<void> setRingtone(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ringtone', name);
    emit(state.copyWith(ringtone: name));
  }

  Future<void> setVibrate(VibratePattern pattern) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('vibrate', pattern.index);
    emit(state.copyWith(vibrate: pattern));
  }

  Future<void> setNotificationPriority(NotificationPriority p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notif_prio', p.index);
    emit(state.copyWith(notificationPriority: p));
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith('cache_')) {
        await prefs.remove(key);
      }
    }
  }
}
