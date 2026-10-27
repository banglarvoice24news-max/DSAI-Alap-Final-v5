// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Nexus';

  @override
  String get tabChats => 'Chats';

  @override
  String get tabMesh => 'Off-Grid';

  @override
  String get tabDialer => 'Dialer';

  @override
  String get tabSettings => 'Settings';

  @override
  String get chatsTitle => 'Encrypted chats';

  @override
  String get chatsEmpty => 'No conversations yet. Start a secure chat.';

  @override
  String get chatsOnline => 'Online';

  @override
  String get chatsOffline => 'Waiting for network';

  @override
  String get meshTitle => 'Off-grid mesh';

  @override
  String get meshSubtitle => 'Nearby devices within 200 m';

  @override
  String get meshScanning => 'Scanning nearby peers';

  @override
  String get meshNoPeers => 'No devices discovered. Keep this screen open.';

  @override
  String get meshConnect => 'Connect';

  @override
  String get meshCall => 'Voice call';

  @override
  String get meshConnected => 'Connected';

  @override
  String get meshConnecting => 'Connecting';

  @override
  String get meshDropped => 'Out of range — reconnecting';

  @override
  String get meshRssi => 'Signal';

  @override
  String meshDistance(int meters) {
    return '~$meters m';
  }

  @override
  String get dialerTitle => 'SIM dialer';

  @override
  String get dialerCall => 'Call';

  @override
  String get dialerContacts => 'Contacts';

  @override
  String get dialerNoInternetTitle => 'No Internet';

  @override
  String get dialerNoInternetBody => 'No Internet. Call via SIM Card?';

  @override
  String get dialerUseSim => 'Call via SIM';

  @override
  String get dialerCancel => 'Cancel';

  @override
  String get dialerInvalidNumber => 'Enter a valid phone number';

  @override
  String get settingsTitle => 'Settings & security';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsEnglish => 'English';

  @override
  String get settingsBengali => 'বাংলা';

  @override
  String get settingsConnection => 'Connection manager';

  @override
  String get settingsPriorityAuto => 'Auto (P2P / Internet / SIM)';

  @override
  String get settingsPriorityInternet => 'Internet only';

  @override
  String get settingsPriorityMesh => 'Mesh only';

  @override
  String get settingsPrioritySim => 'SIM only';

  @override
  String get settingsSecurity => 'Security & privacy';

  @override
  String get settingsAppLock => 'App lock';

  @override
  String get settingsBiometric => 'Biometric / PIN';

  @override
  String get settingsScreenSecurity => 'Screenshot shield';

  @override
  String get settingsScreenSecuritySub =>
      'Block screenshots and screen recording';

  @override
  String get settingsE2eeVerify => 'E2EE key verification';

  @override
  String get settingsBlocked => 'Blocked contacts';

  @override
  String get settingsClearCache => 'Clear cache';

  @override
  String get settingsNetwork => 'Network data usage';

  @override
  String get settingsDataSaver => 'VoIP data saver';

  @override
  String get settingsMeshFreq => 'Mesh discovery frequency';

  @override
  String get settingsBatterySaver => 'Battery saver (slower discovery)';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsRingtone => 'Custom ringtone';

  @override
  String get settingsVibrate => 'Vibrate pattern';

  @override
  String get settingsNotifPriority => 'Notification priority';

  @override
  String get otpTitle => 'Verify phone';

  @override
  String get otpSend => 'Send code';

  @override
  String get otpVerify => 'Verify';

  @override
  String get otpHint => 'We will send a 6-digit SMS code';

  @override
  String get commonSave => 'Save';

  @override
  String get commonClose => 'Close';

  @override
  String get commonRetry => 'Retry';
}
