enum ConnectionPriority { auto, internetOnly, meshOnly, simOnly }

enum VibratePattern { none, short, defaultPattern, long }

enum NotificationPriority { low, defaultPriority, high }

class SettingsSnapshot {
  const SettingsSnapshot({
    this.priority = ConnectionPriority.auto,
    this.appLockEnabled = false,
    this.screenSecurityEnabled = true,
    this.dataSaver = false,
    this.batterySaver = false,
    this.ringtone = 'default',
    this.vibrate = VibratePattern.defaultPattern,
    this.notificationPriority = NotificationPriority.high,
    this.meshDiscoverySeconds = 8,
  });

  final ConnectionPriority priority;
  final bool appLockEnabled;
  final bool screenSecurityEnabled;
  final bool dataSaver;
  final bool batterySaver;
  final String ringtone;
  final VibratePattern vibrate;
  final NotificationPriority notificationPriority;
  final int meshDiscoverySeconds;

  SettingsSnapshot copyWith({
    ConnectionPriority? priority,
    bool? appLockEnabled,
    bool? screenSecurityEnabled,
    bool? dataSaver,
    bool? batterySaver,
    String? ringtone,
    VibratePattern? vibrate,
    NotificationPriority? notificationPriority,
    int? meshDiscoverySeconds,
  }) {
    return SettingsSnapshot(
      priority: priority ?? this.priority,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      screenSecurityEnabled: screenSecurityEnabled ?? this.screenSecurityEnabled,
      dataSaver: dataSaver ?? this.dataSaver,
      batterySaver: batterySaver ?? this.batterySaver,
      ringtone: ringtone ?? this.ringtone,
      vibrate: vibrate ?? this.vibrate,
      notificationPriority: notificationPriority ?? this.notificationPriority,
      meshDiscoverySeconds: meshDiscoverySeconds ?? this.meshDiscoverySeconds,
    );
  }
}
