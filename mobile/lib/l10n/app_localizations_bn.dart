// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class AppLocalizationsBn extends AppLocalizations {
  AppLocalizationsBn([String locale = 'bn']) : super(locale);

  @override
  String get appName => 'নেক্সাস';

  @override
  String get tabChats => 'চ্যাট';

  @override
  String get tabMesh => 'অফ-গ্রিড';

  @override
  String get tabDialer => 'ডায়ালার';

  @override
  String get tabSettings => 'সেটিংস';

  @override
  String get chatsTitle => 'এনক্রিপ্টেড চ্যাট';

  @override
  String get chatsEmpty => 'এখনো কোনো কথোপকথন নেই। নিরাপদ চ্যাট শুরু করুন।';

  @override
  String get chatsOnline => 'অনলাইন';

  @override
  String get chatsOffline => 'নেটওয়ার্কের অপেক্ষা';

  @override
  String get meshTitle => 'অফ-গ্রিড মেশ';

  @override
  String get meshSubtitle => '২০০ মিটারের মধ্যে কাছাকাছি ডিভাইস';

  @override
  String get meshScanning => 'কাছাকাছি পিয়ার খোঁজা হচ্ছে';

  @override
  String get meshNoPeers => 'কোনো ডিভাইস পাওয়া যায়নি। এই স্ক্রিন খোলা রাখুন।';

  @override
  String get meshConnect => 'সংযোগ';

  @override
  String get meshCall => 'ভয়েস কল';

  @override
  String get meshConnected => 'সংযুক্ত';

  @override
  String get meshConnecting => 'সংযোগ হচ্ছে';

  @override
  String get meshDropped => 'রেঞ্জের বাইরে — পুনরায় সংযোগ';

  @override
  String get meshRssi => 'সিগন্যাল';

  @override
  String meshDistance(int meters) {
    return '~$meters মি';
  }

  @override
  String get dialerTitle => 'সিম ডায়ালার';

  @override
  String get dialerCall => 'কল';

  @override
  String get dialerContacts => 'কন্টাক্ট';

  @override
  String get dialerNoInternetTitle => 'ইন্টারনেট নেই';

  @override
  String get dialerNoInternetBody => 'ইন্টারনেট নেই। সিম কার্ড দিয়ে কল করবেন?';

  @override
  String get dialerUseSim => 'সিম দিয়ে কল';

  @override
  String get dialerCancel => 'বাতিল';

  @override
  String get dialerInvalidNumber => 'সঠিক ফোন নম্বর দিন';

  @override
  String get settingsTitle => 'সেটিংস ও নিরাপত্তা';

  @override
  String get settingsLanguage => 'ভাষা';

  @override
  String get settingsEnglish => 'English';

  @override
  String get settingsBengali => 'বাংলা';

  @override
  String get settingsConnection => 'সংযোগ ব্যবস্থাপক';

  @override
  String get settingsPriorityAuto => 'অটো (P2P / ইন্টারনেট / সিম)';

  @override
  String get settingsPriorityInternet => 'শুধু ইন্টারনেট';

  @override
  String get settingsPriorityMesh => 'শুধু মেশ';

  @override
  String get settingsPrioritySim => 'শুধু সিম';

  @override
  String get settingsSecurity => 'নিরাপত্তা ও গোপনীয়তা';

  @override
  String get settingsAppLock => 'অ্যাপ লক';

  @override
  String get settingsBiometric => 'বায়োমেট্রিক / পিন';

  @override
  String get settingsScreenSecurity => 'স্ক্রিনশট শিল্ড';

  @override
  String get settingsScreenSecuritySub =>
      'স্ক্রিনশট ও স্ক্রিন রেকর্ডিং বন্ধ রাখুন';

  @override
  String get settingsE2eeVerify => 'E2EE কী যাচাই';

  @override
  String get settingsBlocked => 'ব্লক করা কন্টাক্ট';

  @override
  String get settingsClearCache => 'ক্যাশ মুছুন';

  @override
  String get settingsNetwork => 'নেটওয়ার্ক ডেটা ব্যবহার';

  @override
  String get settingsDataSaver => 'VoIP ডেটা সেভার';

  @override
  String get settingsMeshFreq => 'মেশ ডিসকভারি ফ্রিকোয়েন্সি';

  @override
  String get settingsBatterySaver => 'ব্যাটারি সেভার (ধীর ডিসকভারি)';

  @override
  String get settingsNotifications => 'নোটিফিকেশন';

  @override
  String get settingsRingtone => 'কাস্টম রিংটোন';

  @override
  String get settingsVibrate => 'ভাইব্রেট প্যাটার্ন';

  @override
  String get settingsNotifPriority => 'নোটিফিকেশন অগ্রাধিকার';

  @override
  String get otpTitle => 'ফোন যাচাই';

  @override
  String get otpSend => 'কোড পাঠান';

  @override
  String get otpVerify => 'যাচাই';

  @override
  String get otpHint => '৬ অঙ্কের এসএমএস কোড পাঠানো হবে';

  @override
  String get commonSave => 'সংরক্ষণ';

  @override
  String get commonClose => 'বন্ধ';

  @override
  String get commonRetry => 'আবার চেষ্টা';
}
