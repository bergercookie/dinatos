package dev.bergercookie.dinatos_frontend

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
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
