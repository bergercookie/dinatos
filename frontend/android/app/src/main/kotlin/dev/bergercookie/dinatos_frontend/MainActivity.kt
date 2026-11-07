package dev.bergercookie.dinatos_frontend

import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var shortcutChannel: MethodChannel? = null

    // True when Android recreated this activity (for example from the recents
    // screen after the process died): the intent it re-delivers is the original
    // launch intent, and a pinned shortcut's must not start a second workout.
    private var restored = false
    private var launchHandled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        restored = savedInstanceState != null
        super.onCreate(savedInstanceState)
    }

    // The bridge for routine shortcuts is deliberately thin: pin a shortcut, and
    // hand over the routine id of a tapped one. Everything else (sign-in, loading
    // the routine, the "workout already in progress" question) is Dart, in
    // lib/features/routines/routine_shortcuts.dart. The channel, method and
    // intent names below must match that file; a test fails if they drift.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SHORTCUT_CHANNEL)
        channel.setMethodCallHandler { call, result -> onShortcutCall(call, result) }
        shortcutChannel = channel
    }

    // The app is already running (launchMode singleTop) and a shortcut was tapped.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val routineId = routineIdOf(intent) ?: return
        intent.removeExtra(EXTRA_ROUTINE_ID)
        shortcutChannel?.invokeMethod(METHOD_ROUTINE_LAUNCHED, routineId)
    }

    private fun onShortcutCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_PIN_SHORTCUT -> pinShortcut(call, result)
            METHOD_INITIAL_ROUTINE_ID -> result.success(takeLaunchRoutineId())
            else -> result.notImplemented()
        }
    }

    // The routine whose shortcut cold-started the app, reported once.
    private fun takeLaunchRoutineId(): Int? {
        if (restored || launchHandled) return null
        launchHandled = true
        val routineId = routineIdOf(intent)
        intent.removeExtra(EXTRA_ROUTINE_ID)
        return routineId
    }

    private fun routineIdOf(intent: Intent?): Int? {
        if (intent?.action != ACTION_START_ROUTINE) return null
        val routineId = intent.getIntExtra(EXTRA_ROUTINE_ID, -1)
        return if (routineId > 0) routineId else null
    }

    private fun pinShortcut(call: MethodCall, result: MethodChannel.Result) {
        val routineId = call.argument<Int>("routineId")
        val name = call.argument<String>("name")
        if (routineId == null || name == null) {
            result.error("bad_arguments", "routineId and name are required", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.success(false)
            return
        }
        val manager = getSystemService(ShortcutManager::class.java)
        if (manager == null || !manager.isRequestPinShortcutSupported) {
            result.success(false)
            return
        }
        val launch = Intent(this, MainActivity::class.java)
            .setAction(ACTION_START_ROUTINE)
            .putExtra(EXTRA_ROUTINE_ID, routineId)
        val label = name.ifBlank { "Routine" }
        // A stable id per routine: pinning again updates the pinned shortcut
        // (a renamed routine) instead of adding a duplicate.
        val shortcut = ShortcutInfo.Builder(this, "routine-$routineId")
            .setShortLabel(label)
            .setLongLabel(label)
            .setIcon(Icon.createWithResource(this, R.mipmap.ic_launcher))
            .setIntent(launch)
            .build()
        result.success(manager.requestPinShortcut(shortcut, null))
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

    private companion object {
        const val SHORTCUT_CHANNEL = "dev.bergercookie.dinatos/shortcuts"
        const val METHOD_PIN_SHORTCUT = "pinShortcut"
        const val METHOD_INITIAL_ROUTINE_ID = "initialRoutineId"
        const val METHOD_ROUTINE_LAUNCHED = "routineLaunched"
        const val ACTION_START_ROUTINE = "dev.bergercookie.dinatos.action.START_ROUTINE"
        const val EXTRA_ROUTINE_ID = "routine_id"
    }
}
