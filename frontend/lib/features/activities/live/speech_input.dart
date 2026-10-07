import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Dictation, as the bulk-add sheet needs it: start, get text as it is
/// recognised, stop. Behind an interface so widget tests need no microphone
/// and no platform plugin.
abstract class SpeechInput {
  /// Whether this platform offers dictation at all. Only Android is wired up
  /// (it uses the system's own recogniser); everywhere else the sheet is
  /// typing-only and does not show a microphone.
  bool get isSupported;

  /// Starts listening. [onText] receives the *whole* transcript so far each
  /// time it changes; [onDone] fires once when listening stops, for any reason
  /// (the person stopped it, a long pause, an error). Resolves with null if
  /// listening began, or with a message to show the person if it could not
  /// (microphone permission refused, no recogniser installed).
  Future<String?> start({required void Function(String text) onText, required VoidCallback onDone});

  Future<void> stop();
}

final speechInputProvider = Provider<SpeechInput>((ref) => SystemSpeechInput());

/// Android's own speech recogniser through the `speech_to_text` plugin.
class SystemSpeechInput implements SpeechInput {
  final SpeechToText _speech = SpeechToText();
  VoidCallback? _onDone;

  @override
  bool get isSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<String?> start({
    required void Function(String text) onText,
    required VoidCallback onDone,
  }) async {
    _onDone = onDone;
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == SpeechToText.notListeningStatus || status == SpeechToText.doneStatus) {
          _finish();
        }
      },
      onError: (_) => _finish(),
    );
    if (!available) {
      _onDone = null;
      return 'Voice input is not available. Allow microphone access for Dinatos in '
          "your phone's settings, and check that a speech recognition service is installed.";
    }
    await _speech.listen(
      onResult: (result) => onText(result.recognizedWords),
      // A list is dictated with pauses between the items, so wait for a long
      // silence before giving up, and keep partial results flowing.
      listenOptions: SpeechListenOptions(
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: const Duration(seconds: 6),
        listenFor: const Duration(minutes: 2),
      ),
    );
    return null;
  }

  void _finish() {
    final done = _onDone;
    _onDone = null;
    done?.call();
  }

  @override
  Future<void> stop() async {
    await _speech.stop();
    _finish();
  }
}
