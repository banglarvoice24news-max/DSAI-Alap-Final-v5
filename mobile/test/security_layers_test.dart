import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_comm/core/security/screen_guard.dart';
import 'package:nexus_comm/core/storage/secure_database.dart';
import 'package:nexus_comm/features/settings/settings_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(ScreenGuard.channelName);

  group('OutboxEntry', () {
    test('serialises and restores every field', () {
      final entry = OutboxEntry(
        id: 'local-1',
        threadId: 't-mesh',
        body: 'hello mesh',
        transport: 'mesh',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      final restored = OutboxEntry.fromMap(entry.toMap());

      expect(restored.id, entry.id);
      expect(restored.threadId, entry.threadId);
      expect(restored.body, entry.body);
      expect(restored.transport, entry.transport);
      expect(restored.createdAt, entry.createdAt);
    });

    test('stores createdAt as an epoch millisecond integer', () {
      final entry = OutboxEntry(
        id: 'x',
        threadId: 't',
        body: 'b',
        transport: 'voip',
        createdAt: DateTime.fromMillisecondsSinceEpoch(42),
      );

      expect(entry.toMap()['created_at'], 42);
    });
  });

  group('SettingsCubit screen security', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('toggling off persists the choice and emits the state', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => true);

      final cubit = SettingsCubit(screenGuard: ScreenGuard(channel: channel));
      expect(cubit.state.screenSecurityEnabled, isTrue);

      await cubit.setScreenSecurity(false);

      expect(cubit.state.screenSecurityEnabled, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('screen_security'), isFalse);
    });

    test('load() restores the persisted value', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'screen_security': false,
      });

      final cubit = SettingsCubit(screenGuard: ScreenGuard(channel: channel));
      await cubit.load();

      expect(cubit.state.screenSecurityEnabled, isFalse);
    });
  });
}
