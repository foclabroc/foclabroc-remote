import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service audio léger pour le Quiz.
/// Utilise un MethodChannel vers AudioTrack Android natif.
/// Aucune dépendance externe requise.
class QuizAudio {
  QuizAudio._();

  static const _ch = MethodChannel('com.foclabroc.batocera_remote/audio');

  static bool _enabled = true;

  static bool get enabled => _enabled;
  static set enabled(bool v) {
    _enabled = v;
    // Son coupé : musique arrêtée ; son remis : la musique du jeu ouvert reprend
    if (!v) {
      _invoke('musicStop');
    } else if (_track != null) {
      musicStart(_track!);
    }
  }

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

  // ── Mini-jeux : effets et musique ─────────────────────────────────────────

  /// Effet chiptune (jump, spring, coin, stomp, powerup, shield, hurt, break,
  /// logo, tier, continue).
  static Future<void> sfx(String name) => _play('sfx', {'name': name});

  static const _kMusicKey = 'mini_music';
  static bool _music = true;
  static bool _musicLoaded = false;
  static int? _track; // musique du jeu actuellement ouvert

  /// Musique des mini-jeux activée (réglage mémorisé).
  static bool get musicEnabled => _music;

  static Future<void> loadPrefs() async {
    if (_musicLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _music = prefs.getBool(_kMusicKey) ?? true;
      _musicLoaded = true;
    } catch (_) {}
  }

  static Future<void> setMusicEnabled(bool v) async {
    _music = v;
    _musicLoaded = true;
    if (!v) {
      _invoke('musicStop');
    } else if (_track != null) {
      musicStart(_track!);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kMusicKey, v);
    } catch (_) {}
  }

  /// Lance la musique [track] en boucle (0 = Rétro Jump, 1 = Breakout).
  static Future<void> musicStart(int track) async {
    _track = track;
    if (!_enabled || !_music) return;
    await _invoke('musicStart', {'track': track});
  }

  static Future<void> musicStop() {
    _track = null;
    return _invoke('musicStop');
  }
  static Future<void> musicPause() => _invoke('musicPause');
  static Future<void> musicResume() async {
    if (!_enabled || !_music) return;
    await _invoke('musicResume');
  }

  static Future<void> _play(String method, [Map<String, dynamic>? args]) async {
    if (!_enabled) return;
    await _invoke(method, args);
  }

  static Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    try {
      await _ch.invokeMethod(method, args);
    } catch (_) {
      // Silencieux si le canal n'est pas disponible (ex: iOS, desktop)
    }
  }
}
