class AppConstants {
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://dsaialap.banglarvoice24news.com',
  );
  static const String b2bApiKey = String.fromEnvironment(
    'DSAIALAP_B2B_KEY',
    defaultValue: '',
  );
  static const int meshRangeMeters = 200;
  static const int audioSampleRate = 16000;
  static const int targetAudioLatencyMs = 100;
  static const Duration otpTtl = Duration(minutes: 3);
}
