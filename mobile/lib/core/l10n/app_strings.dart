// L10N SHIM — prototype labels, Bengali-first.
//
// DECISION LOCKED: gen-l10n must NOT be run in this sandbox (no Flutter SDK).
// This shim carries the hardcoded Bengali labels the new prototype screens use.
// The existing ARB pipeline (lib/l10n/app_en.arb / app_bn.arb + l10n.yaml)
// remains canonical for shipped strings; GitHub Actions CI runs `flutter
// gen-l10n` and can migrate these literals into ARB keys. New screens read from
// here so they never hand-reference AppLocalizations keys that do not exist
// yet.

abstract final class AppStrings {
  // Shell -----------------------------------------------------------------------
  static const String tabChats = 'চ্যাট';
  static const String tabCalls = 'কল';
  static const String tabNearby = 'কাছাকাছি';
  static const String tabSettings = 'সেটিংস';

  // Prototype honesty banner ----------------------------------------------------
  static const String prototypeBanner = 'প্রোটোটাইপ ডেটা — লাইভ বাইন্ডিং শীঘ্রই';

  // Transport -------------------------------------------------------------------
  static const String transportMesh = 'মেশ';
  static const String transportVoip = 'ভিওআইপি';
  static const String transportGsm = 'জিএসএম';
  static const String transportNone = 'কোনো সংযোগ নেই';

  // Delivery ticks --------------------------------------------------------------
  static const String deliveredPending = 'অপেক্ষমাণ';
  static const String deliveredSent = 'পাঠানো হয়েছে';
  static const String deliveredViaMesh = 'মেশ দিয়ে পৌঁছেছে';
  static const String deliveredViaVoip = 'ভিওআইপি দিয়ে পৌঁছেছে';
  static const String deliveredViaGsm = 'জিএসএম দিয়ে পৌঁছেছে';
  static const String readBadge = 'পঠিত';

  // Chats -----------------------------------------------------------------------
  static const String chatsTitle = 'চ্যাট';
  static const String chatsSearchHint = 'খুঁজুন';
  static const String chatsEmpty = 'কোনো কথোপকথন নেই';
  static const String threadComposerHint = 'বার্তা লিখুন';
  static const String threadSend = 'পাঠান';
  static const String waitingForMeshPeer = 'একটি মেশ পিয়ারের অপেক্ষায়';
  static const String retryingOverVoip = 'VoIP দিয়ে আবার চেষ্টা চলছে';
  static const String queuedOverGsm = 'GSM-এ সারিবদ্ধ';

  // Calls -----------------------------------------------------------------------
  static const String callsTitle = 'কল';
  static const String callsRecents = 'সাম্প্রতিক কল';
  static const String callsFavorites = 'প্রিয়';
  static const String callsKeypad = 'কল করুন';
  static const String callViaMesh = 'মেশ কল';
  static const String callViaVoip = 'ভিওআইপি কল';
  static const String callViaGsm = 'জিএসএম কল';
  static const String callFallbackReason = 'সবচেয়ে ভালো পথে সংযোগ হবে';
  static const String callMissed = 'মিসড';
  static const String redial = 'আবার কল';
  static const String callNow = 'এখনই কল';

  // In-call ---------------------------------------------------------------------
  static const String inCallEnd = 'কল শেষ';
  static const String inCallMute = 'নিঃশব্দ';
  static const String inCallSpeaker = 'স্পিকার';
  static const String inCallFallback = 'সংযোগ পড়ছে…';
  static const String inCallFallbackDetail = 'নেটওয়ার্ক বদলে যাচ্ছে';
  static const String inCallOnMesh = 'এই কলটি মেশে চলছে';
  static const String inCallOnVoip = 'এই কলটি ভিওআইপিতে চলছে';
  static const String inCallOnGsm = 'এই কলটি জিএসএমে চলছে';
  static const String inCallHops = 'হপ';
  static const String inCallSwitchTransport = 'ট্রান্সপোর্ট বদলান';

  // Nearby ----------------------------------------------------------------------
  static const String nearbyTitle = 'কাছাকাছি';
  static const String nearbyScanning = 'স্ক্যান চলছে…';
  static const String nearbyNoPeers = 'কাছাকাছি কোনো পিয়ার নেই';
  static const String nearbySectionBroadcast = 'ব্রডকাস্ট';
  static const String nearbySectionPrivate = '১:১ প্রাইভেট';
  static const String nearbySendBroadcast = 'সবাইকে পাঠান';
  static const String nearbySignal = 'সিগন্যাল';
  static const String nearbyConnect = 'সংযোগ';
  static const String nearbyInCall = 'কল চলছে';
  static const String nearbyRangeMeters = 'মি';
  static const String nearbyOfflineHello = 'অফলাইন হ্যালো';
  static const String nearbyStartDiscovery = 'স্ক্যান শুরু';
  static const String nearbyStopDiscovery = 'স্ক্যান বন্ধ';
  static const String nearbyAccept = 'গ্রহণ';
  static const String nearbyReject = 'প্রত্যাখ্যান';
  static const String nearbyConfirmCode = 'কোড মিললে নিশ্চিত করুন';
  static const String nearbySafetyTitle = 'সেফটি কোড যাচাই';
  static const String nearbyIncomingTitle = 'সংযোগের অনুরোধ';
  static const String nearbyTrusted = 'বিশ্বস্ত';
  static const String nearbyQueued = 'সারিতে';
  static const String nearbySending = 'পাঠানো হচ্ছে';
  static const String nearbyWaitingAck = 'ACK-এর অপেক্ষায়';
  static const String nearbyDelivered = 'ডেলিভারড';
  static const String nearbyFailed = 'ব্যর্থ';
  static const String nearbyExpired = 'মেয়াদ শেষ';
  static const String nearbyUntrusted = 'অজানা পিয়ারে পাঠানো যাবে না';
  static const String nearbyOfflineHint = 'SIM/ইন্টারনেট ছাড়াই কাছাকাছি ডিভাইসে এনক্রিপ্টেড বার্তা';

  // Settings --------------------------------------------------------------------
  static const String settingsRoutePref = 'কল রাউটিং পছন্দ';
  static const String settingsNetwork = 'নেটওয়ার্ক ও ডেটা';
  static const String settingsAuto = 'স্বয়ংক্রিয়';
  static const String settingsAutoSub = 'মেশ → ভিওআইপি → জিএসএম';
  static const String settingsMeshOnly = 'শুধু মেশ';
  static const String settingsMeshOnlySub = 'ইন্টারনেট/সিম ব্যবহার হবে না';
  static const String settingsInternetOnly = 'শুধু ইন্টারনেট';
  static const String settingsInternetOnlySub = 'মেশ/সিম ব্যবহার হবে না';
  static const String settingsGsmOnly = 'শুধু জিএসএম';
  static const String settingsGsmOnlySub = 'মেশ/ইন্টারনেট ব্যবহার হবে না';
  static const String settingsDataSaver = 'ডেটা সেভার';
  static const String settingsDataSaverSub = 'কম-বিটরেট Opus/SILK অডিও';
  static const String settingsBatterySaver = 'ব্যাটারি সেভার';
  static const String settingsTransparency = 'কী সংরক্ষণ হয় ও কেন';
  static const String settingsTransparencySub = 'সহজ বাংলায় ব্যাখ্যা';
  static const String settingsOnboarding = 'ভূমিকা আবার দেখুন';
  static const String settingsLanguage = 'ভাষা';

  // Transparency -----------------------------------------------------------------
  static const String transparencyTitle = 'ডেটা ও গোপনীয়তা';
  static const String transparencyIntro =
      'dsaialap যখনই কোনো সংযোগ করে, আমাদের সার্ভার একটি কল রেকর্ড (CDR) রাখে '
      'যাতে আমরা দেখতে পারি আপনার কল পৌঁছেছে কি না, কীভাবে পৌঁছেছে, এবং কোথায় ব্যর্থ হয়েছে।';
  static const String transparencyCdrTitle = 'কল রেকর্ড (CDR) — কী থাকে';
  static const String transparencyCdrBody =
      'কোন নম্বরে, কখন, কতক্ষণ, কোন পথে (মেশ/ভিওআইপি/জিএসএম) কল হয়েছে, আর সফল হয়েছে কি না। '
      'কলের শব্দ বা কথোপকথনের বিষয়বস্তু কখনোই রেকর্ড হয় না।';
  static const String transparencyContentTitle = 'বার্তার বিষয়বস্তু — কী থাকে না';
  static const String transparencyContentBody =
      'বার্তা আপনার ডিভাইসেই এনক্রিপ্ট করা থাকে। সার্ভার শুধু এনক্রিপ্টেড অংশ বহন করে, '
      'খোলা লেখা নয়।';
  static const String transparencyConsentTitle = 'আপনার নিয়ন্ত্রণ';
  static const String transparencyConsentBody =
      'এই রেকর্ড ছাড়া কল-সম্পর্কিত সমস্যা সমাধান বা অপব্যবহার ঠেকানো সম্ভব নয়। '
      'রেকর্ড স্বয়ংক্রিয়ভাবে মুছে যায় এবং আপনি যেকোনো সময় এটি বন্ধ করতে পারেন।';
  static const String transparencyTtl = 'রেকর্ড রাখা হয় ৩০ দিন';
}
