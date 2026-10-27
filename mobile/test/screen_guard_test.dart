import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_comm/core/security/screen_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(ScreenGuard.channelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('setEnabled(false) forwards false to the native shield', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    final guard = ScreenGuard(channel: channel);
    final effective = await guard.setEnabled(false);

    expect(effective, isFalse);
    expect(calls.single.method, 'setSecureScreen');
    expect(calls.single.arguments, false);
  });

  test('setEnabled(true) forwards true and reports shielded', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    final guard = ScreenGuard(channel: channel);
    final effective = await guard.setEnabled(true);

    expect(effective, isTrue);
    expect(calls.single.arguments, true);
  });

  test('keeps the secure default when the channel is unavailable', () async {
    final guard = ScreenGuard(channel: channel);

    expect(await guard.setEnabled(false), isTrue);
    expect(await guard.setEnabled(true), isTrue);
  });

  test('keeps the secure default when the platform rejects the change',
      () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'disabled_by_policy');
    });

    final guard = ScreenGuard(channel: channel);
    expect(await guard.setEnabled(false), isTrue);
  });
}
