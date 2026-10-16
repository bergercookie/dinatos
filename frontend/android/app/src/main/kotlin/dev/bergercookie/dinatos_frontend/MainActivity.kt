package dev.bergercookie.dinatos_frontend

import android.os.Build
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // The "Keep screen on" setting: FLAG_KEEP_SCREEN_ON stops the screen timing
    // out while this window is in the foreground. It is not a wake lock, so it
    // costs nothing once the app is left or the phone is locked by hand.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.bergercookie.dinatos/screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "setShowWhenLocked") {
                    // Only draws the app above the keyguard; the phone stays
                    // locked, so nothing outside the app becomes reachable.
                    val on = call.arguments as? Boolean ?: false
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                        setShowWhenLocked(on)
                    } else if (on) {
                        @Suppress("DEPRECATION")
                        window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
                    } else {
                        @Suppress("DEPRECATION")
                        window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
                    }
                    result.success(null)
                } else if (call.method == "setKeepScreenOn") {
                    val on = call.arguments as? Boolean ?: false
                    if (on) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    // Locking the phone (or leaving the app) with the keyboard up can make
    // Android skip the "keyboard is gone" window-insets update on return, so
    // Flutter keeps a stale keyboard-sized bottom inset: the UI stays cropped
    // until the keyboard is opened and closed again. Re-dispatching the
    // insets whenever the window regains focus makes the system report the
    // real, current ones.
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) refreshInsets()
    }

    override fun onResume() {
        super.onResume()
        refreshInsets()
    }

    private fun refreshInsets() {
        val decor = window.decorView
        decor.requestApplyInsets()
        // The IME state can settle a beat after resume; ask again once it has.
        decor.postDelayed({ decor.requestApplyInsets() }, 300)
    }
}
