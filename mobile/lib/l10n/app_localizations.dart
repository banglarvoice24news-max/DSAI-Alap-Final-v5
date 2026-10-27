import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('bn'),
    Locale('en')
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Nexus'**
  String get appName;

  /// No description provided for @tabChats.
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get tabChats;

  /// No description provided for @tabMesh.
  ///
  /// In en, this message translates to:
  /// **'Off-Grid'**
  String get tabMesh;

  /// No description provided for @tabDialer.
  ///
  /// In en, this message translates to:
  /// **'Dialer'**
  String get tabDialer;

  /// No description provided for @tabSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// No description provided for @chatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Encrypted chats'**
  String get chatsTitle;

  /// No description provided for @chatsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet. Start a secure chat.'**
  String get chatsEmpty;

  /// No description provided for @chatsOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get chatsOnline;

  /// No description provided for @chatsOffline.
  ///
  /// In en, this message translates to:
  /// **'Waiting for network'**
  String get chatsOffline;

  /// No description provided for @meshTitle.
  ///
  /// In en, this message translates to:
  /// **'Off-grid mesh'**
  String get meshTitle;

  /// No description provided for @meshSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nearby devices within 200 m'**
  String get meshSubtitle;

  /// No description provided for @meshScanning.
  ///
  /// In en, this message translates to:
  /// **'Scanning nearby peers'**
  String get meshScanning;

  /// No description provided for @meshNoPeers.
  ///
  /// In en, this message translates to:
  /// **'No devices discovered. Keep this screen open.'**
  String get meshNoPeers;

  /// No description provided for @meshConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get meshConnect;

  /// No description provided for @meshCall.
  ///
  /// In en, this message translates to:
  /// **'Voice call'**
  String get meshCall;

  /// No description provided for @meshConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get meshConnected;

  /// No description provided for @meshConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting'**
  String get meshConnecting;

  /// No description provided for @meshDropped.
  ///
  /// In en, this message translates to:
  /// **'Out of range — reconnecting'**
  String get meshDropped;

  /// No description provided for @meshRssi.
  ///
  /// In en, this message translates to:
  /// **'Signal'**
  String get meshRssi;

  /// No description provided for @meshDistance.
  ///
  /// In en, this message translates to:
  /// **'~{meters} m'**
  String meshDistance(int meters);

  /// No description provided for @dialerTitle.
  ///
  /// In en, this message translates to:
  /// **'SIM dialer'**
  String get dialerTitle;

  /// No description provided for @dialerCall.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get dialerCall;

  /// No description provided for @dialerContacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get dialerContacts;

  /// No description provided for @dialerNoInternetTitle.
  ///
  /// In en, this message translates to:
  /// **'No Internet'**
  String get dialerNoInternetTitle;

  /// No description provided for @dialerNoInternetBody.
  ///
  /// In en, this message translates to:
  /// **'No Internet. Call via SIM Card?'**
  String get dialerNoInternetBody;

  /// No description provided for @dialerUseSim.
  ///
  /// In en, this message translates to:
  /// **'Call via SIM'**
  String get dialerUseSim;

  /// No description provided for @dialerCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dialerCancel;

  /// No description provided for @dialerInvalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number'**
  String get dialerInvalidNumber;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings & security'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsEnglish;

  /// No description provided for @settingsBengali.
  ///
  /// In en, this message translates to:
  /// **'বাংলা'**
  String get settingsBengali;

  /// No description provided for @settingsConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection manager'**
  String get settingsConnection;

  /// No description provided for @settingsPriorityAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto (P2P / Internet / SIM)'**
  String get settingsPriorityAuto;

  /// No description provided for @settingsPriorityInternet.
  ///
  /// In en, this message translates to:
  /// **'Internet only'**
  String get settingsPriorityInternet;

  /// No description provided for @settingsPriorityMesh.
  ///
  /// In en, this message translates to:
  /// **'Mesh only'**
  String get settingsPriorityMesh;

  /// No description provided for @settingsPrioritySim.
  ///
  /// In en, this message translates to:
  /// **'SIM only'**
  String get settingsPrioritySim;

  /// No description provided for @settingsSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security & privacy'**
  String get settingsSecurity;

  /// No description provided for @settingsAppLock.
  ///
  /// In en, this message translates to:
  /// **'App lock'**
  String get settingsAppLock;

  /// No description provided for @settingsBiometric.
  ///
  /// In en, this message translates to:
  /// **'Biometric / PIN'**
  String get settingsBiometric;

  /// No description provided for @settingsScreenSecurity.
  ///
  /// In en, this message translates to:
  /// **'Screenshot shield'**
  String get settingsScreenSecurity;

  /// No description provided for @settingsScreenSecuritySub.
  ///
  /// In en, this message translates to:
  /// **'Block screenshots and screen recording'**
  String get settingsScreenSecuritySub;

  /// No description provided for @settingsE2eeVerify.
  ///
  /// In en, this message translates to:
  /// **'E2EE key verification'**
  String get settingsE2eeVerify;

  /// No description provided for @settingsBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked contacts'**
  String get settingsBlocked;

  /// No description provided for @settingsClearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get settingsClearCache;

  /// No description provided for @settingsNetwork.
  ///
  /// In en, this message translates to:
  /// **'Network data usage'**
  String get settingsNetwork;

  /// No description provided for @settingsDataSaver.
  ///
  /// In en, this message translates to:
  /// **'VoIP data saver'**
  String get settingsDataSaver;

  /// No description provided for @settingsMeshFreq.
  ///
  /// In en, this message translates to:
  /// **'Mesh discovery frequency'**
  String get settingsMeshFreq;

  /// No description provided for @settingsBatterySaver.
  ///
  /// In en, this message translates to:
  /// **'Battery saver (slower discovery)'**
  String get settingsBatterySaver;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsRingtone.
  ///
  /// In en, this message translates to:
  /// **'Custom ringtone'**
  String get settingsRingtone;

  /// No description provided for @settingsVibrate.
  ///
  /// In en, this message translates to:
  /// **'Vibrate pattern'**
  String get settingsVibrate;

  /// No description provided for @settingsNotifPriority.
  ///
  /// In en, this message translates to:
  /// **'Notification priority'**
  String get settingsNotifPriority;

  /// No description provided for @otpTitle.
  ///
  /// In en, this message translates to:
  /// **'Verify phone'**
  String get otpTitle;

  /// No description provided for @otpSend.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get otpSend;

  /// No description provided for @otpVerify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get otpVerify;

  /// No description provided for @otpHint.
  ///
  /// In en, this message translates to:
  /// **'We will send a 6-digit SMS code'**
  String get otpHint;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['bn', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'bn':
      return AppLocalizationsBn();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
