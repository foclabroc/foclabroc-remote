import 'dart:async';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'quiz_audio_service.dart';

// ─── Constantes ───────────────────────────────────────────────────────────────

const _kBestScoreKey  = 'breakout_best_score';
const _kBestLevelKey  = 'breakout_best_level';
const _kBestNameKey   = 'breakout_best_name';

const _brickW       = 72.0;
const _brickH       = 36.0;
const _brickCols    = 5;
const _brickRows    = 5;
const _brickPadX    = 8.0;
const _brickPadY    = 6.0;
const _brickOffsetY = 80.0;
const _paddleW      = 90.0;
const _paddleH      = 18.0;
const _ballR        = 8.0;
const _ballSpeed    = 400.0;
const _bonusAsset     = 'assets/game/batocera_bonus.png';
const _malusAsset     = 'assets/game/recalbox_malus.png';
const _multiballAsset = 'assets/game/mame_multiball.png';
const _paddleWMin   = 50.0;
const _paddleWMax   = 160.0;
const _powerSpeed   = 120.0;
const _slowDuration  = 5.0;
const _shootAsset   = 'assets/game/lightgun_shoot.png';
const _shootDuration = 3.0;
const _shootInterval = 0.3; // secondes entre chaque tir
const _bulletR       = 5.0;
const _bulletSpeed   = 600.0;

const _consoleAssets = [
  'assets/game/3ds.png',        'assets/game/64dd.png',       'assets/game/amiga1200.png',
  'assets/game/amigacd32.png',  'assets/game/apple2.png',     'assets/game/atari7800.png',
  'assets/game/atarijaguar.png','assets/game/cps3.png',        'assets/game/fbneo.png',
  'assets/game/gb.png',         'assets/game/gba.png',         'assets/game/gbc.png',
  'assets/game/gottlieb.png',   'assets/game/mame.png',        'assets/game/mastersystem.png',
  'assets/game/megadrive.png',  'assets/game/model3.png',      'assets/game/n64.png',
  'assets/game/naomi.png',      'assets/game/nes.png',         'assets/game/ps2.png',
  'assets/game/ps3.png',        'assets/game/psp.png',         'assets/game/psvita.png',
  'assets/game/psx.png',        'assets/game/segacd.png',      'assets/game/snes.png',
  'assets/game/switch.png',     'assets/game/taito.png',       'assets/game/triforce.png',
  'assets/game/vpinball.png',   'assets/game/wii.png',         'assets/game/wiiu.png',
  'assets/game/xbox.png',       'assets/game/xbox360.png',
];

// ─── Modèles ──────────────────────────────────────────────────────────────────

class _PowerUp {
  Offset pos;
  bool isBonus;
  bool isSlow;
  bool isShoot;
  ui.Image? image;
  _PowerUp({required this.pos, required this.isBonus, this.isSlow = false, this.isShoot = false, this.image});
}

class _Brick {
  Rect rect;
  bool alive = true;
  ui.Image? image;
  int hp;
  bool isBonus;
  bool isMalus;
  bool isMultiball;
  Color brickColor;
  _Brick({required this.rect, required this.hp, this.image,
      this.isBonus = false, this.isMalus = false, this.isMultiball = false,
      this.brickColor = const Color(0xFF1C2230)});
}

// Balle pistolet
class _Bullet {
  Offset pos;
  _Bullet({required this.pos});
}

// Score pop flottant
class _ScorePop {
  Offset pos;
  String text;
  double life; // 0..1
  _ScorePop({required this.pos, required this.text, this.life = 1.0});
}

// Particule
class _Particle {
  Offset pos;
  Offset vel;
  Color color;
  double life; // 0..1
  _Particle({required this.pos, required this.vel, required this.color, this.life = 1.0});
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAGE D'ACCUEIL
// ═══════════════════════════════════════════════════════════════════════════════

class BreakoutScreen extends StatefulWidget {
  const BreakoutScreen({super.key});
  @override
  State<BreakoutScreen> createState() => _BreakoutScreenState();
}

class _BreakoutScreenState extends State<BreakoutScreen> {
  int _bestScore = 0;
  int _bestLevel = 1;
  String _bestName = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadBest();
  }

  Future<void> _loadBest() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bestScore = prefs.getInt(_kBestScoreKey) ?? 0;
      _bestLevel = prefs.getInt(_kBestLevelKey) ?? 1;
      _bestName  = prefs.getString(_kBestNameKey) ?? '';
      _loading   = false;
    });
  }

  void _onGameFinished(int score, int level, int bricks, int powerUpsCollected) async {
    final prefs = await SharedPreferences.getInstance();
    bool newRecord = score > _bestScore;
    if (score > _bestScore) { await prefs.setInt(_kBestScoreKey, score); _bestScore = score; }
    if (level > _bestLevel) { await prefs.setInt(_kBestLevelKey, level); _bestLevel = level; }
    if (newRecord && mounted) {
      final ctrl = TextEditingController();
      final name = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Text('🏆 New record!',
              style: TextStyle(color: Colors.amberAccent, fontSize: 18, fontWeight: FontWeight.w700)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('$score pts', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 12,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Your name...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                counterStyle: const TextStyle(color: Colors.white38),
              ),
              onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('Skip')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
          ],
        ),
      );
      final finalName = (name ?? '').isEmpty ? 'Anonymous' : name!;
      await prefs.setString(_kBestNameKey, finalName);
      if (mounted) setState(() => _bestName = finalName);
    } else if (mounted) {
      setState(() {});
    }
  }

  void _startGame() {
    Navigator.of(context, rootNavigator: false).push(MaterialPageRoute(
      builder: (_) => _BreakoutGame(onFinished: _onGameFinished),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(64, 8, 16, 0),
            child: Row(children: [
              Text('Breakout', style: Theme.of(context).textTheme.headlineMedium),
              const Spacer(),
              StatefulBuilder(
                builder: (ctx, setS) => GestureDetector(
                  onTap: () => setS(() => QuizAudio.enabled = !QuizAudio.enabled),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Icon(
                      QuizAudio.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      color: QuizAudio.enabled ? Colors.white54 : Colors.white24,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              child: Column(children: [
                // Hero
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2230),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: accent.withOpacity(0.2)),
                  ),
                  child: Column(children: [
                    Container(
                      width: 100, height: 100,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withOpacity(0.1)),
                      child: Icon(Icons.sports_tennis_rounded, size: 56, color: accent),
                    ),
                    const SizedBox(height: 16),
                    const Text('Retro Breakout 🎮',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                      'Destroy retro console logos!\nCollect power-ups and activate multiball.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),
                // Meilleur score
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2230),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.amberAccent.withOpacity(0.25)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: Colors.amberAccent.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Best score',
                            style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                        const SizedBox(height: 2),
                        _loading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent))
                            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(_bestScore == 0 ? '— pts' : '$_bestScore pts',
                                    style: const TextStyle(color: Colors.amberAccent, fontSize: 28, fontWeight: FontWeight.w900)),
                                if (_bestName.isNotEmpty)
                                  Text('par $_bestName', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              ]),
                      ]),
                    ),
                    if (_bestScore > 0)
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Row(children: [
                          const Icon(Icons.layers_rounded, color: Colors.cyanAccent, size: 13),
                          const SizedBox(width: 4),
                          Text('Nv. $_bestLevel', style: const TextStyle(color: Colors.cyanAccent, fontSize: 14, fontWeight: FontWeight.w700)),
                        ]),
                        const Text('best level', style: TextStyle(color: Colors.white38, fontSize: 10)),
                      ]),
                  ]),
                ),
                const SizedBox(height: 16),
                if (_bestScore > 0) ...[
                  Row(children: [
                    _StatCard(icon: Icons.star_rounded, color: Colors.amberAccent, label: 'Score', value: '$_bestScore'),
                    const SizedBox(width: 10),
                    _StatCard(icon: Icons.layers_rounded, color: Colors.cyanAccent, label: 'Level', value: '$_bestLevel'),
                    const SizedBox(width: 10),
                    _StatCard(icon: Icons.grid_view_rounded, color: Colors.purpleAccent, label: 'Bricks', value: '${_brickCols * _brickRows * _bestLevel}+'),
                  ]),
                  const SizedBox(height: 16),
                ],
                // Règles
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: const Color(0xFF1C2230), borderRadius: BorderRadius.circular(16)),
                  child: Column(children: [
                    _RuleRow(icon: Icons.swipe_rounded, color: Colors.cyanAccent, text: 'Slide to move the paddle'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.favorite_rounded, color: Colors.redAccent, text: '3 lives — lose all balls = 1 life'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.star_rounded, color: Colors.amberAccent, text: '10 pts per brick + combo bonus 🔥'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.speed_rounded, color: Colors.orangeAccent, text: 'Speed and rows increase each level'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.shield_rounded, color: Colors.deepOrangeAccent, text: 'Tough bricks (2 hits) from level 2'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.expand_rounded, color: Colors.greenAccent, text: 'Batocera 🟢 → enlarges paddle (+30px)'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.compress_rounded, color: Colors.redAccent, text: 'Recalbox 🔴 → shrinks paddle AND −500 pts if caught!'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.snooze_rounded, color: Colors.cyanAccent, text: 'Slow ball 🐢 → slows ball for 5 seconds'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.blur_on_rounded, color: Colors.white70, text: 'Multiball ⚪ → 2 extra balls (max 4)'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.local_fire_department_rounded, color: Colors.deepOrangeAccent, text: 'Light Gun 🔫 → shoots bullets for 3 seconds'),
                  ]),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startGame,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('New game', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon; final Color color; final String label, value;
  const _StatCard({required this.icon, required this.color, required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 18), const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center),
      ]),
    ),
  );
}

class _RuleRow extends StatelessWidget {
  final IconData icon; final Color color; final String text;
  const _RuleRow({required this.icon, required this.color, required this.text});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 16), const SizedBox(width: 10),
    Expanded(child: Text(text, style: const TextStyle(color: Colors.white60, fontSize: 13))),
  ]);
}

// ═══════════════════════════════════════════════════════════════════════════════
// ÉCRAN DE JEU
// ═══════════════════════════════════════════════════════════════════════════════

class _BreakoutGame extends StatefulWidget {
  final void Function(int score, int level, int bricks, int powerUps) onFinished;
  const _BreakoutGame({required this.onFinished});
  @override
  State<_BreakoutGame> createState() => _BreakoutGameState();
}

class _BreakoutGameState extends State<_BreakoutGame> with TickerProviderStateMixin {

  final Map<String, ui.Image> _images = {};
  bool _assetsLoaded = false;
  final _shareKey = GlobalKey();

  // État jeu
  bool   _started   = false;
  bool   _paused    = false;
  bool   _gameOver  = false;
  int    _score     = 0;
  int    _lives     = 3;
  int    _level     = 1;
  int    _combo     = 0;
  int    _bricksDestroyed = 0;
  int    _powerUpsCollected = 0;

  // Compte à rebours
  // Dimensions
  double _w = 0, _h = 0;

  // Balles
  List<Offset> _ballPos = [Offset.zero];
  List<Offset> _ballDir = [const Offset(0.5, -1.0)];
  double _speed = _ballSpeed;
  double _slowTimer  = 0.0;
  double _shootTimer = 0.0; // secondes restantes pistolet
  double _shootCooldown = 0.0; // cooldown entre tirs
  final List<_Bullet> _bullets = [];

  // Raquette
  double _paddleX = 0;
  double _paddleWCurrent = _paddleW;
  double _paddlePulse = 0.0; // 0..1 effet pulse après power-up

  // Briques & power-ups
  final List<_Brick>    _bricks   = [];
  final List<_PowerUp>  _powerUps = [];

  // Effets visuels
  final List<_ScorePop>  _scorePops  = [];
  final List<_Particle>  _particles  = [];
  Color? _flashColor;
  Timer? _flashTimer;

  // Loop
  Ticker?   _ticker;
  DateTime? _lastTick;
  final _rng = Random();

  // ── Sons ──────────────────────────────────────────────────────────────────
  void _dispatchSound(String s) {
    switch (s) {
      case 'playCorrect': QuizAudio.correct(); break;
      case 'playWrong':   QuizAudio.wrong();   break;
      case 'playWin':     QuizAudio.win();      break;
      case 'playLose':    QuizAudio.lose();     break;
      default:            QuizAudio.tick();     break;
    }
  }

  @override
  void initState() { super.initState(); _loadAssets(); }

  @override
  void dispose() {
    _ticker?.dispose();
    _flashTimer?.cancel();
    super.dispose();
  }

  // ── Assets ────────────────────────────────────────────────────────────────

  Future<void> _shareScore() async {
    try {
      final boundary = _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}/breakout_score.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'I scored $_score pts in Retro Breakout! 🎮🏆',
      );
    } catch (e) {
      debugPrint('Share error: $e');
    }
  }
  Future<void> _loadAssets() async {
    final all = [..._consoleAssets, _bonusAsset, _malusAsset, _multiballAsset, _shootAsset];
    for (final path in all) {
      try {
        final data  = await rootBundle.load(path);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final frame = await codec.getNextFrame();
        _images[path] = frame.image;
      } catch (_) {}
    }
    if (mounted) setState(() => _assetsLoaded = true);
  }

  // ── Init ──────────────────────────────────────────────────────────────────
  void _initGame(double w, double h) {
    _w = w; _h = h;
    _paddleX = w / 2;
    _ballPos = [Offset(w / 2, h * 0.65)];
    _ballDir = [_randomDir()];
    _speed   = _ballSpeed;
    _slowTimer  = 0;
    _shootTimer = 0;
    _shootCooldown = 0;
    _bullets.clear();
    _lives   = 3;
    _score   = 0;
    _level   = 1;
    _combo   = 0;
    _bricksDestroyed = 0;
    _powerUpsCollected = 0;
    _started  = false;
    _paused   = false;
    _gameOver = false;
    _paddleWCurrent = _paddleW;
    _paddlePulse = 0;
    _scorePops.clear();
    _particles.clear();
    _buildLevel();
  }

  void _buildLevel() {
    _powerUps.clear();
    _paddleWCurrent = _paddleW;
    _bullets.clear();
    _shootTimer = 0;
    _bricks.clear();

    final keys = _images.keys
        .where((k) => k != _bonusAsset && k != _malusAsset && k != _multiballAsset && k != _shootAsset)
        .toList()..shuffle(_rng);
    if (keys.isEmpty) return;

    // Calcul dynamique : briques adaptées à la largeur écran avec marge 8px
    const marginX = 8.0;
    final availW  = _w - marginX * 2;
    final brickW  = (availW - (_brickCols - 1) * _brickPadX) / _brickCols;
    final startX  = marginX;
    final density = (0.60 + _level * 0.08).clamp(0.60, 1.0);
    final rows = (_brickRows + (_level - 1)).clamp(_brickRows, _brickRows + 4);

    final positions = <Offset>[];
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < _brickCols; col++) {
        if (_rng.nextDouble() <= density) {
          positions.add(Offset(
            startX + col * (brickW + _brickPadX),
            _brickOffsetY + row * (_brickH + _brickPadY),
          ));
        }
      }
    }
    if (positions.length < 10) { _buildLevel(); return; }
    positions.shuffle(_rng);

    final bonusIdx      = {positions[0], positions[1]};
    final malusIdx      = positions[2];
    final multiballIdxA = positions.length > 3 ? positions[3] : positions[0];
    final multiballIdxB = positions.length > 4 ? positions[4] : positions[1];
    final multiballIdx  = {multiballIdxA, multiballIdxB};
    // Balle lente
    final slowIdx  = positions.length > 5 ? positions[5] : null;
    // Pistolet
    final shootIdx = positions.length > 6 ? positions[6] : null;

    int keyIdx = 0;
    for (final pos in positions) {
      final hp = (_level >= 2 && _rng.nextDouble() < (_level - 1) * 0.1) ? 2 : 1;
      final bool isBonus     = bonusIdx.contains(pos);
      final bool isMalus     = pos == malusIdx;
      final bool isMultiball = multiballIdx.contains(pos) && !isBonus && !isMalus;
      final bool isSlow      = pos == slowIdx  && !isBonus && !isMalus && !isMultiball;
      final bool isShoot     = pos == shootIdx && !isBonus && !isMalus && !isMultiball && !isSlow;
      ui.Image? img;
      Color bCol;
      if (isBonus)     { img = _images[_bonusAsset];     bCol = const Color(0xFF1B5E20); }
      else if (isMalus){ img = _images[_malusAsset];     bCol = const Color(0xFF7F0000); }
      else if (isMultiball){ img = _images[_multiballAsset]; bCol = const Color(0xFFFFFFFF); }
      else if (isSlow)  { img = null;                      bCol = const Color(0xFF003366); }
      else if (isShoot) { img = _images[_shootAsset];    bCol = const Color(0xFF500080); }
      else             { img = _images[keys[keyIdx++ % keys.length]]; bCol = const Color(0xFF1C2230); }
      _bricks.add(_Brick(
        rect: Rect.fromLTWH(pos.dx, pos.dy, brickW, _brickH),
        hp: hp, image: img,
        isBonus: isBonus, isMalus: isMalus, isMultiball: isMultiball,
        brickColor: bCol,
      ));
    }
  }

  Offset _randomDir() {
    final angle = -pi / 2 + (_rng.nextDouble() - 0.5) * pi / 2;
    return Offset(cos(angle), sin(angle));
  }

  // ── Game loop ─────────────────────────────────────────────────────────────
  void _startLoop() {
    _ticker?.dispose();
    _lastTick = DateTime.now();
    _ticker   = createTicker((_) => _tick())..start();
  }

  void _tick() {
    if (!mounted || _paused || _gameOver) return;
    if (!_started) return;
    final now = DateTime.now();
    final dt  = now.difference(_lastTick!).inMicroseconds / 1e6;
    _lastTick = now;
    if (dt > 0.05) return;
    String? sound;
    setState(() {
      sound = _update(dt);
      _updatePowerUps(dt);
      _updateEffects(dt);
    });
    if (sound != null) _dispatchSound(sound!);
  }

  // ── Power-ups ─────────────────────────────────────────────────────────────
  void _updatePowerUps(double dt) {
    final pt2 = _h - 60 - _paddleH;
    _powerUps.removeWhere((p) {
      p.pos = Offset(p.pos.dx, p.pos.dy + _powerSpeed * dt);
      if (p.pos.dy > _h) return true;
      if (p.pos.dy >= pt2 && p.pos.dy <= pt2 + _paddleH + 20 &&
          p.pos.dx >= _paddleX - _paddleWCurrent / 2 - 15 &&
          p.pos.dx <= _paddleX + _paddleWCurrent / 2 + 15) {
        _powerUpsCollected++;
        _paddlePulse = 1.0;
        if (p.isShoot) {
          _shootTimer = _shootDuration;
          _shootCooldown = 0;
        } else if (p.isSlow) {
          _slowTimer = _slowDuration;
        } else if (p.isBonus) {
          _paddleWCurrent = (_paddleWCurrent + 30).clamp(_paddleWMin, _paddleWMax);
        } else {
          // Malus Recalbox : -500 pts + flash rouge
          _score -= 500;
          _combo = 0;
          _flash(Colors.red.withOpacity(0.35));
          _scorePops.add(_ScorePop(
            pos: Offset(_paddleX, _h - 60 - _paddleH - 20),
            text: '-500 💀',
          ));
          _paddleWCurrent = (_paddleWCurrent - 25).clamp(_paddleWMin, _paddleWMax);
        }
        return true;
      }
      return false;
    });
  }

  // ── Effets visuels ────────────────────────────────────────────────────────
  void _updateEffects(double dt) {
    // Score pops
    _scorePops.removeWhere((p) {
      p.pos = Offset(p.pos.dx, p.pos.dy - 40 * dt);
      p.life -= dt * 1.8;
      return p.life <= 0;
    });
    // Particules
    _particles.removeWhere((p) {
      p.pos += p.vel * dt;
      p.vel = Offset(p.vel.dx * 0.95, p.vel.dy * 0.95 + 80 * dt);
      p.life -= dt * 1.5;
      return p.life <= 0;
    });
    // Paddle pulse
    if (_paddlePulse > 0) _paddlePulse = (_paddlePulse - dt * 3).clamp(0, 1);
    // Slow timer
    if (_slowTimer > 0) _slowTimer = (_slowTimer - dt).clamp(0, _slowDuration);
    // Shoot timer + tirs
    if (_shootTimer > 0) {
      _shootTimer = (_shootTimer - dt).clamp(0, _shootDuration);
      _shootCooldown -= dt;
      if (_shootCooldown <= 0) {
        _shootCooldown = _shootInterval;
        // Tir depuis la raquette
        _bullets.add(_Bullet(pos: Offset(_paddleX, _h - 60 - _paddleH - _bulletR)));
      }
      // Déplacer les balles
      _bullets.removeWhere((bu) {
        bu.pos = Offset(bu.pos.dx, bu.pos.dy - _bulletSpeed * dt);
        if (bu.pos.dy < 0) return true;
        // Collision avec briques
        for (final b in _bricks) {
          if (!b.alive) continue;
          if (b.rect.inflate(_bulletR).contains(bu.pos)) {
            b.hp--;
            if (b.hp <= 0) {
              b.alive = false;
              _combo++;
              _bricksDestroyed++;
              final pts = 10 + (_combo > 1 ? (_combo - 1) * 5 : 0);
              _score += pts;
              _scorePops.add(_ScorePop(pos: b.rect.center - const Offset(0, 10), text: '+\$pts'));
              _spawnParticles(b.rect, Colors.orangeAccent);
            }
            return true;
          }
        }
        return false;
      });
    } else {
      _bullets.clear();
    }
  }

  void _spawnParticles(Rect rect, Color color) {
    for (int i = 0; i < 10; i++) {
      final angle = _rng.nextDouble() * 2 * pi;
      final speed = 80 + _rng.nextDouble() * 120;
      _particles.add(_Particle(
        pos: rect.center,
        vel: Offset(cos(angle) * speed, sin(angle) * speed - 60),
        color: color,
      ));
    }
  }

  // ── Physique ──────────────────────────────────────────────────────────────
  String? _update(double dt) {
    String? sound;
    final pt = _h - 60 - _paddleH;
    final List<int> fallen = [];
    final effectiveSpeed = _slowTimer > 0 ? _speed * 0.45 : _speed;

    for (int bi = 0; bi < _ballPos.length; bi++) {
      var nx = _ballPos[bi].dx + _ballDir[bi].dx * effectiveSpeed * dt;
      var ny = _ballPos[bi].dy + _ballDir[bi].dy * effectiveSpeed * dt;
      var vx = _ballDir[bi].dx;
      var vy = _ballDir[bi].dy;

      // Murs
      if (nx - _ballR <= 0)  { nx = _ballR;      vx =  vx.abs(); sound = 'playTick'; }
      if (nx + _ballR >= _w) { nx = _w - _ballR; vx = -vx.abs(); sound = 'playTick'; }
      if (ny - _ballR <= 0)  { ny = _ballR;      vy =  vy.abs(); sound = 'playTick'; }

      // Raquette — angle précis selon position de frappe
      if (vy > 0 &&
          ny + _ballR >= pt && ny - _ballR <= pt + _paddleH &&
          nx >= _paddleX - _paddleWCurrent / 2 && nx <= _paddleX + _paddleWCurrent / 2) {
        ny = pt - _ballR;
        vy = -vy.abs();
        // Zone de frappe -1..+1 → angle -60°..+60°
        final hit = ((nx - _paddleX) / (_paddleWCurrent / 2)).clamp(-1.0, 1.0);
        final angle = hit * pi / 3;
        vx = sin(angle);
        vy = -cos(angle);
        if (bi == 0) _combo = 0;
        sound = 'playTick';
      }

      // Chute
      if (ny - _ballR > _h) { fallen.add(bi); continue; }

      // Briques
      for (final b in _bricks) {
        if (!b.alive) continue;
        if (!b.rect.inflate(_ballR).contains(Offset(nx, ny))) continue;

        final fL = (nx - _ballR - b.rect.right).abs();
        final fR = (nx + _ballR - b.rect.left).abs();
        final fT = (ny - _ballR - b.rect.bottom).abs();
        final fB = (ny + _ballR - b.rect.top).abs();
        if (min(fL, fR) < min(fT, fB)) { vx = -vx; } else { vy = -vy; }
        _speed = min(_speed + 6, _ballSpeed * 2.0);

        b.hp--;
        if (b.hp <= 0) {
          b.alive = false;
          _combo++;
          _bricksDestroyed++;
          final pts = 10 + (_combo > 1 ? (_combo - 1) * 5 : 0);
          _score += pts;
          _flash(Colors.white.withOpacity(0.08));
          _scorePops.add(_ScorePop(
            pos: b.rect.center - const Offset(0, 10),
            text: _combo > 1 ? '+$pts 🔥' : '+$pts',
          ));

          // Particules
          _spawnParticles(b.rect, b.isBonus ? Colors.greenAccent
              : b.isMalus ? Colors.redAccent
              : b.isMultiball ? Colors.cyanAccent
              : Colors.amberAccent);

          sound = 'playCorrect';

          // Spawn power-up
          if (b.isBonus || b.isMalus) {
            _powerUps.add(_PowerUp(
              pos: b.rect.center, isBonus: b.isBonus,
              image: b.isBonus ? _images[_bonusAsset] : _images[_malusAsset],
            ));
          }
          // Balle lente
          if (b.brickColor == const Color(0xFF003366)) {
            _powerUps.add(_PowerUp(pos: b.rect.center, isBonus: true, isSlow: true));
          }
          // Pistolet
          if (b.brickColor == const Color(0xFF500080)) {
            _powerUps.add(_PowerUp(pos: b.rect.center, isBonus: true, isShoot: true));
          }
          // Multiball
          if (b.isMultiball && _ballPos.length < 4) {
            for (int k = 0; k < 2; k++) {
              _ballPos.add(b.rect.center);
              _ballDir.add(_randomDir());
            }
          }
        } else {
          sound = 'playTick';
        }
        break;
      }

      _ballPos[bi] = Offset(nx, ny);
      _ballDir[bi] = Offset(vx, vy);
    }

    // Balles tombées
    for (int i = fallen.length - 1; i >= 0; i--) {
      _ballPos.removeAt(fallen[i]);
      _ballDir.removeAt(fallen[i]);
    }

    if (_ballPos.isEmpty) {
      _lives--;
      _combo = 0;
      if (_lives <= 0) {
        _gameOver = true;
        _started  = false;
        widget.onFinished(_score, _level, _bricksDestroyed, _powerUpsCollected);
        return 'playLose';
      } else {
        _ballPos = [Offset(_w / 2, _h * 0.65)];
        _ballDir = [_randomDir()];
        _started  = false;
        _slowTimer = 0;
        return 'playWrong';
      }
    }

    // Niveau suivant
    if (_bricks.every((b) => !b.alive)) {
      _level++;
      _score += 50;
      _speed  = _ballSpeed + (_level - 1) * 25;
      _slowTimer = 0;
      _buildLevel();
      _ballPos = [Offset(_w / 2, _h * 0.65)];
      _ballDir = [_randomDir()];
      _started  = false;
      return 'playWin';
    }

    return sound;
  }

  void _flash(Color c) {
    _flashColor = c;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 80),
        () { if (mounted) setState(() => _flashColor = null); });
  }

  // ── Input ─────────────────────────────────────────────────────────────────
  void _onPan(DragUpdateDetails d) {
    if (_paused) return;
    setState(() {
      _paddleX = (_paddleX + d.delta.dx)
          .clamp(_paddleWCurrent / 2, _w - _paddleWCurrent / 2).toDouble();
      if (!_started && _ballPos.isNotEmpty) _ballPos[0] = Offset(_paddleX, _ballPos[0].dy);
    });
  }

  void _onTap() {
    if (_gameOver || _paused) return;
    if (!_started) {
      setState(() => _started = true);
      if (_ticker == null || !_ticker!.isActive) _startLoop();
    }
  }

  void _togglePause() {
    if (_gameOver || !_started) return;
    setState(() {
      _paused = !_paused;
      if (!_paused) {
        _lastTick = DateTime.now();
        if (_ticker == null || !_ticker!.isActive) _startLoop();
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: !_assetsLoaded
            ? const Center(child: CircularProgressIndicator(color: Color(0xFFE02020)))
            : LayoutBuilder(builder: (_, c) {
                final w = c.maxWidth, h = c.maxHeight;
                if (_w == 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _initGame(w, h));
                    _startLoop();
                  });
                }
                return _gameOver ? _buildGameOver() : _buildGame(w, h);
              }),
      ),
    );
  }

  Widget _buildGame(double w, double h) {
    return GestureDetector(
      onPanUpdate: _onPan,
      onTap: _onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(children: [
        // Canvas principal
        CustomPaint(
          size: Size(w, h),
          painter: _GamePainter(
            bricks: _bricks,
            balls: _ballPos, ballR: _ballR,
            paddleX: _paddleX,
            paddleW: _paddleWCurrent, paddleH: _paddleH,
            flashColor: _flashColor,
            lives: _lives, score: _score,
            level: _level, combo: _combo,
            screenH: h,
            labelTap: 'Tap to launch',
            labelLvl: 'LV',
            particles: _particles,
            slowTimer: _slowTimer,
            slowDuration: _slowDuration,
            shootTimer: _shootTimer,
            shootDuration: _shootDuration,
            paddlePulse: _paddlePulse,
          ),
        ),

        // Score pops (widgets Flutter)
        ..._scorePops.map((p) => Positioned(
          left: p.pos.dx - 20,
          top: p.pos.dy,
          child: Opacity(
            opacity: p.life.clamp(0, 1),
            child: Text(p.text, style: TextStyle(
              color: p.text.contains('🔥') ? Colors.orangeAccent : Colors.amberAccent,
              fontSize: 13, fontWeight: FontWeight.w900,
              shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
            )),
          ),
        )),

        // Balles pistolet (widgets Flutter)
        ..._bullets.map((bu) => Positioned(
          left: bu.pos.dx - _bulletR,
          top: bu.pos.dy - _bulletR,
          child: Container(
            width: _bulletR * 2, height: _bulletR * 2,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.orangeAccent,
              boxShadow: [BoxShadow(color: Colors.orange, blurRadius: 6, spreadRadius: 1)],
            ),
          ),
        )),

        // Power-ups (widgets Flutter)
        ..._powerUps.map((p) => Positioned(
          left: p.pos.dx - 18,
          top: p.pos.dy - 18,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (p.isShoot ? Colors.deepOrangeAccent
                    : p.isSlow ? Colors.cyanAccent
                    : p.isBonus ? Colors.greenAccent
                    : Colors.redAccent).withOpacity(0.9),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(child: Text(
              p.isShoot ? '🔫' : p.isSlow ? '🐢' : p.isBonus ? '+' : '−',
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
            )),
          ),
        )),

        // Overlay pause
        if (_paused)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.pause_circle_rounded, color: Colors.white, size: 72),
                  const SizedBox(height: 16),
                  const Text('PAUSE', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4)),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: _togglePause,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Resume'),
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14)),
                  ),
                ]),
              ),
            ),
          ),

        // Bouton pause
        Positioned(
          top: 8, right: 48,
          child: GestureDetector(
            onTap: _togglePause,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Icon(_paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: Colors.white54, size: 16),
            ),
          ),
        ),

        // Bouton quitter
        Positioned(
          top: 8, right: 8,
          child: GestureDetector(
            onTap: () async {
              _ticker?.stop();
              final quit = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1C2230),
                  title: const Text('Quit the game?'),
                  content: const Text('Your progress will be lost.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continue')),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                      child: const Text('Quit'),
                    ),
                  ],
                ),
              );
              if (quit == true && mounted) {
                Navigator.of(context).pop();
              } else {
                _lastTick = DateTime.now();
                _ticker?.start();
              }
            },
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: const Icon(Icons.close_rounded, color: Colors.white38, size: 16),
            ),
          ),
        ),

        // Hint
        if (!_started && !_paused)
          Positioned(
            bottom: 100, left: 0, right: 0,
            child: Text('Tap to launch',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13, letterSpacing: 1),
            ),
          ),
      ]),
    );
  }

  // ── Game Over ─────────────────────────────────────────────────────────────
  Widget _buildGameOver() {
    final emoji = _score >= 500 ? '🏆' : _score >= 200 ? '🎮' : '💀';
    final color = _lives > 0 ? Colors.greenAccent : Colors.redAccent;
    final msg   = _lives <= 0 ? 'Game Over!' : _level > 3 ? 'Impressive!' : 'Niveau $_level terminé !';

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              child: Row(children: [
                Text('Results', style: Theme.of(context).textTheme.headlineMedium),
              ]),
            ),
            RepaintBoundary(
              key: _shareKey,
              child: Container(
                color: const Color(0xFF0D0F14),
                padding: const EdgeInsets.all(12),
                child: Column(children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Column(children: [
                Text(emoji, style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(msg, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Text('$_score pts', style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900)),
                Text('Niveau $_level · ${_lives > 0 ? "$_lives vie(s)" : "0 vie"}',
                    style: TextStyle(color: color.withOpacity(0.7), fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 16),
            // Stats détaillées
            Row(children: [
              _StatCard(icon: Icons.star_rounded, color: Colors.amberAccent, label: 'Score', value: '$_score'),
              const SizedBox(width: 8),
              _StatCard(icon: Icons.layers_rounded, color: Colors.cyanAccent, label: 'Level', value: '$_level'),
              const SizedBox(width: 8),
              _StatCard(icon: Icons.favorite_rounded, color: Colors.redAccent, label: 'Lives', value: '$_lives/3'),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _StatCard(icon: Icons.grid_view_rounded, color: Colors.purpleAccent, label: 'Bricks', value: '$_bricksDestroyed'),
              const SizedBox(width: 8),
              _StatCard(icon: Icons.bolt_rounded, color: Colors.orangeAccent, label: 'Power-ups', value: '$_powerUpsCollected'),
              const SizedBox(width: 8),
              _StatCard(icon: Icons.local_fire_department_rounded, color: Colors.deepOrangeAccent, label: 'Max combo', value: '×$_combo'),
            ]),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            // Share button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _shareScore,
                icon: const Icon(Icons.share_rounded),
                label: const Text('Share my score'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  foregroundColor: Colors.amberAccent,
                  side: const BorderSide(color: Colors.amberAccent, width: 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 8),            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Home'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: () => setState(() { _initGame(_w, _h); _startLoop(); }),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Play again', style: TextStyle(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// PAINTER
// ═══════════════════════════════════════════════════════════════════════════════

class _GamePainter extends CustomPainter {
  final List<_Brick>    bricks;
  final List<Offset>    balls;
  final List<_Particle> particles;
  final double ballR, paddleX, paddleW, paddleH, screenH;
  final double slowTimer, slowDuration, paddlePulse;
  final double shootTimer, shootDuration;
  final Color? flashColor;
  final int lives, score, level, combo;
  final String labelTap, labelLvl;

  _GamePainter({
    required this.bricks, required this.balls, required this.ballR,
    required this.paddleX, required this.paddleW, required this.paddleH,
    required this.flashColor,
    required this.lives, required this.score, required this.level,
    required this.combo, required this.screenH,
    required this.labelTap, required this.labelLvl,
    required this.particles,
    required this.slowTimer, required this.slowDuration,
    required this.shootTimer, required this.shootDuration,
    required this.paddlePulse,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;

    // Flash
    if (flashColor != null) {
      canvas.drawRect(Offset.zero & size, Paint()..color = flashColor!);
    }

    // ── Briques ──────────────────────────────────────────────────────────────
    for (final b in bricks) {
      if (!b.alive) continue;
      canvas.drawRRect(
        RRect.fromRectAndRadius(b.rect, const Radius.circular(6)),
        Paint()..color = b.hp > 1 ? Colors.deepOrange.withOpacity(0.5) : b.brickColor.withOpacity(0.9),
      );
      if (b.image != null) {
        final src = Rect.fromLTWH(0, 0, b.image!.width.toDouble(), b.image!.height.toDouble());
        canvas.drawImageRect(b.image!, src, b.rect.deflate(5), Paint()..filterQuality = FilterQuality.low);
      } else if (b.brickColor == const Color(0xFF500080)) {
        final tp2 = TextPainter(textDirection: TextDirection.ltr);
        tp2.text = const TextSpan(text: '🔫', style: TextStyle(fontSize: 18));
        tp2.layout();
        tp2.paint(canvas, b.rect.center - Offset(tp2.width / 2, tp2.height / 2));
      } else if (b.brickColor == const Color(0xFF003366)) {
        // Brique balle lente : icône 🐢 textuelle
        final tp = TextPainter(textDirection: TextDirection.ltr);
        tp.text = const TextSpan(text: '🐢', style: TextStyle(fontSize: 18));
        tp.layout();
        tp.paint(canvas, b.rect.center - Offset(tp.width / 2, tp.height / 2));
      }
      final borderCol = b.hp > 1 ? Colors.orangeAccent
                      : b.isBonus ? Colors.greenAccent
                      : b.isMalus ? Colors.redAccent
                      : b.isMultiball ? Colors.white70
                      : b.brickColor == const Color(0xFF500080) ? Colors.deepOrangeAccent
                      : b.brickColor == const Color(0xFF003366) ? Colors.cyanAccent
                      : Colors.white.withOpacity(0.12);
      canvas.drawRRect(
        RRect.fromRectAndRadius(b.rect, const Radius.circular(6)),
        Paint()
          ..color = borderCol.withOpacity(b.hp > 1 ? 0.9 : 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (b.isBonus || b.isMalus || b.isMultiball) ? 1.5 : 1,
      );
    }

    // ── Particules ───────────────────────────────────────────────────────────
    for (final p in particles) {
      canvas.drawCircle(p.pos, 3 * p.life,
          Paint()..color = p.color.withOpacity(p.life.clamp(0, 1)));
    }

    // ── Raquette ─────────────────────────────────────────────────────────────
    final pt   = screenH - 60 - paddleH;
    final prct = Rect.fromLTWH(paddleX - paddleW / 2, pt, paddleW, paddleH);

    // Pulse quand power-up collecté
    if (paddlePulse > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(prct.inflate(4 * paddlePulse), const Radius.circular(10)),
        Paint()..color = Colors.cyanAccent.withOpacity(0.4 * paddlePulse),
      );
    }

    // Couleur selon slow
    final c1 = slowTimer > 0 ? const Color(0xFF00BCD4) : const Color(0xFF42A5F5);
    final c2 = slowTimer > 0 ? const Color(0xFF006064) : const Color(0xFF1565C0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(prct, const Radius.circular(8)),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [c1, c2],
      ).createShader(prct),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(prct.left + 8, prct.top + 2, prct.width - 16, 4),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white.withOpacity(0.35),
    );

    // Barre shoot timer
    if (shootTimer > 0) {
      final ratioS = shootTimer / shootDuration;
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(prct.left, pt + paddleH + 8, paddleW, 3), const Radius.circular(2)),
        Paint()..color = Colors.deepOrangeAccent.withOpacity(0.3));
      canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTWH(prct.left, pt + paddleH + 8, paddleW * ratioS, 3), const Radius.circular(2)),
        Paint()..color = Colors.deepOrangeAccent);
    }
    // Barre slow timer sous la raquette
    if (slowTimer > 0) {
      final ratio = slowTimer / slowDuration;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(prct.left, pt + paddleH + 4, paddleW, 3),
          const Radius.circular(2),
        ),
        Paint()..color = Colors.cyanAccent.withOpacity(0.3),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(prct.left, pt + paddleH + 4, paddleW * ratio, 3),
          const Radius.circular(2),
        ),
        Paint()..color = Colors.cyanAccent,
      );
    }

    // ── Balles ───────────────────────────────────────────────────────────────
    for (int i = 0; i < balls.length; i++) {
      final b = balls[i];
      canvas.drawCircle(b + const Offset(2, 2), ballR, Paint()..color = Colors.black.withOpacity(0.35));
      final ballColors = i == 0
          ? [Colors.white, const Color(0xFFE02020)]
          : [Colors.white, Colors.cyanAccent];
      canvas.drawCircle(b, ballR,
        Paint()..shader = RadialGradient(
          center: const Alignment(-0.3, -0.3), colors: ballColors,
        ).createShader(Rect.fromCircle(center: b, radius: ballR)),
      );
    }

    // ── HUD ──────────────────────────────────────────────────────────────────
    final tp = TextPainter(textDirection: TextDirection.ltr);

    tp.text = TextSpan(text: '$labelLvl $level',
        style: const TextStyle(color: Colors.white38, fontSize: 11, letterSpacing: 1));
    tp.layout(); tp.paint(canvas, const Offset(12, 16));

    tp.text = TextSpan(text: '$score',
        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, fontFamily: 'monospace'));
    tp.layout(); tp.paint(canvas, Offset(w / 2 - tp.width / 2, 12));

    for (int i = 0; i < 3; i++) {
      tp.text = TextSpan(text: '♥', style: TextStyle(color: i < lives ? Colors.redAccent : Colors.white12, fontSize: 16));
      tp.layout(); tp.paint(canvas, Offset(w - 100 - (3 - i) * 20.0, 12));
    }

    if (combo >= 2) {
      tp.text = TextSpan(text: 'COMBO x$combo',
          style: TextStyle(color: Colors.orangeAccent.withOpacity(0.9), fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1));
      tp.layout(); tp.paint(canvas, Offset(w / 2 - tp.width / 2, 36));
    }

    canvas.drawLine(const Offset(0, 58), Offset(w, 58),
        Paint()..color = Colors.white.withOpacity(0.05)..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_GamePainter o) => true;
}
