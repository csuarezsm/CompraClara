import 'package:speech_to_text/speech_to_text.dart';

/// Dictado por voz en español.
class SpeechService {
  static final SpeechToText _stt = SpeechToText();
  static bool _ready = false;
  static void Function()? _onDone;

  static Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onStatus: (s) {
          if (s == 'done' || s == 'notListening') _onDone?.call();
        },
        onError: (_) => _onDone?.call(),
      );
    } catch (_) {
      _ready = false;
    }
    return _ready;
  }

  static bool get isListening => _stt.isListening;

  /// Escucha y va devolviendo el texto reconocido; [onDone] al terminar.
  static Future<bool> listen({
    required void Function(String text) onText,
    required void Function() onDone,
  }) async {
    if (!await init()) return false;
    String? locale;
    try {
      final locales = await _stt.locales();
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith('es')) {
          locale = l.localeId;
          if (l.localeId.toLowerCase().contains('es_es') || l.localeId.toLowerCase().contains('es-es')) {
            break;
          }
        }
      }
    } catch (_) {}
    var finished = false;
    _onDone = () {
      if (finished) return;
      finished = true;
      onDone();
    };
    await _stt.listen(
      onResult: (r) => onText(r.recognizedWords),
      localeId: locale,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
    );
    return true;
  }

  static Future<void> stop() => _stt.stop();
}
