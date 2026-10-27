package com.nexus.comm

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Host activity.
 *
 * Anti-screenshot shield: FLAG_SECURE is applied before the first frame so the
 * window can never be captured by screenshots, screen recording, or the recent
 * tasks thumbnail. The flag is enabled unconditionally at launch as
 * defense-in-depth; the `com.nexus.comm/security` channel lets Dart turn it off
 * when the user disables "screen security" in Settings.
 */
class MainActivity : FlutterFragmentActivity() {
    private val securityChannel = "com.nexus.comm/security"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applySecureScreen(true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Defense-in-depth: re-assert FLAG_SECURE once the Flutter engine is
        // wired so process re-attach / engine reconfiguration can never expose
        // a frame before the shield is on.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, securityChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecureScreen" -> {
                        applySecureScreen(call.arguments as? Boolean ?: true)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun applySecureScreen(enabled: Boolean) {
        if (enabled) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE,
            )
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
