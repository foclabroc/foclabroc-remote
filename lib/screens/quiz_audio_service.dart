import 'package:flutter/services.dart';

/// Service audio léger pour le Quiz.
/// Utilise un MethodChannel vers AudioTrack Android natif.
/// Aucune dépendance externe requise.
class QuizAudio {
  QuizAudio._();

  static const _ch = MethodChannel('com.example.batocera_remote/audio');

  static bool _enabled = true;

  static bool get enabled => _enabled;
  static set enabled(bool v) => _enabled = v;

  /// Bonne réponse ✅
  static Future<void> correct() => _play('playCorrect');

  /// Mauvaise réponse ❌
  static Future<void> wrong() => _play('playWrong');

  /// Temps écoulé ⏱
  static Future<void> timeout() => _play('playTimeout');

  /// Victoire 🏆 (score >= 70%)
  static Future<void> win() => _play('playWin');

  /// Défaite 💀 (score < 50%)
  static Future<void> lose() => _play('playLose');

  /// Tick timer ⚡ (5 dernières secondes)
  static Future<void> tick() => _play('playTick');

  static Future<void> _play(String method) async {
    if (!_enabled) return;
    try {
      await _ch.invokeMethod(method);
    } catch (_) {
      // Silencieux si le canal n'est pas disponible (ex: iOS, desktop)
    }
  }
}
