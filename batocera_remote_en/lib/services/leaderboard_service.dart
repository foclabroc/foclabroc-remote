import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
<<<<<<< HEAD
import 'dart:typed_data';
=======
>>>>>>> 3a6a65d50b98427fe032e27c117dd488ac95bf81
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ═══════════════════════════════════════════════════════════════════════════
// ONLINE LEADERBOARD (Retro Jump) — Supabase through the REST API (no dependency)
// Boards: "daily" (daily run, same course for everyone) and "all"
// (all-time best score). Writes only through the SQL function
// submit_jump_score (signature + server-side sanity checks).
// Unsent scores (offline) are queued and sent again later.
// ═══════════════════════════════════════════════════════════════════════════

/// Fill in with your Supabase project (Project Settings → API).
/// URL: https://xxxx.supabase.co — key: "anon public" or "publishable".
const kLbUrl = 'https://wwyxfcdubdnwokeanigk.supabase.co';
const kLbKey = 'sb_publishable_M1Rdee-lSEzCfq81zjYq5Q_NgJ0a35z';

const _lbSalt = 'rj-lb#9d2e-foc';      // must match the SQL
<<<<<<< HEAD
const kLbDeviceKey = 'rjlb_device';     // not "jump_": survives a reset
=======
const _kDeviceKey  = 'rjlb_device';     // not "jump_": survives a reset
>>>>>>> 3a6a65d50b98427fe032e27c117dd488ac95bf81
const _kPendingKey = 'rjlb_pending';
const _kNameKey    = 'jump_lb_name';    // player name (exported with the save)
const lbAllDay = '2000-01-01';          // "day" of the all-time board

/// Score rejected by the server (checks): no point sending it again.
class _LbRejected implements Exception {
  final String msg;
  _LbRejected(this.msg);
}

class LbEntry {
  final String pid;
  final String name;
  final int score;
  final int hero;
<<<<<<< HEAD
  final int? coins;
  const LbEntry(this.pid, this.name, this.score, this.hero, [this.coins]);
=======
  const LbEntry(this.pid, this.name, this.score, this.hero);
>>>>>>> 3a6a65d50b98427fe032e27c117dd488ac95bf81
}

class LbRank {
  final int? rank;
  final int? score;
  final int total;
  const LbRank(this.rank, this.score, this.total);
}

<<<<<<< HEAD
class LbGhost {
  final String name;
  final int hero;
  final int score;
  final Uint8List data; // x (uint16, ‰ of width) + height (int32, px) every 0.1 s
  const LbGhost(this.name, this.hero, this.score, this.data);
}

=======
>>>>>>> 3a6a65d50b98427fe032e27c117dd488ac95bf81
class LbBoard {
  final List<LbEntry> top;
  final LbRank me;
  const LbBoard(this.top, this.me);
}

class Leaderboard {
  Leaderboard._();

  static bool get configured => kLbUrl.isNotEmpty && kLbKey.isNotEmpty;

  /// Local date "YYYY-MM-DD" (daily run key).
  static String today() {
    final d = DateTime.now();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

<<<<<<< HEAD
  /// Current week key: Monday "YYYY-MM-DD" (UTC, like the server).
  static String weekKey() {
    final n = DateTime.now().toUtc();
    final m = DateTime.utc(n.year, n.month, n.day).subtract(Duration(days: n.weekday - 1));
    return '${m.year}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
  }

  /// Days left before the Monday reset (1 to 7).
  static int weekDaysLeft() => 8 - DateTime.now().toUtc().weekday;

=======
>>>>>>> 3a6a65d50b98427fe032e27c117dd488ac95bf81
  /// Daily course seed (same for every player).
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
<<<<<<< HEAD
    var id = prefs.getString(kLbDeviceKey);
    if (id == null || id.length < 16) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(kLbDeviceKey, id);
=======
    var id = prefs.getString(_kDeviceKey);
    if (id == null || id.length < 16) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_kDeviceKey, id);
>>>>>>> 3a6a65d50b98427fe032e27c117dd488ac95bf81
    }
    return _device = id;
  }

<<<<<<< HEAD
  /// Takes over the online identity from a save (same player, same name, same scores).
  static Future<void> adoptDevice(String id) async {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLbDeviceKey, id);
    _device = id;
  }

=======
>>>>>>> 3a6a65d50b98427fe032e27c117dd488ac95bf81
  /// Public id (the real id stays secret).
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

  // ── Score submission ─────────────────────────────────────────────────────
  /// Sends the score; returns the rank, or null when offline (queued).
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
      return null; // rejected (inconsistent score…): no retry
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
    // Name actually assigned (taken → suffix, or previous name kept)
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
      // Daily runs too old: rejected by the server, drop them
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
  /// Sends queued scores again (called when opening the leaderboard).
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
          m.remove(k); // rejected by the server: no point retrying
        }
      }
      await prefs.setString(_kPendingKey, jsonEncode(m));
    } catch (_) {
      // still offline: will retry
    } finally {
      _flushing = false;
    }
  }

  // ── Reading ──────────────────────────────────────────────────────────────
  /// Top 50 + player rank; null when offline.
  static Future<LbBoard?> fetch(String mode, String day) async {
    if (!configured) return null;
    try {
      await flushPending();
      final dev = await deviceId();
      final rows = await _call('GET',
<<<<<<< HEAD
          '/rest/v1/jump_scores?select=pid,name,score,hero,coins&mode=eq.$mode&day=eq.$day'
=======
          '/rest/v1/jump_scores?select=pid,name,score,hero&mode=eq.$mode&day=eq.$day'
>>>>>>> 3a6a65d50b98427fe032e27c117dd488ac95bf81
          '&order=score.desc,updated_at.asc&limit=50');
      final me = await _rpc('jump_rank', {'p_device': dev, 'p_mode': mode, 'p_day': day});
      return LbBoard([
        for (final r in (rows as List))
          LbEntry(r['pid'] as String? ?? '', r['name'] as String? ?? '?',
<<<<<<< HEAD
              (r['score'] as num?)?.toInt() ?? 0, ((r['hero'] as num?)?.toInt() ?? 0),
              (r['coins'] as num?)?.toInt()),
=======
              (r['score'] as num?)?.toInt() ?? 0, ((r['hero'] as num?)?.toInt() ?? 0)),
>>>>>>> 3a6a65d50b98427fe032e27c117dd488ac95bf81
      ], _rankFrom(me));
    } catch (_) {
      return null;
    }
  }

<<<<<<< HEAD
  /// Player's coins, shown on the leaderboard (no effect when offline).
  static Future<void> setCoins(int coins) async {
    if (!configured || coins < 0) return;
    try {
      final dev = await deviceId();
      await _rpc('set_jump_coins', {'p_device': dev, 'p_coins': coins, 'p_sig': _sig([dev, coins])});
    } catch (_) {}
  }

  /// Ghost: path of the day's best score (ignored by the server if not the best).
  static Future<void> uploadGhost(String day, int score, String data) async {
    if (!configured || data.isEmpty) return;
    try {
      final dev = await deviceId();
      final h = sha256.convert(utf8.encode(data)).toString();
      await _rpc('submit_jump_ghost',
          {'p_device': dev, 'p_day': day, 'p_score': score, 'p_data': data, 'p_sig': _sig([dev, day, score, h])});
    } catch (_) {}
  }

  /// Ghost of the day's best player (excluding yourself); null if none or offline.
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

=======
>>>>>>> 3a6a65d50b98427fe032e27c117dd488ac95bf81
  static const renameOk = 0;      // saved
  static const renameTaken = 1;   // already used by another player
  static const renameOffline = 2; // kept locally, sent with the next score
  static const renameInvalid = 3;

  /// Changes the (unique) name locally and on every score already sent.
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

/// Seeded pseudo-random generator (mulberry32): same number sequence
/// on every phone and every Dart version.
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
