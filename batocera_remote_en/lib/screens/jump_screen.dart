import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'quiz_audio_service.dart';
import '../services/leaderboard_service.dart';
import '../widgets/in_app_file_picker.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// RETRO JUMP — vertical platformer mini game (offline)
// The hero bounces from cartridge to cartridge. Touch controls: hold the
// left / right half of the screen to move.
// Coins (currency) → hero unlocks; challenges rewarded with coins;
// bugs to stomp; scenery stages; record line; vibrations; neon mode.
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Storage (SharedPreferences) ───────────────────────────────────────────

const _kBestScoreKey  = 'jump_best_score';
const _kBestNameKey   = 'jump_best_name';
const _kHeroKey       = 'jump_hero';
const _kCoinsKey      = 'jump_coins';
const _kUnlockedKey   = 'jump_unlocked';
const _kChallengesKey = 'jump_challenges';
const _kChallengeLvlKey = 'jump_challenge_level';
const _kNeonKey       = 'jump_neon';
const _kHapticsKey    = 'jump_haptics';
const _kTiltKey       = 'jump_tilt';
const _kThemeKey       = 'jump_theme';
const _kThemeUnlockKey = 'jump_theme_unlocked';

// Thèmes visuels (0 = classique, offert). Néon reste acquis si l'ancienne option était activée.
const _themeNames  = ['Classic', 'Neon', 'Pocket', 'Sepia', 'CRT', 'Synthwave', 'Red', 'Disco'];
const _themePrices = [0, 100, 150, 200, 250, 300, 350, 400];
// Deux couleurs d'aperçu par thème (tuile du menu)
const _themeSwatch = [
  [Color(0xFFE02020), Color(0xFF5C6BC0)],
  [Color(0xFFFF4081), Color(0xFF18FFFF)],
  [Color(0xFF0F380F), Color(0xFF9BBC0F)],
  [Color(0xFF704214), Color(0xFFE8D3A9)],
  [Color(0xFF102027), Color(0xFF80CBC4)],
  [Color(0xFF4A148C), Color(0xFFFF4081)],
  [Color(0xFF000000), Color(0xFFFF1744)],
  [Color(0xFFFF4081), Color(0xFFFFEB3B)],
];

/// Filtre de couleur appliqué à toute l'aire de jeu (null = aucun).
List<double>? _themeMatrix(int theme) {
  const lr = 0.299, lg = 0.587, lb = 0.114; // luminance
  switch (theme) {
    case 2: // Pocket : verts façon console portable (contraste renforcé)
      const kr = 1.25, kg = 1.15;
      return [
        lr * kr, lg * kr, lb * kr, 0, -30,
        lr * kg, lg * kg, lb * kg, 0, 18,
        0, 0, 0, 0, 15,
        0, 0, 0, 1, 0,
      ];
    case 3: // Sépia
      return [
        0.45, 0.88, 0.22, 0, -15,
        0.40, 0.79, 0.19, 0, -15,
        0.31, 0.61, 0.15, 0, -15,
        0, 0, 0, 1, 0,
      ];
    case 5: // Synthwave : violet / rose
      return [
        1.0, 0.1, 0.35, 0, 10,
        0.0, 0.55, 0.15, 0, 0,
        0.35, 0.1, 1.0, 0, 25,
        0, 0, 0, 1, 0,
      ];
    case 6: // Rouge sur noir (casque 3D des années 90)
      return [
        lr * 1.8, lg * 1.8, lb * 1.8, 0, -60,
        lr * 0.08, lg * 0.08, lb * 0.08, 0, 0,
        lr * 0.08, lg * 0.08, lb * 0.08, 0, 0,
        0, 0, 0, 1, 0,
      ];
  }
  return null;
}
const _kCodesUsedKey  = 'jump_codes_used';

// Codes de triche : seule leur empreinte SHA-256 (avec sel) est stockée,
// les codes eux-mêmes n'apparaissent nulle part dans le source.
// Ajouter un code : sha256(_codeSalt + CODE_EN_MAJUSCULES) → valeur = effet
// (0 pièces, 1 héros, 2 thèmes, 3 musiques), effet codé dans _applyCode().
// Sauvegarde de la progression (fichier JSON signé dans Download)
const _saveFileName = 'retro_jump_save.json';
const _saveSalt = 'rj-save#41c7';
// Roue de la fortune : 1 tour gratuit par jour. coins > 0 = pièces,
// sinon bonus offert (index dans _bonusNames). w = poids du tirage.
const _kWheelDayKey   = 'jump_wheel_day';
const _kFreeBonusKey  = 'jump_free_bonus';
const _kFreeContKey   = 'jump_free_continue';
const _wheelSpinPrice = 25; // tour supplémentaire payant
const _wheel = <({int coins, int bonus, int w, Color color})>[
  (coins: 10,  bonus: -1, w: 24, color: Color(0xFF5C6BC0)),
  (coins: 0,   bonus: 2,  w: 9,  color: Color(0xFF00ACC1)), // bouclier
  (coins: 25,  bonus: -1, w: 18, color: Color(0xFFEC407A)),
  (coins: 0,   bonus: 3,  w: 8,  color: Color(0xFFEF6C00)), // turbo
  (coins: 15,  bonus: -1, w: 20, color: Color(0xFF7CB342)),
  (coins: 0,   bonus: 0,  w: 6,  color: Color(0xFF26A69A)), // départ 500
  (coins: 50,  bonus: -1, w: 11, color: Color(0xFFAB47BC)),
  (coins: 100, bonus: -1, w: 4,  color: Color(0xFFFFB300)),
  (coins: 0,   bonus: 4,  w: 7,  color: Color(0xFFE53935)), // rejouer offert
];

/// Nom d'un lot de la roue (bonus 0-3, ou 4 = rejouer offert).
String _prizeName(int b) => b == 4 ? 'Continue' : _bonusNames[b];

String _todayKey() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

// Combo : +1 par cartouche plus haute que la précédente, sinon retour à 1.
// Multiplicateur de pièces = 1 + combo ~/ _comboStep (max _comboMax).
const _comboStep = 5;
const _comboMax = 5;
const _kDailyKey     = 'jump_daily_best'; // jour + meilleur score de la partie du jour
const _kDailyRankKey = 'jump_daily_rank'; // jour + rang + total
const _kWorldRankKey = 'jump_world_rank'; // rang + total (tous temps)
const _kPseudoAskedKey = 'jump_lb_asked'; // online name already asked
const _kStatsKey = 'jump_stats'; // statistiques à vie (JSON)

// Bonus à ramasser en partie : 0 aimant · 1 pièces ×2 · 2 super saut · 3 ralenti
const _pickupNames = ['Magnet', 'Coins ×2', 'Super jump', 'Slow-mo'];
const _pickupIcons = ['🧲', '×2', '⏫', '⏳'];
const _pickupColors = [Color(0xFFFF5252), Color(0xFFFFD740), Color(0xFF69F0AE), Color(0xFF40C4FF)];
const _pickupDur = [8.0, 10.0, 0.0, 6.0]; // secondes (super saut = 5 rebonds)

// Pouvoirs des héros (index = héros)
const _heroPowers = [
  'No power: the classic',
  'Moves 12% faster',
  'Continue costs only 10 coins',
  'Bags hold 20 coins',
  'Bounces once on cracked cartridges',
  'Pickups last 50% longer',
  'Attracts nearby coins',
  '1 coin in 4 counts double',
  'Starts every game with a shield',
  'Combo: level every 4 jumps instead of 5',
  'Jumps 13% higher',
  'Turbo lasts 60% longer',
];

const _codeSalt = 'rj#7f3a9c-foc';
const _cheatCodes = {
  '66f74db6e49fb44be73bfd50fdefd80e0ae65b82597278e5590876b745233a57': 0,
  '22487d0bd20c29a97379950c5da3c66434276ebdb75443594918fbba47ed8224': 1,
  'e718b094ded6c80faa6363d81474d5516aa97ba042986363f02a660f006abb81': 2,
  '36c45dca0fe398eacb90813fdcea5d8c927ee5150a0d053bc3979e3ea8b2d6cc': 3,
};

String _codeHash(String code) => sha256.convert(utf8.encode('$_codeSalt$code')).toString();
// Bonus achetables avant une partie (cumulables, consommés au lancement)
const _bonusNames  = ['Start 500', 'Start 1000', 'Shield', 'Turbo'];
const _bonusPrices = [30, 60, 20, 40];
const _bonusIcons  = [Icons.trending_up_rounded, Icons.keyboard_double_arrow_up_rounded,
    Icons.shield_rounded, Icons.rocket_launch_rounded];
const _bonusColors = [Colors.lightGreenAccent, Colors.greenAccent, Colors.cyanAccent, Colors.orangeAccent];
const _kMusicKey      = 'jump_music';
const _kMusicUnlockKey = 'jump_music_unlocked';

// Musiques (index = morceau joué côté Android) : la 1re est offerte
const _musicNames  = ['Disco Funk', 'Shop', 'Good Morning'];
const _musicPrices = [0, 300, 500];
const _kCollectionKey = 'jump_collection';

// Collection par albums de 16 logos de consoles (assets du Breakout).
// Album 1 = série A, album 2 = série B, puis on recommence en alternant avec
// une prise de plus par logo (3, 3, 4, 4, 5, 5…).
const _kAlbumKey = 'jump_collection_album';
const _logoSets = [
  [
    'assets/game/nes.png',       'assets/game/snes.png',        'assets/game/n64.png',
    'assets/game/gb.png',        'assets/game/gba.png',         'assets/game/wii.png',
    'assets/game/switch.png',    'assets/game/mastersystem.png','assets/game/megadrive.png',
    'assets/game/psx.png',       'assets/game/ps2.png',         'assets/game/psp.png',
    'assets/game/xbox.png',      'assets/game/atarijaguar.png', 'assets/game/amiga1200.png',
    'assets/game/mame.png',
  ],
  [
    'assets/game/3ds.png',       'assets/game/amigacd32.png',   'assets/game/apple2.png',
    'assets/game/atari7800.png', 'assets/game/cps3.png',        'assets/game/gbc.png',
    'assets/game/gottlieb.png',  'assets/game/model3.png',      'assets/game/naomi.png',
    'assets/game/ps3.png',       'assets/game/psvita.png',      'assets/game/segacd.png',
    'assets/game/taito.png',     'assets/game/triforce.png',    'assets/game/wiiu.png',
    'assets/game/xbox360.png',
  ],
];
const _logoNameSets = [
  [
    'NES', 'SNES', 'N64', 'GAME BOY', 'GBA', 'WII', 'SWITCH', 'MASTER SYSTEM',
    'MEGA DRIVE', 'PLAYSTATION', 'PS2', 'PSP', 'XBOX', 'JAGUAR', 'AMIGA', 'MAME',
  ],
  [
    '3DS', 'AMIGA CD32', 'APPLE II', 'ATARI 7800', 'CPS-3', 'GB COLOR', 'GOTTLIEB', 'MODEL 3',
    'NAOMI', 'PS3', 'PS VITA', 'SEGA CD', 'TAITO', 'TRIFORCE', 'WII U', 'XBOX 360',
  ],
];

const _bagCoins = 15; // pièces dans un sac

int _album = 0; // album en cours (0 = premier), chargé avec la collection
List<String> get _logoAssets => _logoSets[_album % _logoSets.length];
List<String> get _logoNames => _logoNameSets[_album % _logoNameSets.length];
int get _logoGoal => 3 + _album ~/ _logoSets.length;

/// Bonus versé quand un album est complété.
int _albumBonus(int album) => 500; // cadeau fixe par album complété

List<int> _readCollection(SharedPreferences prefs) {
  _album = prefs.getInt(_kAlbumKey) ?? 0;
  final raw = prefs.getStringList(_kCollectionKey) ?? const <String>[];
  return List<int>.generate(_logoAssets.length,
      (i) => i < raw.length ? (int.tryParse(raw[i]) ?? 0) : 0);
}

// ─── Texts ───────────────────────────────────────────────────────────────────

const _heroNames  = ['Robot', 'Joystick', 'Cabinet', 'Token', 'Cartridge', 'Floppy', 'CD', 'Cassette', 'TV', 'Mouse', 'Cat', 'Rocket'];
const _heroPrices = [0, 50, 100, 150, 200, 250, 300, 350, 400, 450, 500, 550];
const _continuePrice = 20; // pièces pour continuer après une chute (1 fois par partie)
const _txtRecordLine = 'RECORD';
const _txtNewRecord  = 'NEW RECORD!';
const _txtStage      = 'STAGE';

// ─── Physics ─────────────────────────────────────────────────────────────────

const _gravity       = 1800.0;  // px/s²
const _jumpV         = -820.0;  // saut normal (~185 px)
const _springV       = -1300.0; // ressort (~470 px)
const _stompV        = -900.0;  // rebond après avoir écrasé un bug
const _turboV        = -1150.0; // vitesse pendant le turbo
const _turboDuration = 2.2;     // secondes
const _tiltFull      = 2.2;     // m/s² d'inclinaison pour la vitesse max (~13°)
const _tiltDead      = 0.35;    // zone morte (m/s²)
const _moveSpeed     = 330.0;   // vitesse horizontale max
const _moveAccel     = 2200.0;  // accélération horizontale
const _heroW         = 44.0;
const _heroH         = 30.0;
const _platW         = 68.0;
const _platH         = 14.0;
const _enemyW        = 30.0;
const _enemyH        = 23.0;
const _coinR         = 7.0;
const _topBarH       = 56.0;    // zone des boutons (ignorée par les commandes)
const _turboAsset    = 'assets/game/batocera_bonus.png';

// ─── Challenges ────────────────────────────────────────────────────────────────────

class _Challenge {
  final String id;
  final String label;
  final int reward;
  final IconData icon;
  final int target; // valeur à atteindre (pts, turbos, bugs, pièces)
  const _Challenge(this.id, this.label, this.reward, this.icon, this.target);
}

const _thousandSep = ',';

String _fmtNum(int n) {
  final s = '$n';
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(_thousandSep);
    b.write(s[i]);
  }
  return b.toString();
}

/// Défis de la série [lvl] (0 = première). Quand tous sont réussis, une
/// nouvelle série commence avec des objectifs et des récompenses plus élevés.
List<_Challenge> _challengesFor(int lvl) {
  final f = 1 + lvl * 0.5;
  int pts(int base) => ((base * f) / 50).round() * 50;
  int rw(int base) => (base * f).round();
  final h1 = pts(500), h2 = pts(1500), h3 = pts(3000), ns = pts(1000), ne = pts(500);
  final tb = 3 + lvl, st = 5 + 2 * lvl, co = 50 + 20 * lvl;
  return [
    _Challenge('h500',     'Reach ${_fmtNum(h1)} pts',  rw(20),  Icons.flag_rounded, h1),
    _Challenge('h1500',    'Reach ${_fmtNum(h2)} pts', rw(50),  Icons.flag_rounded, h2),
    _Challenge('h3000',    'Reach ${_fmtNum(h3)} pts', rw(100), Icons.emoji_events_rounded, h3),
    _Challenge('nospring', '${_fmtNum(ns)} pts without any spring', rw(60),  Icons.block_rounded, ns),
    _Challenge('turbo3',   '$tb turbos in one game', rw(40),  Icons.rocket_launch_rounded, tb),
    _Challenge('stomp5',   'Stomp $st bugs in one game', rw(40),  Icons.bug_report_rounded, st),
    _Challenge('coins50',  '$co coins in one game', rw(50),  Icons.monetization_on_rounded, co),
    _Challenge('neon500',  '${_fmtNum(ne)} pts in neon mode', rw(30),  Icons.auto_awesome_rounded, ne),
  ];
}

/// Bonus versé quand toute une série est terminée.
int _seriesBonus(int lvl) => 100 * (lvl + 1);

// ─── Scenery stages ─────────────────────────────────────────────────────────

enum _Deco { slit, torch, glyph, ice, lava, neon, space }

/// Style de mur de la tour (un nouveau tous les [_tierStep] pts, en boucle).
class _Tier {
  final String name;
  final double bw, rh;          // taille des briques
  final Color base, mortar;     // brique / joint
  final Color top, bottom;      // ciel (palier Espace)
  final _Deco deco;
  const _Tier(this.name, this.bw, this.rh, this.base, this.mortar, this.top, this.bottom, this.deco);
}

const _tierStep = 400;   // pts entre deux décors
const _parallax = 0.6;   // le mur défile moins vite que les plateformes

const _tiers = [
  _Tier('Castle', 52, 26, Color(0xFF3A3F4A), Color(0xFF181A20), Color(0xFF141826), Color(0xFF0D0F14), _Deco.slit),
  _Tier('Dungeon', 44, 22, Color(0xFF4E2C24), Color(0xFF1C110F), Color(0xFF1A0F0C), Color(0xFF0B0605), _Deco.torch),
  _Tier('Temple', 72, 34, Color(0xFF4E3E24), Color(0xFF221B0F), Color(0xFF2A2010), Color(0xFF120D06), _Deco.glyph),
  _Tier('Ice', 60, 30, Color(0xFF224058), Color(0xFF0F202E), Color(0xFF0B2233), Color(0xFF04101A), _Deco.ice),
  _Tier('Volcano', 56, 28, Color(0xFF2C2628), Color(0xFF100C0D), Color(0xFF1A0A06), Color(0xFF080303), _Deco.lava),
  _Tier('Cyber', 80, 40, Color(0xFF202C38), Color(0xFF0A1016), Color(0xFF06141C), Color(0xFF020609), _Deco.neon),
  _Tier('Space', 0,  0,  Color(0xFF000000), Color(0xFF000000), Color(0xFF070918), Color(0xFF000000), _Deco.space),
];

_Tier _tierFor(int idx) => _tiers[max(0, idx) % _tiers.length];

/// Petit hachage déterministe (0..1) pour varier briques et décorations.
double _hash(int a, int b) {
  var x = (a * 73856093) ^ (b * 19349663);
  x = (x ^ (x >> 13)) * 1274126177;
  x ^= x >> 16;
  return (x & 0xFFFFFF) / 0xFFFFFF;
}

// ─── Models ──────────────────────────────────────────────────────────────────

enum _PlatType { normal, moving, breakable, spring }

class _Plat {
  double x, y;          // x = bord gauche, y = dessus (coordonnées monde)
  final _PlatType type;
  double vx;
  bool broken = false;
  bool hasTurbo;
  bool hasShield;
  final int colorIdx;
  _Plat(this.x, this.y, this.type,
      {this.vx = 0, this.hasTurbo = false, this.hasShield = false, this.colorIdx = 0});
}

class _Enemy {
  double x, y;          // centre (coordonnées monde)
  double vx;
  double phase;
  bool dead = false;
  _Enemy(this.x, this.y, this.vx, this.phase);
  bool get moving => vx != 0;
}

class _Coin {
  double x, y;          // centre (coordonnées monde) — modifiable par l'aimant
  bool taken = false;
  _Coin(this.x, this.y);
}

class _Pickup {
  final double x, y;
  final int kind;
  bool taken = false;
  _Pickup(this.x, this.y, this.kind);
}

class _Logo {
  final double x, y;    // centre (coordonnées monde)
  final int idx;
  bool taken = false;
  _Logo(this.x, this.y, this.idx);
}

class _Particle {
  Offset pos;   // coordonnées monde
  Offset vel;
  double life;  // 1 → 0
  final Color color;
  _Particle(this.pos, this.vel, this.color) : life = 1.0;
}

const _cartColors = [
  Color(0xFF5C6BC0), Color(0xFF26A69A), Color(0xFFAB47BC),
  Color(0xFFEF6C00), Color(0xFF7CB342), Color(0xFFEC407A),
];

// ═══════════════════════════════════════════════════════════════════════════════
// HOME SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class JumpScreen extends StatefulWidget {
  const JumpScreen({super.key});
  @override
  State<JumpScreen> createState() => _JumpScreenState();
}

class _JumpScreenState extends State<JumpScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _idle =
      AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  int _bestScore = 0;
  String _bestName = '';
  int _dailyBest = 0;     // meilleur score de la partie du jour
  String _dailyRank = '';  // « #3 / 57 »
  String _worldRank = '';  // rang tous temps « #12 / 340 »
  // Classement
  int _lbTab = 0;         // 0 aujourd'hui, 1 tous temps
  LbBoard? _lbBoard;
  bool _lbLoading = false, _lbFailed = false;
  String? _lbMyName;
  String _lbPid = '';
  int _hero = 0;
  int _coins = 0;
  Set<int> _unlocked = {0};
  Set<String> _completed = {};
  int _challengeLevel = 0;
  int _theme = 0;
  Set<int> _themeUnlocked = {0};
  final Set<int> _bonusSel = {};
  Set<int> _freeBonus = {};   // bonus offerts par la roue (prochaine partie)
  bool _wheelReady = false;   // tour de roue disponible aujourd'hui
  Map<String, dynamic> _stats = {};
  bool _freeContinue = false; // « rejouer » offert par la roue (prochaine partie)
  bool _haptics = true;
  bool _tilt = false;
  int _musicTrack = 0;
  Set<int> _musicUnlocked = {0};
  List<int> _collection = List<int>.filled(_logoAssets.length, 0);
  bool _loading = true;

  @override
  void dispose() {
    QuizAudio.musicStop(); // retour à la liste des mini-jeux
    _idle.dispose();
    _rev.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Musique dès l'ouverture du jeu (accueil compris), une fois le morceau choisi connu
    _load().then((_) => QuizAudio.loadPrefs()).then((_) {
      if (!mounted) return;
      setState(() {});
      QuizAudio.musicStart(_musicTrack);
      // Free daily spin not used yet: the wheel opens by itself (once, on opening)
      if (_wheelReady) {
        Future.delayed(const Duration(milliseconds: 450), () {
          if (mounted && _wheelReady && ModalRoute.of(context)?.isCurrent == true) _openWheel();
        });
      }
    });
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final unlocked = <int>{0};
    for (final s in prefs.getStringList(_kUnlockedKey) ?? const <String>[]) {
      final i = int.tryParse(s);
      if (i != null && i >= 0 && i < _heroCount) unlocked.add(i);
    }
    var hero = (prefs.getInt(_kHeroKey) ?? 0).clamp(0, _heroCount - 1);
    if (!unlocked.contains(hero)) hero = 0;
    setState(() {
      _bestScore = prefs.getInt(_kBestScoreKey) ?? 0;
      _bestName  = prefs.getString(_kBestNameKey) ?? '';
      _coins     = prefs.getInt(_kCoinsKey) ?? 0;
      _unlocked  = unlocked;
      _hero      = hero;
      _completed = (prefs.getStringList(_kChallengesKey) ?? const <String>[]).toSet();
      _challengeLevel = prefs.getInt(_kChallengeLvlKey) ?? 0;
      _themeUnlocked = {0};
      if (prefs.getBool(_kNeonKey) ?? false) _themeUnlocked.add(1); // ancienne option néon
      for (final s in prefs.getStringList(_kThemeUnlockKey) ?? const <String>[]) {
        final m = int.tryParse(s);
        if (m != null && m >= 0 && m < _themeNames.length) _themeUnlocked.add(m);
      }
      // Ancienne option « néon » → thème Néon
      _theme = (prefs.getInt(_kThemeKey) ?? ((prefs.getBool(_kNeonKey) ?? false) ? 1 : 0))
          .clamp(0, _themeNames.length - 1);
      if (!_themeUnlocked.contains(_theme)) _theme = 0;
      _haptics   = prefs.getBool(_kHapticsKey) ?? true;
      _tilt      = prefs.getBool(_kTiltKey) ?? false;
      _wheelReady = prefs.getString(_kWheelDayKey) != _todayKey();
      _freeContinue = prefs.getBool(_kFreeContKey) ?? false;
      try {
        _stats = Map<String, dynamic>.from(jsonDecode(prefs.getString(_kStatsKey) ?? '{}') as Map);
      } catch (_) {
        _stats = {};
      }
      _freeBonus = {
        for (final s in prefs.getStringList(_kFreeBonusKey) ?? const <String>[])
          if (int.tryParse(s) != null && int.parse(s) >= 0 && int.parse(s) < _bonusNames.length) int.parse(s),
      };
      _musicUnlocked = {0};
      for (final s in prefs.getStringList(_kMusicUnlockKey) ?? const <String>[]) {
        final m = int.tryParse(s);
        if (m != null && m >= 0 && m < _musicNames.length) _musicUnlocked.add(m);
      }
      _musicTrack = (prefs.getInt(_kMusicKey) ?? 0).clamp(0, _musicNames.length - 1);
      if (!_musicUnlocked.contains(_musicTrack)) _musicTrack = 0;
      _collection = _readCollection(prefs);
      final today = Leaderboard.today();
      final db = (prefs.getString(_kDailyKey) ?? '').split('|');
      _dailyBest = db.length >= 2 && db[0] == today ? int.tryParse(db[1]) ?? 0 : 0;
      final dr = (prefs.getString(_kDailyRankKey) ?? '').split('|');
      _dailyRank = dr.length >= 3 && dr[0] == today ? '#${dr[1]} / ${dr[2]}' : '';
      final wr = (prefs.getString(_kWorldRankKey) ?? '').split('|');
      _worldRank = wr.length >= 2 ? '#${wr[0]} / ${wr[1]}' : '';
      _loading   = false;
    });
  }

  /// Online name still automatic: ask for it once after a game
  Future<void> _askPseudoOnce() async {
    if (!Leaderboard.configured) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kPseudoAskedKey) ?? false) return;
    final cur = await Leaderboard.name();
    if (cur != null && !cur.startsWith('Player-')) return;
    await prefs.setBool(_kPseudoAskedKey, true);
    if (!mounted) return;
    final ctrl = TextEditingController(text: _bestName.isNotEmpty && _bestName != 'Anonymous' ? _bestName : '');
    String? error;
    bool busy = false;
    final chosen = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Future<void> submit() async {
          final n = Leaderboard.clean(ctrl.text);
          if (n.isEmpty || busy) return;
          setD(() {
            busy = true;
            error = null;
          });
          final res = await Leaderboard.rename(n);
          if (!ctx.mounted) return;
          if (res == Leaderboard.renameTaken) {
            setD(() {
              busy = false;
              error = '"$n" is already taken';
            });
          } else if (res == Leaderboard.renameInvalid) {
            setD(() {
              busy = false;
              error = 'Name rejected';
            });
          } else {
            Navigator.pop(ctx, n);
          }
        }

        return AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: const [
            Icon(Icons.leaderboard_rounded, color: Colors.amberAccent),
            SizedBox(width: 10),
            Expanded(child: Text('Your name', style: TextStyle(color: Colors.white, fontSize: 18))),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Choose the name shown on the online leaderboard.',
                style: TextStyle(color: Colors.white60, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 16,
              enabled: !busy,
              style: const TextStyle(color: Colors.white),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                hintText: 'Name…',
                hintStyle: const TextStyle(color: Colors.white38),
                errorText: error,
                filled: true,
                fillColor: Colors.white.withOpacity(0.06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                counterStyle: const TextStyle(color: Colors.white38),
              ),
            ),
          ]),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('OK'),
            ),
          ],
        );
      }),
    );
    ctrl.dispose();
    if (chosen != null && mounted) {
      setState(() => _lbMyName = chosen);
      _snack('Name saved : $chosen', ok: true);
    }
  }

  Future<void> _onGameFinished(int score) async {
    // Pièces et défis ont déjà été enregistrés par la partie : on recharge.
    await _load();
    if (!mounted) return;
    if (score <= _bestScore) {
      // No record (so no name entry): ask for the online name once
      await _askPseudoOnce();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBestScoreKey, score);
    if (!mounted) return;
    setState(() => _bestScore = score);
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.only(
          left: 24, right: 24, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Center(
          child: Material(
            color: const Color(0xFF1C2230),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('🏆 New record!',
                    style: TextStyle(color: Colors.amberAccent, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Text('$score pts',
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900)),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  maxLength: 12,
                  style: const TextStyle(color: Colors.white),
                  textInputAction: TextInputAction.done,
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
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(flex: 2, child: TextButton(
                    onPressed: () => Navigator.pop(ctx, ''),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Skip', maxLines: 1, softWrap: false),
                    ),
                  )),
                  const SizedBox(width: 8),
                  Expanded(flex: 3, child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    ),
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    child: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Save', maxLines: 1, softWrap: false),
                    ),
                  )),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
    ctrl.dispose();
    final finalName = (name ?? '').isEmpty ? 'Anonymous' : name!;
    await prefs.setString(_kBestNameKey, finalName);
    if (mounted) setState(() => _bestName = finalName);
    if (finalName != 'Anonymous') {
      final cur = await Leaderboard.name();
      if (cur == null || cur.startsWith('Player-')) {
        // Name already taken by another player: keep the current one
        final res = await Leaderboard.rename(finalName);
        if (mounted && res != Leaderboard.renameTaken && res != Leaderboard.renameInvalid) {
          setState(() => _lbMyName = Leaderboard.clean(finalName));
        }
      }
    }
  }

  /// [i] = -1 : muet ; sinon morceau [i] (déblocage si besoin).
  Future<void> _selectMusic(int i) async {
    if (i < 0) {
      await QuizAudio.setMusicEnabled(false);
      if (mounted) setState(() {});
      return;
    }
    if (!_musicUnlocked.contains(i)) {
      await _tryUnlockMusic(i);
      if (!_musicUnlocked.contains(i)) return;
    }
    setState(() => _musicTrack = i);
    QuizAudio.musicStart(i);
    await QuizAudio.setMusicEnabled(true);
    if (mounted) setState(() {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMusicKey, i);
  }

  Future<void> _tryUnlockMusic(int i) async {
    final price = _musicPrices[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Text('Unlock ${_musicNames[i]}?'),
        content: Row(children: [
          const SizedBox(width: 56, height: 50,
              child: Icon(Icons.music_note_rounded, color: Colors.purpleAccent, size: 36)),
          const SizedBox(width: 16),
          Expanded(child: Text('Price: $price coins\nYou have $_coins.${_coins < price ? '\nYou need ${price - _coins} more coins.' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: _coins >= price ? () => Navigator.pop(ctx, true) : null, child: const Text('Unlock')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _coins -= price;
      _musicUnlocked.add(i);
    });
    await prefs.setInt(_kCoinsKey, _coins);
    await prefs.setStringList(_kMusicUnlockKey, _musicUnlocked.map((e) => '$e').toList());
  }

  Widget _musicTile(int i, Color accent) {
    final muted = !QuizAudio.musicEnabled;
    final selected = i < 0 ? muted : (!muted && _musicTrack == i);
    final locked = i >= 0 && !_musicUnlocked.contains(i);
    return GestureDetector(
      onTap: () => _selectMusic(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.white.withOpacity(0.08),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(children: [
          SizedBox(
            width: 56, height: 40,
            child: Center(child: locked
                ? const Icon(Icons.lock_rounded, color: Colors.white70, size: 22)
                : Icon(i < 0 ? Icons.music_off_rounded : Icons.music_note_rounded,
                    size: 28,
                    color: selected
                        ? (i < 0 ? Colors.white70 : Colors.purpleAccent)
                        : Colors.white.withOpacity(0.25))),
          ),
          const SizedBox(height: 6),
          if (locked)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _CoinIcon(size: 11),
              const SizedBox(width: 3),
              Text('${_musicPrices[i]}',
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w700)),
            ])
          else
            Text(i < 0 ? 'Mute' : _musicNames[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
        ]),
      ),
    );
  }

  Future<void> _selectHero(int i) async {
    if (!_unlocked.contains(i)) {
      await _tryUnlock(i);
      return;
    }
    setState(() => _hero = i);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kHeroKey, i);
  }

  Future<void> _tryUnlock(int i) async {
    final price = _heroPrices[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Text('Unlock ${_heroNames[i]}?'),
        content: Row(children: [
          SizedBox(width: 56, height: 50, child: CustomPaint(painter: _HeroPreviewPainter(i))),
          const SizedBox(width: 16),
          Expanded(child: Text('${_heroPowers[i]}\n\nPrice: $price coins\nYou have $_coins.${_coins < price ? '\nYou need ${price - _coins} more coins.' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: _coins >= price ? () => Navigator.pop(ctx, true) : null, child: const Text('Unlock')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _coins -= price;
      _unlocked.add(i);
      _hero = i;
    });
    await prefs.setInt(_kCoinsKey, _coins);
    await prefs.setStringList(_kUnlockedKey, _unlocked.map((e) => '$e').toList());
    await prefs.setInt(_kHeroKey, i);
  }

  // ── Codes de triche : 5 appuis rapides sur le titre ──────────────────────
  int _titleTaps = 0;
  DateTime _lastTitleTap = DateTime(2000);

  void _onTitleTap() {
    final now = DateTime.now();
    if (now.difference(_lastTitleTap) > const Duration(milliseconds: 1500)) _titleTaps = 0;
    _lastTitleTap = now;
    if (++_titleTaps >= 5) {
      _titleTaps = 0;
      HapticFeedback.mediumImpact();
      _askCode();
    }
  }

  Future<void> _askCode() async {
    final ctrl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.vpn_key_rounded, color: Colors.amberAccent, size: 22),
          SizedBox(width: 8),
          Text('Secret code'),
        ]),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: Colors.white, letterSpacing: 2, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(hintText: 'Enter a code'),
          onSubmitted: (_) => Navigator.pop(ctx, ctrl.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Confirm')),
        ],
      ),
    );
    ctrl.dispose();
    if (code == null || code.trim().isEmpty || !mounted) return;
    final msg = await _applyCode(code);
    if (!mounted) return;
    ScaffoldMessenger.of(_sheetCtx ?? context).showSnackBar(SnackBar(
      content: Text(msg.$1, style: const TextStyle(color: Colors.white)),
      backgroundColor: msg.$2 ? const Color(0xFF1B5E20) : const Color(0xFF1C2230),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
    if (msg.$2) {
      QuizAudio.sfx('powerup');
      await _load();
    }
  }

  /// Applique un code ; renvoie (message, réussi).
  Future<(String, bool)> _applyCode(String raw) async {
    final code = raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    final hash = _codeHash(code);
    final effect = _cheatCodes[hash];
    if (effect == null) return ('Invalid code', false);
    final prefs = await SharedPreferences.getInstance();
    final used = (prefs.getStringList(_kCodesUsedKey) ?? const <String>[]).toSet();
    if (used.contains(hash)) return ('Code already used', false);
    final coins = prefs.getInt(_kCoinsKey) ?? 0;
    Future<void> all(String key, int count) =>
        prefs.setStringList(key, [for (int i = 0; i < count; i++) '$i']);
    String msg;
    switch (effect) {
      case 0:
        await prefs.setInt(_kCoinsKey, coins + 1000);
        msg = 'Code accepted: +1,000 coins!';
        break;
      case 1:
        await all(_kUnlockedKey, _heroCount);
        msg = 'Code accepted: all heroes unlocked!';
        break;
      case 2:
        await all(_kThemeUnlockKey, _themeNames.length);
        msg = 'Code accepted: all themes unlocked!';
        break;
      default:
        await all(_kMusicUnlockKey, _musicNames.length);
        msg = 'Code accepted: all music unlocked!';
    }
    used.add(hash);
    await prefs.setStringList(_kCodesUsedKey, used.toList());
    return (msg, true);
  }

  int get _bonusTotal =>
      _bonusSel.where((i) => !_freeBonus.contains(i)).fold(0, (a, i) => a + _bonusPrices[i]);

  void _toggleBonus(int i) {
    if (_freeBonus.contains(i)) return; // offert par la roue : toujours inclus
    if (_bonusSel.contains(i)) {
      setState(() => _bonusSel.remove(i));
      return;
    }
    final total = _bonusTotal + _bonusPrices[i];
    if (total > _coins) {
      ScaffoldMessenger.of(_sheetCtx ?? context).showSnackBar(SnackBar(
        content: Text('Not enough coins (you need ${total - _coins} more)', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1C2230),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }
    setState(() => _bonusSel.add(i));
  }

  Widget _bonusTile(int i, Color accent) {
    final free = _freeBonus.contains(i);
    final selected = free || _bonusSel.contains(i);
    return GestureDetector(
      onTap: () => _toggleBonus(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.white.withOpacity(0.08),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(children: [
          SizedBox(
            width: 56, height: 34,
            child: Center(child: Icon(_bonusIcons[i], size: 28,
                color: selected ? _bonusColors[i] : Colors.white.withOpacity(0.35))),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(_bonusNames[i],
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white54,
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  )),
            ),
          ),
          const SizedBox(height: 2),
          if (free)
            const Text('Free',
                style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.w800))
          else
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _CoinIcon(size: 10),
              const SizedBox(width: 3),
              Text('${_bonusPrices[i]}',
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 10, fontWeight: FontWeight.w700)),
            ]),
        ]),
      ),
    );
  }

  // ── Sauvegarde / chargement / réinitialisation ──────────────────────────
  void _snack(String msg, {bool ok = false}) {
    ScaffoldMessenger.of(_sheetCtx ?? context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: ok ? const Color(0xFF1B5E20) : const Color(0xFF1C2230),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  String _sign(String data) => sha256.convert(utf8.encode('$_saveSalt$data')).toString();

  /// Toutes les valeurs « jump_… » des préférences, avec leur type.
  Map<String, dynamic> _collectSave(SharedPreferences prefs) {
    final data = <String, dynamic>{};
    for (final k in prefs.getKeys()) {
      if (!k.startsWith('jump_')) continue;
      final v = prefs.get(k);
      if (v is bool) {
        data[k] = {'t': 'b', 'v': v};
      } else if (v is int) {
        data[k] = {'t': 'i', 'v': v};
      } else if (v is double) {
        data[k] = {'t': 'd', 'v': v};
      } else if (v is String) {
        data[k] = {'t': 's', 'v': v};
      } else if (v is List) {
        data[k] = {'t': 'l', 'v': v.map((e) => '$e').toList()};
      }
    }
    return data;
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_collectSave(prefs));
    final content = const JsonEncoder.withIndent('  ').convert({
      'game': 'retro_jump',
      'version': 1,
      'date': DateTime.now().toIso8601String(),
      'data': jsonDecode(data),
      'sig': _sign(data),
    });
    if (!mounted) return;
    // Choix du dossier de destination (picker de l'appli)
    final folder = await Navigator.of(context, rootNavigator: true).push<InAppFolderPickerResult>(
      MaterialPageRoute(
        builder: (_) => const InAppFilePicker(pickFolderMode: true),
        fullscreenDialog: true,
      ),
    );
    if (folder == null || !mounted) return;
    final n = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final name = 'retro_jump_${n.year}${two(n.month)}${two(n.day)}_${two(n.hour)}${two(n.minute)}.json';
    try {
      final file = File('${folder.path}/$name');
      await file.writeAsString(content, flush: true);
      _snack('Progress saved: ${folder.name}/$name', ok: true);
    } catch (_) {
      // Pas d'accès au dossier : on propose le partage du fichier
      try {
        final tmp = File('${(await getTemporaryDirectory()).path}/$_saveFileName');
        await tmp.writeAsString(content, flush: true);
        _snack('Cannot write to this folder: choose where to send the save');
        await Share.shareXFiles([XFile(tmp.path)]);
      } catch (_) {}
    }
  }

  Future<void> _loadProgress() async {
    // Choix du fichier de sauvegarde (picker de l'appli, .json uniquement)
    final picked = await Navigator.of(context, rootNavigator: true).push<List<InAppFilePickerResult>>(
      MaterialPageRoute(
        builder: (_) => const InAppFilePicker(allowedExtensions: {'json'}, allowMultiple: false),
        fullscreenDialog: true,
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    final file = File(picked.first.localPath);
    Map<String, dynamic> save;
    try {
      save = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      _snack('Invalid or modified save file');
      return;
    }
    final data = save['data'];
    if (save['game'] != 'retro_jump' || data is! Map<String, dynamic> ||
        save['sig'] != _sign(jsonEncode(data))) {
      _snack('Invalid or modified save file');
      return;
    }
    final d = DateTime.tryParse('${save['date']}');
    final when = d == null
        ? '?'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Load the save?'),
        content: Text('Save from $when.\nYour current progress will be replaced.', style: const TextStyle(color: Colors.white70, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Load')),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await _clearProgress(prefs);
    for (final e in data.entries) {
      final m = e.value;
      if (m is! Map) continue;
      final v = m['v'];
      switch (m['t']) {
        case 'b':
          if (v is bool) await prefs.setBool(e.key, v);
          break;
        case 'i':
          if (v is int) await prefs.setInt(e.key, v);
          break;
        case 'd':
          if (v is num) await prefs.setDouble(e.key, v.toDouble());
          break;
        case 's':
          if (v is String) await prefs.setString(e.key, v);
          break;
        case 'l':
          if (v is List) await prefs.setStringList(e.key, v.map((x) => '$x').toList());
          break;
      }
    }
    await _afterProgressChange();
    _snack('Progress loaded', ok: true);
  }

  Future<void> _clearProgress(SharedPreferences prefs) async {
    for (final k in prefs.getKeys().toList()) {
      if (k.startsWith('jump_')) await prefs.remove(k);
    }
  }

  Future<void> _resetProgress() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
          SizedBox(width: 8),
          Expanded(child: Text('Reset everything?')),
        ]),
        content: const Text('Coins, heroes, themes, music, record, challenges and collection will be erased. Remember to save first!', style: TextStyle(color: Colors.white70, height: 1.4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await _clearProgress(prefs);
    await _afterProgressChange();
    _snack('Progress reset', ok: true);
  }

  /// Recharge l'accueil et la musique après un chargement / une remise à zéro.
  Future<void> _afterProgressChange() async {
    _bonusSel.clear();
    await _load();
    QuizAudio.musicStart(_musicTrack);
  }

  Widget _saveButton(IconData icon, String label, Color color, VoidCallback onTap) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.5)),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 22),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  // ── Roue de la fortune ────────────────────────────────────────────────────
  Future<void> _openWheel() async {
    final code = await showDialog<int>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _WheelDialog(ready: _wheelReady, coins: _coins),
    );
    if (code == null || !mounted) return;
    final paid = code >= 100; // tour payant : code = segment + 100
    final s = _wheel[code % 100];
    final prefs = await SharedPreferences.getInstance();
    if (paid) {
      _coins -= _wheelSpinPrice;
      await prefs.setInt(_kCoinsKey, _coins);
    } else {
      await prefs.setString(_kWheelDayKey, _todayKey());
    }
    if (s.bonus == 4) {
      _freeContinue = true;
      await prefs.setBool(_kFreeContKey, true);
    } else if (s.coins > 0) {
      _coins += s.coins;
      await prefs.setInt(_kCoinsKey, _coins);
    } else if (s.bonus >= 0) {
      _freeBonus.add(s.bonus);
      await prefs.setStringList(_kFreeBonusKey, _freeBonus.map((e) => '$e').toList());
    }
    if (!mounted) return;
    setState(() {
      if (!paid) _wheelReady = false;
      _bonusSel.remove(s.bonus);
    });
    QuizAudio.sfx('powerup');
    _snack(s.coins > 0 ? 'Wheel: +${s.coins} coins!' : 'Wheel: free ${_prizeName(s.bonus)} for your next game!', ok: true);
  }

  Future<void> _selectTheme(int i) async {
    if (!_themeUnlocked.contains(i)) {
      await _tryUnlockTheme(i);
      if (!_themeUnlocked.contains(i)) return;
    }
    setState(() => _theme = i);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kThemeKey, i);
  }

  Future<void> _tryUnlockTheme(int i) async {
    final price = _themePrices[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Text('Unlock ${_themeNames[i]}?'),
        content: Row(children: [
          _ThemeSwatch(theme: i, size: 50),
          const SizedBox(width: 16),
          Expanded(child: Text('Price: $price coins\nYou have $_coins.${_coins < price ? '\nYou need ${price - _coins} more coins.' : ''}',
              style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: _coins >= price ? () => Navigator.pop(ctx, true) : null, child: const Text('Unlock')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _coins -= price;
      _themeUnlocked.add(i);
      _theme = i;
    });
    await prefs.setInt(_kCoinsKey, _coins);
    await prefs.setStringList(_kThemeUnlockKey, _themeUnlocked.map((e) => '$e').toList());
    await prefs.setInt(_kThemeKey, i);
  }

  Widget _themeTile(int i, Color accent) {
    final selected = _theme == i;
    final locked = !_themeUnlocked.contains(i);
    return GestureDetector(
      onTap: () => _selectTheme(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.white.withOpacity(0.08),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(children: [
          SizedBox(
            width: 56, height: 40,
            child: Center(child: Stack(alignment: Alignment.center, children: [
              Opacity(opacity: locked ? 0.3 : 1, child: _ThemeSwatch(theme: i, size: 34)),
              if (locked) const Icon(Icons.lock_rounded, color: Colors.white70, size: 20),
            ])),
          ),
          const SizedBox(height: 6),
          if (locked)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _CoinIcon(size: 11),
              const SizedBox(width: 3),
              Text('${_themePrices[i]}',
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w700)),
            ])
          else
            Text(_themeNames[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
        ]),
      ),
    );
  }

  Future<void> _setHaptics(bool v) async {
    setState(() => _haptics = v);
    if (v) HapticFeedback.mediumImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHapticsKey, v);
  }

  Future<void> _setTilt(bool v) async {
    setState(() => _tilt = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kTiltKey, v);
  }

  Future<void> _startGame({bool daily = false}) async {
    // Bonus : payés maintenant, appliqués à cette partie seulement
    // (partie du jour : ni bonus ni continue, ils restent pour la prochaine partie normale)
    final bonus = daily ? <int>{} : {..._bonusSel, ..._freeBonus};
    final cost = daily ? 0 : _bonusTotal;
    final freeCont = !daily && _freeContinue;
    if (freeCont) {
      setState(() => _freeContinue = false);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kFreeContKey);
      if (!mounted) return;
    }
    if (!daily && _freeBonus.isNotEmpty) {
      // Bonus offerts par la roue : consommés par cette partie
      setState(() => _freeBonus.clear());
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kFreeBonusKey);
      if (!mounted) return;
    }
    if (cost > 0) {
      if (cost > _coins) {
        setState(() => _bonusSel.clear());
        return;
      }
      setState(() {
        _coins -= cost;
        _bonusSel.clear();
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kCoinsKey, _coins);
      if (!mounted) return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _JumpGame(
        bestScore: _bestScore,
        hero: _hero,
        theme: _theme,
        haptics: _haptics,
        tilt: _tilt,
        completed: Set<String>.of(_completed),
        challengeLevel: _challengeLevel,
        startPts: (bonus.contains(0) ? 500 : 0) + (bonus.contains(1) ? 1000 : 0),
        startShield: bonus.contains(2),
        startTurbo: bonus.contains(3),
        freeContinue: freeCont,
        daily: daily ? Leaderboard.today() : null,
        onFinished: _onGameFinished,
      ),
    )).then((_) {
      // Recharge (ex. logos attrapés avant d'avoir quitté la partie)
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final challenges = _challengesFor(_challengeLevel);
    final doneCount = challenges.where((c) => _completed.contains(c.id)).length;
    final logoCount = _collection.where((n) => n >= _logoGoal).length;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // En-tête : titre (5 appuis = code secret), pièces, son
          Padding(
            padding: const EdgeInsets.fromLTRB(64, 8, 16, 0),
            child: Row(children: [
              // Titre réduit au besoin pour laisser la place aux boutons
              Expanded(
                child: GestureDetector(
                  onTap: _onTitleTap,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('Retro Jump', style: Theme.of(context).textTheme.headlineMedium),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amberAccent.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const _CoinIcon(size: 14),
                  const SizedBox(width: 5),
                  Text('$_coins',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 14, fontWeight: FontWeight.w800)),
                ]),
              ),
              const SizedBox(width: 8),
              // Statistiques à vie
              GestureDetector(
                onTap: _openStats,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(Icons.bar_chart_rounded, color: Colors.tealAccent, size: 20),
                ),
              ),
              const SizedBox(width: 8),
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
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFE02020)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                    child: Column(children: [
                      // Record
                      Row(children: [
                        const Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 20),
                        const SizedBox(width: 8),
                        const Text('Best ',
                            style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(_bestScore == 0 ? '— pts' : '$_bestScore pts',
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 18, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 8),
                        if (_bestName.isNotEmpty)
                          Expanded(child: Text('by $_bestName',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white38, fontSize: 12))),
                      ]),
                      const SizedBox(height: 10),
                      // Partie du jour + Classement : bien visibles, juste sous le record
                      IntrinsicHeight(
                        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Expanded(child: _homeTile(
                            icon: Icons.today_rounded,
                            color: Colors.lightBlueAccent,
                            title: 'Daily run',
                            sub: _dailyBest > 0
                                ? '${_fmtNum(_dailyBest)} pts${_dailyRank.isNotEmpty ? ' · $_dailyRank' : ''}'
                                : 'Play today!',
                            badge: _dailyBest == 0,
                            trailing: Icons.play_arrow_rounded,
                            onTap: _openDaily,
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _homeTile(
                            icon: Icons.leaderboard_rounded,
                            color: Colors.amberAccent,
                            title: 'Ranking',
                            sub: _worldRank.isNotEmpty ? '🌍 $_worldRank' : 'World top',
                            onTap: _openLeaderboard,
                          )),
                        ]),
                      ),
                      const SizedBox(height: 12),

                      // Scène du héros : touche = boutique
                      GestureDetector(
                        onTap: _openShop,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: Colors.white.withOpacity(0.08)),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                _themeSwatch[_theme][0].withOpacity(0.28),
                                _themeSwatch[_theme][1].withOpacity(0.10),
                                const Color(0xFF1C2230),
                              ],
                            ),
                          ),
                          child: Stack(alignment: Alignment.topCenter, clipBehavior: Clip.none, children: [
                        Column(children: [
                            AnimatedBuilder(
                              animation: _idle,
                              builder: (_, __) => SizedBox(
                                width: 130, height: 112,
                                child: CustomPaint(painter: _HeroPreviewPainter(_hero, 0.05 + _idle.value * 60)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(_heroNames[_hero],
                                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text('⚡ ${_heroPowers[_hero]}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
                              _chip(_ThemeSwatch(theme: _theme, size: 14), _themeNames[_theme]),
                              _chip(
                                Icon(QuizAudio.musicEnabled ? Icons.music_note_rounded : Icons.music_off_rounded,
                                    size: 14, color: QuizAudio.musicEnabled ? Colors.purpleAccent : Colors.white38),
                                QuizAudio.musicEnabled ? _musicNames[_musicTrack] : 'Mute',
                              ),
                            ]),
                          ]),
                        Positioned(
                          top: -2, right: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withOpacity(0.18)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: const [
                              Icon(Icons.edit_rounded, size: 13, color: Colors.white70),
                              SizedBox(width: 5),
                              Text('Customize',
                                  style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
                            ]),
                          ),
                        ),
                          ]),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Bonus de départ
                      Row(children: [
                        const Icon(Icons.shopping_bag_rounded, color: Colors.orangeAccent, size: 16),
                        const SizedBox(width: 6),
                        const Text('Bonus for this game',
                            style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        if (_freeContinue) ...[
                          const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 13),
                          const SizedBox(width: 3),
                          const Text('Free continue',
                              style: TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                          const SizedBox(width: 8),
                        ],
                        if (_bonusSel.isNotEmpty) ...[
                          const _CoinIcon(size: 12),
                          const SizedBox(width: 4),
                          Text('$_bonusTotal',
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w800)),
                        ],
                      ]),
                      const SizedBox(height: 8),
                      Row(children: [
                        for (int i = 0; i < _bonusNames.length; i++)
                          Expanded(child: _bonusTile(i, accent)),
                      ]),
                      const SizedBox(height: 16),

                      // Jouer
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _startGame,
                          icon: const Icon(Icons.play_arrow_rounded, size: 28),
                          label: const Text('Play', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1)),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          ),
                        ),
                      ),
                    ]),
                  ),
          ),

          // Barre du bas : boutique, défis, collection, réglages
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            decoration: BoxDecoration(
              color: const Color(0xFF151A24),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
            ),
            child: Row(children: [
              _navButton(Icons.storefront_rounded, 'Shop', Colors.pinkAccent,
                  '${_unlocked.length + _themeUnlocked.length + _musicUnlocked.length}', _openShop),
              _navButton(Icons.military_tech_rounded, 'Challenges', Colors.amberAccent,
                  '$doneCount/${challenges.length}', _openChallenges),
              _navButton(Icons.collections_bookmark_rounded, 'Collection', Colors.lightBlueAccent,
                  '$logoCount/${_logoAssets.length}', _openCollection),
              _navButton(Icons.casino_rounded, 'Wheel', Colors.purpleAccent, _wheelReady ? '1' : null, _openWheel),
              _navButton(Icons.settings_rounded, 'Settings', Colors.cyanAccent, null, _openSettings),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _chip(Widget lead, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          lead,
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _navButton(IconData icon, String label, Color color, String? badge, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(clipBehavior: Clip.none, children: [
              Container(
                width: 46, height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              if (badge != null)
                Positioned(
                  right: -10, top: -6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D0F14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: color.withOpacity(0.6)),
                    ),
                    child: Text(badge, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  // ── Panneaux (montent du bas) ──────────────────────────────────────────────
  // Ils se reconstruisent à chaque setState de l'accueil (via _rev).
  final ValueNotifier<int> _rev = ValueNotifier(0);
  BuildContext? _sheetCtx; // pour afficher les messages au-dessus du panneau

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _rev.value++;
  }

  void _openSheet(String title, IconData icon, Color color, Widget Function(Color accent) body,
      {bool showCoins = true}) {
    final accent = Theme.of(context).colorScheme.primary;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: ScaffoldMessenger(
            child: Builder(builder: (ctx) {
              _sheetCtx = ctx;
              return Scaffold(
                backgroundColor: const Color(0xFF151A24),
                body: Column(children: [
                  const SizedBox(height: 10),
                  Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
                    child: Row(children: [
                      Icon(icon, color: color, size: 22),
                      const SizedBox(width: 10),
                      Expanded(child: Text(title,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
                      if (showCoins) ValueListenableBuilder<int>(
                        valueListenable: _rev,
                        builder: (_, __, ___) => Row(children: [
                          const _CoinIcon(size: 14),
                          const SizedBox(width: 5),
                          Text('$_coins',
                              style: const TextStyle(color: Colors.amberAccent, fontSize: 14, fontWeight: FontWeight.w800)),
                        ]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white54),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _rev,
                      builder: (_, __, ___) => SingleChildScrollView(
                        // + hauteur de la barre de navigation Android
                        padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.of(ctx).viewPadding.bottom),
                        child: body(accent),
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ),
        ),
      ),
    ).whenComplete(() => _sheetCtx = null);
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 10),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(text,
              style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
        ),
      );

  Widget _grid(int count, Widget Function(int i) tile) => Column(children: [
        for (int row = 0; row * 4 < count; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(children: [
            for (int i = row * 4; i < row * 4 + 4; i++)
              Expanded(child: i < count ? tile(i) : const SizedBox()),
          ]),
        ],
      ]);

  /// Tuile de l'accueil (partie du jour, classement) : même gabarit pour les deux
  Widget _homeTile({
    required IconData icon,
    required Color color,
    required String title,
    required String sub,
    required VoidCallback onTap,
    IconData trailing = Icons.chevron_right_rounded,
    bool badge = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(badge ? 0.8 : 0.35), width: badge ? 1.5 : 1),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Stack(clipBehavior: Clip.none, children: [
              Icon(icon, color: color, size: 22),
              if (badge)
                Positioned(
                  right: -3, top: -3,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0D0F14), width: 1.5),
                    ),
                  ),
                ),
            ]),
            const SizedBox(width: 8),
            Expanded(child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(title,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
            )),
            Icon(trailing, color: color, size: 20),
          ]),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(sub,
                maxLines: 1,
                style: TextStyle(color: color.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  // ── Partie du jour : page avec scores du jour, choix et bouton Jouer ──────
  LbBoard? _dayBoard;
  bool _dayLoading = false, _dayFailed = false;

  Future<void> _dayLoad() async {
    setState(() {
      _dayLoading = true;
      _dayFailed = false;
    });
    final b = await Leaderboard.fetch('daily', Leaderboard.today());
    final pid = await Leaderboard.publicId();
    if (!mounted) return;
    setState(() {
      _dayBoard = b;
      _dayFailed = b == null;
      _dayLoading = false;
      _lbPid = pid;
      if (b != null && b.me.rank != null) _dailyRank = '#${b.me.rank} / ${b.me.total}';
    });
  }

  void _openDaily() {
    if (Leaderboard.configured) _dayLoad();
    _openSheet('Daily run', Icons.today_rounded, Colors.lightBlueAccent, (accent) {
      final b = _dayBoard;
      final heroes = [for (int i = 0; i < _heroCount; i++) if (_unlocked.contains(i)) i];
      final themes = [for (int i = 0; i < _themeNames.length; i++) if (_themeUnlocked.contains(i)) i];
      final tracks = [for (int i = 0; i < _musicNames.length; i++) if (_musicUnlocked.contains(i)) i];
      return Column(children: [
        // Règles du jour
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.lightBlueAccent.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.lightBlueAccent.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline_rounded, color: Colors.lightBlueAccent, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(
              _dailyBest > 0
                  ? 'Your best today : ${_fmtNum(_dailyBest)} pts${_dailyRank.isNotEmpty ? ' · $_dailyRank' : ''}\nSame course for everyone, no bonus, continue or coins.\n🔁 Play as many times as you like: only your best score counts.'
                  : 'Same course for everyone, no bonus, continue or coins. New course every day at midnight.\n🔁 Play as many times as you like: only your best score counts.',
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            )),
          ]),
        ),
        const SizedBox(height: 12),
        // Choix : héros / décor / musique (uniquement ce qui est débloqué)
        Row(children: [
          Expanded(child: _dayPick<int>(
            label: 'Hero',
            lead: SizedBox(width: 30, height: 26, child: CustomPaint(painter: _HeroPreviewPainter(_hero))),
            value: _heroNames[_hero],
            items: [
              for (final i in heroes)
                PopupMenuItem(value: i, child: Row(children: [
                  SizedBox(width: 28, height: 24, child: CustomPaint(painter: _HeroPreviewPainter(i))),
                  const SizedBox(width: 10),
                  Text(_heroNames[i], style: TextStyle(color: i == _hero ? Colors.lightBlueAccent : Colors.white)),
                ])),
            ],
            onSelected: _selectHero,
          )),
          const SizedBox(width: 8),
          Expanded(child: _dayPick<int>(
            label: 'Theme',
            lead: _ThemeSwatch(theme: _theme, size: 22),
            value: _themeNames[_theme],
            items: [
              for (final i in themes)
                PopupMenuItem(value: i, child: Row(children: [
                  _ThemeSwatch(theme: i, size: 20),
                  const SizedBox(width: 10),
                  Text(_themeNames[i], style: TextStyle(color: i == _theme ? Colors.lightBlueAccent : Colors.white)),
                ])),
            ],
            onSelected: _selectTheme,
          )),
          const SizedBox(width: 8),
          Expanded(child: _dayPick<int>(
            label: 'Music',
            lead: Icon(QuizAudio.musicEnabled ? Icons.music_note_rounded : Icons.music_off_rounded,
                color: QuizAudio.musicEnabled ? Colors.purpleAccent : Colors.white38, size: 22),
            value: QuizAudio.musicEnabled ? _musicNames[_musicTrack] : 'Mute',
            items: [
              PopupMenuItem(value: -1, child: Row(children: [
                const Icon(Icons.music_off_rounded, color: Colors.white54, size: 20),
                const SizedBox(width: 10),
                Text('Mute', style: TextStyle(color: !QuizAudio.musicEnabled ? Colors.lightBlueAccent : Colors.white)),
              ])),
              for (final i in tracks)
                PopupMenuItem(value: i, child: Row(children: [
                  const Icon(Icons.music_note_rounded, color: Colors.purpleAccent, size: 20),
                  const SizedBox(width: 10),
                  Text(_musicNames[i],
                      style: TextStyle(color: QuizAudio.musicEnabled && i == _musicTrack ? Colors.lightBlueAccent : Colors.white)),
                ])),
            ],
            onSelected: _selectMusic,
          )),
        ]),
        const SizedBox(height: 12),
        // Jouer
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              final ctx = _sheetCtx;
              if (ctx != null) Navigator.of(ctx).pop();
              _startGame(daily: true);
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 26),
            label: const Text('Play the daily run',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.lightBlueAccent.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
        // Scores du jour
        _section('Today\'s scores${b != null ? '  ·  ${b.me.total} players' : ''}'),
        if (!Leaderboard.configured)
          _lbInfo(Icons.cloud_off_rounded, 'Online leaderboard not set up', '')
        else if (_dayLoading && b == null)
          const Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(color: Colors.lightBlueAccent),
          )
        else if (_dayFailed)
          _lbInfo(Icons.wifi_off_rounded, 'Offline', 'Scores unavailable right now.',
              retry: _dayLoad)
        else if (b != null) ...[
          if (b.top.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Nobody has played today yet: be the first!',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)),
            ),
          for (int i = 0; i < b.top.length; i++) _lbRow(i, b.top[i]),
        ],
      ]);
    }, showCoins: false);
  }

  /// Case de choix (menu déroulant limité aux éléments débloqués)
  Widget _dayPick<T>({
    required String label,
    required Widget lead,
    required String value,
    required List<PopupMenuEntry<T>> items,
    required void Function(T) onSelected,
  }) {
    return PopupMenuButton<T>(
      color: const Color(0xFF1C2230),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      itemBuilder: (_) => items,
      onSelected: onSelected,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700))),
            const Icon(Icons.expand_more_rounded, color: Colors.white38, size: 18),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            lead,
            const SizedBox(width: 6),
            Expanded(child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  maxLines: 1,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
            )),
          ]),
        ]),
      ),
    );
  }

  // ── Classement en ligne ────────────────────────────────────────────────────
  Future<void> _lbLoad() async {
    final tab = _lbTab;
    setState(() {
      _lbLoading = true;
      _lbFailed = false;
    });
    final daily = tab == 0;
    final b = await Leaderboard.fetch(daily ? 'daily' : 'all', daily ? Leaderboard.today() : lbAllDay);
    final n = await Leaderboard.name();
    final pid = await Leaderboard.publicId();
    if (!mounted || tab != _lbTab) return;
    setState(() {
      _lbBoard = b;
      _lbFailed = b == null;
      _lbLoading = false;
      _lbMyName = n;
      _lbPid = pid;
      if (daily && b != null && b.me.rank != null) _dailyRank = '#${b.me.rank} / ${b.me.total}';
      if (!daily && b != null && b.me.rank != null) _worldRank = '#${b.me.rank} / ${b.me.total}';
    });
  }

  void _openLeaderboard() {
    _lbBoard = null;
    if (Leaderboard.configured) {
      _lbLoad();
    } else {
      Leaderboard.name().then((n) {
        if (mounted) setState(() => _lbMyName = n);
      });
    }
    _openSheet('Leaderboard', Icons.leaderboard_rounded, Colors.amberAccent, (accent) {
      if (!Leaderboard.configured) {
        return _lbInfo(Icons.cloud_off_rounded, 'Online leaderboard not set up',
            'Fill in kLbUrl and kLbKey in leaderboard_service.dart.');
      }
      final b = _lbBoard;
      return Column(children: [
        Row(children: [
          Expanded(child: _lbTabBtn(0, Icons.today_rounded, 'Today', accent)),
          const SizedBox(width: 8),
          Expanded(child: _lbTabBtn(1, Icons.public_rounded, 'All time', accent)),
        ]),
        const SizedBox(height: 10),
        // Pseudo
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2230),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            const Icon(Icons.person_rounded, color: Colors.white54, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Text('Name : ${_lbMyName ?? '—'}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600))),
            TextButton.icon(
              onPressed: _lbEditName,
              icon: const Icon(Icons.edit_rounded, size: 16),
              label: const Text('Edit'),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        if (_lbLoading && b == null)
          const Padding(
            padding: EdgeInsets.all(30),
            child: CircularProgressIndicator(color: Colors.amberAccent),
          )
        else if (_lbFailed)
          _lbInfo(Icons.wifi_off_rounded, 'Offline', 'Leaderboard unavailable right now.',
              retry: _lbLoad)
        else if (b != null) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
            ),
            child: Text(
              b.me.rank != null
                  ? 'Your rank : #${b.me.rank} / ${b.me.total}  ·  ${_fmtNum(b.me.score ?? 0)} pts'
                  : (_lbTab == 0
                      ? 'No score today yet: play the daily run!'
                      : 'No score yet: play a game to enter the leaderboard.'),
              style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          if (b.top.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No scores yet.', style: TextStyle(color: Colors.white38)),
            ),
          for (int i = 0; i < b.top.length; i++) _lbRow(i, b.top[i]),
        ],
        const SizedBox(height: 8),
        Text(
          _lbTab == 0
              ? 'Daily run: same course for everyone, no start bonus, continue or coins. New course every day at midnight. Only your best score counts.'
              : 'Best score of each player, all games included.',
          style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
        ),
      ]);
    });
  }

  Widget _lbTabBtn(int i, IconData icon, String label, Color accent) {
    final sel = _lbTab == i;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (_lbTab == i) return;
        setState(() {
          _lbTab = i;
          _lbBoard = null;
        });
        _lbLoad();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? accent.withOpacity(0.18) : const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? accent : Colors.white.withOpacity(0.06)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: sel ? Colors.white : Colors.white54),
          const SizedBox(width: 6),
          Flexible(child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: sel ? Colors.white : Colors.white54, fontSize: 13, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }

  Widget _lbRow(int i, LbEntry e) {
    final me = e.pid == _lbPid;
    const medals = ['🥇', '🥈', '🥉'];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: me ? Colors.amberAccent.withOpacity(0.12) : const Color(0xFF1C2230),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: me ? Colors.amberAccent.withOpacity(0.5) : Colors.white.withOpacity(0.05)),
      ),
      child: Row(children: [
        SizedBox(
          width: 34,
          child: i < 3
              ? Text(medals[i], style: const TextStyle(fontSize: 18))
              : Text('${i + 1}', style: const TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w800)),
        ),
        SizedBox(width: 24, height: 22,
            child: CustomPaint(painter: _HeroPreviewPainter(min(max(e.hero, 0), _heroCount - 1)))),
        const SizedBox(width: 10),
        Expanded(child: Text(e.name,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: me ? Colors.amberAccent : Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
        const SizedBox(width: 8),
        Text('${_fmtNum(e.score)} pts',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _lbInfo(IconData icon, String title, String sub, {VoidCallback? retry}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(children: [
          Icon(icon, color: Colors.white38, size: 40),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(sub, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          if (retry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: retry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ]),
      );

  Future<void> _lbEditName() async {
    final ctrl = TextEditingController(text: _lbMyName ?? '');
    final n = await showDialog<String>(
      context: _sheetCtx ?? context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Your name', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 16,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'Name…', hintStyle: TextStyle(color: Colors.white38)),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('OK')),
        ],
      ),
    );
    ctrl.dispose();
    if (n == null || Leaderboard.clean(n).isEmpty) return;
    final res = await Leaderboard.rename(n);
    if (!mounted) return;
    if (res == Leaderboard.renameTaken) {
      _snack('"${Leaderboard.clean(n)}" is already taken, pick another one');
      return;
    }
    if (res == Leaderboard.renameInvalid) {
      _snack('Name rejected');
      return;
    }
    setState(() => _lbMyName = Leaderboard.clean(n));
    final ok = res == Leaderboard.renameOk;
    _snack(ok ? 'Name saved' : 'Name saved (sent with your next score)', ok: ok);
    if (ok && Leaderboard.configured) _lbLoad();
  }

  void _openStats() => _openSheet('Statistics', Icons.bar_chart_rounded, Colors.tealAccent, (accent) {
        final s = _stats;
        int v(String k) => (s[k] as num?)?.toInt() ?? 0;
        final games = v('games');
        final secs = v('time');
        final time = secs >= 3600 ? '${secs ~/ 3600} h ${(secs % 3600) ~/ 60} min' : '${secs ~/ 60} min ${secs % 60} s';
        final items = <(IconData, Color, String, String)>[
          (Icons.sports_esports_rounded, Colors.cyanAccent, 'Games played', _fmtNum(games)),
          (Icons.emoji_events_rounded, Colors.amberAccent, 'Best score', '${_fmtNum(_bestScore)} pts'),
          (Icons.landscape_rounded, Colors.purpleAccent, 'Total points', '${_fmtNum(v('pts'))} pts'),
          (Icons.show_chart_rounded, Colors.lightBlueAccent, 'Average / game', games == 0 ? '—' : '${_fmtNum(v('pts') ~/ games)} pts'),
          (Icons.keyboard_double_arrow_up_rounded, Colors.cyanAccent, 'Jumps', _fmtNum(v('jumps'))),
          (Icons.local_fire_department_rounded, Colors.deepOrangeAccent, 'Best combo', _fmtNum(v('combo'))),
          (Icons.monetization_on_rounded, Colors.amberAccent, 'Coins earned', _fmtNum(v('coins'))),
          (Icons.savings_rounded, Colors.amberAccent, 'Bags collected', _fmtNum(v('bags'))),
          (Icons.bug_report_rounded, Colors.lightGreenAccent, 'Bugs stomped', _fmtNum(v('stomps'))),
          (Icons.rocket_launch_rounded, Colors.greenAccent, 'Turbos', _fmtNum(v('turbos'))),
          (Icons.collections_bookmark_rounded, Colors.lightBlueAccent, 'Logos caught', _fmtNum(v('logos'))),
          (Icons.replay_rounded, Colors.white70, 'Continues used', _fmtNum(v('cont'))),
          (Icons.south_rounded, Colors.redAccent, 'Falls', _fmtNum(v('falls'))),
          (Icons.pest_control_rounded, Colors.redAccent, 'Killed by a bug', _fmtNum(v('bugdeaths'))),
          (Icons.timer_rounded, Colors.tealAccent, 'Play time', time),
        ];
        return Column(children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.6,
            children: [
              for (final it in items)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2230),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: it.$2.withOpacity(0.25)),
                  ),
                  child: Row(children: [
                    Icon(it.$1, color: it.$2, size: 22),
                    const SizedBox(width: 10),
                    Expanded(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(it.$4,
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                        ),
                        Text(it.$3,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 11)),
                      ],
                    )),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('The combo grows with each cartridge higher than the previous one: ×2 from 5, ×3 from 10… (max ×5). It multiplies the coins you pick up.', style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4)),
        ]);
      });

  void _openShop() => _openSheet('Shop', Icons.storefront_rounded, Colors.pinkAccent, (accent) => Column(children: [
        _section('Hero  ·  ${_unlocked.length}/$_heroCount'),
        _grid(_heroCount, (i) => _heroTile(i, accent)),
        _section('Theme  ·  ${_themeUnlocked.length}/${_themeNames.length}'),
        _grid(_themeNames.length, (i) => _themeTile(i, accent)),
        _section('Music  ·  ${_musicUnlocked.length}/${_musicNames.length}'),
        Row(children: [
          Expanded(child: _musicTile(-1, accent)),
          for (int i = 0; i < _musicNames.length; i++)
            Expanded(child: _musicTile(i, accent)),
        ]),
      ]));

  void _openChallenges() {
    final challenges = _challengesFor(_challengeLevel);
    _openSheet('Challenges', Icons.military_tech_rounded, Colors.amberAccent, (accent) => Column(children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Set ${_challengeLevel + 1}',
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const Spacer(),
            Text('${challenges.where((c) => _completed.contains(c.id)).length}/${challenges.length}',
                style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 8),
          for (final c in challenges)
            _ChallengeRow(challenge: c, done: _completed.contains(c.id)),
        ]));
  }

  void _openCollection() => _openSheet('Collection', Icons.collections_bookmark_rounded, Colors.lightBlueAccent,
      (accent) => Column(children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.lightBlueAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Album ${_album + 1}',
                    style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Text('${_collection.where((n) => n >= _logoGoal).length}/${_logoAssets.length}',
                  style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 10),
            // Cadeau de fin d'album
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amberAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amberAccent.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.card_giftcard_rounded, color: Colors.amberAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Album complete = ${_albumBonus(_album)} coins gift',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                const _CoinIcon(size: 14),
              ]),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.15,
              children: [
                for (int i = 0; i < _logoAssets.length; i++)
                  _CollectionTile(index: i, count: _collection[i]),
              ],
            ),
            const SizedBox(height: 12),
            Text('Catch each logo $_logoGoal times along the way to complete its slot.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white38, fontSize: 12)),
          ]));

  void _openSettings() => _openSheet('Settings', Icons.settings_rounded, Colors.cyanAccent, (accent) => Column(children: [
        _section('Options'),
        Row(children: [
          Expanded(child: _OptionTile(icon: Icons.vibration_rounded, color: Colors.cyanAccent,
              label: 'Vibration', value: _haptics, accent: accent, onTap: () => _setHaptics(!_haptics))),
          Expanded(child: _OptionTile(icon: Icons.screen_rotation_rounded, color: Colors.lightGreenAccent,
              label: 'Tilt', value: _tilt, accent: accent, onTap: () => _setTilt(!_tilt))),
          Expanded(child: _OptionTile(
              icon: QuizAudio.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: Colors.amberAccent,
              label: 'Sound', value: QuizAudio.enabled, accent: accent,
              onTap: () => setState(() => QuizAudio.enabled = !QuizAudio.enabled))),
        ]),
        _section('Save'),
        Row(children: [
          Expanded(child: _saveButton(Icons.save_rounded, 'Save', Colors.greenAccent, _saveProgress)),
          const SizedBox(width: 8),
          Expanded(child: _saveButton(Icons.folder_open_rounded, 'Load', Colors.lightBlueAccent, _loadProgress)),
          const SizedBox(width: 8),
          Expanded(child: _saveButton(Icons.restart_alt_rounded, 'Reset', Colors.redAccent, _resetProgress)),
        ]),
        const SizedBox(height: 8),
        const Text('Save: pick the folder · Load: pick the .json file', style: TextStyle(color: Colors.white38, fontSize: 11)),
        _section('How to play'),
        Column(children: [
                    _RuleRow(icon: Icons.touch_app_rounded, color: Colors.cyanAccent,
                        text: 'Hold the left or right side of the screen to move'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.screen_rotation_rounded, color: Colors.lightGreenAccent,
                        text: 'Tilt option: tilt your phone to move (touch still works)'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.shopping_bag_rounded, color: Colors.orangeAccent,
                        text: 'Bonuses to buy before a game: start at 500 / 1,000 pts (stackable), shield, turbo'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.swap_horiz_rounded, color: Colors.white70,
                        text: 'Leave one side of the screen, come back on the other'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.sync_alt_rounded, color: Colors.lightBlueAccent,
                        text: 'Blue cartridge → moves'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.heart_broken_rounded, color: Colors.brown,
                        text: 'Cracked cartridge → breaks, no bounce!'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.unfold_more_rounded, color: Colors.amberAccent,
                        text: 'Spring → super jump'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.rocket_launch_rounded, color: Colors.greenAccent,
                        text: 'Batocera logo 🟢 → invincible turbo for 2 seconds'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.bug_report_rounded, color: Colors.lightGreenAccent,
                        text: 'Bug 🐞 → jump on it to stomp it (+3 coins), otherwise you lose'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.monetization_on_rounded, color: Colors.amberAccent,
                        text: 'Collect coins to unlock new heroes'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.savings_rounded, color: Colors.amberAccent,
                        text: 'Coin bag 💰 → +15 coins (about every 250 pts)'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.auto_fix_high_rounded, color: Colors.redAccent,
                        text: 'In-game pickups: 🧲 magnet, coins ×2, ⏫ super jump (5 bounces), ⏳ slow-mo'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.bolt_rounded, color: Colors.lightBlueAccent,
                        text: 'Each hero has a small power (see the Shop)'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.local_fire_department_rounded, color: Colors.deepOrangeAccent,
                        text: 'Combo: chain higher and higher cartridges → coins ×2, ×3… up to ×5'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.casino_rounded, color: Colors.purpleAccent,
                        text: 'Wheel of fortune: one free spin per day, then $_wheelSpinPrice coins per spin (coins, bonus or free continue)'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.landscape_rounded, color: Colors.purpleAccent,
                        text: 'New scenery every 400 pts: castle, dungeon, temple, ice, volcano, cyber, space…'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.shield_rounded, color: Colors.cyanAccent,
                        text: 'Shield 🛡️ → protects you from one bug hit'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.replay_rounded, color: Colors.amberAccent,
                        text: 'Game over? Continue for 20 coins (once per game)'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.collections_bookmark_rounded, color: Colors.lightBlueAccent,
                        text: 'Console logo → catch it 3 times (more in later albums) to complete it in your collection'),
        ]),
      ]));

  Widget _heroTile(int i, Color accent) {
    final selected = _hero == i;
    final locked = !_unlocked.contains(i);
    return GestureDetector(
      onTap: () => _selectHero(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.12) : const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : Colors.white.withOpacity(0.08),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(children: [
          SizedBox(
            width: 56, height: 50,
            child: Stack(alignment: Alignment.center, children: [
              Opacity(
                opacity: locked ? 0.25 : 1,
                child: CustomPaint(size: const Size(56, 50), painter: _HeroPreviewPainter(i)),
              ),
              if (locked) const Icon(Icons.lock_rounded, color: Colors.white70, size: 22),
            ]),
          ),
          const SizedBox(height: 6),
          if (locked)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _CoinIcon(size: 11),
              const SizedBox(width: 3),
              Text('${_heroPrices[i]}',
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w700)),
            ])
          else
            Text(_heroNames[i],
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
        ]),
      ),
    );
  }
}

// ─── Small widgets ───────────────────────────────────────────────────────────

class _CoinIcon extends StatelessWidget {
  final double size;
  const _CoinIcon({required this.size});

  @override
  Widget build(BuildContext context) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: const Color(0xFFFFD740),
      border: Border.all(color: const Color(0xFFE6A800), width: size / 8),
    ),
  );
}

/// Roue de la fortune (fenêtre) : tourne puis renvoie l'index du segment gagné.
class _WheelDialog extends StatefulWidget {
  final bool ready;
  final int coins; // pour le tour payant
  const _WheelDialog({required this.ready, required this.coins});
  @override
  State<_WheelDialog> createState() => _WheelDialogState();
}

class _WheelDialogState extends State<_WheelDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
  final _rng = Random();
  double _from = 0, _to = 0;
  int? _result;
  bool _paid = false;
  bool _spinning = false;
  int _lastTick = -1;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      // Petit « clic » à chaque segment qui passe sous le pointeur
      final a = _angle;
      final seg = ((a % (2 * pi)) / (2 * pi / _wheel.length)).floor();
      if (seg != _lastTick) {
        _lastTick = seg;
        QuizAudio.sfx('jump');
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double get _angle => _from + (_to - _from) * Curves.easeOutCubic.transform(_ctrl.value);

  void _spin() {
    if (_spinning || _result != null) return;
    _paid = !widget.ready;
    // Tirage pondéré
    final total = _wheel.fold<int>(0, (a, s) => a + s.w);
    var r = _rng.nextInt(total);
    var idx = 0;
    while (r >= _wheel[idx].w) {
      r -= _wheel[idx].w;
      idx++;
    }
    final sweep = 2 * pi / _wheel.length;
    final jitter = (_rng.nextDouble() - 0.5) * sweep * 0.6;
    final target = 2 * pi - (idx + 0.5) * sweep + jitter;
    _from = _angle % (2 * pi);
    _to = 2 * pi * 6 + target;
    setState(() => _spinning = true);
    HapticFeedback.mediumImpact();
    _ctrl.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      setState(() {
        _spinning = false;
        _result = idx;
      });
      QuizAudio.win();
      HapticFeedback.heavyImpact();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _result == null ? null : _wheel[_result!];
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day + 1).difference(now);
    // Pas de fermeture pendant la rotation, ni avant d'avoir récupéré le lot
    return PopScope(
      canPop: !_spinning && _result == null,
      child: Dialog(
      backgroundColor: const Color(0xFF151A24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.casino_rounded, color: Colors.purpleAccent, size: 22),
            SizedBox(width: 8),
            Text('Wheel of fortune', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 4),
          const Text('One free spin per day', style: TextStyle(color: Colors.white38, fontSize: 12)),
          const SizedBox(height: 14),
          SizedBox(
            width: 260, height: 270,
            child: Stack(alignment: Alignment.topCenter, children: [
              Positioned(
                top: 10,
                child: SizedBox(
                  width: 260, height: 260,
                  child: CustomPaint(painter: _WheelPainter(_angle, _ctrl.value, _result)),
                ),
              ),
              // Pointeur
              CustomPaint(size: const Size(28, 30), painter: _WheelPointerPainter()),
            ]),
          ),
          const SizedBox(height: 14),
          if (s != null)
            Text(s.coins > 0 ? '+${s.coins} coins!' : 'Free ${_prizeName(s.bonus)}!',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.amberAccent, fontSize: 20, fontWeight: FontWeight.w900))
          else if (!widget.ready) ...[
            Text('Next spin in ${d.inHours}h ${d.inMinutes % 60}m',
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
            const SizedBox(height: 4),
            Text(widget.coins >= _wheelSpinPrice ? 'or try again for $_wheelSpinPrice coins' : 'Not enough coins for a spin',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _result != null
                  ? () => Navigator.pop(context, _result! + (_paid ? 100 : 0))
                  : (!_spinning && (widget.ready || widget.coins >= _wheelSpinPrice) ? _spin : null),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(_result != null ? 'Collect' : widget.ready ? 'Spin!' : 'Spin for $_wheelSpinPrice coins',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double angle;  // rotation de la roue (radians)
  final double t;      // avancement de l'animation (ampoules)
  final int? winner;
  _WheelPainter(this.angle, this.t, this.winner);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    final n = _wheel.length;
    final sweep = 2 * pi / n;
    // Couronne
    canvas.drawCircle(c, r + 8, Paint()..color = const Color(0xFF2E3446));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    for (int i = 0; i < n; i++) {
      final s = _wheel[i];
      final start = -pi / 2 + i * sweep;
      final rect = Rect.fromCircle(center: Offset.zero, radius: r);
      canvas.drawArc(rect, start, sweep, true, Paint()..color = s.color);
      canvas.drawArc(rect, start, sweep, true, Paint()
        ..color = Colors.white.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5);
      // Libellé orienté vers l'extérieur
      canvas.save();
      canvas.rotate(start + sweep / 2 + pi / 2);
      final label = s.coins > 0 ? '${s.coins}' : const ['500↑', '1000↑', '🛡️', '🚀', '❤️'][s.bonus];
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: s.coins > 0 ? 20 : 18,
            fontWeight: FontWeight.w900,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(-tp.width / 2, -r + 14));
      if (s.coins > 0) {
        final cy = -r + 14 + tp.height + 8;
        canvas.drawCircle(Offset(0, cy), 6, Paint()..color = const Color(0xFFFFD740));
        canvas.drawCircle(Offset(0, cy), 4, Paint()
          ..color = const Color(0xFFE6A800)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
      }
      canvas.restore();
    }
    canvas.restore();
    // Ampoules autour de la roue (clignotent)
    for (int i = 0; i < 24; i++) {
      final a = i / 24 * 2 * pi;
      final on = ((i + (t * 40).floor()) % 2 == 0) || winner != null && i.isEven;
      canvas.drawCircle(c + Offset(cos(a), sin(a)) * (r + 4), 2.6,
          Paint()..color = on ? const Color(0xFFFFF59D) : const Color(0xFF6D6A4A));
    }
    // Moyeu
    canvas.drawCircle(c, 22, Paint()..color = const Color(0xFF1C2230));
    canvas.drawCircle(c, 22, Paint()
      ..color = Colors.amberAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3);
    canvas.drawCircle(c, 8, Paint()..color = Colors.amberAccent);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) =>
      old.angle != angle || old.t != t || old.winner != winner;
}

class _WheelPointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Path()
      ..moveTo(size.width / 2, size.height)
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(p, Paint()
      ..color = Colors.black54
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    canvas.drawPath(p, Paint()..color = const Color(0xFFFF5252));
    canvas.drawPath(p, Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Pastille d'aperçu d'un thème (dégradé de ses deux couleurs).
class _ThemeSwatch extends StatelessWidget {
  final int theme;
  final double size;
  const _ThemeSwatch({required this.theme, required this.size});

  @override
  Widget build(BuildContext context) {
    final c = _themeSwatch[theme];
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
        border: Border.all(color: Colors.white24),
        boxShadow: theme == 1 || theme == 5 || theme == 7
            ? [BoxShadow(color: c[0].withOpacity(0.6), blurRadius: 8)]
            : null,
      ),
      child: theme == 4
          ? CustomPaint(painter: _ScanlinePainter())
          : null,
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withOpacity(0.35);
    for (double y = 1; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(size.width * 0.15, y, size.width * 0.7, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Option activable, présentée comme une tuile de héros (bordure = activée).
class _OptionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool value;
  final Color accent;
  final VoidCallback onTap;
  const _OptionTile({required this.icon, required this.color, required this.label,
      required this.value, required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: value ? accent.withOpacity(0.12) : const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value ? accent : Colors.white.withOpacity(0.08),
            width: value ? 2 : 1,
          ),
        ),
        child: Column(children: [
          SizedBox(
            width: 56, height: 50,
            child: Center(
              child: Icon(icon, size: 30, color: value ? color : Colors.white.withOpacity(0.25)),
            ),
          ),
          const SizedBox(height: 6),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: value ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: value ? FontWeight.w700 : FontWeight.w500,
              )),
        ]),
      ),
    );
  }
}

class _ChallengeRow extends StatelessWidget {
  final _Challenge challenge;
  final bool done;
  const _ChallengeRow({required this.challenge, required this.done});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(children: [
      Icon(done ? Icons.check_circle_rounded : challenge.icon,
          color: done ? Colors.greenAccent : Colors.white38, size: 18),
      const SizedBox(width: 10),
      Expanded(child: Text(challenge.label,
          style: TextStyle(
            color: done ? Colors.white54 : Colors.white,
            fontSize: 13,
            decoration: done ? TextDecoration.lineThrough : null,
          ))),
      const _CoinIcon(size: 11),
      const SizedBox(width: 4),
      Text('+${challenge.reward}',
          style: TextStyle(color: done ? Colors.white24 : Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w700)),
    ]),
  );
}

class _CollectionTile extends StatelessWidget {
  final int index;
  final int count;
  const _CollectionTile({required this.index, required this.count});

  @override
  Widget build(BuildContext context) {
    final done = count >= _logoGoal;
    final seen = count > 0;
    Widget img = Image.asset(_logoAssets[index], fit: BoxFit.contain, filterQuality: FilterQuality.medium);
    if (!seen) {
      img = Opacity(
        opacity: 0.25,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.33, 0.33, 0.33, 0, 0,
            0.33, 0.33, 0.33, 0, 0,
            0.33, 0.33, 0.33, 0, 0,
            0,    0,    0,    1, 0,
          ]),
          child: img,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
      decoration: BoxDecoration(
        color: done ? Colors.greenAccent.withOpacity(0.08) : const Color(0xFF0D0F14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: done ? Colors.greenAccent.withOpacity(0.6) : Colors.white.withOpacity(0.06),
          width: done ? 1.5 : 1,
        ),
      ),
      child: Stack(children: [
        Column(children: [
          Expanded(child: Center(child: img)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (int k = 0; k < _logoGoal; k++)
              Container(
                width: 7, height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: k < count
                      ? (done ? Colors.greenAccent : Colors.amberAccent)
                      : Colors.white.withOpacity(0.12),
                ),
              ),
          ]),
        ]),
        if (done)
          const Positioned(
            top: 0, right: 0,
            child: Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
          ),
      ]),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, value;
  const _StatCard({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      ]),
    ),
  );
}

class _RuleRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _RuleRow({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: color, size: 18),
    const SizedBox(width: 10),
    Expanded(child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 13))),
  ]);
}

// ═══════════════════════════════════════════════════════════════════════════════
// GAME
// ═══════════════════════════════════════════════════════════════════════════════

class _JumpGame extends StatefulWidget {
  final int bestScore;
  final int hero;
  final int theme;
  final bool haptics;
  final bool tilt;
  final Set<String> completed;
  final int challengeLevel;
  final int startPts;      // bonus : départ propulsé jusqu'à cette hauteur
  final bool startShield;  // bonus : bouclier dès le départ
  final bool startTurbo;   // bonus : turbo dès le départ
  final bool freeContinue; // roue : premier « continuer » gratuit
  final String? daily;      // partie du jour : date « AAAA-MM-JJ » (parcours commun)
  final Future<void> Function(int score) onFinished;
  const _JumpGame({
    required this.bestScore,
    required this.hero,
    required this.theme,
    required this.haptics,
    required this.tilt,
    required this.completed,
    required this.challengeLevel,
    this.startPts = 0,
    this.startShield = false,
    this.startTurbo = false,
    this.freeContinue = false,
    this.daily,
    required this.onFinished,
  });
  /// Halo lumineux des thèmes Néon, Synthwave et Disco
  bool get neon => theme == 1 || theme == 5 || theme == 7;

  @override
  State<_JumpGame> createState() => _JumpGameState();
}

class _JumpGameState extends State<_JumpGame> with SingleTickerProviderStateMixin {
  final _shareKey = GlobalKey();
  final _rng = Random();
  Random _gen = Random(); // parcours (graine commune en partie du jour)
  int _runId = 0;
  LbRank? _lbRank;  // rang en ligne après la partie
  int _lbState = 0;  // 0 rien, 1 envoi, 2 reçu, 3 hors ligne
  List<(int, String, int)> _rivals = []; // daily run: (score, name, rank) of other players
  final Set<int> _rivalsPassed = {};
  ui.Image? _turboImg;
  final List<ui.Image?> _logoImgs = List<ui.Image?>.filled(_logoAssets.length, null);
  List<int> _collection = List<int>.filled(_logoAssets.length, 0);
  final List<int> _logosRun = []; // logos attrapés pendant la partie
  late final Set<String> _done = Set<String>.of(widget.completed);
  late int _chLevel = widget.challengeLevel; // série de défis en cours
  int _combo = 0, _bestCombo = 0, _lastMult = 1;
  double _lastLandY = double.infinity; // y de la dernière cartouche touchée
  int _bagsRun = 0, _contUsed = 0;
  double _playTime = 0;
  int get _cStep => widget.hero == 9 ? 4 : _comboStep; // Souris : paliers plus rapides
  int get _comboMult => min(_comboMax, 1 + _combo ~/ _cStep);
  // Bonus ramassés en partie
  final List<_Pickup> _pickups = [];
  double _nextPickupPts = 0;
  double _magnetT = 0, _doubleT = 0, _slowT = 0;
  int _superJumps = 0;
  int get _contPrice => widget.hero == 2 ? 10 : _continuePrice; // Borne
  int get _bagValue => widget.hero == 3 ? 20 : _bagCoins;        // Jeton
  double get _pickupMul => widget.hero == 5 ? 1.5 : 1.0;          // Disquette
  double get _turboDur => widget.hero == 11 ? _turboDuration * 1.6 : _turboDuration; // Fusée
  bool _bonusPending = true; // bonus achetés : appliqués au 1er départ seulement
  late bool _freeCont = widget.freeContinue; // continue gratuit (roue), 1re partie seulement
  int _launchTo = 0;          // > 0 : propulsion de départ jusqu'à ce score
  int _seriesBonusEarned = 0;               // > 0 : série terminée à cette partie
  int _albumBonusEarned = 0;                // > 0 : album complété à cette partie

  // État
  bool _started = false;
  bool _paused = false;
  bool _gameOver = false;
  bool _finishedReported = false;
  bool _deathByBug = false;
  bool _recordPassed = false;
  bool _offer = false;     // proposition « continuer » affichée
  bool _continued = false; // continue déjà utilisé pendant cette partie
  int _spent = 0;          // pièces dépensées pour continuer
  int _wallet = 0;         // pièces en banque (hors partie en cours)
  int _score = 0;
  int _jumps = 0, _springs = 0, _turbos = 0, _stomps = 0, _coinsRun = 0;
  int _tierIdx = 0;

  // Résultats (calculés à la fin de la partie)
  bool _resultsReady = false;
  List<_Challenge> _newChallenges = [];
  int _coinsEarned = 0;

  // Bandeau (palier, record)
  String _banner = '';
  double _bannerT = 0;

  // Dimensions / caméra (y du monde affiché en haut de l'écran)
  double _w = 0, _h = 0;
  double _camY = 0;

  // Héros : x = centre, y = pieds (coordonnées monde)
  double _x = 0, _y = 0, _vx = 0, _vy = 0;
  double _startY = 0, _maxHeight = 0;
  double _turbo = 0;
  bool _shield = false;
  double _invuln = 0;
  double _squash = 0;
  double _time = 0; // horloge d'animation
  bool _facingRight = true;

  // Monde
  final List<_Plat> _plats = [];
  final List<_Enemy> _enemies = [];
  final List<_Coin> _coinList = [];
  final List<_Logo> _logoList = [];
  final List<_Coin> _bagList = [];   // sacs de 15 pièces
  double _nextBagPts = 0;            // hauteur (pts) du prochain sac
  final List<_Particle> _particles = [];
  double _topY = 0;       // y de la plateforme la plus haute générée
  double _lastEnemyY = 0; // y du dernier bug généré
  double _lastLogoY = 0;  // y du dernier logo généré

  // Commandes : dernier doigt posé = direction active
  final LinkedHashMap<int, double> _pointers = LinkedHashMap();
  int _dir = 0;

  // Boucle
  Ticker? _ticker;
  Duration _lastElapsed = Duration.zero;

  // Inclinaison (accéléromètre) : -1 = gauche … 1 = droite
  StreamSubscription<AccelerometerEvent>? _accelSub;
  double _tiltX = 0;   // valeur filtrée (m/s²)
  double _tiltDir = 0;

  @override
  void initState() {
    super.initState();
    _loadAssets();
    _loadWallet();
    _loadRivals();
    if (widget.tilt) {
      try {
        _accelSub = accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval).listen(
          (e) {
            // Filtre passe-bas pour lisser les tremblements
            _tiltX = _tiltX * 0.6 + e.x * 0.4;
            final v = -_tiltX; // téléphone penché à droite → x négatif
            _tiltDir = v.abs() < _tiltDead
                ? 0.0
                : ((v.abs() - _tiltDead) / (_tiltFull - _tiltDead)).clamp(0.0, 1.0).toDouble() * v.sign;
          },
          onError: (_) {},
          cancelOnError: true,
        );
      } catch (_) {}
    }
  }

  /// Other players' score lines in the course (daily or all-time board)
  Future<void> _loadRivals() async {
    if (!Leaderboard.configured) return;
    // Daily run: today's board; normal game: all-time board
    final day = widget.daily;
    final b = day != null ? await Leaderboard.fetch('daily', day) : await Leaderboard.fetch('all', lbAllDay);
    if (b == null || !mounted) return;
    final me = await Leaderboard.publicId();
    final list = <(int, String, int)>[
      for (int i = 0; i < b.top.length; i++)
        if (b.top[i].pid != me && b.top[i].score > 0) (b.top[i].score, b.top[i].name, i + 1),
    ];
    if (mounted) setState(() => _rivals = list.take(20).toList());
  }

  Future<void> _loadWallet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _wallet = prefs.getInt(_kCoinsKey) ?? 0;
      _collection = _readCollection(prefs);
    } catch (_) {}
  }

  @override
  void dispose() {
    QuizAudio.musicResume(); // la musique continue sur l'accueil du jeu
    _accelSub?.cancel();
    _ticker?.dispose();
    super.dispose();
  }

  Future<void> _loadAssets() async {
    try {
      final data = await rootBundle.load(_turboAsset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _turboImg = frame.image;
    } catch (_) {}
    await _loadLogoImgs();
    if (mounted) setState(() {});
  }

  /// Images des logos de l'album en cours (rechargées au changement d'album).
  Future<void> _loadLogoImgs() async {
    final assets = List<String>.of(_logoAssets);
    for (int i = 0; i < assets.length; i++) {
      try {
        final data = await rootBundle.load(assets[i]);
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        _logoImgs[i] = (await codec.getNextFrame()).image;
      } catch (_) {}
    }
  }

  void _haptic(int level) {
    if (!widget.haptics) return;
    switch (level) {
      case 0:
        HapticFeedback.selectionClick();
        break;
      case 1:
        HapticFeedback.lightImpact();
        break;
      case 2:
        HapticFeedback.mediumImpact();
        break;
      default:
        HapticFeedback.heavyImpact();
    }
  }

  // ── Initialisation ─────────────────────────────────────────────────────────
  void _initGame(double w, double h) {
    _gen = widget.daily != null ? SeededRandom(Leaderboard.seedFor(widget.daily!)) : Random();
    _runId++;
    _rivalsPassed.clear();
    _lbRank = null;
    _lbState = 0;
    _w = w;
    _h = h;
    _camY = 0;
    _plats.clear();
    _enemies.clear();
    _coinList.clear();
    _logoList.clear();
    _logosRun.clear();
    _bagList.clear();
    _nextBagPts = 220 + _gen.nextDouble() * 60;
    _particles.clear();
    _pointers.clear();
    _dir = 0;
    _started = false;
    _paused = false;
    _gameOver = false;
    _finishedReported = false;
    _deathByBug = false;
    _recordPassed = false;
    _offer = false;
    _continued = false;
    _spent = 0;
    _resultsReady = false;
    _newChallenges = [];
    _seriesBonusEarned = 0;
    _launchTo = 0;
    _albumBonusEarned = 0;
    _coinsEarned = 0;
    _score = 0;
    _jumps = 0;
    _springs = 0;
    _turbos = 0;
    _stomps = 0;
    _pickups.clear();
    _nextPickupPts = 300 + _gen.nextDouble() * 100;
    _magnetT = 0;
    _doubleT = 0;
    _slowT = 0;
    _superJumps = 0;
    _combo = 0;
    _bestCombo = 0;
    _lastMult = 1;
    _lastLandY = double.infinity;
    _bagsRun = 0;
    _contUsed = 0;
    _playTime = 0;
    _coinsRun = 0;
    _tierIdx = 0;
    _banner = '';
    _bannerT = 0;
    _turbo = 0;
    _shield = false;
    _invuln = 0;
    _squash = 0;
    _vx = 0;
    _vy = 0;
    _facingRight = true;

    // Plateforme de départ sous le héros
    final startY = h - 60;
    _plats.add(_Plat(w / 2 - _platW / 2, startY, _PlatType.normal, colorIdx: 4));
    _x = w / 2;
    _y = startY;
    _startY = startY;
    _maxHeight = 0;
    _topY = startY;
    _lastEnemyY = startY;
    _lastLogoY = startY;
    _generateUntil(_camY - h);
  }

  /// Génère des plateformes (et pièces / bugs) jusqu'à la hauteur [limitY].
  /// L'écart vertical entre deux plateformes « solides » reste toujours
  /// inférieur à la hauteur d'un saut normal (~185 px) : le jeu est toujours
  /// faisable. Les cartouches fissurées et les bugs sont des pièges EN PLUS.
  void _generateUntil(double limitY) {
    while (_topY > limitY) {
      final heightPts = (_startY - _topY) / 10;
      final d = (heightPts / 3000).clamp(0.0, 1.0);
      final minGap = 55 + 35 * d;
      final maxGap = 95 + 70 * d; // ≤ 165
      final gap = minGap + _gen.nextDouble() * (maxGap - minGap);
      final y = _topY - gap;
      final x = _gen.nextDouble() * (_w - _platW);

      final r = _gen.nextDouble();
      _PlatType type;
      if (r < 0.06) {
        type = _PlatType.spring;
      } else if (r < 0.06 + 0.10 + 0.25 * d) {
        type = _PlatType.moving;
      } else {
        type = _PlatType.normal;
      }
      final vx = type == _PlatType.moving
          ? (60 + 90 * d) * (_gen.nextBool() ? 1 : -1)
          : 0.0;
      final turbo = type == _PlatType.normal && _gen.nextDouble() < 0.025;
      // Shield bonus (rare)
      final shield = type == _PlatType.normal && !turbo && heightPts > 150 && _gen.nextDouble() < 0.03;
      _plats.add(_Plat(x, y, type,
          vx: vx, hasTurbo: turbo, hasShield: shield, colorIdx: _gen.nextInt(_cartColors.length)));

      // Pièce posée au-dessus de la cartouche
      if (type == _PlatType.normal && !turbo && !shield && _gen.nextDouble() < 0.28) {
        if (widget.daily == null) _coinList.add(_Coin(x + _platW / 2, y - 24)); // no coins in the daily run
      }
      // Colonne de pièces dans le vide
      if (gap > 90 && _gen.nextDouble() < 0.10) {
        final cx = 20 + _gen.nextDouble() * (_w - 40);
        for (int k = 0; k < 3; k++) {
          if (widget.daily == null) _coinList.add(_Coin(cx, y + gap * 0.2 + k * 18));
        }
      }
      // Piège : cartouche fissurée entre deux plateformes
      if (gap > 70 && _gen.nextDouble() < 0.12 + 0.20 * d) {
        final by = y + gap * (0.35 + _gen.nextDouble() * 0.3);
        final bx = _gen.nextDouble() * (_w - _platW);
        _plats.add(_Plat(bx, by, _PlatType.breakable));
      }
      // Bug (à partir de 200 pts, au moins 350 px entre deux bugs)
      if (heightPts > 200 && y < _lastEnemyY - 350 && _gen.nextDouble() < 0.10 + 0.15 * d) {
        final ex = _enemyW / 2 + _gen.nextDouble() * (_w - _enemyW);
        final moving = _gen.nextDouble() < 0.35 + 0.30 * d;
        final evx = moving ? (50 + 70 * d) * (_gen.nextBool() ? 1 : -1) : 0.0;
        _enemies.add(_Enemy(ex, y + gap / 2, evx, _gen.nextDouble() * 6));
        _lastEnemyY = y;
      }
      // Bonus à ramasser, environ tous les 350 pts
      if (heightPts >= _nextPickupPts) {
        final px = 30 + _gen.nextDouble() * (_w - 60);
        var pt = _gen.nextInt(4);
        if (widget.daily != null && pt < 2) pt += 2; // no coins: no magnet or ×2 (super jump / slow-mo instead)
        _pickups.add(_Pickup(px, y + gap / 2, pt));
        _nextPickupPts += 300 + _gen.nextDouble() * 120;
      }
      // Sac de 15 pièces, environ tous les 250 pts
      if (heightPts >= _nextBagPts) {
        final bx = 26 + _gen.nextDouble() * (_w - 52);
        if (widget.daily == null) _bagList.add(_Coin(bx, y + gap / 2));
        _nextBagPts += 210 + _gen.nextDouble() * 80;
      }
      // Logo de console à collectionner (rare, au moins 700 px entre deux)
      if (heightPts > 80 && y < _lastLogoY - 700 && _gen.nextDouble() < 0.09) {
        final lx = 34 + _gen.nextDouble() * (_w - 68);
        _logoList.add(_Logo(lx, y + gap / 2, _pickLogo()));
        _lastLogoY = y;
      }
      _topY = y;
    }
  }

  /// Logo au hasard, en privilégiant ceux qui ne sont pas encore validés.
  int _pickLogo() {
    final missing = [
      for (int i = 0; i < _logoAssets.length; i++)
        if (_collection[i] < _logoGoal) i,
    ];
    if (missing.isNotEmpty && _rng.nextDouble() < 0.75) {
      return missing[_rng.nextInt(missing.length)];
    }
    return _rng.nextInt(_logoAssets.length);
  }

  Future<void> _saveCollection() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kCollectionKey, _collection.map((n) => '$n').toList());
    } catch (_) {}
  }

  // ── Boucle ────────────────────────────────────────────────────────────────
  void _startLoop() {
    if (_ticker != null) return; // SingleTickerProvider : un seul Ticker
    _lastElapsed = Duration.zero;
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastElapsed).inMicroseconds / 1e6).clamp(0.0, 1 / 30);
    _lastElapsed = elapsed;
    if (!mounted || !_started || _paused || _gameOver || _offer || _w == 0) return;
    setState(() => _update(dt));
  }

  void _update(double dt) {
    _time += dt;
    _playTime += dt;
    // Minuteries des bonus (temps réel), puis ralenti du monde
    if (_magnetT > 0) _magnetT = max(0, _magnetT - dt);
    if (_doubleT > 0) _doubleT = max(0, _doubleT - dt);
    if (_slowT > 0) {
      _slowT = max(0, _slowT - dt);
      dt *= 0.55;
    }
    if (_bannerT > 0) _bannerT = max(0, _bannerT - dt);
    if (_invuln > 0) _invuln = max(0, _invuln - dt);

    // Horizontal (accélération douce + passage d'un bord à l'autre)
    // Le tactile reste prioritaire ; sinon l'inclinaison (si activée)
    final dir = _pointers.isNotEmpty || !widget.tilt ? _dir.toDouble() : _tiltDir;
    final target = dir * _moveSpeed * (widget.hero == 1 ? 1.12 : 1.0); // Joystick
    if (_vx < target) {
      _vx = min(target, _vx + _moveAccel * dt);
    } else if (_vx > target) {
      _vx = max(target, _vx - _moveAccel * dt);
    }
    _x += _vx * dt;
    if (_x < -_heroW / 2) _x += _w + _heroW;
    if (_x > _w + _heroW / 2) _x -= _w + _heroW;
    if (dir.abs() > 0.05) _facingRight = dir > 0;

    // Vertical
    final prevY = _y;
    if (_launchTo > 0) {
      // Propulsion de départ (bonus) : montée rapide et invincible
      _turbo = max(_turbo, 0.2);
      if (_score >= _launchTo) {
        _launchTo = 0;
        if (widget.startTurbo) {
          _turbo = _turboDur;
          _turbos++;
        } else {
          _turbo = 0.05;
        }
      }
    }
    if (_turbo > 0) {
      _turbo -= dt;
      _vy = _launchTo > 0 ? _turboV * 2.5 : _turboV;
      if (_rng.nextDouble() < 0.8) {
        _particles.add(_Particle(
          Offset(_x + (_rng.nextDouble() - 0.5) * 14, _y + 2),
          Offset((_rng.nextDouble() - 0.5) * 80, 150 + _rng.nextDouble() * 120),
          _rng.nextBool() ? Colors.orangeAccent : Colors.amberAccent,
        ));
      }
    } else {
      _vy += _gravity * (widget.hero == 10 ? 0.88 : 1.0) * dt; // Chat : saute plus haut
    }
    _y += _vy * dt;
    if (_squash > 0) _squash = max(0, _squash - dt * 5);

    // Plateformes mobiles / cassées
    for (final p in _plats) {
      if (p.type == _PlatType.moving) {
        p.x += p.vx * dt;
        if (p.x < 0) { p.x = 0; p.vx = p.vx.abs(); }
        if (p.x > _w - _platW) { p.x = _w - _platW; p.vx = -p.vx.abs(); }
      }
      if (p.broken) p.y += 520 * dt;
    }

    // Bugs
    for (final e in _enemies) {
      e.phase += dt;
      if (e.dead) {
        e.y += 480 * dt;
        continue;
      }
      if (e.moving) {
        e.x += e.vx * dt;
        if (e.x < _enemyW / 2) { e.x = _enemyW / 2; e.vx = e.vx.abs(); }
        if (e.x > _w - _enemyW / 2) { e.x = _w - _enemyW / 2; e.vx = -e.vx.abs(); }
      }
    }

    // Atterrissage (uniquement en descente, hors turbo)
    if (_vy > 0 && _turbo <= 0) {
      for (final p in _plats) {
        if (p.broken) continue;
        final overlap = (_x + _heroW * 0.35) > p.x && (_x - _heroW * 0.35) < p.x + _platW;
        if (!overlap || prevY > p.y || _y < p.y) continue;
        if (p.type == _PlatType.breakable) {
          p.broken = true;
          _burst(Offset(p.x + _platW / 2, p.y), Colors.brown, 10);
          QuizAudio.sfx('break');
          _haptic(1);
          if (widget.hero != 4) continue; // Cartouche : rebondit quand même une fois
        }
        _y = p.y;
        _jumps++;
        _squash = 1;
        // Combo : cartouche plus haute que la précédente → +1, sinon on repart à 1
        _combo = p.y < _lastLandY - 1 ? _combo + 1 : 1;
        _lastLandY = p.y;
        if (_combo > _bestCombo) _bestCombo = _combo;
        final mult = _comboMult;
        if (mult > _lastMult) {
          _showBanner('COMBO ×$mult');
          QuizAudio.sfx('logo');
          _haptic(1);
        }
        _lastMult = mult;
        if (p.type == _PlatType.spring) {
          _vy = _springV;
          _springs++;
          QuizAudio.sfx('spring');
          _haptic(2);
        } else if (_superJumps > 0) {
          _superJumps--;
          _vy = _springV;
          QuizAudio.sfx('spring');
        } else {
          _vy = _jumpV;
          QuizAudio.sfx('jump');
        }
        _burst(Offset(_x, p.y), Colors.white54, 5);
        break;
      }
    }

    // Contact avec les bugs
    for (final e in _enemies) {
      if (e.dead) continue;
      final ey = e.y + sin(e.phase * 3) * 3;
      final hitX = (_x - e.x).abs() < _enemyW / 2 + _heroW * 0.3;
      final hitY = _y > ey - _enemyH / 2 && _y - _heroH < ey + _enemyH / 2;
      if (!hitX || !hitY) continue;
      final stomp = _vy > 0 && prevY <= ey - _enemyH / 2 + 10;
      if (_turbo > 0 || stomp) {
        e.dead = true;
        _stomps++;
        if (widget.daily == null) _coinsRun += 3;
        if (_turbo <= 0) {
          _vy = _stompV;
          _squash = 1;
        }
        _burst(Offset(e.x, ey), e.moving ? Colors.purpleAccent : Colors.lightGreenAccent, 14);
        QuizAudio.sfx('stomp');
        _haptic(2);
      } else if (_invuln > 0) {
        continue;
      } else if (_shield) {
          // Shield: absorbs the hit, then 1 s of invulnerability
          _shield = false;
          _invuln = 1.0;
          e.dead = true;
          _burst(Offset(e.x, ey), Colors.cyanAccent, 16);
          QuizAudio.sfx('hurt');
          _haptic(2);
      } else {
        _die(byBug: true);
        return;
      }
    }

    // Bonus turbo
    for (final p in _plats) {
      if (!p.hasTurbo || p.broken) continue;
      final c = Offset(p.x + _platW / 2, p.y - 24);
      if ((c - Offset(_x, _y - _heroH / 2)).distance < 30) {
        p.hasTurbo = false;
        _turbo = _turboDur;
        _turbos++;
        _burst(c, Colors.greenAccent, 14);
        QuizAudio.sfx('powerup');
        _haptic(2);
      }
    }

    // Bouclier
    for (final p in _plats) {
      if (!p.hasShield || p.broken) continue;
      final c = Offset(p.x + _platW / 2, p.y - 24);
      if ((c - Offset(_x, _y - _heroH / 2)).distance < 30) {
        p.hasShield = false;
        _shield = true;
        _burst(c, Colors.cyanAccent, 12);
        QuizAudio.sfx('shield');
        _haptic(2);
      }
    }

    // Pièces
    final heroC = Offset(_x, _y - _heroH / 2);
    final magnetR = _magnetT > 0 ? 170.0 : (widget.hero == 6 ? 75.0 : 0.0); // aimant / CD
    for (final c in _coinList) {
      if (c.taken) continue;
      final dist = (Offset(c.x, c.y) - heroC).distance;
      if (magnetR > 0 && dist < magnetR) {
        final k = min(1.0, dt * 7);
        c.x += (heroC.dx - c.x) * k;
        c.y += (heroC.dy - c.y) * k;
      }
      if (dist < 24) {
        c.taken = true;
        final lucky = widget.hero == 7 && _rng.nextInt(4) == 0; // Cassette
        _coinsRun += _comboMult * (_doubleT > 0 ? 2 : 1) * (lucky ? 2 : 1);
        _burst(Offset(c.x, c.y), Colors.amberAccent, 4);
        QuizAudio.sfx('coin');
        _haptic(0);
      }
    }

    // Sacs de pièces
    for (final b in _bagList) {
      if (b.taken) continue;
      if ((Offset(b.x, b.y) - heroC).distance < 30) {
        b.taken = true;
        final gain = _bagValue * _comboMult * (_doubleT > 0 ? 2 : 1);
        _coinsRun += gain;
        _bagsRun++;
        _showBanner('+$gain 🪙');
        _burst(Offset(b.x, b.y), Colors.amberAccent, 22);
        QuizAudio.sfx('coin');
        QuizAudio.sfx('logo');
        _haptic(1);
      }
    }

    // Bonus à ramasser
    for (final pk in _pickups) {
      if (pk.taken) continue;
      if ((Offset(pk.x, pk.y) - heroC).distance < 30) {
        pk.taken = true;
        switch (pk.kind) {
          case 0:
            _magnetT = _pickupDur[0] * _pickupMul;
            break;
          case 1:
            _doubleT = _pickupDur[1] * _pickupMul;
            break;
          case 2:
            _superJumps = (5 * _pickupMul).round();
            break;
          default:
            _slowT = _pickupDur[3] * _pickupMul;
        }
        _showBanner(_pickupNames[pk.kind].toUpperCase());
        _burst(Offset(pk.x, pk.y), _pickupColors[pk.kind], 18);
        QuizAudio.sfx('powerup');
        _haptic(2);
      }
    }

    // Logos de consoles
    for (final lg in _logoList) {
      if (lg.taken) continue;
      if ((Offset(lg.x, lg.y) - heroC).distance < 32) {
        lg.taken = true;
        _collection[lg.idx]++;
        _logosRun.add(lg.idx);
        final n = _collection[lg.idx];
        final name = _logoNames[lg.idx];
        _showBanner(n == _logoGoal ? '$name COMPLETE!' : n < _logoGoal ? '$name $n/$_logoGoal' : '$name ✓');
        _burst(Offset(lg.x, lg.y), n >= _logoGoal ? Colors.greenAccent : Colors.lightBlueAccent, 14);
        QuizAudio.sfx('logo');
        _haptic(1);
        _saveCollection();
      }
    }

    // Particules
    for (final pa in _particles) {
      pa.pos += pa.vel * dt;
      pa.vel = Offset(pa.vel.dx, pa.vel.dy + 600 * dt);
      pa.life -= dt * 1.8;
    }
    _particles.removeWhere((pa) => pa.life <= 0);

    // Caméra : le héros ne monte jamais au-dessus de 45 % de l'écran
    if (_y - _camY < _h * 0.45) _camY = _y - _h * 0.45;

    // Score = hauteur maximale atteinte
    final height = _startY - _y;
    if (height > _maxHeight) {
      _maxHeight = height;
      _score = (_maxHeight / 10).floor();
    }

    // Record battu en cours de partie
    if (!_recordPassed && widget.bestScore > 0 && _score > widget.bestScore) {
      _recordPassed = true;
      _showBanner(_txtNewRecord);
      _haptic(2);
    }

    // Another player passed
    int passed = -1;
    for (int i = _rivals.length - 1; i >= 0; i--) {
      if (!_rivalsPassed.contains(i) && _score > _rivals[i].$1) {
        _rivalsPassed.add(i);
        passed = i;
      }
    }
    if (passed >= 0) {
      _showBanner('YOU PASSED ${_rivals[passed].$2.toUpperCase()}!');
      QuizAudio.sfx('tier');
      _haptic(1);
    }

    // Nouveau palier de décor
    final tier = _score ~/ _tierStep;
    if (tier > _tierIdx) {
      _tierIdx = tier;
      _showBanner('$_txtStage ${_tierFor(tier).name.toUpperCase()}');
      QuizAudio.sfx('tier');
      _haptic(1);
    }

    // Nettoyage + génération
    final bottom = _camY + _h + 80;
    _plats.removeWhere((p) => p.y > bottom);
    _enemies.removeWhere((e) => e.y > bottom);
    _coinList.removeWhere((c) => c.taken || c.y > bottom);
    _logoList.removeWhere((l) => l.taken || l.y > bottom);
    _bagList.removeWhere((b) => b.taken || b.y > bottom);
    _pickups.removeWhere((p) => p.taken || p.y > bottom);
    _generateUntil(_camY - 120);

    // Chute sous l'écran → fin de partie
    if (_y - _heroH > _camY + _h + 10) _die(byBug: false);
  }

  void _showBanner(String text) {
    _banner = text;
    _bannerT = 2.0;
  }

  void _burst(Offset at, Color color, int n) {
    for (int i = 0; i < n; i++) {
      final a = _rng.nextDouble() * pi;
      final s = 80 + _rng.nextDouble() * 160;
      _particles.add(_Particle(at, Offset(cos(a) * s, -sin(a) * s), color));
    }
  }

  void _die({required bool byBug}) {
    if (_gameOver || _offer) return;
    _deathByBug = byBug;
    QuizAudio.lose();
    _haptic(3);
    _pointers.clear();
    _dir = 0;
    // Continue possible : 1 fois par partie, si assez de pièces (banque + partie)
    if (widget.daily == null && (_freeCont || (!_continued && _wallet + _coinsRun - _spent >= _contPrice))) {
      _offer = true;
    } else {
      _endRun();
    }
  }

  void _endRun() {
    _offer = false;
    _gameOver = true;
    _saveRun();
  }

  void _declineContinue() {
    if (!_offer) return;
    setState(_endRun);
  }

  /// Relance le héros : cartouche de secours en bas de l'écran, bugs
  /// visibles retirés, saut + 2 s d'invulnérabilité.
  void _acceptContinue() {
    if (!_offer) return;
    setState(() {
      _offer = false;
      _contUsed++;
      _combo = 0;
      _lastMult = 1;
      _lastLandY = double.infinity;
      if (_freeCont) {
        _freeCont = false; // offert par la roue
      } else {
        _continued = true;
        _spent += _contPrice;
      }
      _enemies.removeWhere((e) => e.y > _camY - 60);
      final py = _camY + _h - 110;
      final px = (_x - _platW / 2).clamp(0.0, _w - _platW);
      _plats.add(_Plat(px, py, _PlatType.normal, colorIdx: 4));
      _x = px + _platW / 2;
      _y = py;
      _vx = 0;
      _vy = _springV;
      _turbo = 0;
      _invuln = 2.0;
      _squash = 1;
      _pointers.clear();
      _dir = 0;
      _burst(Offset(_x, _y), Colors.amberAccent, 18);
    });
    QuizAudio.sfx('continue');
    _haptic(2);
  }

  bool _challengeMet(_Challenge c) {
    switch (c.id) {
      case 'h500':
      case 'h1500':
      case 'h3000':
        return _score >= c.target;
      case 'nospring':
        return _score >= c.target && _springs == 0;
      case 'turbo3':
        return _turbos >= c.target;
      case 'stomp5':
        return _stomps >= c.target;
      case 'coins50':
        return _coinsRun >= c.target;
      case 'neon500':
        return widget.neon && _score >= c.target;
    }
    return false;
  }

  /// Fin de partie : défis réussis + pièces gagnées, enregistrés tout de suite
  /// (le record et la saisie du nom restent gérés par l'écran d'accueil).
  /// Statistiques à vie : ajoute cette partie aux cumuls.
  Future<void> _saveStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      Map<String, dynamic> st = {};
      try {
        st = Map<String, dynamic>.from(jsonDecode(prefs.getString(_kStatsKey) ?? '{}') as Map);
      } catch (_) {}
      void add(String k, num v) => st[k] = ((st[k] as num?) ?? 0) + v;
      add('games', 1);
      add('pts', _score);
      add('jumps', _jumps);
      add('coins', _coinsRun);
      add('bags', _bagsRun);
      add('stomps', _stomps);
      add('turbos', _turbos);
      add('logos', _logosRun.length);
      add('cont', _contUsed);
      add(_deathByBug ? 'bugdeaths' : 'falls', 1);
      add('time', _playTime.round());
      st['combo'] = max(((st['combo'] as num?) ?? 0).toInt(), _bestCombo);
      await prefs.setString(_kStatsKey, jsonEncode(st));
    } catch (_) {}
  }

  Future<void> _saveRun() async {
    _saveStats();
    final chals = _challengesFor(_chLevel);
    final newOnes = chals.where((c) => !_done.contains(c.id) && _challengeMet(c)).toList();
    final rewards = newOnes.fold<int>(0, (a, c) => a + c.reward);
    _done.addAll(newOnes.map((c) => c.id));
    // Série terminée : bonus + nouvelle série plus difficile
    var bonus = 0;
    if (chals.every((c) => _done.contains(c.id))) {
      bonus = _seriesBonus(_chLevel);
      _chLevel++;
      _done.clear();
    }
    // Album complété : bonus + album suivant (nouveaux logos ou plus de prises)
    var albumBonus = 0;
    if (_collection.every((n) => n >= _logoGoal)) {
      albumBonus = _albumBonus(_album);
      _album++;
      _collection = List<int>.filled(_logoAssets.length, 0);
      _logoList.clear();
      _loadLogoImgs();
    }
    final earned = _coinsRun + rewards + bonus + albumBonus;
    final net = earned - _spent;
    try {
      final prefs = await SharedPreferences.getInstance();
      final total = max(0, (prefs.getInt(_kCoinsKey) ?? 0) + net);
      await prefs.setInt(_kCoinsKey, total);
      _wallet = total;
      await prefs.setStringList(_kChallengesKey, _done.toList());
      await prefs.setInt(_kChallengeLvlKey, _chLevel);
      await prefs.setInt(_kAlbumKey, _album);
      await prefs.setStringList(_kCollectionKey, _collection.map((n) => '$n').toList());
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _newChallenges = newOnes;
      _seriesBonusEarned = bonus;
      _albumBonusEarned = albumBonus;
      _coinsEarned = earned;
      _resultsReady = true;
    });
    if (newOnes.isNotEmpty) QuizAudio.win();
    _submitOnline();
  }

  /// Classement en ligne : meilleur score de tous les temps (+ partie du jour).
  Future<void> _submitOnline() async {
    final run = _runId;
    final day = widget.daily;
    final score = _score;
    final time = max(1, _playTime.round());
    if (day != null) {
      // Meilleur score du jour en local (affiché sur l'accueil)
      try {
        final prefs = await SharedPreferences.getInstance();
        final p = (prefs.getString(_kDailyKey) ?? '').split('|');
        final best = p.length >= 2 && p[0] == day ? int.tryParse(p[1]) ?? 0 : 0;
        if (score > best) await prefs.setString(_kDailyKey, '$day|$score');
      } catch (_) {}
    }
    if (!Leaderboard.configured || score <= 0) return;
    if (mounted && run == _runId) setState(() => _lbState = 1);
    var name = await Leaderboard.name();
    if (name == null) {
      name = 'Player-${(await Leaderboard.publicId()).substring(0, 4).toUpperCase()}';
      await Leaderboard.setLocalName(name);
    }
    final all = Leaderboard.submit(
        mode: 'all', day: lbAllDay, score: score, hero: widget.hero, time: time, name: name);
    final daily = day == null
        ? null
        : Leaderboard.submit(mode: 'daily', day: day, score: score, hero: widget.hero, time: time, name: name);
    final rAll = await all;
    final rDay = daily == null ? null : await daily;
    final r = day == null ? rAll : rDay;
    final wRank = rAll?.rank;
    if (rAll != null && wRank != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kWorldRankKey, '$wRank|${rAll.total}');
      } catch (_) {}
    }
    final rank = r?.rank;
    if (day != null && r != null && rank != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kDailyRankKey, '$day|$rank|${r.total}');
      } catch (_) {}
    }
    if (!mounted || run != _runId) return;
    setState(() {
      _lbRank = r;
      _lbState = r == null ? 3 : 2;
    });
  }

  String _lbText() {
    switch (_lbState) {
      case 1:
        return 'Sending score…';
      case 3:
        return 'Offline: score will be sent later';
    }
    final r = _lbRank;
    if (r == null || r.rank == null) return 'Leaderboard unavailable';
    final what = widget.daily != null ? 'Daily rank' : 'World rank';
    return '$what : #${r.rank} / ${r.total}';
  }

  /// Transmet le score à l'écran d'accueil (record + saisie du nom), une
  /// seule fois par partie : en quittant les résultats (bouton Accueil ou
  /// retour Android) ou avant de rejouer.
  Future<void> _reportFinished() async {
    if (_finishedReported) return;
    _finishedReported = true;
    await widget.onFinished(_score);
  }

  // ── Commandes tactiles ─────────────────────────────────────────────────────
  void _updateDir() {
    if (_pointers.isEmpty) {
      _dir = 0;
    } else {
      _dir = _pointers.values.last < _w / 2 ? -1 : 1;
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.localPosition.dy < _topBarH) return; // zone des boutons
    if (!_started && !_paused) {
      setState(() => _started = true);
      _vy = _jumpV; // premier saut
      QuizAudio.sfx('jump');
      if (widget.hero == 8) _shield = true; // Télé : bouclier offert
      if (_bonusPending) {
        _bonusPending = false;
        if (widget.startShield) _shield = true;
        if (widget.startPts > 0) {
          _launchTo = widget.startPts;
          _turbo = 0.2;
          QuizAudio.sfx('powerup');
        } else if (widget.startTurbo) {
          _turbo = _turboDur;
          _turbos++;
          QuizAudio.sfx('powerup');
        }
      }
    }
    _pointers.remove(e.pointer);
    _pointers[e.pointer] = e.localPosition.dx;
    _updateDir();
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition.dx;
    _updateDir();
  }

  void _onPointerUp(PointerEvent e) {
    _pointers.remove(e.pointer);
    _updateDir();
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      _pointers.clear();
      _dir = 0;
    });
    if (_paused) {
      QuizAudio.musicPause();
    } else if (_started) {
      QuizAudio.musicResume();
    }
  }

  Future<void> _confirmQuit() async {
    final wasPaused = _paused;
    setState(() => _paused = true);
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
    if (!mounted) return;
    if (quit == true) {
      Navigator.of(context).pop();
    } else {
      setState(() => _paused = wasPaused);
    }
  }

  Future<void> _shareScore() async {
    try {
      final boundary = _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final tmpDir = await getTemporaryDirectory();
      final file = File('${tmpDir.path}/retro_jump_score.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'I climbed to $_score pts in Retro Jump! 🎮🚀',
      );
    } catch (e) {
      debugPrint('Share error: $e');
    }
  }

  // ── Affichage ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _gameOver,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _offer) {
          _declineContinue();
        } else if (!didPop) {
          _confirmQuit();
        } else if (_gameOver) {
          _reportFinished();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0F14),
        body: SafeArea(
          // Barre de navigation Android : marge garantie même si un parent l'a retirée
          minimum: EdgeInsets.only(bottom: MediaQueryData.fromView(View.of(context)).viewPadding.bottom),
          child: LayoutBuilder(builder: (_, c) {
            final w = c.maxWidth, h = c.maxHeight;
            if (_w == 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _w != 0) return;
                setState(() => _initGame(w, h));
                _startLoop();
              });
              return const SizedBox.shrink();
            }
            // Zone de jeu redimensionnée (barres système, rotation…) : on suit
            if ((w - _w).abs() > 1 || (h - _h).abs() > 1) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _w = w;
                  _h = h;
                });
              });
            }
            // ClipRect : rien ne déborde sous la barre d'état ni sous la barre Android
            return _gameOver ? _buildGameOver() : ClipRect(child: _buildGame(w, h));
          }),
        ),
      ),
    );
  }

  /// Applique le filtre de couleur du thème à l'aire de jeu.
  Widget _themed(Widget child) {
    final m = _themeMatrix(widget.theme);
    return m == null ? child : ColorFiltered(colorFilter: ColorFilter.matrix(m), child: child);
  }

  Widget _buildGame(double w, double h) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerUp,
      child: Stack(children: [
        _themed(CustomPaint(
          size: Size(w, h),
          painter: _JumpPainter(
            plats: _plats,
            enemies: _enemies,
            coins: _coinList,
            logos: _logoList,
            bags: _bagList,
            pickups: _pickups,
            slowmo: _slowT > 0,
            logoImgs: _logoImgs,
            particles: _particles,
            camY: _camY,
            heroX: _x,
            heroY: _y,
            facingRight: _facingRight,
            squash: _squash,
            turbo: _turbo,
            shieldOn: _shield,
            invuln: _invuln,
            turboImg: _turboImg,
            hero: widget.hero,
            time: _time,
            neon: widget.neon,
            crt: widget.theme == 4,
            disco: widget.theme == 7,
            startY: _startY,
            recordY: widget.bestScore > 0 ? _startY - widget.bestScore * 10 : null,
            rivals: _rivals,
          ),
        )),

        // Score + record
        Positioned(
          top: 10, left: 72, // à droite du bouton menu (hamburger)
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$_score',
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900,
                    shadows: [Shadow(color: Colors.black, blurRadius: 6)])),
            if (widget.bestScore > 0 || widget.daily != null)
              Text([
                if (widget.daily != null) '📅 Daily',
                if (widget.bestScore > 0) 'Best: ${widget.bestScore}',
              ].join(' · '),
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        ),

        // Bonus actifs (sous le score)
        if (_magnetT > 0 || _doubleT > 0 || _slowT > 0 || _superJumps > 0)
          Positioned(
            top: 62, left: 72,
            child: Row(children: [
              for (final e in [
                if (_magnetT > 0) (0, '${_magnetT.ceil()}s'),
                if (_doubleT > 0) (1, '${_doubleT.ceil()}s'),
                if (_superJumps > 0) (2, '×$_superJumps'),
                if (_slowT > 0) (3, '${_slowT.ceil()}s'),
              ])
                Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _pickupColors[e.$1].withOpacity(0.7)),
                  ),
                  child: Text('${_pickupIcons[e.$1]} ${e.$2}',
                      style: TextStyle(color: _pickupColors[e.$1], fontSize: 11, fontWeight: FontWeight.w800)),
                ),
            ]),
          ),

        // Run coins (none in the daily run)
        if (widget.daily == null) Positioned(
          top: 48, right: 10,
          child: Row(children: [
            const _CoinIcon(size: 14),
            const SizedBox(width: 5),
            Text('$_coinsRun',
                style: const TextStyle(color: Colors.amberAccent, fontSize: 15, fontWeight: FontWeight.w800,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
          ]),
        ),

        // Combo en cours
        if (_combo >= 2)
          Positioned(
            top: 72, right: 10,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(children: [
                const Icon(Icons.local_fire_department_rounded, color: Colors.deepOrangeAccent, size: 14),
                const SizedBox(width: 3),
                Text(_comboMult > 1 ? '${_combo} · ×$_comboMult' : '$_combo',
                    style: TextStyle(
                        color: _comboMult > 1 ? Colors.deepOrangeAccent : Colors.white70,
                        fontSize: 13, fontWeight: FontWeight.w900,
                        shadows: const [Shadow(color: Colors.black, blurRadius: 4)])),
              ]),
              if (_comboMult < _comboMax)
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 46, height: 4,
                  decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(2)),
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: (_combo % _cStep) / _cStep,
                    child: Container(decoration: BoxDecoration(
                        color: Colors.deepOrangeAccent, borderRadius: BorderRadius.circular(2))),
                  ),
                ),
            ]),
          ),

        // Barre de turbo
        if (_turbo > 0)
          Positioned(
            top: 16, left: w / 2 - 50,
            child: Container(
              width: 100, height: 6,
              decoration: BoxDecoration(
                color: Colors.greenAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (_turbo / _turboDur).clamp(0.0, 1.0),
                child: Container(decoration: BoxDecoration(
                  color: Colors.greenAccent,
                  borderRadius: BorderRadius.circular(3),
                )),
              ),
            ),
          ),

        // Bandeau (palier / record)
        if (_bannerT > 0)
          Positioned(
            top: h * 0.18, left: 0, right: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: (_bannerT / 0.4).clamp(0.0, 1.0),
                child: Text(_banner,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: widget.neon ? Colors.pinkAccent : Colors.amberAccent,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      shadows: const [Shadow(color: Colors.black, blurRadius: 8)],
                    )),
              ),
            ),
          ),

        // Bouton pause
        Positioned(
          top: 8, right: 48,
          child: GestureDetector(
            onTap: _togglePause,
            child: _TopButton(icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
          ),
        ),
        // Bouton quitter
        Positioned(
          top: 8, right: 8,
          child: GestureDetector(
            onTap: _confirmQuit,
            child: const _TopButton(icon: Icons.close_rounded),
          ),
        ),

        // Aide de départ
        if (!_started && !_paused)
          Positioned(
            bottom: h * 0.30, left: 0, right: 0,
            child: Column(children: [
              Text('Touch the screen to start',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14, letterSpacing: 1)),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.arrow_back_rounded, color: Colors.white.withOpacity(0.3), size: 20),
                const SizedBox(width: 8),
                Text(widget.tilt ? 'tilt your phone' : 'left  |  right',
                    style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, color: Colors.white.withOpacity(0.3), size: 20),
              ]),
            ]),
          ),

        // Pause
        if (_paused)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.7),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.pause_circle_rounded, color: Colors.white, size: 72),
                  const SizedBox(height: 16),
                  const Text('PAUSE',
                      style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 4)),
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

        // Proposition « continuer »
        if (_offer)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.75),
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(_deathByBug ? '🐞' : '💥', style: const TextStyle(fontSize: 52)),
                  const SizedBox(height: 10),
                  Text(_deathByBug ? 'A bug got you!' : 'You fell!',
                      style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text('Continue?',
                      style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 2)),
                  const SizedBox(height: 6),
                  Text('$_score pts',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _acceptContinue,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.replay_rounded, size: 20),
                          const SizedBox(width: 8),
                          const Text('Continue  ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          if (_freeCont)
                            const Text('Free', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF1B5E20)))
                          else ...[
                            const _CoinIcon(size: 18),
                            const SizedBox(width: 4),
                            Text('$_contPrice', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          ],
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text('You have ${_wallet + _coinsRun - _spent} coins',
                      style: const TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _declineContinue,
                    child: const Text('Give up', style: TextStyle(color: Colors.white54)),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildGameOver() {
    final record = _score > widget.bestScore && _score > 0;
    final color = record ? Colors.amberAccent : Colors.redAccent;
    final emoji = record ? '🏆' : _deathByBug ? '🐞' : _score >= 500 ? '🎮' : '💀';
    final msg = record ? 'New record!' : _deathByBug ? 'Fatal bug!' : 'Free fall!';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 4, 0, 16), // laisse la place au bouton menu
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
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Text(emoji, style: const TextStyle(fontSize: 40)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(msg, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700)),
                    Text('$_score pts',
                        style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, height: 1.15)),
                    Row(children: [
                      SizedBox(width: 22, height: 20, child: CustomPaint(painter: _HeroPreviewPainter(widget.hero))),
                      const SizedBox(width: 6),
                      Flexible(child: Text('${widget.daily != null ? 'Daily run' : 'Retro Jump'} · ${_heroNames[widget.hero]}${widget.theme != 0 ? ' · ${_themeNames[widget.theme]}' : ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white38, fontSize: 12))),
                    ]),
                    if (_lbState != 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          Icon(_lbState == 3 ? Icons.cloud_off_rounded : Icons.public_rounded, size: 14,
                              color: _lbState == 3 ? Colors.white38 : Colors.lightBlueAccent),
                          const SizedBox(width: 6),
                          Flexible(child: Text(_lbText(),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: _lbState == 3 ? Colors.white38 : Colors.lightBlueAccent,
                                  fontSize: 12, fontWeight: FontWeight.w700))),
                        ]),
                      ),
                  ])),
                ]),
              ),
              const SizedBox(height: 16),
              Row(children: [
                _StatCard(icon: Icons.monetization_on_rounded, color: Colors.amberAccent,
                    label: 'Coins', value: '$_coinsRun'),
                const SizedBox(width: 8),
                _StatCard(icon: Icons.bug_report_rounded, color: Colors.lightGreenAccent,
                    label: 'Bugs', value: '$_stomps'),
                const SizedBox(width: 8),
                _StatCard(icon: Icons.rocket_launch_rounded, color: Colors.greenAccent,
                    label: 'Turbos', value: '$_turbos'),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                _StatCard(icon: Icons.keyboard_double_arrow_up_rounded, color: Colors.cyanAccent,
                    label: 'Jumps', value: '$_jumps'),
                const SizedBox(width: 8),
                _StatCard(icon: Icons.unfold_more_rounded, color: Colors.orangeAccent,
                    label: 'Springs', value: '$_springs'),
                const SizedBox(width: 8),
                _StatCard(icon: Icons.landscape_rounded, color: Colors.purpleAccent,
                    label: 'Stage', value: _tierFor(_tierIdx).name),
              ]),
            ]),
          ),
        ),
        if (_resultsReady) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1C2230),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amberAccent.withOpacity(0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const _CoinIcon(size: 18),
                const SizedBox(width: 8),
                Text('+$_coinsEarned coins earned',
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 15, fontWeight: FontWeight.w800)),
              ]),
              if (_bestCombo >= _cStep) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.local_fire_department_rounded, color: Colors.deepOrangeAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Best combo: $_bestCombo jumps (×${min(_comboMax, 1 + _bestCombo ~/ _cStep)})',
                      style: const TextStyle(color: Colors.white, fontSize: 13))),
                ]),
              ],
              if (_spent > 0) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.replay_rounded, color: Colors.white54, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Continue used',
                      style: TextStyle(color: Colors.white70, fontSize: 13))),
                  Text('−$_spent',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ],
              if (_albumBonusEarned == 0) for (final i in _logosRun.toSet()) ...[
                const SizedBox(height: 8),
                Row(children: [
                  Icon(_collection[i] >= _logoGoal ? Icons.check_circle_rounded : Icons.collections_bookmark_rounded,
                      color: _collection[i] >= _logoGoal ? Colors.greenAccent : Colors.lightBlueAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Logo ${_logoNames[i]}',
                      style: const TextStyle(color: Colors.white, fontSize: 13))),
                  Text('${min(_collection[i], _logoGoal)}/$_logoGoal',
                      style: TextStyle(
                          color: _collection[i] >= _logoGoal ? Colors.greenAccent : Colors.lightBlueAccent,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ],
              for (final c in _newChallenges) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.military_tech_rounded, color: Colors.greenAccent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Challenge done: ${c.label}',
                      style: const TextStyle(color: Colors.white, fontSize: 13))),
                  Text('+${c.reward}',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ],
              if (_albumBonusEarned > 0) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.lightBlueAccent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.lightBlueAccent.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.collections_bookmark_rounded, color: Colors.lightBlueAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Album complete!',
                          style: TextStyle(color: Colors.lightBlueAccent, fontSize: 13, fontWeight: FontWeight.w800)),
                      Text(_album % _logoSets.length == 0
                              ? 'Album ${_album + 1} unlocked: ${_logoGoal} catches per logo'
                              : 'Album ${_album + 1} unlocked: new logos to find',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ])),
                    Text('+$_albumBonusEarned',
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ],
              if (_seriesBonusEarned > 0) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amberAccent.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.workspace_premium_rounded, color: Colors.amberAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Set completed bonus',
                          style: TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w800)),
                      Text('Set ${_chLevel + 1} unlocked: tougher challenges!',
                          style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ])),
                    Text('+$_seriesBonusEarned',
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ],
            ]),
          ),
        ],
        const SizedBox(height: 12),
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
        const SizedBox(height: 20),
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
              onPressed: () async {
                // Le record éventuel est enregistré avant de relancer
                await _reportFinished();
                if (!mounted) return;
                _freeCont = false; // le continue offert ne valait que pour la 1re partie
                setState(() => _initGame(_w, _h));
              },
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
    );
  }
}

class _TopButton extends StatelessWidget {
  final IconData icon;
  const _TopButton({required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    width: 32, height: 32,
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withOpacity(0.1)),
    ),
    child: Icon(icon, color: Colors.white54, size: 16),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// HEROES
// Each hero is drawn with origin (0, 0) = middle of its feet.
// 0 = Pixel robot · 1 = Arcade joystick · 2 = Mini cabinet · 3 = Token
// 4 = Cartridge · 5 = Floppy · 6 = CD · 7 = Cassette · 8 = TV · 9 = Mouse
// 10 = Pixel cat · 11 = Rocket
// ═══════════════════════════════════════════════════════════════════════════════

const _heroCount = 12;
const _dark = Color(0xFF0D0F14);
const _heroRed = Color(0xFFE02020);

void _eyes(Canvas c, double x1, double x2, double y, double r, bool right) {
  final look = (right ? 1 : -1) * r * 0.4;
  final white = Paint()..color = Colors.white;
  final pupil = Paint()..color = _dark;
  c.drawCircle(Offset(x1, y), r, white);
  c.drawCircle(Offset(x2, y), r, white);
  c.drawCircle(Offset(x1 + look, y + 0.5), r * 0.48, pupil);
  c.drawCircle(Offset(x2 + look, y + 0.5), r * 0.48, pupil);
  c.drawCircle(Offset(x1 + look + r * 0.25, y - r * 0.25), r * 0.18, white);
  c.drawCircle(Offset(x2 + look + r * 0.25, y - r * 0.25), r * 0.18, white);
}

void _rr(Canvas c, double x, double y, double w, double h, double r, Color color) {
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)), Paint()..color = color);
}

/// Draws hero [id]. [time] (seconds) drives the eye blink.
void _drawHero(Canvas c, int id, bool right, double time) {
  switch (id) {
    case 1:
      _drawJoystick(c, right, time);
      break;
    case 2:
      _drawCabinet(c, right, time);
      break;
    case 3:
      _drawCoin(c, right);
      break;
    case 4:
      _drawCartridge(c, right);
      break;
    case 5:
      _drawFloppy(c, right);
      break;
    case 6:
      _drawDisc(c, right, time);
      break;
    case 7:
      _drawCassette(c, right, time);
      break;
    case 8:
      _drawTv(c, right, time);
      break;
    case 9:
      _drawMouse(c, right, time);
      break;
    case 10:
      _drawCat(c, right, time);
      break;
    case 11:
      _drawRocket(c, right, time);
      break;
    default:
      _drawRobot(c, right);
  }
}

const _robotMap = [
  '......Y......',
  '......X......',
  '..XXXXXXXXX..',
  '.XXXXXXXXXXX.',
  '.XWWXXXXXWWX.',
  '.XWBXXXXXWBX.',
  '.XXXXXXXXXXX.',
  '.XXXKKKKKXXX.',
  '..XXXXXXXXX..',
  '...XX...XX...',
  '..XXX...XXX..',
];

void _drawRobot(Canvas c, bool right) {
  const p = 3.4;
  final cols = _robotMap.first.length;
  final rows = _robotMap.length;
  final ox = -cols * p / 2;
  final oy = -rows * p;
  final paint = Paint();
  for (int r = 0; r < rows; r++) {
    // Pupils on the movement side
    final row = right ? _robotMap[r] : _robotMap[r].replaceAll('WB', 'BW');
    for (int col = 0; col < cols; col++) {
      final ch = row[col];
      if (ch == '.') continue;
      paint.color = switch (ch) {
        'X' => _heroRed,
        'W' => Colors.white,
        'Y' => const Color(0xFFFFD740),
        'K' => const Color(0xFF7A0F0F),
        _ => _dark,
      };
      c.drawRect(Rect.fromLTWH(ox + col * p, oy + r * p, p + 0.2, p + 0.2), paint);
    }
  }
}

void _drawJoystick(Canvas c, bool right, double time) {
  final base = RRect.fromRectAndRadius(const Rect.fromLTWH(-20, -14, 40, 14), const Radius.circular(5));
  c.drawRRect(base, Paint()..color = const Color(0xFF2E3446));
  c.drawRRect(base, Paint()
    ..color = _heroRed
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2);
  c.drawCircle(const Offset(12, -7), 2.6, Paint()..color = const Color(0xFFFFD740));
  c.drawCircle(const Offset(17, -7), 2.6, Paint()..color = const Color(0xFF69F0AE));
  // Stick tilted toward the movement + slight sway
  final tilt = (right ? 0.18 : -0.18) + sin(time * 7) * 0.14;
  c.save();
  c.translate(0, -12);
  c.rotate(tilt);
  c.translate(0, 12);
  _rr(c, -2, -34, 4, 22, 2, const Color(0xFFB0B8C8));
  c.drawCircle(const Offset(0, -36), 10, Paint()..color = _heroRed);
  c.drawCircle(const Offset(-3, -39), 3, Paint()..color = Colors.white.withOpacity(0.35));
  _eyes(c, -3.8, 3.8, -36, 2.8, right);
  c.restore();
  // Ball joint on the base
  c.drawCircle(const Offset(0, -13), 3.2, Paint()..color = const Color(0xFF8A93A6));
}

void _drawCabinet(Canvas c, bool right, double time) {
  final body = Path()
    ..moveTo(-14, -40)
    ..lineTo(14, -40)
    ..lineTo(14, -26)
    ..lineTo(18, -18)
    ..lineTo(16, -2)
    ..lineTo(-16, -2)
    ..lineTo(-18, -18)
    ..lineTo(-14, -26)
    ..close();
  c.drawPath(body, Paint()..color = _heroRed);
  _rr(c, -12, -38, 24, 5, 1.5, const Color(0xFFFFD740));  // marquee
  _rr(c, -11, -31, 22, 14, 2, const Color(0xFF10131B));  // screen
  // Pixel face on the screen (blinks every ~3 s)
  final face = Paint()..color = const Color(0xFF18FFFF);
  final lx = right ? 1.0 : -1.0;
  final blink = (time % 3.2) < 0.14;
  if (blink) {
    c.drawRect(Rect.fromLTWH(-6 + lx, -25.5, 3, 1), face);
    c.drawRect(Rect.fromLTWH(3 + lx, -25.5, 3, 1), face);
  } else {
    c.drawRect(Rect.fromLTWH(-6 + lx, -27, 3, 3), face);
    c.drawRect(Rect.fromLTWH(3 + lx, -27, 3, 3), face);
  }
  c.drawRect(const Rect.fromLTWH(-3, -22, 6, 1.6), face);
  c.drawRect(const Rect.fromLTWH(-4, -23, 1.6, 1.6), face);
  c.drawRect(const Rect.fromLTWH(2.4, -23, 1.6, 1.6), face);
  // Control panel
  _rr(c, -16, -18, 32, 5, 1.5, const Color(0xFF2E3446));
  _rr(c, -9.6, -19.5, 1.2, 3.5, 0.5, const Color(0xFFB0B8C8));
  c.drawCircle(const Offset(-9, -16), 1.8, Paint()..color = const Color(0xFFFFD740));
  c.drawCircle(const Offset(4, -15.5), 1.6, Paint()..color = const Color(0xFF69F0AE));
  c.drawCircle(const Offset(8, -15.5), 1.6, Paint()..color = const Color(0xFF448AFF));
  c.drawCircle(const Offset(12, -15.5), 1.6, Paint()..color = const Color(0xFFFF5252));
  // Coin slot + feet
  _rr(c, -2, -9, 4, 4, 0.8, const Color(0xFF10131B));
  c.drawRect(const Rect.fromLTWH(-0.4, -8.3, 0.8, 2.6), Paint()..color = const Color(0xFFFF5252));
  _rr(c, -14, -2, 6, 3, 1, const Color(0xFF7A0F0F));
  _rr(c, 8, -2, 6, 3, 1, const Color(0xFF7A0F0F));
}

void _drawCoin(Canvas c, bool right) {
  c.drawCircle(const Offset(0, -15), 16, Paint()..color = const Color(0xFFC79100)); // edge
  c.drawCircle(const Offset(0, -17), 16, Paint()..color = const Color(0xFFFFD740));
  c.drawCircle(const Offset(0, -17), 12, Paint()
    ..color = const Color(0xFFE6A800)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2);
  c.drawCircle(const Offset(-6, -24), 4, Paint()..color = Colors.white.withOpacity(0.45));
  _eyes(c, -5, 5, -19, 3.4, right);
  c.drawArc(
    Rect.fromCircle(center: const Offset(0, -13.5), radius: 3),
    0.25, pi - 0.5, false,
    Paint()
      ..color = const Color(0xFF5D4300)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4,
  );
  final blush = Paint()..color = const Color(0xFFFF5252).withOpacity(0.55);
  c.drawCircle(const Offset(-9, -13), 1.8, blush);
  c.drawCircle(const Offset(9, -13), 1.8, blush);
}

// ── Héros 4 à 11 ──────────────────────────────────────────────────────────────

void _circle(Canvas c, double x, double y, double r, Color color) =>
    c.drawCircle(Offset(x, y), r, Paint()..color = color);

void _smile(Canvas c, double x, double y, double r, Color color, double w) {
  c.drawArc(Rect.fromCircle(center: Offset(x, y), radius: r), 0.25, pi - 0.5, false, Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = w);
}

void _legs(Canvas c, Color color) {
  _rr(c, -10, -4, 5, 4, 1.2, color);
  _rr(c, 5, -4, 5, 4, 1.2, color);
}

void _drawCartridge(Canvas c, bool right) {
  _legs(c, const Color(0xFF3A3F4A));
  c.drawPath(
    Path()
      ..moveTo(-15, -40)
      ..lineTo(15, -40)
      ..lineTo(15, -8)
      ..lineTo(11, -4)
      ..lineTo(-11, -4)
      ..lineTo(-15, -8)
      ..close(),
    Paint()..color = const Color(0xFF8A93A6),
  );
  for (int i = 0; i < 5; i++) {
    _rr(c, -12 + i * 5.2, -39, 3, 4, 1, const Color(0xFF6B7385));
  }
  _rr(c, -12, -32, 24, 20, 2, const Color(0xFF2979FF)); // étiquette
  _rr(c, -12, -32, 24, 4, 2, const Color(0xFF82B1FF));
  _eyes(c, -5, 5, -22, 3.2, right);
  _smile(c, 0, -17.5, 2.6, const Color(0xFF0D2B66), 1.4);
  _rr(c, -8, -8, 16, 3, 1, const Color(0xFF5C6476));
}

void _drawFloppy(Canvas c, bool right) {
  _legs(c, const Color(0xFF1A237E));
  c.drawPath(
    Path()
      ..moveTo(-16, -40)
      ..lineTo(12, -40)
      ..lineTo(16, -36)
      ..lineTo(16, -4)
      ..lineTo(-16, -4)
      ..close(),
    Paint()..color = const Color(0xFF283593),
  );
  _rr(c, -9, -40, 18, 11, 1, const Color(0xFFCFD8DC)); // volet métal
  _rr(c, 2, -38, 4, 7, 0.8, const Color(0xFF283593));
  _rr(c, -12, -24, 24, 18, 2, const Color(0xFFFAFAFA)); // étiquette
  c.drawRect(const Rect.fromLTWH(-12, -24, 24, 3), Paint()..color = const Color(0xFFE53935));
  _eyes(c, -5, 5, -15, 3.0, right);
  _smile(c, 0, -11, 2.4, const Color(0xFF37474F), 1.3);
}

void _drawDisc(Canvas c, bool right, double time) {
  _legs(c, const Color(0xFF78909C));
  const cy = -21.0, r = 17.0;
  _circle(c, 0, cy, r, const Color(0xFFCFD8DC));
  // Reflet arc-en-ciel qui tourne
  c.save();
  c.translate(0, cy);
  c.rotate(time * 2);
  c.drawCircle(Offset.zero, r - 1, Paint()
    ..shader = ui.Gradient.sweep(Offset.zero, const [
      Color(0x8CFF8A80), Color(0x8CFFD180), Color(0x8CFFFF8D), Color(0x8CB9F6CA),
      Color(0x8C80D8FF), Color(0x8CB388FF), Color(0x8CFF8A80),
    ], const [0.0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6, 1.0])); // 7 couleurs → 7 arrêts obligatoires
  c.restore();
  _circle(c, 0, cy, 6, const Color(0xFFECEFF1));
  _circle(c, 0, cy, 2.6, _dark);
  _eyes(c, -8, 8, cy - 4, 3.2, right);
  _smile(c, 0, cy + 7, 3, const Color(0xFF37474F), 1.4);
}

void _drawCassette(Canvas c, bool right, double time) {
  _legs(c, const Color(0xFF4E342E));
  _rr(c, -18, -34, 36, 30, 3, const Color(0xFFFF8F00));
  _rr(c, -14, -31, 28, 9, 1.5, const Color(0xFFFFF8E1));
  c.drawRect(const Rect.fromLTWH(-12, -28, 24, 1.2), Paint()..color = const Color(0xFFFF8F00));
  _rr(c, -13, -21, 26, 11, 5, const Color(0xFF3E2723));
  // Les bobines font office d'yeux (et tournent)
  final look = (right ? 1 : -1) * 1.4;
  final spoke = Paint()
    ..color = const Color(0xFFBDBDBD)
    ..strokeWidth = 1;
  for (final x in const [-7.0, 7.0]) {
    _circle(c, x, -15.5, 4.2, Colors.white);
    _circle(c, x + look, -15.5, 2.2, _dark);
    for (int k = 0; k < 3; k++) {
      final a = time * 4 + k * 2.09;
      c.drawLine(Offset(x + look, -15.5), Offset(x + look + cos(a) * 2, -15.5 + sin(a) * 2), spoke);
    }
  }
  c.drawPath(
    Path()
      ..moveTo(-9, -4)
      ..lineTo(-6, -8)
      ..lineTo(6, -8)
      ..lineTo(9, -4)
      ..close(),
    Paint()..color = const Color(0xFFE65100),
  );
}

void _drawTv(Canvas c, bool right, double time) {
  _legs(c, const Color(0xFF4E342E));
  final w = sin(time * 5) * 3; // antennes qui oscillent
  final ant = Paint()
    ..color = const Color(0xFFB0BEC5)
    ..strokeWidth = 1.6;
  c.drawLine(const Offset(0, -32), Offset(-9 + w, -46), ant);
  c.drawLine(const Offset(0, -32), Offset(9 + w, -46), ant);
  _circle(c, -9 + w, -46, 1.8, const Color(0xFFFFD740));
  _circle(c, 9 + w, -46, 1.8, const Color(0xFFFFD740));
  _rr(c, -19, -33, 38, 29, 4, const Color(0xFF8D6E63));
  _rr(c, -16, -30, 25, 22, 5, const Color(0xFF1A2733));
  // Visage en pixels + ligne de balayage
  final face = Paint()..color = const Color(0xFF18FFFF);
  final lx = right ? 1.0 : -1.0;
  final blink = (time % 3.4) < 0.14;
  c.drawRect(Rect.fromLTWH(-10 + lx, blink ? -22.5 : -24, 3, blink ? 1 : 3), face);
  c.drawRect(Rect.fromLTWH(-2 + lx, blink ? -22.5 : -24, 3, blink ? 1 : 3), face);
  c.drawRect(const Rect.fromLTWH(-8, -16, 8, 1.6), face);
  c.drawRect(const Rect.fromLTWH(-9, -17.5, 1.6, 1.6), face);
  c.drawRect(const Rect.fromLTWH(-0.6, -17.5, 1.6, 1.6), face);
  c.drawRect(Rect.fromLTWH(-16, -30 + (time * 20) % 20, 25, 2), Paint()..color = Colors.white.withOpacity(0.08));
  _circle(c, 14, -25, 2.2, const Color(0xFFFFD740));
  _circle(c, 14, -18, 2.2, const Color(0xFFBCAAA4));
  for (int i = 0; i < 3; i++) {
    c.drawRect(Rect.fromLTWH(11.5, -13 + i * 2.4, 5, 1.2), Paint()..color = const Color(0xFF5D4037));
  }
}

void _drawMouse(Canvas c, bool right, double time) {
  final s = right ? -1.0 : 1.0; // le fil part à l'opposé du déplacement
  c.drawPath(
    Path()
      ..moveTo(0, -38)
      ..cubicTo(s * 2, -46, s * 14, -44, s * 13 + sin(time * 6) * 2, -50),
    Paint()
      ..color = const Color(0xFF90A4AE)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  _legs(c, const Color(0xFF546E7A));
  c.drawOval(Rect.fromCenter(center: const Offset(0, -20), width: 30, height: 36), Paint()..color = const Color(0xFFECEFF1));
  final line = Paint()
    ..color = const Color(0xFFB0BEC5)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  c.drawLine(const Offset(0, -38), const Offset(0, -27), line);
  c.drawPath(Path()
    ..moveTo(-15, -27)
    ..quadraticBezierTo(0, -24, 15, -27), line);
  _rr(c, -1.6, -35, 3.2, 6, 1.5, _heroRed); // molette
  _eyes(c, -5.5, 5.5, -17, 3.2, right);
  _smile(c, 0, -11, 2.6, const Color(0xFF546E7A), 1.4);
  final blush = Paint()..color = const Color(0xFFFF5252).withOpacity(0.5);
  c.drawCircle(const Offset(-10, -12), 1.8, blush);
  c.drawCircle(const Offset(10, -12), 1.8, blush);
}

const _catMap = [
  '.X.......X.',
  '.XX.....XX.',
  '.XXXXXXXXX.',
  'XXXXXXXXXXX',
  'XXWBXXXWBXX',
  'XXXXMPMXXXX',
  'XXXXKMKXXXX',
  '.XXXXXXXXX.',
  '.XX.XXX.XX.',
  '.XX.....XX.',
];

void _drawCat(Canvas c, bool right, double time) {
  const p = 3.6;
  final cols = _catMap.first.length;
  final rows = _catMap.length;
  final ox = -cols * p / 2;
  final oy = -rows * p;
  // Queue qui remue, à l'opposé du déplacement
  final s = right ? -1.0 : 1.0;
  c.drawPath(
    Path()
      ..moveTo(s * 14, -8)
      ..quadraticBezierTo(s * 22, -12, s * 20 + sin(time * 4) * 3, -24),
    Paint()
      ..color = const Color(0xFFFF9800)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round,
  );
  final paint = Paint();
  for (int r = 0; r < rows; r++) {
    final row = right ? _catMap[r] : _catMap[r].replaceAll('WB', 'BW');
    for (int col = 0; col < cols; col++) {
      final ch = row[col];
      if (ch == '.') continue;
      paint.color = switch (ch) {
        'X' => const Color(0xFFFF9800),
        'W' => Colors.white,
        'M' => const Color(0xFFFFE0B2),
        'P' => const Color(0xFFF48FB1),
        'K' => const Color(0xFF5D4037),
        _ => _dark,
      };
      c.drawRect(Rect.fromLTWH(ox + col * p, oy + r * p, p + 0.2, p + 0.2), paint);
    }
  }
}

void _drawRocket(Canvas c, bool right, double time) {
  final fl = 5 + sin(time * 25) * 2; // flamme qui vacille
  c.drawPath(
    Path()
      ..moveTo(-5, -6)
      ..lineTo(0, -6 + fl)
      ..lineTo(5, -6)
      ..close(),
    Paint()..color = const Color(0xFFFFAB00),
  );
  final fin = Paint()..color = _heroRed;
  c.drawPath(Path()..moveTo(-10, -20)..lineTo(-17, -4)..lineTo(-8, -8)..close(), fin);
  c.drawPath(Path()..moveTo(10, -20)..lineTo(17, -4)..lineTo(8, -8)..close(), fin);
  c.drawPath(
    Path()
      ..moveTo(0, -48)
      ..cubicTo(13, -38, 12, -16, 9, -7)
      ..lineTo(-9, -7)
      ..cubicTo(-12, -16, -13, -38, 0, -48)
      ..close(),
    Paint()..color = const Color(0xFFECEFF1),
  );
  c.drawPath(
    Path()
      ..moveTo(0, -48)
      ..cubicTo(6, -44, 8, -41, 9, -38)
      ..lineTo(-9, -38)
      ..cubicTo(-8, -41, -6, -44, 0, -48)
      ..close(),
    fin,
  );
  _circle(c, 0, -26, 7.5, const Color(0xFF90A4AE)); // hublot
  _circle(c, 0, -26, 6, const Color(0xFF263238));
  _eyes(c, -2.6, 2.6, -26, 2.2, right);
  _rr(c, -9, -11, 18, 3, 1, const Color(0xFFB0BEC5));
}

/// Hero preview (selector, results screen).
class _HeroPreviewPainter extends CustomPainter {
  final int hero;
  final double time; // > 0 : héros animé qui sautille (accueil)
  const _HeroPreviewPainter(this.hero, [this.time = 0]);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.height / 50;
    final hop = time > 0 ? sin(time * 2.4).abs() * 7 : 0.0;
    if (time > 0) {
      // Ombre au sol (rétrécit quand le héros monte)
      canvas.drawOval(
        Rect.fromCenter(center: Offset(size.width / 2, size.height - 2 * s),
            width: (34 - hop * 1.6) * s, height: 5 * s),
        Paint()..color = Colors.black.withOpacity(0.35),
      );
    }
    canvas.save();
    canvas.translate(size.width / 2, size.height - 2 * s - hop * s);
    canvas.scale(s, s);
    _drawHero(canvas, hero, true, time > 0 ? time : 1.0);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HeroPreviewPainter old) => old.hero != hero || old.time != time;
}

// ═══════════════════════════════════════════════════════════════════════════════
// DRAWING
// ═══════════════════════════════════════════════════════════════════════════════

// Bug = beetle seen from above (2 frames for the leg animation)
const _bugFrames = [
  [
    '...HHH...',
    '..HWHWH..',
    'L.XXDXX.L',
    '.XXSDSXX.',
    'LXXXDXXXL',
    '.XSXDXSX.',
    'L.XXDXX.L',
  ],
  [
    '...HHH...',
    '..HWHWH..',
    '..XXDXX..',
    'LXXSDSXXL',
    '.XXXDXXX.',
    'LXSXDXSXL',
    '..XXDXX..',
  ],
];

class _JumpPainter extends CustomPainter {
  final List<_Plat> plats;
  final List<_Enemy> enemies;
  final List<_Coin> coins;
  final List<_Logo> logos;
  final List<_Coin> bags;
  final List<_Pickup> pickups;
  final bool slowmo;
  final List<ui.Image?> logoImgs;
  final List<_Particle> particles;
  final double camY, heroX, heroY, squash, turbo, time, invuln;
  final double startY; // y monde du départ (hauteur 0)
  final bool facingRight, neon, shieldOn;
  final bool crt; // thème CRT : lignes de balayage + bords sombres
  final bool disco; // thème Disco : lumières qui clignotent
  final ui.Image? turboImg;
  final int hero;
  final double? recordY; // y monde de la ligne du record (null = pas de record)
  final List<(int, String, int)> rivals; // other players (score, name, rank)

  _JumpPainter({
    required this.plats,
    required this.enemies,
    required this.coins,
    required this.logos,
    required this.bags,
    required this.pickups,
    required this.slowmo,
    required this.logoImgs,
    required this.particles,
    required this.camY,
    required this.heroX,
    required this.heroY,
    required this.facingRight,
    required this.squash,
    required this.turbo,
    required this.shieldOn,
    required this.invuln,
    required this.turboImg,
    required this.hero,
    required this.time,
    required this.neon,
    required this.crt,
    required this.disco,
    required this.startY,
    required this.recordY,
    this.rivals = const [],
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintBackground(canvas, size);
    if (disco) _paintDiscoLights(canvas, size);
    _paintRecordLine(canvas, size);
    _paintRivals(canvas, size);
    for (final p in plats) {
      final sy = p.y - camY;
      if (sy < -40 || sy > size.height + 40) continue;
      _paintCartridge(canvas, p, Offset(p.x, sy));
      if (p.hasTurbo) _paintTurbo(canvas, Offset(p.x + _platW / 2, sy - 24));
      if (p.hasShield) _paintShieldItem(canvas, Offset(p.x + _platW / 2, sy - 24));
    }
    for (final c in coins) {
      final sy = c.y - camY;
      if (c.taken || sy < -20 || sy > size.height + 20) continue;
      _paintCoin(canvas, Offset(c.x, sy));
    }
    for (final pk in pickups) {
      final sy = pk.y - camY + sin(time * 3.5 + pk.x) * 5;
      if (pk.taken || sy < -30 || sy > size.height + 30) continue;
      _paintPickup(canvas, pk.kind, Offset(pk.x, sy));
    }
    for (final b in bags) {
      final sy = b.y - camY + sin(time * 3 + b.x) * 4;
      if (b.taken || sy < -30 || sy > size.height + 30) continue;
      _paintBag(canvas, Offset(b.x, sy));
    }
    for (final lg in logos) {
      final sy = lg.y - camY + sin(time * 3 + lg.x) * 4;
      if (lg.taken || sy < -30 || sy > size.height + 30) continue;
      _paintLogo(canvas, lg, Offset(lg.x, sy));
    }
    for (final e in enemies) {
      final sy = e.y - camY + (e.dead ? 0 : sin(e.phase * 3) * 3);
      if (sy < -30 || sy > size.height + 30) continue;
      _paintBug(canvas, e, Offset(e.x, sy));
    }
    for (final pa in particles) {
      canvas.drawCircle(
        Offset(pa.pos.dx, pa.pos.dy - camY),
        2.5,
        Paint()..color = pa.color.withOpacity(pa.life.clamp(0.0, 1.0)),
      );
    }
    _paintHero(canvas, Offset(heroX, heroY - camY));
    if (crt) _paintCrt(canvas, size);
    if (disco) _paintDiscoPulse(canvas, size);
    if (slowmo) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF40C4FF).withOpacity(0.08));
    }
  }

  /// Thème Disco : boule à facettes, faisceaux de couleur, reflets et pulsation.
  void _paintDiscoLights(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final beat = (time * 2) % 1.0; // 2 pulsations par seconde (≈ 120 BPM)
    final ball = Offset(w / 2, 34);
    // Faisceaux qui balaient l'écran depuis la boule
    const beamColors = [Color(0xFFFF4081), Color(0xFF18FFFF), Color(0xFFFFEB3B), Color(0xFF7C4DFF), Color(0xFF69F0AE)];
    for (int i = 0; i < beamColors.length; i++) {
      final a = pi / 2 + sin(time * (0.7 + i * 0.23) + i * 1.7) * 0.9;
      final len = h * 1.3;
      final end = ball + Offset(cos(a), sin(a)) * len;
      final perp = Offset(-sin(a), cos(a)) * (len * 0.12);
      final path = Path()
        ..moveTo(ball.dx, ball.dy)
        ..lineTo(end.dx + perp.dx, end.dy + perp.dy)
        ..lineTo(end.dx - perp.dx, end.dy - perp.dy)
        ..close();
      canvas.drawPath(path, Paint()
        ..shader = ui.Gradient.linear(ball, end, [
          beamColors[i].withOpacity(0.28),
          beamColors[i].withOpacity(0.0),
        ]));
    }
    // Reflets de la boule : petites taches de lumière qui tournent
    final dot = Paint();
    for (int i = 0; i < 46; i++) {
      final ang = time * 0.6 + i * 2.39996;
      final rad = (0.15 + ((i * 37) % 100) / 100 * 0.85) * max(w, h) * 0.75;
      final p = Offset(w / 2 + cos(ang) * rad, h * 0.45 + sin(ang) * rad * 0.8);
      if (p.dx < -10 || p.dx > w + 10 || p.dy < -10 || p.dy > h + 10) continue;
      final hue = (i * 47 + time * 90) % 360;
      final tw = 0.5 + 0.5 * sin(time * 6 + i);
      dot.color = HSVColor.fromAHSV(0.35 + 0.4 * tw, hue, 0.7, 1).toColor();
      canvas.drawCircle(p, 2.2 + 1.8 * tw, dot);
    }
    // Boule à facettes
    canvas.drawCircle(ball, 26, Paint()
      ..color = Colors.white.withOpacity(0.25 + 0.2 * (1 - beat))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: ball, radius: 16)));
    canvas.drawCircle(ball, 16, Paint()..color = const Color(0xFF9EA7B8));
    const tile = 4.0;
    final off = (time * 8) % tile; // les facettes défilent : la boule tourne
    for (double y = ball.dy - 16; y < ball.dy + 16; y += tile) {
      for (double x = ball.dx - 16 - off; x < ball.dx + 16; x += tile) {
        final k = ((x - off) / tile).floor() * 31 + (y / tile).floor() * 17;
        final shine = 0.4 + 0.6 * (0.5 + 0.5 * sin(time * 5 + k));
        canvas.drawRect(Rect.fromLTWH(x + 0.5, y + 0.5, tile - 1, tile - 1),
            Paint()..color = Color.lerp(const Color(0xFF5C6476), Colors.white, shine)!);
      }
    }
    canvas.restore();
    canvas.drawLine(Offset(ball.dx, 0), Offset(ball.dx, ball.dy - 16), Paint()
      ..color = const Color(0xFF9EA7B8)
      ..strokeWidth = 1.5);
  }

  /// Pulsation colorée de tout l'écran, en rythme (douce, sans flash brutal).
  void _paintDiscoPulse(Canvas canvas, Size size) {
    final beat = (time * 2) % 1.0;
    final hue = (time * 60) % 360;
    canvas.drawRect(Offset.zero & size, Paint()
      ..color = HSVColor.fromAHSV(0.10 * (1 - beat), hue, 0.8, 1).toColor());
  }

  /// Thème CRT : lignes de balayage, léger scintillement et coins assombris.
  void _paintCrt(Canvas canvas, Size size) {
    final line = Paint()..color = Colors.black.withOpacity(0.22 + 0.04 * sin(time * 50));
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1.2), line);
    }
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.radial(c, size.longestSide * 0.62, [
        Colors.transparent,
        Colors.black.withOpacity(0.55),
      ], [0.6, 1.0]));
    // Reflet de la vitre
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(size.width, size.height), [
        Colors.white.withOpacity(0.05),
        Colors.transparent,
      ], [0.0, 0.4]));
  }

  // ── Fond : mur de la tour (un style tous les 400 pts) ─────────────────────
  /// Hauteur (pts) correspondant à une ligne de l'écran, parallaxe comprise.
  double _heightAt(double sy) => (startY - camY - sy / _parallax) / 10;

  /// Ligne d'écran où commence la hauteur [pts].
  double _syOfHeight(double pts) => _parallax * (startY - camY - pts * 10);

  void _paintBackground(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bottomIdx = max(0, (_heightAt(h) / _tierStep).floor());
    final topIdx = max(0, (_heightAt(0) / _tierStep).floor());
    for (int k = bottomIdx; k <= topIdx; k++) {
      final secBottom = k == 0 ? h : min(h, _syOfHeight(k * _tierStep.toDouble()));
      final secTop = max(0.0, _syOfHeight((k + 1) * _tierStep.toDouble()));
      if (secBottom <= secTop) continue;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, secTop, w, secBottom));
      final t = _tierFor(k);
      if (t.deco == _Deco.space) {
        _paintSpace(canvas, size, t, k);
      } else {
        _paintWall(canvas, w, secTop, secBottom, t);
      }
      canvas.restore();
    }
    // Corniches entre deux décors
    for (int k = max(1, bottomIdx); k <= topIdx; k++) {
      final y = _syOfHeight(k * _tierStep.toDouble());
      if (y > -20 && y < h + 20) _paintLedge(canvas, w, y);
    }
    // Ombre sur les bords (effet de tour arrondie) + mode néon plus sombre
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(w, 0), [
        Colors.black.withOpacity(0.65),
        Colors.black.withOpacity(0.25),
        Colors.black.withOpacity(0.15),
        Colors.black.withOpacity(0.25),
        Colors.black.withOpacity(0.65),
      ], [0, 0.18, 0.5, 0.82, 1]));
    if (neon) canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.35));
  }

  void _paintWall(Canvas canvas, double w, double top, double bottom, _Tier t) {
    final bw = t.bw, rh = t.rh;
    final scroll = camY * _parallax;
    canvas.drawRect(Rect.fromLTRB(0, top, w, bottom), Paint()..color = t.mortar);
    final brick = Paint();
    final hi = Paint()..color = Colors.white.withOpacity(0.06);
    final lo = Paint()..color = Colors.black.withOpacity(0.18);
    final r0 = ((scroll + top) / rh).floor();
    final r1 = ((scroll + bottom) / rh).floor();
    for (int r = r0; r <= r1; r++) {
      final sy = r * rh - scroll;
      final off = r.isOdd ? bw / 2 : 0.0;
      for (int col = 0; col * bw - off < w; col++) {
        final x = col * bw - off;
        final v = 0.85 + 0.3 * _hash(r, col);
        brick.color = Color.fromARGB(255,
            (t.base.red * v).clamp(0, 255).toInt(),
            (t.base.green * v).clamp(0, 255).toInt(),
            (t.base.blue * v).clamp(0, 255).toInt());
        canvas.drawRect(Rect.fromLTWH(x + 1.5, sy + 1.5, bw - 3, rh - 3), brick);
        canvas.drawRect(Rect.fromLTWH(x + 1.5, sy + 1.5, bw - 3, 2), hi);
        canvas.drawRect(Rect.fromLTWH(x + 1.5, sy + rh - 3.5, bw - 3, 2), lo);
        _paintBrickDeco(canvas, t, r, col, x, sy);
      }
      _paintRowDeco(canvas, t, r, sy, w);
    }
  }

  /// Décoration sur une brique (fissures de lave, givre, glyphes, rivets).
  void _paintBrickDeco(Canvas canvas, _Tier t, int r, int col, double x, double sy) {
    final bw = t.bw, rh = t.rh;
    final d = _hash(r * 3 + 7, col * 5 + 1);
    switch (t.deco) {
      case _Deco.lava:
        if (d < 0.18) {
          final gl = 0.5 + 0.5 * sin(time * 2 + r + col);
          canvas.drawPath(
            Path()
              ..moveTo(x + bw * 0.2, sy + 3)
              ..lineTo(x + bw * 0.45, sy + rh * 0.5)
              ..lineTo(x + bw * 0.35, sy + rh - 3),
            Paint()
              ..color = Color.fromARGB(((0.35 + 0.4 * gl) * 255).toInt(), 255, (90 + 60 * gl).toInt(), 0)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
        break;
      case _Deco.ice:
        if (d < 0.25) {
          canvas.drawPath(
            Path()
              ..moveTo(x + 6, sy + rh - 6)
              ..lineTo(x + bw * 0.5, sy + 4)
              ..lineTo(x + bw * 0.5 + 6, sy + 4)
              ..lineTo(x + 12, sy + rh - 6)
              ..close(),
            Paint()..color = const Color(0x1AC8F0FF),
          );
        }
        break;
      case _Deco.glyph:
        if (d < 0.12) {
          final cx = x + bw / 2, cy = sy + rh / 2;
          final p = Paint()
            ..color = const Color(0xB3281E0F)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2;
          canvas.drawCircle(Offset(cx, cy - 4), 4, p);
          canvas.drawLine(Offset(cx, cy), Offset(cx, cy + 9), p);
          canvas.drawLine(Offset(cx - 5, cy + 3), Offset(cx + 5, cy + 3), p);
        }
        break;
      case _Deco.neon:
        final rivet = Paint()..color = Colors.black.withOpacity(0.35);
        for (final o in [Offset(4, 4), Offset(bw - 6, 4), Offset(4, rh - 6), Offset(bw - 6, rh - 6)]) {
          canvas.drawRect(Rect.fromLTWH(x + o.dx, sy + o.dy, 2, 2), rivet);
        }
        break;
      default:
        break;
    }
  }

  /// Décoration sur une rangée (meurtrières, torches, néons).
  void _paintRowDeco(Canvas canvas, _Tier t, int r, double sy, double w) {
    final rh = t.rh;
    switch (t.deco) {
      case _Deco.slit:
        if (r % 7 == 0) {
          final sx = w * (0.2 + 0.6 * _hash(r, 5));
          final hh = rh * 2 - 6;
          canvas.drawRect(Rect.fromLTWH(sx - 6, sy + 1, 12, hh + 4), Paint()..color = const Color(0xFF7A808C));
          canvas.drawPath(
            Path()
              ..moveTo(sx - 3, sy + hh + 3)
              ..lineTo(sx - 3, sy + 7)
              ..arcToPoint(Offset(sx + 3, sy + 7), radius: const Radius.circular(3))
              ..lineTo(sx + 3, sy + hh + 3)
              ..close(),
            Paint()..color = const Color(0xFF07080B),
          );
        }
        break;
      case _Deco.torch:
        if (r % 9 == 0) {
          final sx = (r ~/ 9).isOdd ? w * 0.15 : w * 0.85;
          final f = 0.7 + 0.3 * sin(time * 9 + r) * sin(time * 13);
          final c = Offset(sx, sy);
          canvas.drawCircle(c, 70, Paint()
            ..shader = ui.Gradient.radial(c, 70, [
              Color.fromARGB((0.35 * f * 255).toInt(), 255, 160, 40),
              const Color(0x00FF7800),
            ]));
          canvas.drawRect(Rect.fromLTWH(sx - 3, sy, 6, 14), Paint()..color = const Color(0xFF3B2A1A));
          canvas.drawOval(Rect.fromCenter(center: Offset(sx, sy - 4), width: 8, height: (7 * f + 2) * 2),
              Paint()..color = Color.fromARGB(255, 255, (170 + 50 * f).toInt(), 60));
        }
        break;
      case _Deco.neon:
        if (r % 6 == 0) {
          final gl = 0.6 + 0.4 * sin(time * 3 + r);
          final y = sy + rh / 2 - 1;
          canvas.drawRect(Rect.fromLTWH(0, y - 2, w, 6), Paint()
            ..color = const Color(0xFF00E5FF).withOpacity(0.25 * gl)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
          canvas.drawRect(Rect.fromLTWH(0, y, w, 2), Paint()..color = const Color(0xFF00E5FF).withOpacity(0.5 * gl));
        }
        break;
      default:
        break;
    }
  }

  void _paintSpace(Canvas canvas, Size size, _Tier t, int k) {
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), [t.top, t.bottom]));
    final starPaint = Paint();
    for (int i = 0; i < 70; i++) {
      final sx = ((i * 7919) % 1000) / 1000 * size.width;
      final base = ((i * 104729) % 1000) / 1000 * size.height;
      final sy = (base - camY * 0.25) % size.height;
      final tw = 0.5 + 0.5 * sin(time * 2 + i);
      starPaint.color = Colors.white.withOpacity(0.25 + 0.55 * tw);
      canvas.drawCircle(Offset(sx, sy), i % 7 == 0 ? 1.6 : 1.0, starPaint);
    }
    // Planète à anneau, au milieu du palier
    final c = Offset(size.width * 0.75, _syOfHeight(k * _tierStep + _tierStep * 0.55));
    if (c.dy > -80 && c.dy < size.height + 80) {
      canvas.drawCircle(c, 38, Paint()
        ..shader = ui.Gradient.radial(c, 40, [const Color(0xFF7E57C2), const Color(0xFF311B92)]));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-0.3);
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 124, height: 24), Paint()
        ..color = const Color(0x80C8B4FF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
      canvas.restore();
    }
  }

  /// Corniche de pierre qui marque le passage à un nouveau décor.
  void _paintLedge(Canvas canvas, double w, double y) {
    canvas.drawRect(Rect.fromLTWH(0, y - 2, w, 4), Paint()..color = const Color(0xAA000000));
    canvas.drawRect(Rect.fromLTWH(0, y, w, 10), Paint()..color = const Color(0xFF5A5F6A));
    canvas.drawRect(Rect.fromLTWH(0, y, w, 2), Paint()..color = const Color(0xFF7A808C));
    canvas.drawRect(Rect.fromLTWH(0, y + 10, w, 4), Paint()..color = const Color(0xFF2A2D34));
    final dent = Paint()..color = const Color(0xFF4A4F5A);
    for (double x = 0; x < w; x += 18) {
      canvas.drawRect(Rect.fromLTWH(x + 2, y + 12, 12, 6), dent);
    }
  }

  /// Thick lines of other players, with rank and name
  void _paintRivals(Canvas canvas, Size size) {
    for (final r in rivals) {
      final y = startY - r.$1 * 10 - camY;
      if (y < -40 || y > size.height + 20) continue;
      final c = r.$3 == 1
          ? const Color(0xFFFFD740)
          : r.$3 == 2
              ? const Color(0xFFCFD8DC)
              : r.$3 == 3
                  ? const Color(0xFFFFAB40)
                  : const Color(0xFF40C4FF);
      canvas.drawRect(Rect.fromLTWH(0, y - 4, size.width, 8),
          Paint()
            ..color = c.withOpacity(0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      canvas.drawRect(Rect.fromLTWH(0, y - 2.5, size.width, 5), Paint()..color = c.withOpacity(0.9));
      final tp = TextPainter(
        text: TextSpan(children: [
          TextSpan(text: '#${r.$3} ', style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w900)),
          TextSpan(text: r.$2, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
          TextSpan(text: '  ${_fmtNum(r.$1)}', style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
        ]),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width * 0.65);
      final box = RRect.fromRectAndRadius(
          Rect.fromLTWH(8, y - tp.height - 10, tp.width + 14, tp.height + 6), const Radius.circular(8));
      canvas.drawRRect(box, Paint()..color = Colors.black.withOpacity(0.65));
      canvas.drawRRect(box, Paint()
        ..color = c
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2);
      tp.paint(canvas, Offset(box.left + 7, box.top + 3));
    }
  }

  void _paintRecordLine(Canvas canvas, Size size) {
    final ry = recordY;
    if (ry == null) return;
    final y = ry - camY;
    if (y < -10 || y > size.height + 10) return;
    final paint = Paint()
      ..color = const Color(0xFFFFD740).withOpacity(0.7)
      ..strokeWidth = 2;
    for (double x = 0; x < size.width; x += 16) {
      canvas.drawLine(Offset(x, y), Offset(x + 9, y), paint);
    }
    final tp = TextPainter(
      text: const TextSpan(
        text: _txtRecordLine,
        style: TextStyle(color: Color(0xFFFFD740), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width - tp.width - 8, y - tp.height - 3));
  }

  Paint _glow(Color c, double blur, double width) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur);

  void _paintCartridge(Canvas canvas, _Plat p, Offset o) {
    final Color body;
    switch (p.type) {
      case _PlatType.moving:
        body = Colors.lightBlueAccent.shade400;
        break;
      case _PlatType.breakable:
        body = const Color(0xFF6D4C41);
        break;
      default:
        // Disco : les cartouches normales changent de couleur en rythme
        body = disco
            ? HSVColor.fromAHSV(1, (time * 120 + p.colorIdx * 60 + p.x) % 360, 0.75, 1).toColor()
            : _cartColors[p.colorIdx % _cartColors.length];
    }
    final opacity = p.broken ? 0.5 : 1.0;
    canvas.save();
    if (p.broken) {
      canvas.translate(o.dx + _platW / 2, o.dy + _platH / 2);
      canvas.rotate(0.25);
      canvas.translate(-(o.dx + _platW / 2), -(o.dy + _platH / 2));
    }
    final rect = RRect.fromRectAndCorners(
      Rect.fromLTWH(o.dx, o.dy, _platW, _platH),
      topLeft: const Radius.circular(4), topRight: const Radius.circular(4),
      bottomLeft: const Radius.circular(2), bottomRight: const Radius.circular(2),
    );
    if (neon) {
      // Contour lumineux façon borne d'arcade
      final c = p.type == _PlatType.breakable ? const Color(0xFFFF8A65) : body;
      canvas.drawRRect(rect, _glow(c.withOpacity(0.8 * opacity), 6, 3));
      canvas.drawRRect(rect, Paint()..color = c.withOpacity(0.14 * opacity));
      canvas.drawRRect(rect, Paint()
        ..color = c.withOpacity(opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6);
    } else {
      canvas.drawRRect(rect, Paint()..color = body.withOpacity(opacity));
      // Étiquette
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(o.dx + 10, o.dy + 3, _platW - 20, _platH - 7), const Radius.circular(2)),
        Paint()..color = Colors.white.withOpacity(0.28 * opacity),
      );
      // Encoches du connecteur
      final notch = Paint()..color = Colors.black.withOpacity(0.35 * opacity);
      for (int i = 0; i < 5; i++) {
        canvas.drawRect(Rect.fromLTWH(o.dx + 14 + i * 9, o.dy + _platH - 3, 5, 3), notch);
      }
    }
    // Fissures
    if (p.type == _PlatType.breakable) {
      final crack = Paint()
        ..color = (neon ? const Color(0xFFFF8A65) : Colors.black).withOpacity(0.6 * opacity)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      final path = Path()
        ..moveTo(o.dx + 22, o.dy)
        ..lineTo(o.dx + 28, o.dy + 6)
        ..lineTo(o.dx + 24, o.dy + 10)
        ..lineTo(o.dx + 31, o.dy + _platH)
        ..moveTo(o.dx + 46, o.dy)
        ..lineTo(o.dx + 41, o.dy + 7)
        ..lineTo(o.dx + 47, o.dy + _platH);
      canvas.drawPath(path, crack);
    }
    // Ressort
    if (p.type == _PlatType.spring) {
      final cx = o.dx + _platW / 2;
      final coil = Paint()
        ..color = Colors.amberAccent
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(cx - 6, o.dy);
      for (int i = 0; i < 4; i++) {
        path.lineTo(i.isEven ? cx + 6 : cx - 6, o.dy - 3 - i * 3);
      }
      if (neon) canvas.drawPath(path, _glow(Colors.amberAccent, 4, 3));
      canvas.drawPath(path, coil);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(cx - 9, o.dy - 16, 18, 4), const Radius.circular(2)),
        Paint()..color = Colors.amberAccent,
      );
    }
    canvas.restore();
  }

  void _paintCoin(Canvas canvas, Offset c) {
    // Pièce qui tourne sur elle-même
    final sx = max(0.25, cos(time * 4 + c.dx * 0.05).abs());
    if (neon) {
      canvas.drawCircle(c, _coinR + 3, Paint()
        ..color = const Color(0xFFFFD740).withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(sx, 1);
    canvas.drawCircle(Offset.zero, _coinR, Paint()..color = const Color(0xFFFFD740));
    canvas.drawCircle(Offset.zero, _coinR - 2.5, Paint()
      ..color = const Color(0xFFE6A800)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4);
    canvas.drawCircle(const Offset(-2.2, -2.2), 1.6, Paint()..color = Colors.white.withOpacity(0.6));
    canvas.restore();
  }

  void _paintBug(Canvas canvas, _Enemy e, Offset c) {
    final body = e.moving ? const Color(0xFFE040FB) : const Color(0xFF76FF03);
    final dark = e.moving ? const Color(0xFF6A1B9A) : const Color(0xFF33691E);
    const p = 3.3;
    final rows = _bugFrames[(time * 5 + e.phase).floor().isEven ? 0 : 1];
    final cols = rows.first.length;
    final ox = -cols * p / 2;
    final oy = -rows.length * p / 2;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    if (e.dead) {
      canvas.rotate(pi);
    }
    if (neon && !e.dead) {
      canvas.drawCircle(Offset.zero, 16, Paint()
        ..color = body.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }
    final paint = Paint();
    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];
      for (int col = 0; col < cols; col++) {
        final ch = row[col];
        if (ch == '.') continue;
        paint.color = switch (ch) {
          'X' => body,
          'W' => Colors.white,
          _ => dark,
        };
        if (e.dead) paint.color = paint.color.withOpacity(0.6);
        canvas.drawRect(Rect.fromLTWH(ox + col * p, oy + r * p, p + 0.2, p + 0.2), paint);
      }
    }
    canvas.restore();
  }

  /// Shield bonus: cyan bubble with a badge.
  void _paintShieldItem(Canvas canvas, Offset c) {
    final bob = sin(time * 3) * 2;
    final o = Offset(c.dx, c.dy + bob);
    canvas.drawCircle(o, 16, Paint()
      ..color = Colors.cyanAccent.withOpacity(neon ? 0.45 : 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(o, 13, Paint()..color = Colors.cyanAccent.withOpacity(0.15));
    canvas.drawCircle(o, 13, Paint()
      ..color = Colors.cyanAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final badge = Path()
      ..moveTo(o.dx, o.dy - 7)
      ..lineTo(o.dx + 6, o.dy - 4.5)
      ..lineTo(o.dx + 5, o.dy + 2)
      ..quadraticBezierTo(o.dx + 3, o.dy + 6, o.dx, o.dy + 8)
      ..quadraticBezierTo(o.dx - 3, o.dy + 6, o.dx - 5, o.dy + 2)
      ..lineTo(o.dx - 6, o.dy - 4.5)
      ..close();
    canvas.drawPath(badge, Paint()..color = Colors.cyanAccent);
    canvas.drawCircle(Offset(o.dx - 4, o.dy - 6), 2, Paint()..color = Colors.white.withOpacity(0.7));
  }

  /// Logo de console à collectionner : carte sombre au contour lumineux.
  /// Sac de pièces : bourse dorée nouée, avec halo qui pulse.
  /// Bonus à ramasser : bulle colorée qui pulse, avec son symbole.
  void _paintPickup(Canvas canvas, int kind, Offset c) {
    final col = _pickupColors[kind];
    final pulse = 0.5 + 0.5 * sin(time * 6 + c.dx);
    canvas.drawCircle(c, 20 + 3 * pulse, Paint()
      ..color = col.withOpacity(0.25 + 0.2 * pulse)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(c, 15, Paint()..color = const Color(0xE61C2230));
    canvas.drawCircle(c, 15, Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2);
    final tp = TextPainter(
      text: TextSpan(
        text: _pickupIcons[kind],
        style: TextStyle(color: col, fontSize: kind == 1 ? 13 : 15, fontWeight: FontWeight.w900),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintBag(Canvas canvas, Offset c) {
    final glow = 0.5 + 0.5 * sin(time * 5 + c.dx);
    canvas.drawCircle(c, 20, Paint()
      ..color = const Color(0xFFFFD740).withOpacity((neon ? 0.35 : 0.18) + 0.15 * glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    // Corps du sac
    final body = Path()
      ..moveTo(c.dx - 6, c.dy - 8)
      ..cubicTo(c.dx - 18, c.dy - 2, c.dx - 17, c.dy + 14, c.dx, c.dy + 14)
      ..cubicTo(c.dx + 17, c.dy + 14, c.dx + 18, c.dy - 2, c.dx + 6, c.dy - 8)
      ..close();
    canvas.drawPath(body, Paint()..color = const Color(0xFF8D5A2B));
    canvas.drawPath(body, Paint()
      ..color = const Color(0xFF5D3A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4);
    // Col froncé + lien doré
    canvas.drawPath(
      Path()
        ..moveTo(c.dx - 7, c.dy - 9)
        ..lineTo(c.dx - 9, c.dy - 15)
        ..lineTo(c.dx - 3, c.dy - 12)
        ..lineTo(c.dx, c.dy - 16)
        ..lineTo(c.dx + 3, c.dy - 12)
        ..lineTo(c.dx + 9, c.dy - 15)
        ..lineTo(c.dx + 7, c.dy - 9)
        ..close(),
      Paint()..color = const Color(0xFFA0693A),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(c.dx, c.dy - 8.5), width: 15, height: 3.5),
          const Radius.circular(2)),
      Paint()..color = const Color(0xFFFFD740),
    );
    // Pièce dessinée sur le sac + reflet
    canvas.drawCircle(Offset(c.dx, c.dy + 3), 6, Paint()..color = const Color(0xFFFFD740));
    canvas.drawCircle(Offset(c.dx, c.dy + 3), 4, Paint()
      ..color = const Color(0xFFE6A800)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    canvas.drawCircle(Offset(c.dx - 7, c.dy - 2), 2, Paint()..color = Colors.white.withOpacity(0.35));
    // Petite étincelle
    if (glow > 0.8) {
      final sp = Paint()
        ..color = Colors.white.withOpacity((glow - 0.8) * 5)
        ..strokeWidth = 1.4;
      final p = Offset(c.dx + 10, c.dy - 12);
      canvas.drawLine(p.translate(-3, 0), p.translate(3, 0), sp);
      canvas.drawLine(p.translate(0, -3), p.translate(0, 3), sp);
    }
  }

  void _paintLogo(Canvas canvas, _Logo lg, Offset c) {
    final glow = 0.5 + 0.5 * sin(time * 5 + lg.x);
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 60, height: 34), const Radius.circular(8));
    final color = neon ? Colors.pinkAccent : Colors.lightBlueAccent;
    canvas.drawRRect(r.inflate(3), Paint()
      ..color = color.withOpacity(0.20 + 0.25 * glow)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawRRect(r, Paint()..color = const Color(0xE61C2230));
    canvas.drawRRect(r, Paint()
      ..color = color.withOpacity(0.6 + 0.4 * glow)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    final img = logoImgs[lg.idx];
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromCenter(center: c, width: 52, height: 26),
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
  }

  void _paintTurbo(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 17, Paint()
      ..color = Colors.greenAccent.withOpacity(neon ? 0.45 : 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(c, 14, Paint()..color = const Color(0xFF1C2230));
    canvas.drawCircle(c, 14, Paint()
      ..color = Colors.greenAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    final img = turboImg;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        Rect.fromCenter(center: c, width: 20, height: 20),
        Paint()..filterQuality = FilterQuality.medium,
      );
    } else {
      canvas.drawCircle(c, 5, Paint()..color = Colors.greenAccent);
    }
  }

  /// Héros choisi, avec écrasement au rebond et flamme du turbo.
  /// [feet] = milieu du bas du héros, en coordonnées écran.
  void _paintHero(Canvas canvas, Offset feet) {
    final sx = 1 + 0.15 * squash;
    final sy = 1 - 0.20 * squash;
    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    canvas.scale(sx, sy);
    if (neon) {
      canvas.drawCircle(const Offset(0, -20), 26, Paint()
        ..color = _heroRed.withOpacity(0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    }
    if (turbo > 0) {
      final flame = Path()
        ..moveTo(-8, 0)
        ..lineTo(0, 18 + (turbo * 37 % 6))
        ..lineTo(8, 0)
        ..close();
      canvas.drawPath(flame, Paint()..color = Colors.orangeAccent);
    }
    _drawHero(canvas, hero, facingRight, time);
    canvas.restore();
    // Shield bubble (blinks during invulnerability)
    final blink = invuln > 0 && (time * 12).floor().isEven;
    if (shieldOn || blink) {
      final center = Offset(feet.dx, feet.dy - 22);
      canvas.drawCircle(center, 30, Paint()
        ..color = Colors.cyanAccent.withOpacity(0.10));
      canvas.drawCircle(center, 30, Paint()
        ..color = Colors.cyanAccent.withOpacity(shieldOn ? 0.85 : 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);
      canvas.drawArc(Rect.fromCircle(center: center, radius: 25), -2.4, 0.9, false, Paint()
        ..color = Colors.white.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(covariant _JumpPainter old) => true;
}
