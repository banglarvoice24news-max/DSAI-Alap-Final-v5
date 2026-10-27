import 'package:flutter/services.dart';

/// Toggles the native anti-screenshot shield.
///
/// The Android host enables `FLAG_SECURE` before the first frame
/// (defense-in-depth) so screenshots, screen recording, and recent-task
/// thumbnails are blocked. Settings can switch it off for the current session
/// through this wrapper.
///
/// Platform-channel failures are swallowed on purpose: the handler does not
/// exist in unit tests or on desktop/web, and some managed devices reject the
/// flag. In every failure mode the secure default (shield on) is kept, so the
/// app never crashes and never silently downgrades privacy.
class ScreenGuard {
  ScreenGuard({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.nexus.comm/security';
  static const String _setSecureScreen = 'setSecureScreen';

  final MethodChannel _channel;

  /// Applies [enabled] to the native window. Returns the effective state.
  Future<bool> setEnabled(bool enabled) async {
    if (!enabled) {
      try {
        await _channel.invokeMethod<bool>(_setSecureScreen, false);
        return false;
      } on MissingPluginException {
        return true;
      } on PlatformException {
        return true;
      }
    }
    try {
      await _channel.invokeMethod<bool>(_setSecureScreen, true);
    } on MissingPluginException {
      // Shield is already applied natively at launch.
    } on PlatformException {
      // Shield is already applied natively at launch.
    }
    return true;
  }
}
