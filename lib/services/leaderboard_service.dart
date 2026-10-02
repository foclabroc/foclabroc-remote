import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// CLASSEMENT EN LIGNE (Rétro Jump) — Supabase via l'API REST (sans dépendance)
// Tableaux : « daily » (partie du jour, même parcours pour tous) et « all »
// (meilleur score de tous les temps). Écriture uniquement via la fonction SQL
// submit_jump_score (signature + contrôles de cohérence côté serveur).
// Scores non envoyés (hors ligne) : mis en file d'attente et renvoyés plus tard.
// ═══════════════════════════════════════════════════════════════════════════

/// À remplir avec ton projet Supabase (Project Settings → API).
/// URL : https://xxxx.supabase.co — clé : « anon public » ou « publishable ».
const kLbUrl = 'https://wwyxfcdubdnwokeanigk.supabase.co';
const kLbKey = 'sb_publishable_M1Rdee-lSEzCfq81zjYq5Q_NgJ0a35z';

const _lbSalt = 'rj-lb#9d2e-foc';      // doit être identique dans le SQL
const kLbDeviceKey = 'rjlb_device';     // hors « jump_ » : survit au reset
const _kPendingKey = 'rjlb_pending';
const _kNameKey    = 'jump_lb_name';    // pseudo (exporté avec la sauvegarde)
const lbAllDay = '2000-01-01';          // « jour » du tableau tous temps

/// Score refusé par le serveur (contrôles) : inutile de le renvoyer.
class _LbRejected implements Exception {
  final String msg;
  _LbRejected(this.msg);
}

class LbEntry {
  final String pid;
  final String name;
  final int score;
  final int hero;
  final int? coins;
  const LbEntry(this.pid, this.name, this.score, this.hero, [this.coins]);
}

class LbRank {
  final int? rank;
  final int? score;
  final int total;
  const LbRank(this.rank, this.score, this.total);
}

class LbGhost {
  final String name;
  final int hero;
  final int score;
  final Uint8List data; // x (uint16, ‰ de la largeur) + hauteur (int32, px) tous les 0,1 s
  const LbGhost(this.name, this.hero, this.score, this.data);
}

class LbBoard {
  final List<LbEntry> top;
  final LbRank me;
  const LbBoard(this.top, this.me);
}

class Leaderboard {
  Leaderboard._();

  static bool get configured => kLbUrl.isNotEmpty && kLbKey.isNotEmpty;

  /// Date locale « AAAA-MM-JJ » (clé de la partie du jour).
  static String today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Clé de la semaine en cours : lundi « AAAA-MM-JJ » (UTC, comme le serveur).
  static String weekKey() {
    final n = DateTime.now().toUtc();
    final m = DateTime.utc(n.year, n.month, n.day).subtract(Duration(days: n.weekday - 1));
    return '${m.year}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
  }

  /// Jours restants avant la remise à zéro du lundi (1 à 7).
  static int weekDaysLeft() => 8 - DateTime.now().toUtc().weekday;

  /// Graine du parcours du jour (identique pour tous les joueurs).
  static int seedFor(String day) {
    var h = 0x811C9DC5;
    for (final c in day.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static String? _device;
  static Future<String> deviceId() async {
    if (_device != null) return _device!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(kLbDeviceKey);
    if (id == null || id.length < 16) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(kLbDeviceKey, id);
    }
    return _device = id;
  }

  /// Reprend l'identité en ligne d'une sauvegarde (même joueur, même pseudo, mêmes scores).
  static Future<void> adoptDevice(String id) async {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLbDeviceKey, id);
    _device = id;
  }

  /// Identifiant public (le vrai identifiant reste secret).
  static Future<String> publicId() async =>
      sha256.convert(utf8.encode(await deviceId())).toString().substring(0, 16);

  static Future<String?> name() async {
    final prefs = await SharedPreferences.getInstance();
    final n = prefs.getString(_kNameKey);
    return (n == null || n.trim().isEmpty) ? null : n;
  }

  static String clean(String n) {
    final s = n.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
    return s.length > 16 ? s.substring(0, 16) : s;
  }

  static String _sig(List<Object> parts) =>
      sha256.convert(utf8.encode([_lbSalt, ...parts].join('|'))).toString();

  // ── HTTP ──────────────────────────────────────────────────────────────────
  static Future<dynamic> _call(String method, String path, [Map<String, dynamic>? body]) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.openUrl(method, Uri.parse('$kLbUrl$path')).timeout(const Duration(seconds: 8));
      req.headers.set('apikey', kLbKey);
      if (kLbKey.startsWith('eyJ')) req.headers.set('Authorization', 'Bearer $kLbKey');
      req.headers.contentType = ContentType.json;
      if (body != null) req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 8));
      final txt = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 8));
      if (res.statusCode >= 400 && res.statusCode < 500) throw _LbRejected(txt);
      if (res.statusCode >= 300) throw HttpException('HTTP ${res.statusCode}');
      return txt.isEmpty ? null : jsonDecode(txt);
    } finally {
      client.close(force: true);
    }
  }

  static Future<dynamic> _rpc(String fn, Map<String, dynamic> body) => _call('POST', '/rest/v1/rpc/$fn', body);

  // ── Envoi d'un score ─────────────────────────────────────────────────────
  /// Envoie le score ; renvoie le rang, ou null si hors ligne (mis en attente).
  static Future<LbRank?> submit({
    required String mode,
    required String day,
    required int score,
    required int hero,
    required int time,
    required String name,
  }) async {
    if (!configured || score <= 0) return null;
    try {
      final r = await _send(mode, day, score, hero, time, name);
      unawaited(flushPending());
      return r;
    } on _LbRejected catch (_) {
      return null; // refusé (score incohérent…) : pas de nouvel essai
    } catch (_) {
      await _queue(mode, day, score, hero, time);
      return null;
    }
  }

  static Future<LbRank> _send(String mode, String day, int score, int hero, int time, String name) async {
    final dev = await deviceId();
    final res = await _rpc('submit_jump_score', {
      'p_device': dev,
      'p_name': clean(name),
      'p_mode': mode,
      'p_day': day,
      'p_score': score,
      'p_hero': hero,
      'p_time': time,
      'p_sig': _sig([dev, mode, day, score, time, hero]),
    });
    // Pseudo réellement attribué (déjà pris → suffixe, ou ancien pseudo conservé)
    final row = res is List ? (res.isEmpty ? null : res.first) : res;
    final given = row is Map ? row['name'] as String? : null;
    if (given != null && given.isNotEmpty && given != clean(name)) await setLocalName(given);
    return _rankFrom(res);
  }

  static LbRank _rankFrom(dynamic res) {
    final row = res is List ? (res.isEmpty ? null : res.first) : res;
    if (row is! Map) return const LbRank(null, null, 0);
    return LbRank((row['rank'] as num?)?.toInt(), (row['score'] as num?)?.toInt(), (row['total'] as num?)?.toInt() ?? 0);
  }

  static Future<void> _queue(String mode, String day, int score, int hero, int time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = Map<String, dynamic>.from(jsonDecode(prefs.getString(_kPendingKey) ?? '{}') as Map);
      final k = '$mode|$day';
      final old = (m[k] as Map?)?['s'] as int? ?? -1;
      if (score > old) m[k] = {'s': score, 'h': hero, 't': time};
      // Parties du jour trop anciennes : refusées par le serveur, on les oublie
      final keep = today();
      m.removeWhere((key, _) => key.startsWith('daily|') && key.compareTo('daily|$keep') < 0 &&
          key != 'daily|${_yesterday()}');
      await prefs.setString(_kPendingKey, jsonEncode(m));
    } catch (_) {}
  }

  static String _yesterday() {
    final d = DateTime.now().subtract(const Duration(days: 1));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  static bool _flushing = false;
  /// Renvoie les scores restés en attente (appelé à l'ouverture du classement).
  static Future<void> flushPending() async {
    if (!configured || _flushing) return;
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final m = Map<String, dynamic>.from(jsonDecode(prefs.getString(_kPendingKey) ?? '{}') as Map);
      if (m.isEmpty) return;
      final n = await name() ?? '?';
      for (final k in m.keys.toList()) {
        final p = k.split('|');
        final v = m[k] as Map;
        try {
          await _send(p[0], p[1], v['s'] as int, v['h'] as int, v['t'] as int, n);
          m.remove(k);
        } on _LbRejected catch (_) {
          m.remove(k); // refusé par le serveur : inutile de réessayer
        }
      }
      await prefs.setString(_kPendingKey, jsonEncode(m));
    } catch (_) {
      // toujours hors ligne : on réessaiera
    } finally {
      _flushing = false;
    }
  }

  // ── Lecture ──────────────────────────────────────────────────────────────
  /// Top 50 + rang du joueur ; null si hors ligne.
  static Future<LbBoard?> fetch(String mode, String day) async {
    if (!configured) return null;
    try {
      await flushPending();
      final dev = await deviceId();
      final rows = await _call('GET',
          '/rest/v1/jump_scores?select=pid,name,score,hero,coins&mode=eq.$mode&day=eq.$day'
          '&order=score.desc,updated_at.asc&limit=50');
      final me = await _rpc('jump_rank', {'p_device': dev, 'p_mode': mode, 'p_day': day});
      return LbBoard([
        for (final r in (rows as List))
          LbEntry(r['pid'] as String? ?? '', r['name'] as String? ?? '?',
              (r['score'] as num?)?.toInt() ?? 0, ((r['hero'] as num?)?.toInt() ?? 0),
              (r['coins'] as num?)?.toInt()),
      ], _rankFrom(me));
    } catch (_) {
      return null;
    }
  }

  /// Pièces du joueur, affichées dans le classement (sans effet hors ligne).
  static Future<void> setCoins(int coins) async {
    if (!configured || coins < 0) return;
    try {
      final dev = await deviceId();
      await _rpc('set_jump_coins', {'p_device': dev, 'p_coins': coins, 'p_sig': _sig([dev, coins])});
    } catch (_) {}
  }

  /// Fantôme : trajet du meilleur score du jour (ignoré par le serveur si ce n'est pas le meilleur).
  static Future<void> uploadGhost(String day, int score, String data) async {
    if (!configured || data.isEmpty) return;
    try {
      final dev = await deviceId();
      final h = sha256.convert(utf8.encode(data)).toString();
      await _rpc('submit_jump_ghost',
          {'p_device': dev, 'p_day': day, 'p_score': score, 'p_data': data, 'p_sig': _sig([dev, day, score, h])});
    } catch (_) {}
  }

  /// Fantôme du meilleur joueur du jour (hors soi-même) ; null si aucun ou hors ligne.
  static Future<LbGhost?> topGhost(String day) async {
    if (!configured) return null;
    try {
      final dev = await deviceId();
      final res = await _rpc('jump_top_ghost', {'p_device': dev, 'p_day': day});
      final row = res is List ? (res.isEmpty ? null : res.first) : res;
      if (row is! Map || row['data'] == null) return null;
      return LbGhost(row['name'] as String? ?? '?', (row['hero'] as num?)?.toInt() ?? 0,
          (row['score'] as num?)?.toInt() ?? 0, base64Decode(row['data'] as String));
    } catch (_) {
      return null;
    }
  }

  static const renameOk = 0;      // enregistré
  static const renameTaken = 1;   // déjà pris par un autre joueur
  static const renameOffline = 2; // gardé en local, envoyé avec le prochain score
  static const renameInvalid = 3;

  /// Change le pseudo (unique) localement et sur tous les scores déjà envoyés.
  static Future<int> rename(String newName) async {
    final n = clean(newName);
    if (n.isEmpty) return renameInvalid;
    if (!configured) {
      await setLocalName(n);
      return renameOk;
    }
    try {
      final dev = await deviceId();
      final res = await _rpc('rename_jump_player', {'p_device': dev, 'p_name': n, 'p_sig': _sig([dev, n])});
      if (res == 'taken') return renameTaken;
      await setLocalName(n);
      return renameOk;
    } on _LbRejected catch (_) {
      return renameInvalid;
    } catch (_) {
      await setLocalName(n);
      return renameOffline;
    }
  }

  static Future<void> setLocalName(String n) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNameKey, clean(n));
  }
}

/// Générateur pseudo-aléatoire à graine (mulberry32) : même suite de nombres
/// sur tous les téléphones et toutes les versions de Dart.
class SeededRandom implements Random {
  int _s;
  SeededRandom(int seed) : _s = seed & 0xFFFFFFFF;

  int _next32() {
    _s = (_s + 0x6D2B79F5) & 0xFFFFFFFF;
    var t = _s;
    t = _imul(t ^ (t >> 15), t | 1);
    t ^= (t + _imul(t ^ (t >> 7), t | 61)) & 0xFFFFFFFF;
    return (t ^ (t >> 14)) & 0xFFFFFFFF;
  }

  static int _imul(int a, int b) => (a * b) & 0xFFFFFFFF;

  @override
  double nextDouble() => _next32() / 4294967296.0;

  @override
  int nextInt(int max) {
    if (max <= 0) throw RangeError.range(max, 1, null, 'max');
    return (nextDouble() * max).floor();
  }

  @override
  bool nextBool() => (_next32() & 1) == 1;
}
