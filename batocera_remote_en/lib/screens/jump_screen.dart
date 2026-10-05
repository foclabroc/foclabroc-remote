import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
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
const _kRulesV2Key    = 'jump_rules_v2_hide'; // explication des classements masquée
const _kAvatarKey     = 'jump_avatar';     // avatar façon Mii (8 caractères)
const _kHapticLvlKey  = 'jump_haptic_lvl'; // intensité des vibrations : 0 faible, 1 normale, 2 forte
const _kTiltKey       = 'jump_tilt';
const _kGhostKey      = 'jump_ghost';      // fantôme du n°1 affiché (partie du jour)
const _kSensTouchKey  = 'jump_sens_touch'; // sensibilité tactile (0,7 à 1,3)
const _kSensTiltKey   = 'jump_sens_tilt';  // sensibilité inclinaison (0,5 à 2)
const _kThemeKey       = 'jump_theme';
const _kThemeUnlockKey = 'jump_theme_unlocked';
const _kThemeV2Key     = 'jump_theme_v2'; // theme numbers after removing "Red"

// Thèmes visuels (0 = classique, offert). Néon reste acquis si l'ancienne option était activée.
const _themeNames  = ['Classic', 'Neon', 'Pocket', 'Sepia', 'CRT', 'Synthwave', 'Disco', 'Night', 'Negative', 'Matrix', 'Realistic', 'Frozen tower', 'Jungle', 'Beach', 'City at night', 'Canyon'];
const _themePrices = [0, 100, 150, 200, 250, 300, 400, 450, 500, 550, 800, 900, 950, 1000, 1050, 1100];
// Deux couleurs d'aperçu par thème (tuile du menu)
const _themeSwatch = [
  [Color(0xFFE02020), Color(0xFF5C6BC0)],
  [Color(0xFFFF4081), Color(0xFF18FFFF)],
  [Color(0xFF0F380F), Color(0xFF9BBC0F)],
  [Color(0xFF704214), Color(0xFFE8D3A9)],
  [Color(0xFF102027), Color(0xFF80CBC4)],
  [Color(0xFF4A148C), Color(0xFFFF4081)],
  [Color(0xFFFF4081), Color(0xFFFFEB3B)],
  [Color(0xFF0D1B3E), Color(0xFFFFF59D)],
  [Color(0xFF1FDFDF), Color(0xFFFFFFFF)],
  [Color(0xFF000000), Color(0xFF00FF41)],
  [Color(0xFF3A7BD5), Color(0xFF7CB342)],
  [Color(0xFF4A5568), Color(0xFFE3F2FD)],
  [Color(0xFF1B5E20), Color(0xFF9CCC65)], // Jungle
  [Color(0xFFFF7043), Color(0xFF4FC3F7)], // Plage
  [Color(0xFF1A237E), Color(0xFFFF4081)], // Ville la nuit
  [Color(0xFFBF5B2C), Color(0xFFFFCC80)], // Canyon
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
    case 8: // Negative: inverted colours
      return [
        -1, 0, 0, 0, 255,
        0, -1, 0, 0, 255,
        0, 0, -1, 0, 255,
        0, 0, 0, 1, 0,
      ];
    case 9: // Matrix: all phosphor green
      return [
        lr * 0.25, lg * 0.25, lb * 0.25, 0, 0,
        lr * 1.35, lg * 1.35, lb * 1.35, 0, 12,
        lr * 0.3, lg * 0.3, lb * 0.3, 0, 0,
        0, 0, 0, 1, 0,
      ];
  }
  return null;
}
// Jump trails (shop)
const _kTrailKey       = 'jump_trail';
const _kTrailUnlockKey = 'jump_trail_unlocked';
const _trailNames  = ['None', 'Rainbow', 'Sparkles', 'Pixels', 'Flames', 'Bubbles'];
const _trailIcons  = ['🚫', '🌈', '✨', '👾', '🔥', '💧'];
const _trailPrices = [0, 150, 200, 250, 300, 350];
// Dynamic weather (an event around 1,100, 2,100, 3,100… pts)
const _weatherNames   = ['Wind', 'Rain', 'Storm', 'Fog'];
const _weatherIcons   = ['💨', '🌧️', '⛈️', '🌫️'];
const _weatherBanners = ['💨 GUST OF WIND!', '🌧️ RAIN: IT\'S SLIPPERY!', '⛈️ STORM!', '🌫️ FOG'];
const _weatherDur = 18.0; // seconds
const _kCodesUsedKey  = 'jump_codes_used';
const _kCodeMaxUses   = 3; // utilisations max par code

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
const _wheelSpinPrice = 75; // tour supplémentaire payant
// Lots revus pour les prix actuels de la boutique (objets jusqu'à 1 500 pièces).
// bonus : -1 pièces · 0-3 bonus de départ · 4 rejouer offert · 6 objet surprise
const _wheel = <({int coins, int bonus, int w, Color color})>[
  (coins: 20,   bonus: -1, w: 22, color: Color(0xFF5C6BC0)),
  (coins: 0,    bonus: 2,  w: 9,  color: Color(0xFF00ACC1)), // bouclier
  (coins: 50,   bonus: -1, w: 18, color: Color(0xFFEC407A)),
  (coins: 0,    bonus: 3,  w: 8,  color: Color(0xFFEF6C00)), // turbo
  (coins: 100,  bonus: -1, w: 12, color: Color(0xFF7CB342)),
  (coins: 0,    bonus: 1,  w: 6,  color: Color(0xFF26A69A)), // départ 1000
  (coins: 250,  bonus: -1, w: 6,  color: Color(0xFFAB47BC)),
  (coins: 0,    bonus: 4,  w: 7,  color: Color(0xFFE53935)), // rejouer offert
  (coins: 500,  bonus: -1, w: 3,  color: Color(0xFFFFB300)),
  (coins: 0,    bonus: 6,  w: 2,  color: Color(0xFF8E24AA)), // objet surprise
  (coins: 1000, bonus: -1, w: 1,  color: Color(0xFFFFD54F)), // jackpot
];

/// Nom d'un lot de la roue (bonus 0-3, ou 4 = rejouer offert).
String _prizeName(int b) => b == 4 ? 'Continue' : b == 6 ? 'Mystery item' : _bonusNames[b];

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
  'Stomping a bug gives 6 coins',
  'Each logo caught counts double',
  'One free second chance per game (not in the daily run)',
  '+25% XP every game',
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
const _musicNames  = ['Disco Funk', 'Shop', 'Good Morning', '8-bit Retro', 'Mountain', 'Video Game', 'Pixel Fight',
    'RPG Battle', '8-bit Console', 'Byte Blast', 'Game On'];
const _musicPrices = [0, 300, 500, 600, 700, 800, 1000, 1100, 1200, 1300, 1500];
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

/// Player progress (0-100%), shown on the leaderboard:
/// 40% shop (heroes, themes, music, trails) + 30% albums (first 4) + 30% trophies.
Future<int> _progressPct() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    int owned(String key, int max) {
      final s = <int>{0};
      for (final v in prefs.getStringList(key) ?? const <String>[]) {
        final i = int.tryParse(v);
        if (i != null && i >= 0 && i < max) s.add(i);
      }
      return s.length;
    }
    final shopTotal = _heroCount + _themeNames.length + _musicNames.length + _trailNames.length;
    final shopHave = owned(_kUnlockedKey, _heroCount) + owned(_kThemeUnlockKey, _themeNames.length) +
        owned(_kMusicUnlockKey, _musicNames.length) + owned(_kTrailUnlockKey, _trailNames.length);
    // Albums (30%): 4 albums × 16 logos; current album counted logo by logo
    const albumsGoal = 4;
    final perAlbum = _logoSets.first.length;
    final album = prefs.getInt(_kAlbumKey) ?? 0;
    var albumUnits = min(album, albumsGoal) * perAlbum;
    if (album < albumsGoal) {
      final goal = 3 + album ~/ _logoSets.length;
      albumUnits += (prefs.getStringList(_kCollectionKey) ?? const <String>[])
          .where((c) => (int.tryParse(c) ?? 0) >= goal)
          .length
          .clamp(0, perAlbum);
    }
    // Trophées (30 %)
    final ids = {for (final x in _trophies) x.id};
    final trophiesHave = (prefs.getStringList(_kTrophyKey) ?? const <String>[]).where(ids.contains).length;
    final pct = 40 * shopHave / shopTotal + 30 * albumUnits / (albumsGoal * perAlbum) + 30 * trophiesHave / _trophies.length;
    return pct.round().clamp(0, 100);
  } catch (_) {
    return 0;
  }
}


/// Bonus versé quand un album est complété.
// ─── Trophées (succès permanents) ────────────────────────────────────────────
const _kTrophyKey = 'jump_trophies';

class _Trophy {
  final String id;
  final int tier;        // 0 bronze, 1 argent, 2 or
  final IconData icon;
  final String key;      // clé de la photo de progression (_trophySnapshot)
  final int goal;
  final String name, desc;
  const _Trophy(this.id, this.tier, this.icon, this.key, this.goal, this.name, this.desc);
}

const _tierColors = [Color(0xFFCD7F32), Color(0xFFCFD8DC), Color(0xFFFFD54F)];
const _tierNames = ['Bronze', 'Silver', 'Gold'];
const _tierReward = [25, 75, 200];

final _trophies = <_Trophy>[
  _Trophy('g10', 0, Icons.sports_esports_rounded, 'games', 10, 'First steps', 'Play 10 games'),
  _Trophy('g100', 1, Icons.sports_esports_rounded, 'games', 100, 'Regular', 'Play 100 games'),
  _Trophy('g500', 2, Icons.sports_esports_rounded, 'games', 500, 'Addicted', 'Play 500 games'),
  _Trophy('g1000', 2, Icons.sports_esports_rounded, 'games', 1000, 'Living legend', 'Play 1,000 games'),
  _Trophy('b1000', 0, Icons.emoji_events_rounded, 'best', 1000, 'Lift-off', 'Score 1,000 pts'),
  _Trophy('b3000', 1, Icons.emoji_events_rounded, 'best', 3000, 'High flyer', 'Score 3,000 pts'),
  _Trophy('b6000', 2, Icons.emoji_events_rounded, 'best', 6000, 'Among the stars', 'Score 6,000 pts'),
  _Trophy('b10000', 2, Icons.emoji_events_rounded, 'best', 10000, 'Beyond space', 'Score 10,000 pts'),
  _Trophy('p50k', 0, Icons.landscape_rounded, 'pts', 50000, 'Climber', '50,000 total pts'),
  _Trophy('p500k', 1, Icons.landscape_rounded, 'pts', 500000, 'Mountaineer', '500,000 total pts'),
  _Trophy('p2m', 2, Icons.landscape_rounded, 'pts', 2000000, 'Conqueror', '2,000,000 total pts'),
  _Trophy('p10m', 2, Icons.landscape_rounded, 'pts', 10000000, 'Titan', '10,000,000 total pts'),
  _Trophy('s100', 0, Icons.bug_report_rounded, 'stomps', 100, 'Bug hunter', 'Stomp 100 bugs'),
  _Trophy('s1000', 1, Icons.bug_report_rounded, 'stomps', 1000, 'Debugger', 'Stomp 1,000 bugs'),
  _Trophy('s5000', 2, Icons.bug_report_rounded, 'stomps', 5000, 'Exterminator', 'Stomp 5,000 bugs'),
  _Trophy('s20000', 2, Icons.bug_report_rounded, 'stomps', 20000, 'Bug bane', 'Stomp 20,000 bugs'),
  _Trophy('j1k', 0, Icons.keyboard_double_arrow_up_rounded, 'jumps', 1000, 'Jumper', 'Make 1,000 jumps'),
  _Trophy('j10k', 1, Icons.keyboard_double_arrow_up_rounded, 'jumps', 10000, 'Kangaroo', 'Make 10,000 jumps'),
  _Trophy('j100k', 2, Icons.keyboard_double_arrow_up_rounded, 'jumps', 100000, 'Human spring', 'Make 100,000 jumps'),
  _Trophy('t25', 0, Icons.rocket_launch_rounded, 'turbos', 25, 'Pedal to the metal', 'Use 25 turbos'),
  _Trophy('t250', 1, Icons.rocket_launch_rounded, 'turbos', 250, 'Supersonic', 'Use 250 turbos'),
  _Trophy('t1000', 2, Icons.rocket_launch_rounded, 'turbos', 1000, 'Human rocket', 'Use 1,000 turbos'),
  _Trophy('c10', 0, Icons.local_fire_department_rounded, 'combo', 10, 'Chain', 'Combo of 10 jumps'),
  _Trophy('c25', 1, Icons.local_fire_department_rounded, 'combo', 25, 'On fire', 'Combo of 25 jumps'),
  _Trophy('c50', 2, Icons.local_fire_department_rounded, 'combo', 50, 'Unstoppable', 'Combo of 50 jumps'),
  _Trophy('o1k', 0, Icons.monetization_on_rounded, 'coins', 1000, 'Piggy bank', 'Earn 1,000 coins'),
  _Trophy('o10k', 1, Icons.monetization_on_rounded, 'coins', 10000, 'Vault', 'Earn 10,000 coins'),
  _Trophy('o50k', 2, Icons.monetization_on_rounded, 'coins', 50000, 'Royal treasure', 'Earn 50,000 coins'),
  _Trophy('o200k', 2, Icons.monetization_on_rounded, 'coins', 200000, 'Fortune', 'Earn 200,000 coins'),
  _Trophy('bag20', 0, Icons.savings_rounded, 'bags', 20, 'Gatherer', 'Collect 20 bags'),
  _Trophy('bag200', 1, Icons.savings_rounded, 'bags', 200, 'Banker', 'Collect 200 bags'),
  _Trophy('bag1000', 2, Icons.savings_rounded, 'bags', 1000, 'Tycoon', 'Collect 1,000 bags'),
  _Trophy('l50', 0, Icons.collections_bookmark_rounded, 'logos', 50, 'Collector', 'Catch 50 logos'),
  _Trophy('l500', 1, Icons.collections_bookmark_rounded, 'logos', 500, 'Archivist', 'Catch 500 logos'),
  _Trophy('l2000', 2, Icons.collections_bookmark_rounded, 'logos', 2000, 'Curator', 'Catch 2,000 logos'),
  _Trophy('h1', 0, Icons.timer_rounded, 'time', 3600, 'One hour', 'Play 1 h in total'),
  _Trophy('h10', 1, Icons.timer_rounded, 'time', 36000, 'Enthusiast', 'Play 10 h in total'),
  _Trophy('h50', 2, Icons.timer_rounded, 'time', 180000, 'Jump legend', 'Play 50 h in total'),
  _Trophy('lv10', 0, Icons.military_tech_rounded, 'level', 10, 'Promoted', 'Reach level 10'),
  _Trophy('lv25', 1, Icons.military_tech_rounded, 'level', 25, 'Veteran', 'Reach level 25'),
  _Trophy('lv50', 2, Icons.military_tech_rounded, 'level', 50, 'Jump master', 'Reach level 50'),
  _Trophy('lv75', 2, Icons.military_tech_rounded, 'level', 75, 'Demigod', 'Reach level 75'),
  _Trophy('lv99', 2, Icons.military_tech_rounded, 'level', 99, 'Max level', 'Reach level 99'),
  _Trophy('a1', 0, Icons.auto_stories_rounded, 'album', 1, 'First album', 'Complete 1 album'),
  _Trophy('a4', 2, Icons.auto_stories_rounded, 'album', 4, 'Museum', 'Complete 4 albums'),
  _Trophy('a8', 2, Icons.auto_stories_rounded, 'album', 8, 'Encyclopedia', 'Complete 8 albums'),
  _Trophy('he5', 0, Icons.person_rounded, 'heroes', 5, 'Small team', 'Unlock 5 heroes'),
  _Trophy('he10', 1, Icons.person_rounded, 'heroes', 10, 'Big family', 'Unlock 10 heroes'),
  _Trophy('heAll', 2, Icons.person_rounded, 'heroes', _heroCount, 'Full squad', 'Unlock every hero'),
  _Trophy('thAll', 1, Icons.palette_rounded, 'themes', _themeNames.length, 'Decorator', 'Unlock every theme'),
  _Trophy('muAll', 1, Icons.music_note_rounded, 'musics', _musicNames.length, 'Music lover', 'Unlock every music'),
  _Trophy('trAll', 1, Icons.auto_awesome_rounded, 'trails', _trailNames.length, 'Comet', 'Unlock every trail'),
  _Trophy('se1', 0, Icons.workspace_premium_rounded, 'series', 1, 'Challenge accepted', 'Complete 1 challenge series'),
  _Trophy('se5', 1, Icons.workspace_premium_rounded, 'series', 5, 'Persistent', 'Complete 5 challenge series'),
  _Trophy('se10', 2, Icons.workspace_premium_rounded, 'series', 10, 'Tireless', 'Complete 10 challenge series'),
  _Trophy('se20', 2, Icons.workspace_premium_rounded, 'series', 20, 'Challenge master', 'Complete 20 challenge series'),
  _Trophy('st3', 0, Icons.event_repeat_rounded, 'streak_best', 3, 'Loyal', 'Play 3 days in a row'),
  _Trophy('st7', 1, Icons.event_repeat_rounded, 'streak_best', 7, 'One week', 'Play 7 days in a row'),
  _Trophy('st30', 2, Icons.event_repeat_rounded, 'streak_best', 30, 'Inseparable', 'Play 30 days in a row'),
  _Trophy('d10', 0, Icons.today_rounded, 'dailies', 10, 'Daily player', 'Play 10 daily runs'),
  _Trophy('d50', 1, Icons.today_rounded, 'dailies', 50, 'Ritual', 'Play 50 daily runs'),
  _Trophy('d100', 2, Icons.today_rounded, 'dailies', 100, 'Devoted', 'Play 100 daily runs'),
  _Trophy('top3', 1, Icons.leaderboard_rounded, 'top3', 1, 'Podium', 'Finish top 3 in a daily challenge'),
  _Trophy('daily1', 2, Icons.leaderboard_rounded, 'daily1', 1, 'Daily champion', 'Be 1st in a daily challenge'),
  _Trophy('chat1', 0, Icons.chat_bubble_rounded, 'chat', 1, 'Chatty', 'Post in the chat'),
  _Trophy('fall100', 0, Icons.south_rounded, 'falls', 100, 'Gravity', 'Fall 100 times'),
  _Trophy('cont10', 0, Icons.replay_rounded, 'cont', 10, 'Never give up', 'Use 10 continues'),
  _Trophy('bd50', 0, Icons.pest_control_rounded, 'bugdeaths', 50, 'Bitten', 'Get caught by bugs 50 times'),
];

/// Progression actuelle du joueur (stats à vie + collection + niveau…).
Future<Map<String, int>> _trophySnapshot(SharedPreferences prefs) async {
  final s = <String, int>{};
  try {
    final st = jsonDecode(prefs.getString(_kStatsKey) ?? '{}') as Map;
    st.forEach((k, v) {
      if (v is num) s['$k'] = v.toInt();
    });
  } catch (_) {}
  s['best'] = prefs.getInt(_kBestScoreKey) ?? 0;
  s['level'] = _levelFor(await _readXp(prefs));
  s['album'] = prefs.getInt(_kAlbumKey) ?? 0;
  s['heroes'] = _ownedCount(prefs, _kUnlockedKey, _heroCount);
  s['themes'] = _ownedCount(prefs, _kThemeUnlockKey, _themeNames.length);
  s['musics'] = _ownedCount(prefs, _kMusicUnlockKey, _musicNames.length);
  s['trails'] = _ownedCount(prefs, _kTrailUnlockKey, _trailNames.length);
  s['series'] = prefs.getInt(_kChallengeLvlKey) ?? 0;
  return s;
}

/// Débloque et enregistre les trophées atteints ; renvoie les nouveaux.
Future<List<_Trophy>> _unlockTrophies({int score = 0}) async {
  final prefs = await SharedPreferences.getInstance();
  final have = (prefs.getStringList(_kTrophyKey) ?? const <String>[]).toSet();
  final s = await _trophySnapshot(prefs);
  s['best'] = max(s['best'] ?? 0, score);
  final news = [for (final t in _trophies) if (!have.contains(t.id) && (s[t.key] ?? 0) >= t.goal) t];
  if (news.isNotEmpty) await prefs.setStringList(_kTrophyKey, [...have, ...news.map((t) => t.id)]);
  return news;
}

/// Ajoute à une statistique à vie (ou garde le maximum avec atLeast).
Future<void> _bumpStat(String k, {int by = 1, int? atLeast}) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic> st = {};
    try {
      st = Map<String, dynamic>.from(jsonDecode(prefs.getString(_kStatsKey) ?? '{}') as Map);
    } catch (_) {}
    final cur = (st[k] as num?)?.toInt() ?? 0;
    st[k] = atLeast != null ? max(cur, atLeast) : cur + by;
    await prefs.setString(_kStatsKey, jsonEncode(st));
  } catch (_) {}
}

// ─── Niveau du joueur (XP) ───────────────────────────────────────────────────
const _kXpKey = 'jump_xp';
const _kMaxLevel = 99;

/// XP totale pour atteindre le niveau l : niv. 2 = 100, niv. 10 = 4 500, niv. 50 = 122 500.
int _xpForLevel(int l) => 50 * l * (l - 1);

int _levelFor(int xp) {
  var l = 1;
  while (l < _kMaxLevel && xp >= _xpForLevel(l + 1)) {
    l++;
  }
  return l;
}

/// XP d'une partie : 1 par 10 points, +10 par partie, +25 par défi réussi, +30 partie du jour.
int _runXp(int score, int challenges, bool daily) => score ~/ 10 + 10 + challenges * 25 + (daily ? 30 : 0);

/// Pièces offertes en atteignant le niveau l.
int _levelReward(int l) => 20 * l;

/// Rang par tranche de 10 niveaux.
const _levelRanks = <(String, Color)>[
  ('Rookie', Color(0xFF9E9E9E)), ('Bronze', Color(0xFFCD7F32)), ('Silver', Color(0xFFCFD8DC)), ('Gold', Color(0xFFFFD54F)), ('Platinum', Color(0xFF80DEEA)), ('Diamond', Color(0xFF64B5F6)), ('Master', Color(0xFFCE93D8)), ('Legend', Color(0xFFFF5252)),
];
(String, Color) _rankFor(int l) => _levelRanks[min(l ~/ 10, _levelRanks.length - 1)];

/// XP enregistrée ; la première fois, calculée d'après les stats à vie (les anciens joueurs ne repartent pas de 0).
Future<int> _readXp(SharedPreferences prefs) async {
  final x = prefs.getInt(_kXpKey);
  if (x != null) return x;
  var xp = 0;
  try {
    final st = jsonDecode(prefs.getString(_kStatsKey) ?? '{}') as Map;
    xp = ((st['pts'] as num?)?.toInt() ?? 0) ~/ 10 + ((st['games'] as num?)?.toInt() ?? 0) * 10;
  } catch (_) {}
  await prefs.setInt(_kXpKey, xp);
  return xp;
}

int _ownedCount(SharedPreferences prefs, String key, int max) {
  final s = <int>{0};
  for (final v in prefs.getStringList(key) ?? const <String>[]) {
    final i = int.tryParse(v);
    if (i != null && i >= 0 && i < max) s.add(i);
  }
  return s.length;
}

/// Statistiques visibles par les autres joueurs (fiche joueur du classement).
Future<Map<String, int>> _publicStats() async {
  final prefs = await SharedPreferences.getInstance();
  final out = <String, int>{};
  try {
    final st = jsonDecode(prefs.getString(_kStatsKey) ?? '{}') as Map;
    for (final k in const ['games', 'pts', 'time', 'jumps', 'combo', 'coins', 'bags', 'stomps', 'turbos',
        'logos', 'cont', 'falls', 'bugdeaths']) {
      final v = st[k];
      if (v is num) out[k] = v.toInt();
    }
  } catch (_) {}
  out['best'] = prefs.getInt(_kBestScoreKey) ?? 0;
  out['album'] = prefs.getInt(_kAlbumKey) ?? 0;
  out['heroes'] = _ownedCount(prefs, _kUnlockedKey, _heroCount);
  out['heroes_n'] = _heroCount;
  out['themes'] = _ownedCount(prefs, _kThemeUnlockKey, _themeNames.length);
  out['themes_n'] = _themeNames.length;
  out['musics'] = _ownedCount(prefs, _kMusicUnlockKey, _musicNames.length);
  out['musics_n'] = _musicNames.length;
  out['trails'] = _ownedCount(prefs, _kTrailUnlockKey, _trailNames.length);
  out['trails_n'] = _trailNames.length;
  out['trophies'] = (prefs.getStringList(_kTrophyKey) ?? const <String>[]).length;
  out['trophies_n'] = _trophies.length;
  final xp = await _readXp(prefs);
  out['xp'] = xp;
  out['level'] = _levelFor(xp);
  return out;
}

/// Pièces, avancement et stats du joueur, visibles dans le classement.
Future<void> _syncProfile(int coins) async {
  await Leaderboard.setProfile(coins, await _progressPct());
  await Leaderboard.setStats(await _publicStats());
  final av = (await SharedPreferences.getInstance()).getString(_kAvatarKey);
  if (_avParse(av) != null) await Leaderboard.setAvatar(av!);
}

int _albumBonus(int album) => 500; // cadeau fixe par album complété

List<int> _readCollection(SharedPreferences prefs) {
  _album = prefs.getInt(_kAlbumKey) ?? 0;
  final raw = prefs.getStringList(_kCollectionKey) ?? const <String>[];
  return List<int>.generate(_logoAssets.length,
      (i) => i < raw.length ? (int.tryParse(raw[i]) ?? 0) : 0);
}

// ─── Texts ───────────────────────────────────────────────────────────────────

const _heroNames  = ['Robot', 'Joystick', 'Cabinet', 'Token', 'Cartridge', 'Floppy', 'CD', 'Cassette', 'TV', 'Mouse', 'Cat', 'Rocket', 'Gamepad', 'Handheld', 'Ghost', 'Headset'];
const _heroPrices = [0, 50, 100, 150, 200, 250, 300, 350, 400, 450, 500, 550, 600, 650, 700, 800];
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

/// Vibration de force [level] (0 à 3) décalée selon l'intensité choisie (0 faible, 1 normale, 2 forte).
void _hapticAt(int level, int strength) {
  switch ((level + strength - 1).clamp(0, 3)) {
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
  int _lbTab = 0;         // 0 aujourd'hui, 1 tous temps, 2 semaine, 3 chat
  int _xp = 0;            // XP du joueur (niveau)
  int _trophyCount = 0;   // trophées débloqués
  // Chat
  List<LbChatMsg> _chat = [];
  bool _chatLoading = false, _chatFailed = false, _chatSending = false, _chatBusy = false;
  bool _chatNew = false;  // pastille : message pas encore vu
  bool _chatMention = false; // quelqu'un a écrit @mon_pseudo
  Timer? _chatTimer;
  final _chatCtrl = TextEditingController();
  LbBoard? _lbBoard;
  List<LbEntry> _lbMore = [];        // pages suivantes (« Voir plus »), jusqu'à 500
  bool _lbMoreLoading = false, _lbNoMore = false;
  final _lbMeKey = GlobalKey();       // ma ligne (« Ma position »)
  bool _lbLoading = false, _lbFailed = false;
  String? _lbMyName;
  String _lbPid = '';
  int _hero = 0;
  int _coins = 0;
  Set<int> _unlocked = {0};
  Set<String> _completed = {};
  int _challengeLevel = 0;
  int _theme = 0;
  int _trail = 0;
  Set<int> _trailUnlocked = {0};
  Set<int> _themeUnlocked = {0};
  final Set<int> _bonusSel = {};
  Set<int> _freeBonus = {};   // bonus offerts par la roue (prochaine partie)
  bool _wheelReady = false;   // tour de roue disponible aujourd'hui
  Map<String, dynamic> _stats = {};
  bool _freeContinue = false; // « rejouer » offert par la roue (prochaine partie)
  bool _haptics = true;
  String? _avatar;        // avatar façon Mii (null = héros)
  bool _lastDaily = false; // dernière partie lancée = défi du jour (hors record Solo)
  int _hapticLvl = 1;     // intensité des vibrations (0 faible, 1 normale, 2 forte)
  Future<List<LbOvertake>>? _overtakesF; // « record battu » : joueurs qui m'ont dépassé
  bool _afterSplashDone = false;
  bool _tilt = false;
  bool _ghostOn = true;
  double _sensTouch = 1.0, _sensTilt = 1.0;
  bool _msgOpen = false;  // feuille Messages (chat) ouverte
  int _questTab = 0;      // Quêtes : 0 défis, 1 trophées, 2 collection
  Set<String> _trHave = {};
  Map<String, int> _trSnap = {};
  bool _splashOn = true, _splashGone = false, _wheelAtStart = false;
  List<LbEntry> _podium = const []; // 3 meilleurs scores (écran de démarrage)
  int _musicTrack = 0;
  Set<int> _musicUnlocked = {0};
  List<int> _collection = List<int>.filled(_logoAssets.length, 0);
  bool _loading = true;

  @override
  void dispose() {
    QuizAudio.musicStop(); // retour à la liste des mini-jeux
    _idle.dispose();
    _rev.dispose();
    _chatStop();
    _chatCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Suggestions @pseudo mises à jour pendant la saisie
    _chatCtrl.addListener(() {
      if (mounted && _sheetCtx != null && _msgOpen) setState(() {});
    });
    // Musique dès l'ouverture du jeu (accueil compris), une fois le morceau choisi connu
    _load().then((_) => QuizAudio.loadPrefs()).then((_) {
      if (!mounted) return;
      setState(() {});
      QuizAudio.musicStart(_musicTrack);
      _chatCheckNew();
      // Tour gratuit du jour pas encore joué : la roue s'ouvrira après l'écran de démarrage
      _wheelAtStart = _wheelReady;
      if (!_splashOn) _afterSplash();
      _refreshSolo();
    });
    _overtakesF = Leaderboard.overtakes();
    // Écran de démarrage : reste affiché jusqu'à ce que le joueur touche l'écran
    _loadPodium();
  }

  /// Podium de l'écran de démarrage : 3 meilleurs scores de tous les temps.
  Future<void> _loadPodium() async {
    if (!Leaderboard.configured) return;
    final b = await Leaderboard.fetch('all', lbAllDay);
    if (b == null || !mounted || !_splashOn) return;
    setState(() => _podium = b.top.where((e) => e.score > 0).take(3).toList());
  }

  void _endSplash() {
    if (!mounted || !_splashOn || _loading) return; // pas avant la fin du chargement
    setState(() => _splashOn = false);
    _afterSplash();
  }

  /// Record Solo (parties normales) et rang, tels que connus du serveur.
  Future<void> _refreshSolo() async {
    final r = await Leaderboard.myRank('all', lbAllDay);
    final best = r?.score;
    if (r == null || best == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (best != _bestScore) await prefs.setInt(_kBestScoreKey, best);
    if (!mounted) return;
    setState(() {
      _bestScore = best;
      if (r.rank != null) _worldRank = '#${r.rank} / ${r.total}';
    });
  }

  /// Explication des nouveaux classements (jusqu'à « Ne plus afficher »).
  Future<void> _maybeShowRules() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kRulesV2Key) ?? false) return;
    if (!mounted) return;
    var hide = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.leaderboard_rounded, color: Colors.amberAccent),
          SizedBox(width: 8),
          Expanded(child: Text('New leaderboards')),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('🥇 Daily challenge: the top 3 win a gold, silver or bronze medal (given at midnight).', style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.35)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('📅 Weekly challenge: ranked by medals won this week. Every Monday, cups 🏆 for the top 3 and a participation medal for the other players.', style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.35)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('🏆 Overall challenge: all your awards since the start.', style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.35)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('👤 Solo: your best score in normal games (the daily challenge no longer counts).', style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.35)),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => setD(() => hide = !hide),
              child: Row(children: [
                Checkbox(value: hide, onChanged: (v) => setD(() => hide = v ?? false)),
                Text("Don't show again", style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          ]),
        ),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: Text('Got it'))],
      )),
    );
    if (hide) await prefs.setBool(_kRulesV2Key, true);
  }

  /// Après l'écran de démarrage : « record battu » s'il y a lieu, puis la roue.
  Future<void> _afterSplash() async {
    if (_afterSplashDone) return;
    _afterSplashDone = true;
    await Future.delayed(const Duration(milliseconds: 400));
    if (mounted && ModalRoute.of(context)?.isCurrent == true) await _maybeShowRules();
    final list = await (_overtakesF ?? Future.value(const <LbOvertake>[]))
        .timeout(const Duration(seconds: 4), onTimeout: () => const <LbOvertake>[]);
    if (list.isNotEmpty && mounted && ModalRoute.of(context)?.isCurrent == true) {
      await Future.delayed(const Duration(milliseconds: 450));
      if (mounted) await _showOvertakes(list);
    }
    _wheelAfterSplash();
  }

  Future<void> _showOvertakes(List<LbOvertake> list) async {
    if (_haptics) HapticFeedback.mediumImpact();
    QuizAudio.sfx('powerup');
    final shown = list.take(5).toList();
    final see = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 24),
          SizedBox(width: 8),
          Expanded(child: Text('Record beaten!')),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('They overtook you on the Solo leaderboard since your last visit:',
              style: TextStyle(color: Colors.white60, fontSize: 13)),
          const SizedBox(height: 10),
          for (final o in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                const Icon(Icons.arrow_upward_rounded, color: Colors.redAccent, size: 18),
                const SizedBox(width: 6),
                Expanded(child: Text.rich(TextSpan(children: [
                  TextSpan(text: o.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  const TextSpan(text: ' passed you', style: TextStyle(color: Colors.white70)),
                ]), overflow: TextOverflow.ellipsis)),
                Text('${_fmtNum(o.score)} pts',
                    style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w800)),
              ]),
            ),
          if (list.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('and ${list.length - shown.length} more players',
                  style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('OK')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('See leaderboard')),
        ],
      ),
    );
    if (see == true && mounted) {
      setState(() => _lbTab = 1);
      _openLeaderboard();
    }
  }

  void _wheelAfterSplash() {
    if (!_wheelAtStart) return;
    _wheelAtStart = false;
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted && _wheelReady && ModalRoute.of(context)?.isCurrent == true) _openWheel();
    });
  }

  /// Old numbering (with "Red" as 6) → new one; a bought Red is refunded (350 coins).
  Future<void> _migrateThemes(SharedPreferences prefs) async {
    if (prefs.getBool(_kThemeV2Key) ?? false) return;
    int? map(int i) => i < 6 ? i : (i == 6 ? null : i - 1);
    final old = prefs.getStringList(_kThemeUnlockKey);
    if (old != null) {
      final out = <String>[];
      var refund = false;
      for (final s in old) {
        final i = int.tryParse(s);
        if (i == null) continue;
        final m = map(i);
        if (m == null) {
          refund = true;
        } else {
          out.add('$m');
        }
      }
      await prefs.setStringList(_kThemeUnlockKey, out);
      if (refund) await prefs.setInt(_kCoinsKey, (prefs.getInt(_kCoinsKey) ?? 0) + 350);
    }
    final t = prefs.getInt(_kThemeKey);
    if (t != null) await prefs.setInt(_kThemeKey, map(t) ?? 0);
    await prefs.setBool(_kThemeV2Key, true);
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    await _migrateThemes(prefs);
    _xp = await _readXp(prefs);
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
      _trailUnlocked = {0};
      for (final s in prefs.getStringList(_kTrailUnlockKey) ?? const <String>[]) {
        final t = int.tryParse(s);
        if (t != null && t >= 0 && t < _trailNames.length) _trailUnlocked.add(t);
      }
      _trail = (prefs.getInt(_kTrailKey) ?? 0).clamp(0, _trailNames.length - 1);
      if (!_trailUnlocked.contains(_trail)) _trail = 0;
      _haptics   = prefs.getBool(_kHapticsKey) ?? true;
      _hapticLvl = (prefs.getInt(_kHapticLvlKey) ?? 1).clamp(0, 2);
      _avatar    = _avParse(prefs.getString(_kAvatarKey)) == null ? null : prefs.getString(_kAvatarKey);
      _tilt      = prefs.getBool(_kTiltKey) ?? false;
      _ghostOn   = prefs.getBool(_kGhostKey) ?? true;
      _sensTouch = (prefs.getDouble(_kSensTouchKey) ?? 1.0).clamp(0.7, 1.3).toDouble();
      _sensTilt  = (prefs.getDouble(_kSensTiltKey) ?? 1.0).clamp(0.5, 2.0).toDouble();
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
      _trophyCount = (prefs.getStringList(_kTrophyKey) ?? const <String>[]).length;
      _loading   = false;
    });
    _homeTrophies();
  }

  /// Trophées gagnés hors partie (achats, chat…) ; la 1re fois : rattrapage sans pièces.
  bool _trBusy = false;
  Future<void> _homeTrophies() async {
    if (_trBusy) return;
    _trBusy = true;
    try {
      await _homeTrophiesRun();
    } finally {
      _trBusy = false;
    }
  }

  Future<void> _homeTrophiesRun() async {
    final prefs = await SharedPreferences.getInstance();
    final first = prefs.getStringList(_kTrophyKey) == null;
    final news = await _unlockTrophies(score: _bestScore);
    if (!mounted) return;
    final count = (prefs.getStringList(_kTrophyKey) ?? const <String>[]).length;
    if (news.isEmpty) {
      if (count != _trophyCount) setState(() => _trophyCount = count);
      return;
    }
    if (first) {
      setState(() => _trophyCount = count);
      _snack('🏆 ${news.length} trophies unlocked from your progress', ok: true);
      return;
    }
    final gain = news.fold<int>(0, (a, x) => a + _tierReward[x.tier]);
    _coins += gain;
    await prefs.setInt(_kCoinsKey, _coins);
    if (!mounted) return;
    setState(() => _trophyCount = count);
    QuizAudio.win();
    _snack(news.length == 1 ? '🏆 Trophy "${news.first.name}" +$gain' : '🏆 ${news.length} trophies unlocked +$gain', ok: true);
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
    if (score <= _bestScore || _lastDaily) {
      // No record (so no name entry): ask for the online name once
      await _askPseudoOnce();
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBestScoreKey, score);
    if (!mounted) return;
    setState(() => _bestScore = score);
    // Pseudo déjà choisi : record enregistré à ce nom, sans redemander
    final pseudo = await Leaderboard.name();
    if (pseudo != null && !pseudo.startsWith('Joueur-') && !pseudo.startsWith('Player-')) {
      await prefs.setString(_kBestNameKey, pseudo);
      if (!mounted) return;
      setState(() => _bestName = pseudo);
      _snack('🏆 New record: ${_fmtNum(score)} pts!', ok: true);
      return;
    }
    if (!mounted) return;
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
    _homeTrophies();
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
          // Name always shown (greyed out while locked)
          Text(i < 0 ? 'Mute' : _musicNames[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: locked ? Colors.white38 : selected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
          if (locked)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _CoinIcon(size: 11),
              const SizedBox(width: 3),
              Text('${_musicPrices[i]}',
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w700)),
            ])
          else
            const SizedBox(height: 14), // same height as the price row
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
    _homeTrophies();
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
    // Libéré après l'animation de fermeture (sinon le champ l'utilise encore)
    Future.delayed(const Duration(milliseconds: 600), ctrl.dispose);
    if (code == null || code.trim().isEmpty || !mounted) return;
    (String, bool) msg;
    try {
      msg = await _applyCode(code);
    } catch (_) {
      msg = ('Error, try again', false);
    }
    if (!mounted) return;
    if (msg.$2) {
      QuizAudio.sfx('powerup');
      await _load();
      if (!mounted) return;
      _rev.value++; // feuilles ouvertes (pièces) rafraîchies
    }
    // Résultat dans une fenêtre : toujours visible, même par-dessus une feuille
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        content: Row(children: [
          Icon(msg.$2 ? Icons.check_circle_rounded : Icons.error_outline_rounded,
              color: msg.$2 ? Colors.greenAccent : Colors.redAccent, size: 28),
          const SizedBox(width: 12),
          Expanded(child: Text(msg.$1,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
        ]),
        actions: [ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  /// Applique un code ; renvoie (message, réussi).
  Future<(String, bool)> _applyCode(String raw) async {
    final code = raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    final hash = _codeHash(code);
    final effect = _cheatCodes[hash];
    if (effect == null) return ('Invalid code', false);
    final prefs = await SharedPreferences.getInstance();
    // Chaque code est utilisable 3 fois (une entrée par utilisation)
    final used = List<String>.of(prefs.getStringList(_kCodesUsedKey) ?? const <String>[]);
    final uses = used.where((h) => h == hash).length;
    if (uses >= _kCodeMaxUses) return ('Code already used 3 times', false);
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
    await prefs.setStringList(_kCodesUsedKey, used);
    return ('$msg (${uses + 1}/$_kCodeMaxUses)', true);
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
    // Online identity (name + leaderboard scores): travels with the save
    final dev = prefs.getString(kLbDeviceKey);
    if (dev != null) data[kLbDeviceKey] = {'t': 's', 'v': dev};
    return data;
  }

  Future<void> _saveProgress() async {
    if (Leaderboard.configured) await Leaderboard.deviceId(); // creates the identity if needed
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
        content: Text('Save from $when.\nYour current progress will be replaced, along with your online name and scores.', style: const TextStyle(color: Colors.white70, height: 1.4)),
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
      if (e.key == kLbDeviceKey) {
        if (v is String) await Leaderboard.adoptDevice(v); // become the same online player again
        continue;
      }
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
    String? surprise;
    if (s.bonus == 6) {
      // Objet surprise : un héros, thème, musique ou traînée encore verrouillé (sinon 1 000 pièces)
      final rng = Random();
      final c = <(int, int)>[
        for (int i = 0; i < _heroCount; i++) if (!_unlocked.contains(i)) (0, i),
        for (int i = 0; i < _themeNames.length; i++) if (!_themeUnlocked.contains(i)) (1, i),
        for (int i = 0; i < _musicNames.length; i++) if (!_musicUnlocked.contains(i)) (2, i),
        for (int i = 0; i < _trailNames.length; i++) if (!_trailUnlocked.contains(i)) (3, i),
      ];
      if (c.isEmpty) {
        _coins += 1000;
        await prefs.setInt(_kCoinsKey, _coins);
      } else {
        final (kind, i) = c[rng.nextInt(c.length)];
        List<String> ids(Set<int> x) => x.map((e) => '$e').toList();
        switch (kind) {
          case 0:
            _unlocked.add(i);
            await prefs.setStringList(_kUnlockedKey, ids(_unlocked));
            surprise = 'Hero ${_heroNames[i]}';
            break;
          case 1:
            _themeUnlocked.add(i);
            await prefs.setStringList(_kThemeUnlockKey, ids(_themeUnlocked));
            surprise = 'Theme ${_themeNames[i]}';
            break;
          case 2:
            _musicUnlocked.add(i);
            await prefs.setStringList(_kMusicUnlockKey, ids(_musicUnlocked));
            surprise = 'Music ${_musicNames[i]}';
            break;
          default:
            _trailUnlocked.add(i);
            await prefs.setStringList(_kTrailUnlockKey, ids(_trailUnlocked));
            surprise = 'Trail ${_trailNames[i]}';
        }
        _homeTrophies();
      }
    } else if (s.bonus == 4) {
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
    _snack(s.bonus == 6
        ? (surprise != null ? 'Wheel: 🎁 $surprise unlocked!' : 'Wheel: everything is unlocked already, +1,000 coins!')
        : s.coins > 0 ? 'Wheel: +${_fmtNum(s.coins)} coins!' : 'Wheel: free ${_prizeName(s.bonus)} for your next game!', ok: true);
  }

  Future<void> _selectTrail(int i) async {
    if (!_trailUnlocked.contains(i)) {
      await _tryUnlockTrail(i);
      if (!_trailUnlocked.contains(i)) return;
    }
    setState(() => _trail = i);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTrailKey, i);
  }

  Future<void> _tryUnlockTrail(int i) async {
    final price = _trailPrices[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Text('Unlock ${_trailNames[i]} ?'),
        content: Row(children: [
          Text(_trailIcons[i], style: const TextStyle(fontSize: 40)),
          const SizedBox(width: 16),
          Expanded(child: Text('Price : $price coins\nYou have $_coins.${_coins < price ? '\nYou need ${price - _coins} more coins.' : ''}',
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
      _trailUnlocked.add(i);
      _trail = i;
    });
    await prefs.setInt(_kCoinsKey, _coins);
    await prefs.setStringList(_kTrailUnlockKey, _trailUnlocked.map((e) => '$e').toList());
    _homeTrophies();
    await prefs.setInt(_kTrailKey, i);
  }

  Widget _trailTile(int i, Color accent) {
    final selected = _trail == i;
    final locked = !_trailUnlocked.contains(i);
    return GestureDetector(
      onTap: () => _selectTrail(i),
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
              Opacity(opacity: locked ? 0.3 : 1, child: Text(_trailIcons[i], style: const TextStyle(fontSize: 26))),
              if (locked) const Icon(Icons.lock_rounded, color: Colors.white70, size: 20),
            ])),
          ),
          const SizedBox(height: 6),
          Text(_trailNames[i],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: locked ? Colors.white38 : selected ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              )),
          if (locked)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _CoinIcon(size: 11),
              const SizedBox(width: 3),
              Text('${_trailPrices[i]}',
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w700)),
            ])
          else
            const SizedBox(height: 14),
        ]),
      ),
    );
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
    _homeTrophies();
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
          // Name always shown (greyed out while locked)
          Text(_themeNames[i],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: locked ? Colors.white38 : selected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
          if (locked)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _CoinIcon(size: 11),
              const SizedBox(width: 3),
              Text('${_themePrices[i]}',
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w700)),
            ])
          else
            const SizedBox(height: 14), // same height as the price row
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

  Future<void> _setGhost(bool v) async {
    setState(() => _ghostOn = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kGhostKey, v);
  }

  Future<void> _setHapticLvl(int v) async {
    setState(() => _hapticLvl = v);
    _hapticAt(2, v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kHapticLvlKey, v);
  }

  Widget _hapticLvlRow(Color color) {
    const labels = ['Light', 'Normal', 'Strong'];
    return Opacity(
      opacity: _haptics ? 1 : 0.4,
      child: Row(children: [
        Icon(Icons.vibration_rounded, color: color, size: 20),
        const SizedBox(width: 8),
        SizedBox(width: 84, child: Text('Vibration', style: const TextStyle(color: Colors.white70, fontSize: 13))),
        for (int i = 0; i < 3; i++)
          Expanded(child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
            child: GestureDetector(
              onTap: _haptics ? () => _setHapticLvl(i) : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: _hapticLvl == i ? color.withOpacity(0.18) : Colors.white.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _hapticLvl == i ? color : Colors.white12),
                ),
                child: Text(labels[i], textAlign: TextAlign.center,
                    style: TextStyle(color: _hapticLvl == i ? color : Colors.white60,
                        fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          )),
      ]),
    );
  }

  // ── Avatar façon Mii ────────────────────────────────────────────────────
  Future<void> _setAvatar(String? code) async {
    setState(() => _avatar = code);
    _rev.value++;
    final prefs = await SharedPreferences.getInstance();
    if (code == null) {
      await prefs.remove(_kAvatarKey);
    } else {
      await prefs.setString(_kAvatarKey, code);
    }
    await Leaderboard.setAvatar(code ?? '');
  }

  Future<void> _openAvatarEditor() async {
    const cats = ['Skin', 'Face', 'Hairstyle', 'Hair colour', 'Eyes', 'Mouth', 'Extra', 'Background'];
    final rnd = Random();
    final a = _avParse(_avatar) ?? _avRandom(rnd);
    int cat = 0;
    final res = await showDialog<List<int>>(
      context: _sheetCtx ?? context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        Widget swatch(int v) {
          final col = cat == 0 ? _avSkin[v] : cat == 3 ? _avHair[v] : cat == 7 ? _avBg[v] : null;
          if (col != null) {
            return Center(child: Container(width: 34, height: 34,
                decoration: BoxDecoration(color: Color(col), shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24))));
          }
          return CustomPaint(painter: _MiiPainter(List<int>.of(a)..[cat] = v));
        }
        return Dialog(
          backgroundColor: const Color(0xFF151A24),
          insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.face_rounded, color: Colors.pinkAccent),
                const SizedBox(width: 8),
                const Expanded(child: Text('My avatar',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
                TextButton.icon(
                  onPressed: () => setD(() {
                    final r = _avRandom(rnd);
                    for (int i = 0; i < a.length; i++) {
                      a[i] = r[i];
                    }
                  }),
                  icon: const Icon(Icons.casino_rounded, size: 18),
                  label: const Text('Random'),
                ),
              ]),
              const SizedBox(height: 6),
              SizedBox(width: 120, height: 120, child: CustomPaint(painter: _MiiPainter(List<int>.of(a)))),
              const SizedBox(height: 10),
              SizedBox(
                height: 36,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (int i = 0; i < cats.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(cats[i]),
                        selected: cat == i,
                        onSelected: (_) => setD(() => cat = i),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 210,
                child: GridView.count(
                  crossAxisCount: 5,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  children: [
                    for (int v = 0; v < _avCounts[cat]; v++)
                      GestureDetector(
                        onTap: () => setD(() => a[cat] = v),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: a[cat] == v ? Colors.pinkAccent : Colors.white12, width: 2),
                          ),
                          child: swatch(v),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: () => Navigator.pop(ctx, List<int>.of(a)), child: const Text('Save')),
              ]),
            ]),
          ),
        );
      }),
    );
    if (res == null || !mounted) return;
    await _setAvatar(_avCode(res));
    if (mounted) _snack('Avatar saved', ok: true);
  }

  Future<void> _saveSens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kSensTouchKey, _sensTouch);
    await prefs.setDouble(_kSensTiltKey, _sensTilt);
  }

  Widget _sensSlider(IconData icon, Color color, String label, double value, double lo, double hi,
      ValueChanged<double> onChanged) {
    return Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      SizedBox(width: 84, child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
      Expanded(child: Slider(
        value: value.clamp(lo, hi).toDouble(),
        min: lo,
        max: hi,
        divisions: ((hi - lo) * 20).round(),
        onChanged: onChanged,
        onChangeEnd: (_) => _saveSens(),
      )),
      SizedBox(width: 46, child: Text('${(value * 100).round()} %', textAlign: TextAlign.right,
          style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800))),
    ]);
  }

  Future<void> _startGame({bool daily = false}) async {
    _lastDaily = daily;
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
    // Partie du jour : record du jour (relu, le jour a pu changer depuis l'ouverture)
    var best = _bestScore;
    if (daily) {
      final prefs = await SharedPreferences.getInstance();
      final db = (prefs.getString(_kDailyKey) ?? '').split('|');
      best = db.length >= 2 && db[0] == Leaderboard.today() ? int.tryParse(db[1]) ?? 0 : 0;
      if (!mounted) return;
      if (best != _dailyBest) setState(() => _dailyBest = best);
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _JumpGame(
        bestScore: best,
        hero: _hero,
        theme: _theme,
        trail: _trail,
        haptics: _haptics,
        hapticLvl: _hapticLvl,
        tilt: _tilt,
        ghost: _ghostOn,
        touchSens: _sensTouch,
        tiltSens: _sensTilt,
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
      body: Stack(children: [
       SafeArea(
        child: Column(children: [
          // En-tête : titre (5 appuis = code secret), pièces, son
          Padding(
            padding: const EdgeInsets.fromLTRB(64, 8, 16, 0),
            child: Row(children: [
              // Titre réduit au besoin pour laisser la place aux boutons
              Expanded(
                child: GestureDetector(
                  onTap: _onTitleTap,
                  // Titre remonté + signature
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text('Retro Jump', style: Theme.of(context).textTheme.headlineMedium?.copyWith(height: 1.0)),
                    ),
                    const SizedBox(height: 3),
                    const Text('by foclabroc',
                        style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              _hdrItem('Coins', Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
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
              )),
              const SizedBox(width: 8),
              // Trophées (avec le nombre débloqué)
              _hdrItem('Trophies', GestureDetector(
                onTap: () => _openQuests(1),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD54F).withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFD54F).withOpacity(0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD54F), size: 19),
                    const SizedBox(width: 3),
                    Text('$_trophyCount',
                        style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 13, fontWeight: FontWeight.w800)),
                  ]),
                ),
              )),
              const SizedBox(width: 8),
              // Statistiques à vie
              _hdrItem('Stats', GestureDetector(
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
              )),
              const SizedBox(width: 8),
              _hdrItem('Sound', StatefulBuilder(
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
              )),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFE02020)))
                // Accueil fixe (sans défilement) : la scène du héros prend la place restante
                : Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Column(children: [
                      _levelBar(),
                      const SizedBox(height: 12),
                      // Record
                      Row(children: [
                        const Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 20),
                        const SizedBox(width: 8),
                        const Text('Solo best ',
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
                            title: 'Daily challenge',
                            badge: _dailyBest == 0,
                            trailing: Icons.play_arrow_rounded,
                            subW: const _DailyCountdown(color: Colors.lightBlueAccent, prefix: '⏳ Ends in '),
                            onTap: _openDaily,
                          )),
                          const SizedBox(width: 8),
                          Expanded(child: _homeTile(
                            icon: Icons.leaderboard_rounded,
                            color: Colors.amberAccent,
                            title: 'Leaderboard',
                            onTap: _openLeaderboard,
                          )),
                        ]),
                      ),
                      const SizedBox(height: 12),

                      // Scène du héros : touche = boutique (réduite si l'écran est petit)
                      Expanded(child: GestureDetector(
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
                        Center(child: FittedBox(fit: BoxFit.scaleDown, child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                          ]))),
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
                      )),
                      const SizedBox(height: 12),

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
                    ]),
                  ),
          ),

          // Jouer : fixé au-dessus de la barre du bas (toujours visible, quelle que soit la taille d'écran)
          if (!_loading)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _startGame,
                  icon: const Icon(Icons.play_arrow_rounded, size: 28),
                  label: const Text('Play', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1)),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  ),
                ),
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
              _navButton(Icons.military_tech_rounded, 'Quests', Colors.amberAccent,
                  '$doneCount/${challenges.length}', _openQuests),
              _navButton(Icons.chat_bubble_rounded, 'Messages', Colors.lightGreenAccent,
                  _chatMention ? '@' : (_chatNew ? 'NEW' : null), _openMessages),
              _navButton(Icons.casino_rounded, 'Wheel', Colors.purpleAccent, _wheelReady ? '1' : null, _openWheel),
              _navButton(Icons.settings_rounded, 'Settings', Colors.cyanAccent, null, _openSettings),
            ]),
          ),
        ]),
      ),
       // Écran de démarrage (fondu à la fin du chargement)
       if (!_splashGone)
         Positioned.fill(
           child: IgnorePointer(
             ignoring: !_splashOn,
             child: AnimatedOpacity(
               opacity: _splashOn ? 1 : 0,
               duration: const Duration(milliseconds: 450),
               onEnd: () {
                 if (!_splashOn && mounted) setState(() => _splashGone = true);
               },
               child: GestureDetector(
                 onTap: _endSplash,
                 child: _SplashView(hero: _hero, loading: _loading, podium: _podium, podiumTitle: 'TOP SCORES',
                     title1: 'RETRO', title2: 'JUMP', loadingText: 'Loading…', tapText: 'Tap to start'),
               ),
             ),
           ),
         ),
      ]),
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
    BuildContext? mine;
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
              _sheetCtx = mine = ctx;
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
    ).whenComplete(() {
      // Une autre feuille a pu s'ouvrir entre-temps : on ne l'oublie pas
      if (_sheetCtx == mine) {
        _sheetCtx = null;
        _msgOpen = false;
        _chatStop(); // plus de rafraîchissement du chat une fois la feuille fermée
      }
    });
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
  /// Bouton de l'en-tête avec son nom en dessous.
  Widget _hdrItem(String label, Widget child) => Column(mainAxisSize: MainAxisSize.min, children: [
        child,
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 9.5, fontWeight: FontWeight.w600)),
      ]);

  Widget _homeTile({
    required IconData icon,
    required Color color,
    required String title,
    String? sub,
    Widget? subW,
    required VoidCallback onTap,
    IconData trailing = Icons.chevron_right_rounded,
    bool badge = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(badge ? 0.8 : 0.35), width: badge ? 1.5 : 1),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
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
          if (sub != null) const SizedBox(height: 6),
          if (sub != null) FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(sub,
                maxLines: 1,
                style: TextStyle(color: color.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w700)),
          ),
          if (subW != null) ...[
            const SizedBox(height: 5),
            subW,
          ],
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
    await _syncProfile(_coins);
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
    await _syncProfile(_coins); // Player's coins, shown on the leaderboard
    final b = tab == 2
        ? await Leaderboard.fetchWeekMedals() // défi semaine : médailles de la semaine
        : tab == 3
            ? await Leaderboard.fetchGeneral() // défi général : toutes les récompenses
        : tab == 1
            ? await Leaderboard.fetch('all', lbAllDay) // Solo
            : await Leaderboard.fetch('daily', Leaderboard.today());
    final n = await Leaderboard.name();
    final pid = await Leaderboard.publicId();
    if (!mounted || tab != _lbTab) return;
    setState(() {
      _lbBoard = b;
      _lbMore = [];
      _lbNoMore = b == null || b.top.length < 50;
      _lbFailed = b == null;
      _lbLoading = false;
      _lbMyName = n;
      _lbPid = pid;
      if (daily && b != null && b.me.rank != null) _dailyRank = '#${b.me.rank} / ${b.me.total}';
      if (tab == 1 && b != null && b.me.rank != null) _worldRank = '#${b.me.rank} / ${b.me.total}';
    });
  }

  (String, String) _lbModeDay() => _lbTab == 2
      ? ('week', Leaderboard.weekKey())
      : _lbTab == 0
          ? ('daily', Leaderboard.today())
          : ('all', lbAllDay);

  /// Charge les lignes suivantes (50 par défaut), sans dépasser 500.
  Future<bool> _lbLoadMore([int count = 50]) async {
    final b = _lbBoard;
    if (b == null || _lbMoreLoading || _lbNoMore) return false;
    final shown = b.top.length + _lbMore.length;
    final n = min(count, 500 - shown);
    if (n <= 0) return false;
    final tab = _lbTab;
    setState(() => _lbMoreLoading = true);
    final (mode, day) = _lbModeDay();
    final page = tab == 2
        ? await Leaderboard.fetchWeekMedalsPage(shown, n)
        : tab == 3
            ? await Leaderboard.fetchGeneralPage(shown, n)
            : await Leaderboard.fetchPage(mode, day, shown, n);
    if (!mounted || tab != _lbTab) return false;
    setState(() {
      _lbMoreLoading = false;
      if (page != null) {
        _lbMore = [..._lbMore, ...page];
        if (page.length < n || b.top.length + _lbMore.length >= 500) _lbNoMore = true;
      }
    });
    return page != null;
  }

  /// Fait défiler jusqu'à ma ligne (charge les pages manquantes si besoin).
  Future<void> _lbGoToMe() async {
    final b = _lbBoard;
    final r = b?.me.rank;
    if (b == null || r == null) return;
    if (r > 500) {
      _snack('Your position is beyond the top 500');
      return;
    }
    final shown = b.top.length + _lbMore.length;
    if (r > shown) await _lbLoadMore(r - shown + 5);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _lbMeKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 400), alignment: 0.4);
      }
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
      final tabs = Row(children: [
        Expanded(child: _lbTabBtn(0, Icons.today_rounded, 'Daily challenge', accent)),
        const SizedBox(width: 6),
        Expanded(child: _lbTabBtn(2, Icons.date_range_rounded, 'Weekly challenge', accent)),
        const SizedBox(width: 6),
        Expanded(child: _lbTabBtn(3, Icons.emoji_events_rounded, 'Overall challenge', accent)),
        const SizedBox(width: 6),
        Expanded(child: _lbTabBtn(1, Icons.person_rounded, 'Solo', accent)),
      ]);
      return Column(children: [
        tabs,
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
          // Fin du défi du jour / de la semaine
          if (_lbTab == 0 || _lbTab == 2)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _lbTab == 0
                    ? const _DailyCountdown(color: Colors.lightBlueAccent, prefix: '⏳ Challenge ends in ')
                    : const _DailyCountdown(color: Colors.lightBlueAccent, prefix: '⏳ Week ends in ', weekly: true),
              ),
            ),
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
                      : _lbTab == 2
                          ? 'No challenge this week yet: play the daily run!'
                          : _lbTab == 3
                          ? 'No award yet: play the daily run!'
                          : 'No score yet: play a game to enter the leaderboard.'),
              style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          if (b.top.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No scores yet.', style: TextStyle(color: Colors.white38)),
            ),
          for (int i = 0; i < b.top.length + _lbMore.length; i++)
            _lbRow(i, i < b.top.length ? b.top[i] : _lbMore[i - b.top.length],
                key: (i < b.top.length ? b.top[i] : _lbMore[i - b.top.length]).pid == _lbPid ? _lbMeKey : null),
          // Voir plus (jusqu'à 500) + Ma position
          if (b.top.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 6),
              child: Row(children: [
                if (!_lbNoMore)
                  Expanded(child: OutlinedButton.icon(
                    onPressed: _lbMoreLoading ? null : () => _lbLoadMore(),
                    icon: _lbMoreLoading
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.expand_more_rounded, size: 18),
                    label: Text('Show more (${b.top.length + _lbMore.length + 1}-${min(500, b.top.length + _lbMore.length + 50)})'),
                  )),
                if (!_lbNoMore && b.me.rank != null) const SizedBox(width: 8),
                if (b.me.rank != null)
                  Expanded(child: OutlinedButton.icon(
                    onPressed: _lbMoreLoading ? null : _lbGoToMe,
                    icon: const Icon(Icons.my_location_rounded, size: 18),
                    label: Text('My position #${b.me.rank}'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.amberAccent,
                        side: BorderSide(color: Colors.amberAccent.withOpacity(0.5))),
                  )),
              ]),
            ),
          if (b.top.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Row(children: [
                Icon(Icons.touch_app_rounded, size: 14, color: Colors.white38),
                SizedBox(width: 6),
                Text('Tap a player to see their card.', style: TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),
        ],
        const SizedBox(height: 8),
        Text(
          _lbTab == 0
              ? 'Daily challenge: same course for everyone, no start bonus, continue or coins. New course every day at midnight. The top 3 win a gold, silver or bronze medal (given at midnight).'
              : _lbTab == 2
                  ? 'Weekly challenge: medals won this week in the daily challenge (gold, then silver, then bronze; ties broken by best challenge score). Every Monday, gold, silver and bronze cups go to the top 3 and a participation medal to the other players of the week · ends in ${Leaderboard.weekDaysLeft()} d.'
                  : _lbTab == 3
                      ? 'Overall challenge: every award won since the start — gold, silver and bronze cups, then daily medals, then participation medals (ties broken by best challenge score).'
                      : 'Solo: each player\'s best score in normal games (daily challenge not included).',
          style: const TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
        ),
      ]);
    });
  }

  Widget _lbTabBtn(int i, IconData icon, String label, Color accent, {bool badge = false}) {
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
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: sel ? accent.withOpacity(0.18) : const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? accent : Colors.white.withOpacity(0.06)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(icon, size: 18, color: sel ? Colors.white : Colors.white54),
            if (badge)
              Positioned(
                right: -4, top: -3,
                child: Container(
                  width: 9, height: 9,
                  decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                ),
              ),
          ]),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                maxLines: 1,
                style: TextStyle(color: sel ? Colors.white : Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    );
  }

  // ── Chat ───────────────────────────────────────────────────────────────────
  void _chatStop() {
    _chatTimer?.cancel();
    _chatTimer = null;
  }

  /// Pastille « nouveau message » sur la tuile Classement (au lancement du jeu).
  Future<void> _chatCheckNew() async {
    final last = await Leaderboard.chatLastId();
    final seen = await Leaderboard.chatSeen();
    if (mounted && last != null && last > seen) setState(() => _chatNew = true);
    // Mentions @pseudo pas encore vues
    final n = await Leaderboard.name();
    if (n == null) return;
    final pid = await Leaderboard.publicId();
    final m = (await Leaderboard.chatMentions(n, await Leaderboard.mentionSeen()))
        ?.where((x) => x.pid != pid)
        .toList();
    if (!mounted || m == null || m.isEmpty) return;
    setState(() => _chatMention = true);
    _snack('💬 ${m.first.name} mentioned you in the chat');
  }

  Future<void> _chatOpen() async {
    _chatStop();
    setState(() {
      _chat = [];
      _chatLoading = true;
      _chatFailed = false;
    });
    final n = await Leaderboard.name();
    final pid = await Leaderboard.publicId();
    if (!mounted) return;
    setState(() {
      _lbMyName = n;
      _lbPid = pid;
    });
    await _chatLoad();
    // Rafraîchi toutes les 8 s tant que l'onglet est affiché
    _chatTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || _sheetCtx == null || !_msgOpen) {
        _chatStop();
        return;
      }
      _chatLoad();
    });
  }

  Future<void> _chatLoad() async {
    if (_chatBusy) return;
    _chatBusy = true;
    final res = await Leaderboard.chat(afterId: _chat.isEmpty ? 0 : _chat.last.id);
    _chatBusy = false;
    if (!mounted) return;
    if (res == null) {
      if (_chat.isEmpty) {
        setState(() {
          _chatFailed = true;
          _chatLoading = false;
        });
      }
      return;
    }
    if (res.isEmpty && !_chatLoading && !_chatFailed) return;
    setState(() {
      _chatFailed = false;
      _chatLoading = false;
      _chat = [..._chat, ...res];
      if (_chat.length > 100) _chat = _chat.sublist(_chat.length - 100);
      _chatNew = false;
      _chatMention = false;
    });
    if (_chat.isNotEmpty) {
      Leaderboard.setChatSeen(_chat.last.id);
      Leaderboard.setMentionSeen(_chat.last.id);
    }
  }

  Future<void> _chatSend() async {
    final txt = _chatCtrl.text;
    if (txt.trim().isEmpty || _chatSending) return;
    setState(() => _chatSending = true);
    final r = await Leaderboard.sendChat(txt, _hero);
    if (!mounted) return;
    setState(() => _chatSending = false);
    if (r == Leaderboard.chatOk || r == Leaderboard.chatEmpty) {
      _chatCtrl.clear();
      if (r == Leaderboard.chatOk) {
        _chatLoad();
        _bumpStat('chat').then((_) => _homeTrophies());
      }
    } else if (r == Leaderboard.chatWait) {
      _snack('Wait a few seconds before sending another message');
    } else if (r == Leaderboard.chatNoName) {
      _snack('Pick a name first');
      _lbEditName();
    } else if (r == Leaderboard.chatBanned) {
      _snack('You can no longer post in the chat');
    } else {
      _snack('Offline: message not sent');
    }
  }

  Future<void> _chatReport(LbChatMsg m) async {
    final ok = await showDialog<bool>(
      context: _sheetCtx ?? context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Report this message?', style: TextStyle(color: Colors.white)),
        content: Text('${m.name} : ${m.msg}', style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Report')),
        ],
      ),
    );
    if (ok != true) return;
    await Leaderboard.reportChat(m.id);
    if (!mounted) return;
    setState(() => _chat = _chat.where((x) => x.id != m.id).toList());
    _snack('Message reported, thanks!', ok: true);
  }

  String _chatTime(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    final now = DateTime.now();
    final hm = '${two(d.hour)}:${two(d.minute)}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) return hm;
    final y = now.subtract(const Duration(days: 1));
    if (d.year == y.year && d.month == y.month && d.day == y.day) return 'yesterday $hm';
    return '${two(d.day)}/${two(d.month)} $hm';
  }

  static const _chatNameColors = [
    Colors.lightBlueAccent, Colors.pinkAccent, Colors.lightGreenAccent, Colors.orangeAccent,
    Colors.purpleAccent, Colors.cyanAccent, Colors.limeAccent, Colors.tealAccent,
  ];

  Widget _chatView(Color accent) {
    final h = MediaQuery.of(context).size.height * 0.42;
    Widget box;
    if (_chatLoading && _chat.isEmpty) {
      box = const Center(child: CircularProgressIndicator(color: Colors.amberAccent));
    } else if (_chatFailed) {
      box = Center(child: _lbInfo(Icons.wifi_off_rounded, 'Offline', 'Chat unavailable right now.', retry: _chatOpen));
    } else if (_chat.isEmpty) {
      box = const Center(child: Text('No messages yet. Start the conversation!', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)));
    } else {
      box = ListView.builder(
        reverse: true, // le plus récent en bas
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: _chat.length,
        itemBuilder: (_, i) => _chatRow(_chat[_chat.length - 1 - i]),
      );
    }
    return Column(children: [
      Container(
        height: h,
        decoration: BoxDecoration(
          color: const Color(0xFF10141C),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: box,
      ),
      const SizedBox(height: 8),
      if (_lbMyName != null && _chatMentionSuggestions().isNotEmpty)
        SizedBox(
          height: 38,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final n in _chatMentionSuggestions())
              Padding(
                padding: const EdgeInsets.only(right: 6, bottom: 4),
                child: ActionChip(
                  avatar: const Icon(Icons.alternate_email_rounded, size: 16, color: Colors.lightBlueAccent),
                  label: Text(n, style: const TextStyle(color: Colors.white, fontSize: 12)),
                  backgroundColor: const Color(0xFF1C2230),
                  side: BorderSide(color: Colors.lightBlueAccent.withOpacity(0.4)),
                  onPressed: () => _chatInsertMention(n),
                ),
              ),
          ]),
        ),
      if (_lbMyName == null)
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _lbEditName,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Pick a name to post'),
          ),
        )
      else
        Row(children: [
          Expanded(child: TextField(
            controller: _chatCtrl,
            maxLength: 120,
            maxLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _chatSend(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Your message…',
              hintStyle: const TextStyle(color: Colors.white38),
              counterText: '',
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF1C2230),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          )),
          const SizedBox(width: 6),
          IconButton(
            onPressed: _chatSending ? null : _chatSend,
            icon: _chatSending
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.send_rounded, color: accent),
          ),
        ]),
      const SizedBox(height: 8),
      const Text('Be nice! Messages are filtered, 1 message every 10 s. Type @name to mention a player (or tap their message). Long-press to report.',
          style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4)),
    ]);
  }

  Widget _chatRow(LbChatMsg m) {
    final me = m.pid == _lbPid;
    final nameColor = me ? Colors.amberAccent : _chatNameColors[m.pid.codeUnits.fold<int>(0, (a, c) => a + c) % _chatNameColors.length];
    return GestureDetector(
      onTap: () => _openPlayerCard(m.pid, m.name, m.hero, mention: true),
      onLongPress: me ? null : () => _chatReport(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _Avatar(code: m.avatar, hero: m.hero, size: 24),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
            decoration: BoxDecoration(
              color: me ? Colors.amberAccent.withOpacity(0.10) : const Color(0xFF1C2230),
              borderRadius: BorderRadius.circular(12),
              // Message qui me mentionne : encadré
              border: !me && _lbMyName != null && Leaderboard.mentions(m.msg, _lbMyName!)
                  ? Border.all(color: Colors.amberAccent.withOpacity(0.7), width: 1.2)
                  : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                if (m.level != null) ...[
                  _LevelBadge(level: m.level!, size: 15),
                  const SizedBox(width: 5),
                ],
                Expanded(child: Text(m.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: nameColor, fontSize: 12, fontWeight: FontWeight.w800))),
                const SizedBox(width: 6),
                Text(_chatTime(m.at), style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ]),
              const SizedBox(height: 2),
              Text.rich(TextSpan(children: _chatSpans(m.msg)),
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, height: 1.3)),
            ]),
          )),
        ]),
      ),
    );
  }

  /// Texte d'un message : les @pseudo en couleur (le mien en doré).
  List<TextSpan> _chatSpans(String msg) {
    if (!msg.contains('@')) return [TextSpan(text: msg)];
    final names = {for (final c in _chat) c.name, if (_lbMyName != null) _lbMyName!}.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final re = RegExp('@(?:${[for (final n in names) RegExp.escape(n), r'[^\s@]+'].join('|')})', caseSensitive: false);
    final out = <TextSpan>[];
    var pos = 0;
    for (final mt in re.allMatches(msg)) {
      if (mt.start > pos) out.add(TextSpan(text: msg.substring(pos, mt.start)));
      final mine = _lbMyName != null && mt.group(0)!.toLowerCase() == '@${_lbMyName!.toLowerCase()}';
      out.add(TextSpan(
        text: mt.group(0),
        style: TextStyle(
          color: mine ? Colors.amberAccent : Colors.lightBlueAccent,
          fontWeight: FontWeight.w800,
          backgroundColor: mine ? Colors.amberAccent.withOpacity(0.15) : null,
        ),
      ));
      pos = mt.end;
    }
    if (pos < msg.length) out.add(TextSpan(text: msg.substring(pos)));
    return out;
  }

  /// Ajoute « @pseudo » au message en cours de saisie.
  void _chatInsertMention(String name) {
    final t = _chatCtrl.text;
    final m = RegExp(r'@[^@\n]*$').firstMatch(t);
    final base = m != null && _chatMentionQuery() != null ? t.substring(0, m.start) : (t.isEmpty || t.endsWith(' ') ? t : '$t ');
    final nt = '$base@$name ';
    _chatCtrl.value = TextEditingValue(text: nt, selection: TextSelection.collapsed(offset: nt.length));
  }

  /// Texte tapé après le dernier « @ » (null si on n'est pas en train de mentionner).
  String? _chatMentionQuery() {
    final m = RegExp(r'@([^@\n]{0,16})$').firstMatch(_chatCtrl.text);
    return m?.group(1);
  }

  /// Pseudos proposés pendant la saisie de « @… » (joueurs présents dans le chat).
  List<String> _chatMentionSuggestions() {
    final q = _chatMentionQuery();
    if (q == null) return const [];
    final ql = q.toLowerCase();
    final seen = <String>{};
    final out = <String>[];
    for (final c in _chat.reversed) {
      if (c.pid == _lbPid || !seen.add(c.name.toLowerCase())) continue;
      if (c.name.toLowerCase().startsWith(ql) && c.name.toLowerCase() != ql) out.add(c.name);
      if (out.length >= 6) break;
    }
    return out;
  }

  Widget _lbRow(int i, LbEntry e, {Key? key}) => GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: () => _openPlayerCard(e.pid, e.name, e.hero),
        child: _lbRowBody(i, e),
      );

  // ── Fiche joueur ────────────────────────────────────────────────────────────
  Future<void> _openPlayerCard(String pid, String name, int hero, {bool mention = false}) async {
    final f = Leaderboard.playerCard(pid);
    await showDialog<void>(
      context: _sheetCtx ?? context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF151A24),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: FutureBuilder<Map<String, dynamic>?>(
          future: f,
          builder: (_, snap) {
            final c = snap.data;
            final loading = snap.connectionState != ConnectionState.done;
            final h = (c?['hero'] as num?)?.toInt() ?? hero;
            final av = c?['avatar'] as String?;
            final coins = (c?['coins'] as num?)?.toInt();
            final prog = (c?['progress'] as num?)?.toInt();
            final lvl = (c?['level'] as num?)?.toInt() ??
                ((c?['stats'] is Map) ? ((c!['stats'] as Map)['level'] as num?)?.toInt() : null);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(children: [
                  if (_avParse(av) != null)
                    _Avatar(code: av, hero: h, size: 56)
                  else
                    Container(
                      width: 52, height: 52,
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(color: const Color(0xFF1C2230), borderRadius: BorderRadius.circular(14)),
                      child: CustomPaint(painter: _HeroPreviewPainter(min(max(h, 0), _heroCount - 1))),
                    ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text((c?['name'] as String?) ?? name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Row(children: [
                      if (lvl != null) ...[
                        _LevelBadge(level: lvl, size: 16),
                        const SizedBox(width: 4),
                        Text(_rankFor(lvl).$1,
                            style: TextStyle(color: _rankFor(lvl).$2, fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 12),
                      ],
                      if (coins != null) ...[
                        const _CoinIcon(size: 12),
                        const SizedBox(width: 4),
                        Text(_fmtNum(coins),
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 12),
                      ],
                      if (prog != null) ...[
                        const Icon(Icons.inventory_2_rounded, size: 13, color: Colors.lightBlueAccent),
                        const SizedBox(width: 4),
                        Text('$prog %',
                            style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 13, fontWeight: FontWeight.w700)),
                      ],
                    ]),
                  ])),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white54),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ]),
                const SizedBox(height: 6),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(28),
                    child: CircularProgressIndicator(color: Colors.amberAccent),
                  )
                else if (c == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Card unavailable (offline?)', style: TextStyle(color: Colors.white54)),
                  )
                else
                  Flexible(child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 8),
                    child: _playerCardBody(c),
                  )),
                if (mention && pid != _lbPid && _lbMyName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _chatInsertMention((c?['name'] as String?) ?? name);
                        },
                        icon: const Icon(Icons.alternate_email_rounded, size: 18),
                        label: Text('Mention @${(c?['name'] as String?) ?? name}'),
                      ),
                    ),
                  ),
              ]),
            );
          },
        ),
      ),
    );
  }

  Widget _playerCardBody(Map<String, dynamic> c) {
    final st = c['stats'] is Map ? Map<String, dynamic>.from(c['stats'] as Map) : <String, dynamic>{};
    int? n(String k) => (c[k] as num?)?.toInt();
    int? v(String k) => (st[k] as num?)?.toInt();
    String fmt(int? x) => x == null ? '—' : _fmtNum(x);
    String rank(int? r, [int? total]) => r == null ? '' : (total == null ? '  #$r' : '  #$r/$total');
    String own(String k) => v(k) == null ? '—' : '${v(k)}/${v('${k}_n') ?? '?'}';
    final secs = v('time');
    final time = secs == null
        ? '—'
        : secs >= 3600 ? '${secs ~/ 3600} h ${(secs % 3600) ~/ 60} min' : '${secs ~/ 60} min';
    final games = v('games');
    final best = n('best') ?? v('best');
    Widget tile(IconData icon, Color color, String label, String value) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF1C2230),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(value,
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                ),
                Text(label,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
              ],
            )),
          ]),
        );
    Widget grid(List<Widget> tiles) => GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.7,
          children: tiles,
        );
    Widget head(String txt) => Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(txt,
                style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          ),
        );
    final since = DateTime.tryParse(c['since'] as String? ?? '')?.toLocal();
    final lastPlayed = DateTime.tryParse(c['last_played'] as String? ?? '')?.toLocal();
    final chat = n('chat') ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if ((n('gold') ?? 0) + (n('silver') ?? 0) + (n('bronze') ?? 0) + (n('medals') ?? 0) +
              (n('mgold') ?? 0) + (n('msilver') ?? 0) + (n('mbronze') ?? 0) > 0) ...[
        head('AWARDS'),
        Align(
          alignment: Alignment.centerLeft,
          child: _Cups(gold: n('gold') ?? 0, silver: n('silver') ?? 0, bronze: n('bronze') ?? 0,
              medals: n('medals') ?? 0, mGold: n('mgold') ?? 0, mSilver: n('msilver') ?? 0,
              mBronze: n('mbronze') ?? 0, size: 20),
        ),
      ],
      // Défi du jour : jour, semaine (médailles), général (coupes)
      head('DAILY CHALLENGE'),
      grid([
        tile(Icons.today_rounded, Colors.cyanAccent, 'Daily challenge${rank(n('rank_today'))}', fmt(n('today'))),
        tile(Icons.date_range_rounded, Colors.lightBlueAccent, 'Weekly challenge${rank(n('rank_wch'), n('total_wch'))}',
            n('rank_wch') == null ? '—' : '🥇${n('wg') ?? 0} 🥈${n('ws') ?? 0} 🥉${n('wb') ?? 0}'),
        tile(Icons.emoji_events_rounded, Colors.amberAccent, 'Overall challenge${rank(n('rank_gen'), n('total_gen'))}',
            n('rank_gen') == null ? '—' : '🏆 ${(n('gold') ?? 0) + (n('silver') ?? 0) + (n('bronze') ?? 0)}'),
        tile(Icons.workspace_premium_rounded, Colors.orangeAccent, 'Dailies won', fmt(n('daily_wins'))),
        tile(Icons.event_repeat_rounded, Colors.tealAccent, 'Dailies played', fmt(n('dailies'))),
        tile(Icons.star_rounded, Colors.yellowAccent, 'Best daily', fmt(n('daily_best'))),
      ]),
      // Solo : parties normales
      head('SOLO'),
      grid([
        tile(Icons.person_rounded, Colors.amberAccent, 'Solo best${rank(n('rank_all'), n('total_all'))}', fmt(best)),
        tile(Icons.date_range_rounded, Colors.lightBlueAccent, 'Solo week${rank(n('rank_week'))}', fmt(n('week'))),
      ]),
      head('GAMES'),
      grid([
        tile(Icons.sports_esports_rounded, Colors.cyanAccent, 'Games played', fmt(games)),
        tile(Icons.timer_rounded, Colors.tealAccent, 'Play time', time),
        tile(Icons.landscape_rounded, Colors.purpleAccent, 'Total points', fmt(v('pts'))),
        tile(Icons.show_chart_rounded, Colors.lightBlueAccent, 'Average / game',
            games == null || games == 0 || v('pts') == null ? '—' : _fmtNum(v('pts')! ~/ games)),
        tile(Icons.local_fire_department_rounded, Colors.deepOrangeAccent, 'Best combo', fmt(v('combo'))),
        tile(Icons.monetization_on_rounded, Colors.amberAccent, 'Coins earned', fmt(v('coins'))),
        tile(Icons.keyboard_double_arrow_up_rounded, Colors.cyanAccent, 'Jumps', fmt(v('jumps'))),
        tile(Icons.bug_report_rounded, Colors.lightGreenAccent, 'Bugs stomped', fmt(v('stomps'))),
        tile(Icons.savings_rounded, Colors.amberAccent, 'Bags collected', fmt(v('bags'))),
        tile(Icons.rocket_launch_rounded, Colors.greenAccent, 'Turbos', fmt(v('turbos'))),
        tile(Icons.south_rounded, Colors.redAccent, 'Falls', fmt(v('falls'))),
        tile(Icons.collections_bookmark_rounded, Colors.lightBlueAccent, 'Logos caught', fmt(v('logos'))),
      ]),
      head('COLLECTION'),
      grid([
        tile(Icons.auto_stories_rounded, Colors.lightBlueAccent, 'Albums completed', fmt(v('album'))),
        tile(Icons.person_rounded, Colors.pinkAccent, 'Heroes', own('heroes')),
        tile(Icons.palette_rounded, Colors.purpleAccent, 'Themes', own('themes')),
        tile(Icons.music_note_rounded, Colors.greenAccent, 'Music', own('musics')),
        tile(Icons.auto_awesome_rounded, Colors.amberAccent, 'Trails', own('trails')),
        tile(Icons.emoji_events_rounded, Colors.amberAccent, 'Trophies', own('trophies')),
      ]),
      if (st.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Text('Detailed stats will show once this player updates their game.', style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4)),
        ),
      const SizedBox(height: 10),
      Text(
        [
          if (lastPlayed != null) 'Last game: ${_chatTime(lastPlayed)}',
          if (since != null) 'Player since ${since.day.toString().padLeft(2, '0')}/${since.month.toString().padLeft(2, '0')}/${since.year}',
          if (chat > 0) '$chat chat messages',
        ].join('  ·  '),
        style: const TextStyle(color: Colors.white38, fontSize: 12),
      ),
    ]);
  }

  Widget _lbRowBody(int i, LbEntry e) {
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
        // Avatar + héros utilisé pour ce record en pastille (sans avatar : le héros seul)
        SizedBox(width: 34, height: 30, child: Stack(clipBehavior: Clip.none, children: [
          _Avatar(code: e.avatar, hero: e.hero, size: 30),
          if (_avParse(e.avatar) != null)
            Positioned(right: -6, bottom: -5, child: SizedBox(width: 17, height: 15,
                child: CustomPaint(painter: _HeroPreviewPainter(min(max(e.hero, 0), _heroCount - 1))))),
        ])),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (e.level != null) ...[
              _LevelBadge(level: e.level!, size: 18),
              const SizedBox(width: 6),
            ],
            Flexible(child: Text(e.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: me ? Colors.amberAccent : Colors.white, fontSize: 14, fontWeight: FontWeight.w700))),
            // Coupes gagnées au défi semaine
            if ((e.cups ?? 0) > 0) ...[
              const SizedBox(width: 5),
              const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD54F), size: 15),
              Text('${e.cups}', style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 12, fontWeight: FontWeight.w900)),
            ],
          ]),
          if (e.coins != null || e.progress != null || e.lastPlayed != null)
            Row(children: [
              if (e.coins != null) ...[
                const _CoinIcon(size: 10),
                const SizedBox(width: 4),
                Text(_fmtNum(e.coins!),
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
              ],
              // Progress: unlocked items + albums
              if (e.progress != null) ...[
                const Icon(Icons.inventory_2_rounded, size: 11, color: Colors.lightBlueAccent),
                const SizedBox(width: 3),
                Text('${e.progress} %',
                    style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
              ],
              // Heure de la dernière partie
              if (e.lastPlayed != null) ...[
                const Icon(Icons.schedule_rounded, size: 11, color: Colors.white38),
                const SizedBox(width: 3),
                Flexible(child: Text(_chatTime(e.lastPlayed!),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600))),
              ],
            ]),
        ])),
        const SizedBox(width: 8),
        if (e.mGold != null)
          // Défi semaine / général : récompenses, meilleur score du défi en petit
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 120), child:
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            _Cups(gold: e.gold ?? 0, silver: e.silver ?? 0, bronze: e.bronze ?? 0, medals: e.medals ?? 0,
                mGold: e.mGold ?? 0, mSilver: e.mSilver ?? 0, mBronze: e.mBronze ?? 0, size: 14),
            const SizedBox(height: 2),
            Text('${_fmtNum(e.score)} pts',
                style: const TextStyle(color: Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ]))
        else
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

  // ── Niveau du joueur ─────────────────────────────────────────────────────────
  Widget _levelBar() {
    final lvl = _levelFor(_xp);
    final rk = _rankFor(lvl);
    final base = _xpForLevel(lvl), next = _xpForLevel(lvl + 1);
    final frac = lvl >= _kMaxLevel ? 1.0 : ((_xp - base) / (next - base)).clamp(0.0, 1.0);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: _openLevels,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: rk.$2.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: rk.$2.withOpacity(0.35)),
        ),
        child: Row(children: [
          _LevelBadge(level: lvl, size: 32),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('Level $lvl', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Text(rk.$1, style: TextStyle(color: rk.$2, fontSize: 12, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(lvl >= _kMaxLevel ? 'Max level!' : '${_fmtNum(_xp - base)} / ${_fmtNum(next - base)} XP',
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ]),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: frac, minHeight: 6, backgroundColor: Colors.white10, color: rk.$2),
            ),
          ])),
        ]),
      ),
    );
  }

  void _openLevels() => _openSheet('Level', Icons.military_tech_rounded, _rankFor(_levelFor(_xp)).$2, (accent) {
        Widget line(IconData icon, Color color, String txt) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 10),
                Expanded(child: Text(txt, style: const TextStyle(color: Colors.white70, fontSize: 13))),
              ]),
            );
        final lvl = _levelFor(_xp);
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IgnorePointer(child: _levelBar()),
          _section('EARNING XP'),
          line(Icons.landscape_rounded, Colors.purpleAccent, '1 XP per 10 points scored'),
          line(Icons.sports_esports_rounded, Colors.cyanAccent, '+10 XP per game played'),
          line(Icons.military_tech_rounded, Colors.greenAccent, '+25 XP per challenge completed'),
          line(Icons.today_rounded, Colors.lightBlueAccent, '+30 XP for the daily run'),
          line(Icons.monetization_on_rounded, Colors.amberAccent, 'Each level: 20 coins × the level reached'),
          _section('RANKS'),
          for (int i = 0; i < _levelRanks.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _rankFor(lvl) == _levelRanks[i] ? _levelRanks[i].$2.withOpacity(0.12) : const Color(0xFF1C2230),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _levelRanks[i].$2.withOpacity(_rankFor(lvl) == _levelRanks[i] ? 0.6 : 0.15)),
              ),
              child: Row(children: [
                _LevelBadge(level: max(1, i * 10), size: 24),
                const SizedBox(width: 10),
                Expanded(child: Text(_levelRanks[i].$1,
                    style: TextStyle(color: _levelRanks[i].$2, fontSize: 14, fontWeight: FontWeight.w800))),
                Text('${'from level'} ${max(1, i * 10)}', style: const TextStyle(color: Colors.white38, fontSize: 12)),
              ]),
            ),
        ]);
      });

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
        _grid(_musicNames.length + 1, (k) => _musicTile(k - 1, accent)),
        _section('Trail  ·  ${_trailUnlocked.length}/${_trailNames.length}'),
        _grid(_trailNames.length, (i) => _trailTile(i, accent)), // Mute + tracks, 4 per row
      ]));

  /// Trophées débloqués + progression (pour l'onglet Trophées des Quêtes)
  Future<void> _loadTrophyView() async {
    final prefs = await SharedPreferences.getInstance();
    final have = (prefs.getStringList(_kTrophyKey) ?? const <String>[]).toSet();
    final snap = await _trophySnapshot(prefs);
    snap['best'] = max(snap['best'] ?? 0, _bestScore);
    if (mounted) {
      setState(() {
        _trHave = have;
        _trSnap = snap;
      });
    }
  }

  Widget _trophiesBody(Color accent) {
    final have = _trHave;
    final snap = _trSnap;
    final got = _trophies.where((x) => have.contains(x.id)).length;
    return Column(children: [
          Row(children: [
            Text('$got / ${_trophies.length}',
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
            const Spacer(),
            for (int k = 0; k < 3; k++) ...[
              Icon(Icons.emoji_events_rounded, size: 16, color: _tierColors[k]),
              const SizedBox(width: 3),
              Text('${_trophies.where((x) => x.tier == k && have.contains(x.id)).length}',
                  style: TextStyle(color: _tierColors[k], fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(width: 10),
            ],
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
                value: got / _trophies.length, minHeight: 6, backgroundColor: Colors.white10, color: const Color(0xFFFFD54F)),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 2.0,
            children: [
              for (final x in [..._trophies.where((x) => have.contains(x.id)), ..._trophies.where((x) => !have.contains(x.id))])
                _trophyTile(x, have.contains(x.id), snap[x.key] ?? 0),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Each trophy unlocked gives coins: bronze 25, silver 75, gold 200. They also count in your progress %.', style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4)),
        ]);
  }

  Widget _trophyTile(_Trophy x, bool got, int value) {
    final c = _tierColors[x.tier];
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: got ? c.withOpacity(0.10) : const Color(0xFF1C2230),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: got ? c.withOpacity(0.6) : Colors.white.withOpacity(0.05)),
      ),
      child: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: got ? c.withOpacity(0.2) : Colors.white.withOpacity(0.04),
            border: Border.all(color: got ? c : Colors.white24, width: 1.5),
          ),
          child: Icon(got ? x.icon : Icons.lock_rounded, size: 17, color: got ? c : Colors.white24),
        ),
        const SizedBox(width: 8),
        Expanded(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(x.name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: got ? Colors.white : Colors.white60, fontSize: 12.5, fontWeight: FontWeight.w800)),
            Text(x.desc,
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 10.5, height: 1.2)),
            const SizedBox(height: 3),
            if (got)
              Text('${_tierNames[x.tier]} · +${_tierReward[x.tier]}',
                  style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700))
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                    value: (value / x.goal).clamp(0.0, 1.0), minHeight: 3,
                    backgroundColor: Colors.white10, color: c.withOpacity(0.7)),
              ),
          ],
        )),
      ]),
    );
  }

  // ── Quêtes : Défis / Trophées / Collection ────────────────────────────────
  void _openQuests([int tab = 0]) {
    _questTab = tab;
    _loadTrophyView();
    _openSheet('Quests', Icons.military_tech_rounded, Colors.amberAccent, (accent) {
      final ch = _challengesFor(_challengeLevel);
      return Column(children: [
        Row(children: [
          Expanded(child: _questTabBtn(0, Icons.flag_rounded, 'Challenges',
              '${ch.where((c) => _completed.contains(c.id)).length}/${ch.length}', Colors.amberAccent)),
          const SizedBox(width: 6),
          Expanded(child: _questTabBtn(1, Icons.emoji_events_rounded, 'Trophies',
              '$_trophyCount/${_trophies.length}', const Color(0xFFFFD54F))),
          const SizedBox(width: 6),
          Expanded(child: _questTabBtn(2, Icons.collections_bookmark_rounded, 'Collection',
              '${_collection.where((n) => n >= _logoGoal).length}/${_logoAssets.length}', Colors.lightBlueAccent)),
        ]),
        const SizedBox(height: 14),
        if (_questTab == 0)
          _challengesBody(accent)
        else if (_questTab == 1)
          _trophiesBody(accent)
        else
          _collectionBody(accent),
      ]);
    });
  }

  Widget _questTabBtn(int i, IconData icon, String label, String count, Color color) {
    final sel = _questTab == i;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        if (_questTab == i) return;
        setState(() => _questTab = i);
        if (i == 1) _loadTrophyView();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: sel ? color.withOpacity(0.16) : const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? color : Colors.white.withOpacity(0.06)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 19, color: sel ? color : Colors.white54),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1,
                style: TextStyle(color: sel ? Colors.white : Colors.white54, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Text(count, style: TextStyle(color: sel ? color : Colors.white38, fontSize: 10.5, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }

  // ── Messages (chat), ouverts depuis la barre du bas ──────────────────────
  void _openMessages() {
    if (!Leaderboard.configured) return;
    _msgOpen = true;
    _chatOpen();
    _openSheet('Messages', Icons.chat_bubble_rounded, Colors.lightGreenAccent, (accent) => _chatView(accent));
  }

  Widget _challengesBody(Color accent) {
    final challenges = _challengesFor(_challengeLevel);
    return Column(children: [
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
        ]);
  }

  Widget _collectionBody(Color accent) => Column(children: [
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
          ]);

  void _openSettings() => _openSheet('Settings', Icons.settings_rounded, Colors.cyanAccent, (accent) => Column(children: [
        _section('Avatar'),
        Row(children: [
          GestureDetector(onTap: _openAvatarEditor, child: _Avatar(code: _avatar, hero: _hero, size: 56)),
          const SizedBox(width: 12),
          Expanded(child: Text('Shown in the leaderboard, the chat and your player card.', style: const TextStyle(color: Colors.white54, fontSize: 12))),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
            ElevatedButton.icon(
              onPressed: _openAvatarEditor,
              icon: const Icon(Icons.face_rounded, size: 18),
              label: Text(_avatar == null ? 'Create my avatar' : 'Edit'),
            ),
            if (_avatar != null)
              TextButton(onPressed: () => _setAvatar(null), child: const Text('Remove')),
          ]),
        ]),
        _section('Options'),
        Row(children: [
          Expanded(child: _OptionTile(icon: Icons.vibration_rounded, color: Colors.cyanAccent,
              label: 'Vibration', value: _haptics, accent: accent, onTap: () => _setHaptics(!_haptics))),
          Expanded(child: _OptionTile(icon: Icons.screen_rotation_rounded, color: Colors.lightGreenAccent,
              label: 'Tilt', value: _tilt, accent: accent, onTap: () => _setTilt(!_tilt))),
          Expanded(child: _OptionTile(icon: Icons.blur_on_rounded, color: Colors.white70,
              label: 'Ghost', value: _ghostOn, accent: accent, onTap: () => _setGhost(!_ghostOn))),
          Expanded(child: _OptionTile(
              icon: QuizAudio.enabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: Colors.amberAccent,
              label: 'Sound', value: QuizAudio.enabled, accent: accent,
              onTap: () => setState(() => QuizAudio.enabled = !QuizAudio.enabled))),
        ]),
        _section('Sensitivity'),
        _sensSlider(Icons.touch_app_rounded, Colors.cyanAccent, 'Touch', _sensTouch, 0.7, 1.3,
            (v) => setState(() => _sensTouch = v)),
        _sensSlider(Icons.screen_rotation_rounded, Colors.lightGreenAccent, 'Tilt', _sensTilt, 0.5, 2.0,
            (v) => setState(() => _sensTilt = v)),
        Text('Touch: movement speed and responsiveness · Tilt: the higher, the less you need to tilt', style: const TextStyle(color: Colors.white38, fontSize: 11)),
        _hapticLvlRow(Colors.cyanAccent),
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
                        text: 'Wheel of fortune: one free spin per day, then $_wheelSpinPrice coins per spin (up to 1,000 coins, bonus, free continue or mystery item 🎁)'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.landscape_rounded, color: Colors.purpleAccent,
                        text: 'New scenery every 400 pts: castle, dungeon, temple, ice, volcano, cyber, space…'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.shield_rounded, color: Colors.cyanAccent,
                        text: 'Shield 🛡️ → protects you from one bug hit. A 2nd one goes in reserve: tap the bubble at the bottom to use it'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.replay_rounded, color: Colors.amberAccent,
                        text: 'Game over? Continue for 20 coins (once per game)'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.collections_bookmark_rounded, color: Colors.lightBlueAccent,
                        text: 'Console logo → catch it 3 times (more in later albums) to complete it in your collection'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.thunderstorm_rounded, color: Colors.blueGrey.shade200,
                        text: 'Weather (around 1,100, 2,100… pts): 💨 wind pushes you, 🌧️ rain makes you slide, ⛈️ storm with falling coins, 🌫️ fog'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.today_rounded, color: Colors.lightBlueAccent,
                        text: 'Daily run: same course for everyone, no bonuses or coins. Replay as often as you like, only your best score counts'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.blur_on_rounded, color: Colors.white70,
                        text: 'Ghost: in the daily run, today\'s #1 player climbs alongside you'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.leaderboard_rounded, color: Colors.amberAccent,
                        text: 'Leaderboards: daily challenge (a medal for the top 3 every day), weekly challenge (cups for the 3 players with the most medals every Monday, a participation medal for the others), overall challenge (every award since the start) and Solo (best score in normal games). Tap a player to see their card'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.military_tech_rounded, color: Colors.lightGreenAccent,
                        text: 'Level: 1 XP per 10 pts, +10 per game, +25 per challenge completed, +30 for the daily run. Each level gives 20 × the level in coins'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.emoji_events_rounded, color: Color(0xFFFFD54F),
                        text: 'Trophies: 52 permanent badges to unlock (bronze +25, silver +75, gold +200 coins)'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.inventory_2_rounded, color: Colors.lightBlueAccent,
                        text: 'Progress % (leaderboard): 40% shop + 30% albums + 30% trophies'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.chat_bubble_rounded, color: Colors.cyanAccent,
                        text: 'Chat: be nice! Type @name to mention a player, long-press a message to report it'),
                    SizedBox(height: 10),
                    _RuleRow(icon: Icons.save_rounded, color: Colors.greenAccent,
                        text: 'Save: also keeps your name and online scores (handy when changing phones)'),
        ]),
        // Version (appli Rétro Jump seule) + vérification manuelle des mises à jour
        if (lbAppVersion.isNotEmpty) ...[
          const SizedBox(height: 16),
          Center(child: Text('Retro Jump v$lbAppVersion',
              style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600))),
          if (lbCheckUpdate != null)
            Center(child: TextButton.icon(
              onPressed: () async {
                final r = await lbCheckUpdate!();
                if (!mounted) return;
                if (r == 0) _snack('You have the latest version', ok: true);
                if (r == 2) _snack('Offline: unable to check');
              },
              icon: const Icon(Icons.system_update_rounded, size: 18),
              label: const Text('Check for updates'),
            )),
        ],
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
          // Name always shown (greyed out while locked)
          Text(_heroNames[i],
                style: TextStyle(
                  color: locked ? Colors.white38 : selected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                )),
          if (locked)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const _CoinIcon(size: 11),
              const SizedBox(width: 3),
              Text('${_heroPrices[i]}',
                  style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w700)),
            ])
          else
            const SizedBox(height: 14), // same height as the price row
        ]),
      ),
    );
  }
}

// ─── Small widgets ───────────────────────────────────────────────────────────

/// Temps restant avant le prochain défi du jour (minuit, heure du téléphone).
class _DailyCountdown extends StatefulWidget {
  final Color color;
  final String prefix;
  final bool weekly; // jusqu'à lundi minuit (défi semaine)
  const _DailyCountdown({required this.color, required this.prefix, this.weekly = false});

  @override
  State<_DailyCountdown> createState() => _DailyCountdownState();
}

class _DailyCountdownState extends State<_DailyCountdown> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final left = DateTime(now.year, now.month, now.day + (widget.weekly ? 8 - now.weekday : 1)).difference(now);
    String two(int v) => v.toString().padLeft(2, '0');
    final days = left.inDays;
    final txt = '${days > 0 ? '$days d ' : ''}${two(left.inHours % 24)}:${two(left.inMinutes % 60)}:${two(left.inSeconds % 60)}';
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text('${widget.prefix}$txt',
          maxLines: 1,
          style: TextStyle(
            color: widget.color.withOpacity(0.9),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
          )),
    );
  }
}

/// Écran de démarrage : ciel de nuit, titre, héros qui rebondit sur une cartouche.
class _SplashView extends StatefulWidget {
  final int hero;
  final bool loading;
  final List<LbEntry> podium;   // 3 meilleurs scores (vide tant que non chargés)
  final String podiumTitle;
  final String title1, title2, loadingText, tapText;
  const _SplashView({required this.hero, required this.loading, required this.title1, required this.title2,
      required this.loadingText, required this.tapText, this.podium = const [], this.podiumTitle = ''});

  @override
  State<_SplashView> createState() => _SplashViewState();
}

class _SplashViewState extends State<_SplashView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Podium : 2ᵉ à gauche, 1ᵉʳ au centre (plus haut), 3ᵉ à droite.
  Widget _podiumView() {
    const colors = [Color(0xFFFFD54F), Color(0xFFCFD8DC), Color(0xFFCD7F32)];
    const heights = [78.0, 56.0, 40.0];
    Widget place(int i) {
      if (i >= widget.podium.length) return const SizedBox(width: 104);
      final e = widget.podium[i];
      final c = colors[i];
      return SizedBox(
        width: 104,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (i == 0) const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD54F), size: 22),
          SizedBox(width: 50, height: 46, child: Stack(clipBehavior: Clip.none, children: [
            _Avatar(code: e.avatar, hero: e.hero, size: 42),
            // Héros du record en pastille (si l'avatar le remplace)
            if (_avParse(e.avatar) != null)
              Positioned(right: -2, bottom: -2, child: SizedBox(width: 20, height: 18,
                  child: CustomPaint(painter: _HeroPreviewPainter(min(max(e.hero, 0), _heroCount - 1))))),
          ])),
          const SizedBox(height: 4),
          Text(e.name,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c, fontSize: 13, fontWeight: FontWeight.w800)),
          Text(_fmtNum(e.score),
              style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Container(
            width: 96,
            height: heights[i],
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [c.withOpacity(0.85), c.withOpacity(0.35)],
              ),
              boxShadow: [BoxShadow(color: c.withOpacity(0.35), blurRadius: 14)],
            ),
            child: Text('${i + 1}',
                style: const TextStyle(color: Color(0xFF0D0F14), fontSize: 26, fontWeight: FontWeight.w900)),
          ),
        ]),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(widget.podiumTitle,
          style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2)),
      const SizedBox(height: 8),
      Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        place(1),
        const SizedBox(width: 4),
        place(0),
        const SizedBox(width: 4),
        place(2),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D1B3E), Color(0xFF1A2A5E), Color(0xFF0D0F14)],
          stops: [0, 0.6, 1],
        ),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          final jump = sin(t * pi);                // 0 → 1 → 0 : un saut par cycle
          final squash = t < 0.12 || t > 0.88 ? 1.0 - jump : 0.0;
          return CustomPaint(
            painter: _SplashSkyPainter(_c.lastElapsedDuration?.inMilliseconds ?? 0),
            child: SafeArea(
              child: Column(children: [
                const Spacer(flex: 3),
                // Titre
                ShaderMask(
                  shaderCallback: (r) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFFFFDE7), Color(0xFFFFD54F)],
                  ).createShader(r),
                  child: Column(children: [
                    Text(widget.title1,
                        style: const TextStyle(color: Colors.white, fontSize: 60, fontWeight: FontWeight.w900, height: 1.0,
                            letterSpacing: 2, shadows: [Shadow(color: Color(0xFF0D0F14), blurRadius: 0, offset: Offset(0, 5))])),
                    Text(widget.title2,
                        style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.w900, height: 1.0,
                            letterSpacing: 4, shadows: [Shadow(color: Color(0xFF0D0F14), blurRadius: 0, offset: Offset(0, 6))])),
                  ]),
                ),
                const SizedBox(height: 10),
                const Text('by foclabroc',
                    style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 1.5)),
                const Spacer(flex: 1),
                // Héros qui rebondit + cartouche (réduit si l'écran est petit)
                Expanded(flex: 4, child: FittedBox(child: SizedBox(
                  width: 160,
                  height: 190,
                  child: Stack(alignment: Alignment.bottomCenter, children: [
                    Positioned(
                      bottom: 22 + jump * 110,
                      child: Transform.scale(
                        scaleX: 1 + squash * 0.15,
                        scaleY: 1 - squash * 0.15,
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(width: 84, height: 72,
                            child: CustomPaint(painter: _HeroPreviewPainter(widget.hero))),
                      ),
                    ),
                    Container(
                      width: 130, height: 18,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEC407A),
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [BoxShadow(color: const Color(0xFFEC407A).withOpacity(0.5), blurRadius: 18)],
                      ),
                    ),
                  ]),
                ))),
                const SizedBox(height: 14),
                // Podium des 3 meilleurs scores (apparaît dès qu'il est chargé)
                AnimatedOpacity(
                  opacity: widget.podium.isEmpty ? 0 : 1,
                  duration: const Duration(milliseconds: 500),
                  child: SizedBox(
                    height: 190,
                    child: FittedBox(child: _podiumView()),
                  ),
                ),
                const SizedBox(height: 18),
                // Chargement
                SizedBox(
                  width: 160,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: widget.loading
                        ? const LinearProgressIndicator(minHeight: 4, backgroundColor: Colors.white10, color: Color(0xFFFFD54F))
                        : const LinearProgressIndicator(value: 1, minHeight: 4, backgroundColor: Colors.white10, color: Color(0xFFFFD54F)),
                  ),
                ),
                const SizedBox(height: 10),
                Opacity(
                  opacity: widget.loading ? 0.6 : 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 2 * pi)),
                  child: Text(widget.loading ? widget.loadingText : widget.tapText,
                      style: TextStyle(
                        color: widget.loading ? Colors.white38 : const Color(0xFFFFD54F),
                        fontSize: widget.loading ? 12 : 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      )),
                ),
                const SizedBox(height: 28),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Étoiles qui scintillent + lune (écran de démarrage).
class _SplashSkyPainter extends CustomPainter {
  final int ms;
  _SplashSkyPainter(this.ms);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Random(7);
    final tw = ms / 1000.0;
    for (int i = 0; i < 70; i++) {
      final x = r.nextDouble() * size.width, y = r.nextDouble() * size.height * 0.85;
      final a = 0.25 + 0.6 * (0.5 + 0.5 * sin(tw * (1 + r.nextDouble() * 2) + i));
      canvas.drawCircle(Offset(x, y), 0.6 + r.nextDouble() * 1.6, Paint()..color = Colors.white.withOpacity(a.clamp(0.0, 1.0)));
    }
    final moon = Offset(size.width * 0.82, size.height * 0.12);
    canvas.drawCircle(moon, 60, Paint()
      ..shader = RadialGradient(colors: [const Color(0xFFFFF59D).withOpacity(0.35), const Color(0x00FFF59D)])
          .createShader(Rect.fromCircle(center: moon, radius: 60)));
    canvas.drawCircle(moon, 26, Paint()..color = const Color(0xFFF5F5DC));
    canvas.drawCircle(moon + const Offset(-8, -5), 5, Paint()..color = Colors.black.withOpacity(0.12));
    canvas.drawCircle(moon + const Offset(9, 8), 6.5, Paint()..color = Colors.black.withOpacity(0.12));
  }

  @override
  bool shouldRepaint(covariant _SplashSkyPainter old) => old.ms != ms;
}

/// Pastille de niveau (couleur du rang).
class _LevelBadge extends StatelessWidget {
  final int level;
  final double size;
  const _LevelBadge({required this.level, this.size = 18});

  @override
  Widget build(BuildContext context) {
    final c = _rankFor(level).$2;
    return Container(
      width: size, height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withOpacity(0.18),
        shape: BoxShape.circle,
        border: Border.all(color: c, width: size >= 30 ? 2 : 1.2),
      ),
      child: Padding(
        padding: EdgeInsets.all(size * 0.14),
        child: FittedBox(
          child: Text('$level', style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: size * 0.5)),
        ),
      ),
    );
  }
}

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
      final label = s.coins > 0 ? '${s.coins}' : const ['500↑', '1000↑', '🛡️', '🚀', '❤️', '', '🎁'][s.bonus];
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
        boxShadow: theme == 1 || theme == 5 || theme == 6 || theme == 9
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
  final int trail; // chosen jump trail
  final bool haptics;
  final int hapticLvl;     // intensité des vibrations (0 faible, 1 normale, 2 forte)
  final bool tilt;
  final bool ghost;        // fantôme du n°1 (partie du jour)
  final double touchSens;  // sensibilité tactile
  final double tiltSens;   // sensibilité inclinaison
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
    this.trail = 0,
    required this.haptics,
    this.hapticLvl = 1,
    required this.tilt,
    this.ghost = true,
    this.touchSens = 1.0,
    this.tiltSens = 1.0,
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
  bool get neon => theme == 1 || theme == 5 || theme == 6;

  @override
  State<_JumpGame> createState() => _JumpGameState();
}

class _JumpGameState extends State<_JumpGame> with SingleTickerProviderStateMixin {
  final _shareKey = GlobalKey();
  final _rng = Random();
  Random _gen = Random(); // parcours (graine commune en partie du jour)
  int _runId = 0;
  // Weather
  int _weather = -1;
  double _weatherT = 0, _boltT = 0, _flash = 0;
  int _nextWeatherAt = 1100, _windDir = 1;
  Random _wx = Random();
  // Trail: (x, world y, time, seed)
  final List<(double, double, double, int)> _trailPts = [];
  double get _grip => (_weather == 1 || _weather == 2) ? 0.3 : 1.0; // slippery in the rain
  LbRank? _lbRank;  // rang en ligne après la partie
  int _lbState = 0;  // 0 rien, 1 envoi, 2 reçu, 3 hors ligne
  List<(int, String, int)> _rivals = []; // daily run: (score, name, rank) of other players
  final Set<int> _rivalsPassed = {};
  // Ghost (daily run): path recorded every 0.1 s
  final List<int> _ghX = [], _ghH = [];
  double _ghNext = 0;
  LbGhost? _ghost;              // ghost of the day's #1 (playback)
  Uint16List _gpX = Uint16List(0);
  Int32List _gpH = Int32List(0);
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
  int _xpGain = 0, _xpNow = 0, _lvlFrom = 1, _lvlTo = 1, _lvlReward = 0; // niveau du joueur
  List<_Trophy> _newTrophies = const []; // trophées gagnés à cette partie

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
  bool _spiritUsed = false;    // Fantôme : 2ᵉ chance déjà utilisée
  bool _shieldReserve = false; // 2ᵉ bouclier ramassé : en réserve (bulle en bas, touche pour l'activer)
  Rect _reserveRect = Rect.zero;
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
            // Sensibilité : plus elle est haute, moins il faut pencher pour la vitesse max
            final full = max(_tiltDead + 0.3, _tiltFull / widget.tiltSens);
            _tiltDir = v.abs() < _tiltDead
                ? 0.0
                : ((v.abs() - _tiltDead) / (full - _tiltDead)).clamp(0.0, 1.0).toDouble() * v.sign;
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
    if (day != null && widget.ghost) {
      final g = await Leaderboard.topGhost(day);
      if (g == null || !mounted || g.data.length < 12) return;
      final n = g.data.length ~/ 6;
      final bd = ByteData.sublistView(g.data);
      final xs = Uint16List(n), hs = Int32List(n);
      for (int i = 0; i < n; i++) {
        xs[i] = bd.getUint16(i * 6, Endian.little);
        hs[i] = bd.getInt32(i * 6 + 2, Endian.little);
      }
      setState(() {
        _ghost = g;
        _gpX = xs;
        _gpH = hs;
      });
    }
  }

  /// Encoded ghost (base64) for upload
  String _ghostData() {
    final n = min(_ghX.length, _ghH.length);
    if (n < 2) return '';
    final bd = ByteData(n * 6);
    for (int i = 0; i < n; i++) {
      bd.setUint16(i * 6, _ghX[i], Endian.little);
      bd.setInt32(i * 6 + 2, _ghH[i], Endian.little);
    }
    return base64Encode(bd.buffer.asUint8List());
  }

  /// Ghost position at the current game time (null once its run is over)
  (double, double, String, int, bool)? _ghostPos() {
    final g = _ghost;
    final n = _gpX.length;
    if (g == null || n < 2 || !_started || _w == 0) return null;
    final f = _playTime / 0.1;
    final i = f.floor();
    if (i >= n - 1) return null;
    final t = f - i;
    final x0 = _gpX[i].toDouble(), x1 = _gpX[i + 1].toDouble();
    final x = (x1 - x0).abs() > 500 ? x0 : x0 + (x1 - x0) * t; // edge wrap
    final h = _gpH[i] + (_gpH[i + 1] - _gpH[i]) * t;
    return (x / 1000 * _w, _startY - h, g.name, g.hero, x1 >= x0);
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
    _hapticAt(level, widget.hapticLvl);
  }

  // ── Initialisation ─────────────────────────────────────────────────────────
  void _initGame(double w, double h) {
    _gen = widget.daily != null ? SeededRandom(Leaderboard.seedFor(widget.daily!)) : Random();
    _runId++;
    _rivalsPassed.clear();
    _ghX.clear();
    _ghH.clear();
    _ghNext = 0;
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
    // Weather: same event sequence for everyone in the daily run
    _wx = widget.daily != null ? SeededRandom(Leaderboard.seedFor(widget.daily!) ^ 0x5EED) : Random();
    _weather = -1;
    _weatherT = 0;
    _flash = 0;
    _nextWeatherAt = 1100;
    _trailPts.clear();
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
    _shieldReserve = false;
    _spiritUsed = false;
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
    final touch = _pointers.isNotEmpty || !widget.tilt;
    final dir = touch ? _dir.toDouble() : _tiltDir;
    final ts = touch ? widget.touchSens : 1.0; // sensibilité tactile : vitesse + réactivité
    final target = dir * _moveSpeed * ts * (widget.hero == 1 ? 1.12 : 1.0); // Joystick
    if (_vx < target) {
      _vx = min(target, _vx + _moveAccel * ts * _grip * dt);
    } else if (_vx > target) {
      _vx = max(target, _vx - _moveAccel * ts * _grip * dt);
    }
    _x += _vx * dt;
    if (_weather == 0) _x += _windDir * (80 + 45 * sin(_time * 1.7)) * dt; // wind
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
      // Fin du turbo : 2 s de bouclier (bulle clignotante) pour ne pas retomber sur un bug
      if (_turbo <= 0 && _launchTo <= 0) _invuln = max(_invuln, 2.0);
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
    // Ghost: position recorded every 0.1 s (daily run)
    if (widget.daily != null) {
      while (_playTime >= _ghNext && _ghX.length < 6000) {
        _ghX.add(((_x / max(1.0, _w)).clamp(0.0, 1.0) * 1000).round());
        _ghH.add((_startY - _y).round());
        _ghNext += 0.1;
      }
    }
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
        // Plateforme sous le bas de l'écran (invisible) : pas de rebond
        if (p.y > _camY + _h - 6) continue;
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
        if (widget.daily == null) _coinsRun += widget.hero == 12 ? 6 : 3; // Manette : ×2
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
        if (_shield) {
          // Déjà protégé : le bouclier part en réserve (1 au maximum)
          if (!_shieldReserve) _showBanner('🛡️ SHIELD IN RESERVE');
          _shieldReserve = true;
        } else {
          _shield = true;
        }
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
        _collection[lg.idx] += widget.hero == 13 ? 2 : 1; // Portable : compte double
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

    // Dynamic weather
    if (_score >= _nextWeatherAt) {
      _nextWeatherAt += 1000;
      _weather = _wx.nextInt(4);
      _windDir = _wx.nextBool() ? 1 : -1;
      _weatherT = _weatherDur;
      _boltT = 1.5;
      _showBanner(_weatherBanners[_weather]);
      QuizAudio.sfx('powerup');
      _haptic(1);
    }
    if (_weatherT > 0) {
      _weatherT = max(0, _weatherT - dt);
      if (_weatherT == 0) _weather = -1;
    }
    if (_flash > 0) _flash = max(0, _flash - dt);
    if (_weather == 2) {
      _boltT -= dt;
      if (_boltT <= 0) {
        // Lightning: flash + coins falling from the sky (normal game)
        _boltT = 2.5 + _rng.nextDouble() * 2.5;
        _flash = 0.3;
        _haptic(1);
        if (widget.daily == null) {
          for (int k = 0; k < 3; k++) {
            _coinList.add(_Coin((_x + (k - 1) * 26).clamp(14.0, max(14.0, _w - 14)), _camY + 70 + k * 6));
          }
        }
      }
    }
    // Jump trail
    if (widget.trail > 0) {
      final last = _trailPts.isEmpty ? null : _trailPts.last;
      if (last == null || (last.$1 - _x).abs() + (last.$2 - (_y - 14)).abs() > 5) {
        _trailPts.add((_x, _y - 14, _time, _trailPts.length + _jumps * 7));
      }
      _trailPts.removeWhere((p) => _time - p.$3 > 0.45);
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
    // Fantôme : une 2ᵉ chance gratuite par partie (hors partie du jour)
    if (widget.hero == 14 && widget.daily == null && !_spiritUsed) {
      _spiritUsed = true;
      final keep = _freeCont;
      _offer = true;
      _freeCont = true;
      _acceptContinue();
      _freeCont = keep;
      _showBanner('👻 SECOND CHANCE!');
      return;
    }
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
      if (widget.daily != null) add('dailies', 1);
      st['combo'] = max(((st['combo'] as num?) ?? 0).toInt(), _bestCombo);
      // Série de jours joués d'affilée
      final now = DateTime.now();
      final d = now.year * 10000 + now.month * 100 + now.day;
      final last = (st['last_day'] as num?)?.toInt() ?? 0;
      if (last != d) {
        final y = now.subtract(const Duration(days: 1));
        final yd = y.year * 10000 + y.month * 100 + y.day;
        final streak = last == yd ? ((st['streak'] as num?)?.toInt() ?? 0) + 1 : 1;
        st['streak'] = streak;
        st['last_day'] = d;
        st['streak_best'] = max(((st['streak_best'] as num?) ?? 0).toInt(), streak);
      }
      await prefs.setString(_kStatsKey, jsonEncode(st));
    } catch (_) {}
  }

  Future<void> _saveRun() async {
    await _saveStats();
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
    var earned = _coinsRun + rewards + bonus + albumBonus;
    // XP : niveau(x) gagné(s) = pièces offertes
    final xpGain = (_runXp(_score, newOnes.length, widget.daily != null) * (widget.hero == 15 ? 1.25 : 1.0)).round(); // Casque : +25 %
    var xpNow = 0, lvlFrom = 1, lvlTo = 1, lvlReward = 0;
    var newTrophies = <_Trophy>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final xp0 = await _readXp(prefs);
      xpNow = xp0 + xpGain;
      lvlFrom = _levelFor(xp0);
      lvlTo = _levelFor(xpNow);
      for (var l = lvlFrom + 1; l <= lvlTo; l++) {
        lvlReward += _levelReward(l);
      }
      await prefs.setInt(_kXpKey, xpNow);
      earned += lvlReward;
      // Trophées (la toute 1re vérification se fait à l'accueil, sans pièces)
      if (prefs.getStringList(_kTrophyKey) != null) {
        await prefs.setInt(_kChallengeLvlKey, _chLevel);
        newTrophies = await _unlockTrophies(score: _score);
        earned += newTrophies.fold<int>(0, (a, x) => a + _tierReward[x.tier]);
      }
      final net = earned - _spent;
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
      _xpGain = xpGain;
      _xpNow = xpNow;
      _lvlFrom = lvlFrom;
      _lvlTo = lvlTo;
      _lvlReward = lvlReward;
      _newTrophies = newTrophies;
      _resultsReady = true;
    });
    if (newOnes.isNotEmpty || lvlTo > lvlFrom || newTrophies.isNotEmpty) QuizAudio.win();
    _submitOnline();
  }

  /// Classement en ligne : meilleur score de tous les temps (+ partie du jour).
  Future<void> _submitOnline() async {
    final run = _runId;
    final day = widget.daily;
    final score = _score;
    final time = max(1, _playTime.round());
    final ghostData = day != null ? _ghostData() : '';
    var newDayBest = false;
    if (day != null) {
      // Meilleur score du jour en local (affiché sur l'accueil)
      try {
        final prefs = await SharedPreferences.getInstance();
        final p = (prefs.getString(_kDailyKey) ?? '').split('|');
        final best = p.length >= 2 && p[0] == day ? int.tryParse(p[1]) ?? 0 : 0;
        if (score > best) {
          newDayBest = true;
          await prefs.setString(_kDailyKey, '$day|$score');
        }
      } catch (_) {}
    }
    if (!Leaderboard.configured || score <= 0) return;
    if (mounted && run == _runId) setState(() => _lbState = 1);
    var name = await Leaderboard.name();
    if (name == null) {
      name = 'Player-${(await Leaderboard.publicId()).substring(0, 4).toUpperCase()}';
      await Leaderboard.setLocalName(name);
    }
    // Solo : parties normales seulement (le défi du jour a son propre classement)
    final all = day != null
        ? null
        : Leaderboard.submit(mode: 'all', day: lbAllDay, score: score, hero: widget.hero, time: time, name: name);
    final daily = day == null
        ? null
        : Leaderboard.submit(mode: 'daily', day: day, score: score, hero: widget.hero, time: time, name: name);
    final rAll = all == null ? null : await all;
    final rDay = daily == null ? null : await daily;
    if (day != null && rDay != null && newDayBest) await Leaderboard.uploadGhost(day, score, ghostData);
    await _syncProfile(_wallet); // Player's coins, shown on the leaderboard
    final r = day == null ? rAll : rDay;
    final wRank = rAll?.rank;
    if (rAll != null && wRank != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kWorldRankKey, '$wRank|${rAll.total}');
      } catch (_) {}
    }
    final rank = r?.rank;
    if (day != null && rank != null && rank <= 3) {
      await _bumpStat('top3', atLeast: 1);
      if (rank == 1) await _bumpStat('daily1', atLeast: 1);
    }
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

  /// Résultats : XP gagnée, barre de niveau, niveau atteint + récompense.
  Widget _xpPanel() {
    final lvl = _lvlTo;
    final rk = _rankFor(lvl);
    final base = _xpForLevel(lvl), next = _xpForLevel(lvl + 1);
    final frac = lvl >= _kMaxLevel ? 1.0 : ((_xpNow - base) / (next - base)).clamp(0.0, 1.0);
    final up = _lvlTo > _lvlFrom;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: rk.$2.withOpacity(up ? 0.14 : 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: rk.$2.withOpacity(up ? 0.8 : 0.35), width: up ? 1.5 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _LevelBadge(level: lvl, size: 36),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(up ? 'Level $lvl reached!' : 'Level $lvl',
                style: TextStyle(color: up ? rk.$2 : Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            Text(rk.$1, style: TextStyle(color: rk.$2, fontSize: 12, fontWeight: FontWeight.w700)),
          ])),
          Text('+${_fmtNum(_xpGain)} XP',
              style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 16, fontWeight: FontWeight.w900)),
        ]),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(value: frac, minHeight: 8, backgroundColor: Colors.white10, color: rk.$2),
        ),
        const SizedBox(height: 4),
        Text(lvl >= _kMaxLevel
                ? 'Max level!'
                : '${_fmtNum(_xpNow - base)} / ${_fmtNum(next - base)} XP  ·  level ${lvl + 1}',
            style: const TextStyle(color: Colors.white54, fontSize: 11)),
        if (up && _lvlReward > 0) ...[
          const SizedBox(height: 8),
          Row(children: [
            const _CoinIcon(size: 16),
            const SizedBox(width: 8),
            const Expanded(child: Text('Level reward', style: TextStyle(color: Colors.white, fontSize: 13))),
            Text('+$_lvlReward',
                style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w800)),
          ]),
        ],
      ]),
    );
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
    // Bulle du bouclier en réserve : l'activer (ne compte pas comme un déplacement)
    if (_shieldReserve && !_paused && _reserveRect.inflate(10).contains(e.localPosition)) {
      _useReserve();
      return;
    }
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

  void _useReserve() {
    if (_shield) return; // déjà protégé : la réserve attend
    setState(() {
      _shield = true;
      _shieldReserve = false;
    });
    _burst(Offset(_x, _y - _heroH / 2), Colors.cyanAccent, 16);
    QuizAudio.sfx('shield');
    _haptic(2);
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
    _reserveRect = Rect.fromCenter(center: Offset(w / 2, h - 62), width: 64, height: 64);
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
            disco: widget.theme == 6,
            theme: widget.theme,
            trailKind: widget.trail,
            trailPts: _trailPts,
            weather: _weather,
            weatherAlpha: _weather < 0 ? 0.0 : min(1.0, min(_weatherT / 1.5, (_weatherDur - _weatherT) / 1.5)),
            windDir: _windDir,
            flash: _flash,
            startY: _startY,
            recordY: widget.bestScore > 0 ? _startY - widget.bestScore * 10 : null,
            rivals: _rivals,
            ghost: _ghostPos(),
          ),
        )),

        // Bouclier en réserve (bulle en bas au milieu ; grisée tant qu'un bouclier est actif)
        if (_shieldReserve)
          Positioned(
            left: w / 2 - 32,
            bottom: 30,
            child: IgnorePointer(
              child: Opacity(
                opacity: _shield ? 0.45 : 1,
                child: Transform.scale(
                  scale: _shield ? 1.0 : 1.0 + 0.07 * sin(_time * 6),
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        Colors.cyanAccent.withOpacity(0.55),
                        const Color(0xFF006064).withOpacity(0.85),
                      ]),
                      border: Border.all(color: Colors.white.withOpacity(0.85), width: 2),
                      boxShadow: [BoxShadow(color: Colors.cyanAccent.withOpacity(_shield ? 0.2 : 0.6), blurRadius: 18)],
                    ),
                    child: const Icon(Icons.shield_rounded, color: Colors.white, size: 32),
                  ),
                ),
              ),
            ),
          ),

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

        // Current weather
        if (_weather >= 0)
          Positioned(
            top: 88, left: 72,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.lightBlueAccent.withOpacity(0.6)),
              ),
              child: Text('${_weatherIcons[_weather]} ${_weatherNames[_weather]} ${_weatherT.ceil()}s',
                  style: const TextStyle(color: Colors.lightBlueAccent, fontSize: 11, fontWeight: FontWeight.w800)),
            ),
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

    // Boutons Accueil / Rejouer fixés en bas, le reste défile
    return Column(children: [
      Expanded(child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
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
          _xpPanel(),
          const SizedBox(height: 12),
          if (_newTrophies.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD54F).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD54F).withOpacity(0.6), width: 1.3),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.emoji_events_rounded, color: Color(0xFFFFD54F), size: 20),
                  const SizedBox(width: 8),
                  Text(_newTrophies.length == 1 ? 'Trophy unlocked' : 'Trophies unlocked',
                      style: const TextStyle(color: Color(0xFFFFD54F), fontSize: 15, fontWeight: FontWeight.w900)),
                ]),
                for (final x in _newTrophies) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(x.icon, color: _tierColors[x.tier], size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(x.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
                      Text(x.desc, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                    ])),
                    Text('+${_tierReward[x.tier]}',
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.w800)),
                  ]),
                ],
              ]),
            ),
            const SizedBox(height: 12),
          ],
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
      ]),
      )),
      Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 12 + MediaQuery.of(context).padding.bottom),
        child: Row(children: [
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
      ),
    ]);
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

const _heroCount = 16;
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
    case 12:
      _drawPad(c, right, time);
      break;
    case 13:
      _drawHandheld(c, right, time);
      break;
    case 14:
      _drawGhostHero(c, right, time);
      break;
    case 15:
      _drawHeadset(c, right, time);
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

/// Manette : corps gris arrondi, croix directionnelle, boutons, fil qui ondule.
void _drawPad(Canvas c, bool right, double time) {
  final s = right ? -1.0 : 1.0;
  c.drawPath(
    Path()
      ..moveTo(0, -30)
      ..cubicTo(s * 3, -40, s * 12, -40, s * 11 + sin(time * 6) * 2, -48),
    Paint()
      ..color = const Color(0xFF455A64)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2,
  );
  // Poignées + corps
  _circle(c, -14, -12, 9, const Color(0xFF9EA7B0));
  _circle(c, 14, -12, 9, const Color(0xFF9EA7B0));
  _rr(c, -21, -31, 42, 22, 9, const Color(0xFFB8C0C8));
  _rr(c, -21, -31, 42, 4, 2, Colors.white.withOpacity(0.35));
  // Croix directionnelle
  _rr(c, -17, -22, 10, 3.4, 1, const Color(0xFF263238));
  _rr(c, -13.7, -25.3, 3.4, 10, 1, const Color(0xFF263238));
  // Boutons A / B
  _circle(c, 11, -19, 2.8, _heroRed);
  _circle(c, 16.5, -22.5, 2.8, _heroRed);
  // Yeux au centre
  _eyes(c, -3, 3.5, -24, 2.6, right);
  _rr(c, -4, -15, 8, 1.8, 1, const Color(0xFF546E7A));
}

/// Console portable : boîtier clair, écran vert où se trouve le visage.
void _drawHandheld(Canvas c, bool right, double time) {
  _legs(c, const Color(0xFF616161));
  _rr(c, -15, -47, 30, 44, 5, const Color(0xFFCFCFC8));
  _rr(c, -15, -47, 30, 3, 2, Colors.white.withOpacity(0.5));
  _rr(c, -12, -43, 24, 19, 3, const Color(0xFF545A63));
  _rr(c, -10, -41, 20, 15, 1.5, const Color(0xFF9BBC0F));
  // Visage pixelisé sur l'écran
  final px = Paint()..color = const Color(0xFF0F380F);
  final lx = right ? 1.0 : -1.0;
  final blink = (time % 3.1) < 0.13;
  c.drawRect(Rect.fromLTWH(-6 + lx, blink ? -36 : -37.5, 3, blink ? 1 : 3), px);
  c.drawRect(Rect.fromLTWH(3 + lx, blink ? -36 : -37.5, 3, blink ? 1 : 3), px);
  c.drawRect(const Rect.fromLTWH(-4, -31, 8, 1.6), px);
  c.drawRect(const Rect.fromLTWH(-5.4, -32.4, 1.6, 1.6), px);
  c.drawRect(const Rect.fromLTWH(3.8, -32.4, 1.6, 1.6), px);
  // Croix + boutons + haut-parleur
  _rr(c, -11, -18, 9, 3, 1, const Color(0xFF263238));
  _rr(c, -8, -21, 3, 9, 1, const Color(0xFF263238));
  _circle(c, 6, -15, 2.6, const Color(0xFF9C2463));
  _circle(c, 11, -18, 2.6, const Color(0xFF9C2463));
  for (int i = 0; i < 3; i++) {
    c.drawLine(Offset(5 + i * 3.0, -8), Offset(8 + i * 3.0, -11), Paint()
      ..color = const Color(0xFF8D8D86)
      ..strokeWidth = 1.2);
  }
}

/// Fantôme : drap arrondi, bas ondulé, flotte doucement.
void _drawGhostHero(Canvas c, bool right, double time) {
  final bob = sin(time * 3) * 1.5;
  final wave = time * 6;
  final p = Path()
    ..moveTo(-16, -6 + bob)
    ..lineTo(-16, -26 + bob)
    ..arcToPoint(Offset(16, -26 + bob), radius: const Radius.circular(16))
    ..lineTo(16, -6 + bob);
  for (int i = 0; i < 4; i++) {
    final x0 = 16 - i * 8.0;
    p.quadraticBezierTo(x0 - 4, -6 + bob + (i.isEven ? 5 : -1) + sin(wave + i) * 1.5, x0 - 8, -6 + bob);
  }
  p.close();
  c.drawPath(p, Paint()..color = const Color(0xFFF3EEFF).withOpacity(0.95));
  c.drawPath(p, Paint()
    ..color = const Color(0xFFB39DDB)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4);
  _eyes(c, -5.5, 5.5, -27 + bob, 3.6, right);
  _circle(c, -10, -20 + bob, 2.4, const Color(0xFFFF8FB1).withOpacity(0.6));
  _circle(c, 10, -20 + bob, 2.4, const Color(0xFFFF8FB1).withOpacity(0.6));
  c.drawOval(Rect.fromCenter(center: Offset(0, -18.5 + bob), width: 5, height: 4), Paint()..color = const Color(0xFF4A3A6B));
}

/// Casque audio : tête ronde, arceau et écouteurs rouges, notes de musique.
void _drawHeadset(Canvas c, bool right, double time) {
  _legs(c, const Color(0xFF37474F));
  _circle(c, 0, -22, 17, const Color(0xFF29323C));
  _circle(c, -5, -28, 6, Colors.white.withOpacity(0.06));
  c.drawArc(const Rect.fromLTWH(-20, -46, 40, 40), pi * 1.05, pi * 0.9, false, Paint()
    ..color = const Color(0xFF1A1A1A)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.5);
  _rr(c, -23, -31, 8, 17, 3.5, _heroRed);
  _rr(c, 15, -31, 8, 17, 3.5, _heroRed);
  _rr(c, -22, -30, 3, 15, 1.5, Colors.white.withOpacity(0.3));
  _eyes(c, -5, 5, -23, 3.4, right);
  c.drawArc(const Rect.fromLTWH(-5, -19, 10, 7), 0.2, pi - 0.4, false, Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6
    ..strokeCap = StrokeCap.round);
  // Note de musique qui s'élève
  final t = (time * 0.8) % 1;
  final np = Offset((right ? 20 : -20) + sin(time * 4) * 2, -38 - t * 16);
  final nc = const Color(0xFFFFD740).withOpacity(1 - t);
  c.drawCircle(np, 2.4, Paint()..color = nc);
  c.drawLine(np.translate(2.2, 0), np.translate(2.2, -8), Paint()
    ..color = nc
    ..strokeWidth = 1.4);
}

/// Hero preview (selector, results screen).
// ─── Avatars façon Mii ────────────────────────────────────────────────────────
// Code de 8 caractères (base 36) : peau, visage, coiffure, couleur des cheveux,
// yeux, bouche, accessoire, fond. Quelques octets côté serveur.
const _avCounts = [12, 6, 20, 16, 12, 12, 14, 16];
const _avSkin = [0xFFFFE0C4, 0xFFF5C9A0, 0xFFE0A878, 0xFFC68A5A, 0xFF8D5A3B, 0xFF5C3A24,
    0xFFFDEDE2, 0xFFD9A066, 0xFFB07A4F, 0xFF6E4630, 0xFF9CCC65, 0xFF81D4FA];
const _avHair = [0xFF1E1A18, 0xFF5A3825, 0xFF8B5A2B, 0xFFE5C26B, 0xFFB5462A, 0xFFB8B8C0, 0xFF3F7CFF, 0xFFFF6FB5,
    0xFFF5F5F5, 0xFFF0E2B6, 0xFF3B2416, 0xFF7B2E1E, 0xFF43A047, 0xFF8E44D9, 0xFF00BFA5, 0xFFFF8F00];
const _avBg = [0xFF3949AB, 0xFF00897B, 0xFFE53935, 0xFFFB8C00, 0xFF8E24AA, 0xFF43A047, 0xFF546E7A, 0xFFFFB300,
    0xFFEC407A, 0xFF00ACC1, 0xFF6D4C41, 0xFF1A237E, 0xFF7CB342, 0xFF37474F, 0xFF5E35B1, 0xFFF4511E];

List<int>? _avParse(String? c) {
  if (c == null || c.length != 8) return null;
  final out = <int>[];
  for (int i = 0; i < 8; i++) {
    final v = int.tryParse(c[i], radix: 36);
    if (v == null) return null;
    out.add(v % _avCounts[i]);
  }
  return out;
}

String _avCode(List<int> a) => a.map((v) => v.toRadixString(36)).join();
List<int> _avRandom(Random r) => [for (final n in _avCounts) r.nextInt(n)];

/// Avatar du joueur, ou son héros s'il n'en a pas créé.
class _Avatar extends StatelessWidget {
  final String? code;
  final int hero;
  final double size;
  const _Avatar({this.code, this.hero = 0, required this.size});

  @override
  Widget build(BuildContext context) {
    final a = _avParse(code);
    return SizedBox(
      width: size,
      height: size,
      child: a == null
          ? Padding(
              padding: EdgeInsets.all(size * 0.06),
              child: CustomPaint(painter: _HeroPreviewPainter(min(max(hero, 0), _heroCount - 1))))
          : CustomPaint(painter: _MiiPainter(a)),
    );
  }
}

/// Coupes de la semaine, médailles du jour (or, argent, bronze) et de participation ; « — » si rien.
class _Cups extends StatelessWidget {
  final int gold, silver, bronze, medals, mGold, mSilver, mBronze, stars;
  final double size;
  const _Cups({required this.gold, required this.silver, required this.bronze, required this.medals,
      this.mGold = 0, this.mSilver = 0, this.mBronze = 0, this.stars = 0, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.emoji_events_rounded, const Color(0xFFFFD54F), gold),
      (Icons.emoji_events_rounded, const Color(0xFFCFD8DC), silver),
      (Icons.emoji_events_rounded, const Color(0xFFE0904F), bronze),
      (Icons.star_rounded, const Color(0xFFFFEB3B), stars),
      (Icons.military_tech_rounded, const Color(0xFFFFD54F), mGold),
      (Icons.military_tech_rounded, const Color(0xFFCFD8DC), mSilver),
      (Icons.military_tech_rounded, const Color(0xFFE0904F), mBronze),
      (Icons.verified_rounded, const Color(0xFF80DEEA), medals),
    ].where((x) => x.$3 > 0).toList();
    if (items.isEmpty) {
      return Text('—', style: TextStyle(color: Colors.white38, fontSize: size, fontWeight: FontWeight.w800));
    }
    // Passe à la ligne si le palmarès est trop long
    return Wrap(alignment: WrapAlignment.end, spacing: size * 0.4, runSpacing: 2, children: [
      for (final (icon, color, count) in items)
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: size + 2),
          Text('$count', style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w900)),
        ]),
    ]);
  }
}

class _MiiPainter extends CustomPainter {
  final List<int> a;
  const _MiiPainter(this.a);

  static Path _heart(Offset c, double r) => Path()
    ..moveTo(c.dx, c.dy + r * 0.9)
    ..cubicTo(c.dx - r * 1.6, c.dy - r * 0.2, c.dx - r * 0.6, c.dy - r * 1.3, c.dx, c.dy - r * 0.4)
    ..cubicTo(c.dx + r * 0.6, c.dy - r * 1.3, c.dx + r * 1.6, c.dy - r * 0.2, c.dx, c.dy + r * 0.9)
    ..close();

  static Path _star(Offset c, double r) {
    final p = Path();
    for (int i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final an = -pi / 2 + i * pi / 5;
      final pt = c + Offset(cos(an) * rr, sin(an) * rr);
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    final skin = Color(_avSkin[a[0]]);
    final skinD = Color.lerp(skin, Colors.black, 0.18)!;
    final hairC = Color(_avHair[a[3]]);
    final bg = Color(_avBg[a[7]]);
    const dark = Color(0xFF1B1B24);
    final accent = (a[7] == 2 || a[7] == 15 || a[7] == 8) ? const Color(0xFF1E88E5) : const Color(0xFFE53935);
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s, s), Radius.circular(s * 0.28));
    canvas.clipRRect(box);
    canvas.drawRRect(box, Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, s),
          [Color.lerp(bg, Colors.white, 0.18)!, Color.lerp(bg, Colors.black, 0.22)!]));

    final c = Offset(s * 0.5, s * 0.5);
    final face = a[1];
    final hw = s * const [0.52, 0.46, 0.52, 0.52, 0.58, 0.44][face];
    final hh = s * const [0.54, 0.58, 0.54, 0.55, 0.50, 0.60][face];
    final head = Rect.fromCenter(center: c, width: hw, height: hh);
    final Path headPath;
    switch (face) {
      case 2:
        headPath = Path()..addRRect(RRect.fromRectAndRadius(head, Radius.circular(s * 0.11)));
        break;
      case 5:
        headPath = Path()..addRRect(RRect.fromRectAndRadius(head, Radius.circular(s * 0.16)));
        break;
      case 3: // en cœur
        headPath = Path()
          ..moveTo(c.dx, head.bottom)
          ..cubicTo(head.left + hw * 0.15, head.bottom - hh * 0.1, head.left, c.dy + hh * 0.1, head.left, c.dy - hh * 0.05)
          ..cubicTo(head.left, head.top - hh * 0.02, head.right, head.top - hh * 0.02, head.right, c.dy - hh * 0.05)
          ..cubicTo(head.right, c.dy + hh * 0.1, head.right - hw * 0.15, head.bottom - hh * 0.1, c.dx, head.bottom)
          ..close();
        break;
      default:
        headPath = Path()..addOval(head);
    }
    final hairP = Paint()..color = hairC;
    final style = a[2], extra = a[6];

    // Épaules + cou
    canvas.drawOval(Rect.fromLTRB(s * 0.12, s * 0.8, s * 0.88, s * 1.25), Paint()..color = Color.lerp(bg, Colors.black, 0.45)!);
    canvas.drawRect(Rect.fromCenter(center: Offset(c.dx, head.bottom + s * 0.03), width: s * 0.14, height: s * 0.1),
        Paint()..color = skinD);

    void longBack(double bottom) => canvas.drawRRect(RRect.fromRectAndRadius(
        Rect.fromLTRB(head.left - s * 0.04, head.top - s * 0.02, head.right + s * 0.04, bottom),
        Radius.circular(s * 0.14)), hairP);

    // Cheveux (arrière)
    switch (style) {
      case 4: // longs
      case 19: // longs + frange
        longBack(c.dy + hh * 0.62);
        break;
      case 13: // longs ondulés
        longBack(c.dy + hh * 0.55);
        for (int k = 0; k < 3; k++) {
          canvas.drawCircle(Offset(head.left - s * 0.02 + k * s * 0.03, c.dy + hh * 0.58 + (k % 2) * s * 0.02), s * 0.045, hairP);
          canvas.drawCircle(Offset(head.right + s * 0.02 - k * s * 0.03, c.dy + hh * 0.58 + (k % 2) * s * 0.02), s * 0.045, hairP);
        }
        break;
      case 5: // carré
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTRB(head.left - s * 0.035, head.top - s * 0.02, head.right + s * 0.035, c.dy + hh * 0.28),
            Radius.circular(s * 0.1)), hairP);
        break;
      case 6: // queue de cheval
        canvas.drawOval(Rect.fromCenter(center: Offset(head.right + s * 0.05, c.dy + hh * 0.05), width: s * 0.13, height: s * 0.3), hairP);
        break;
      case 7: // afro
        canvas.drawCircle(Offset(c.dx, c.dy - hh * 0.12), hw * 0.78, hairP);
        break;
      case 9: // chignons
        canvas.drawCircle(Offset(head.left + hw * 0.1, head.top + s * 0.02), s * 0.08, hairP);
        canvas.drawCircle(Offset(head.right - hw * 0.1, head.top + s * 0.02), s * 0.08, hairP);
        break;
      case 12: // couettes
        for (final sx in const [-1.0, 1.0]) {
          final x = sx < 0 ? head.left - s * 0.04 : head.right + s * 0.04;
          canvas.drawOval(Rect.fromCenter(center: Offset(x, c.dy + hh * 0.18), width: s * 0.1, height: s * 0.24), hairP);
          canvas.drawCircle(Offset(x - sx * s * 0.01, c.dy - hh * 0.06), s * 0.022, Paint()..color = accent);
        }
        break;
      case 16: // tresse
        for (int k = 0; k < 5; k++) {
          canvas.drawOval(Rect.fromCenter(center: Offset(head.right - s * 0.01 + (k.isEven ? 0 : s * 0.01), c.dy + k * s * 0.065),
              width: s * 0.075, height: s * 0.085), hairP);
        }
        break;
      case 18: // chignon haut
        canvas.drawCircle(Offset(c.dx, head.top - s * 0.04), s * 0.065, hairP);
        break;
    }

    // Oreilles + tête
    for (final sx in const [-1.0, 1.0]) {
      canvas.drawCircle(Offset(c.dx + sx * hw / 2, c.dy + s * 0.02), s * 0.045, Paint()..color = skinD);
    }
    final headP = Paint()..color = skin;
    canvas.drawPath(headPath, headP);

    final eyeY = c.dy - hh * 0.02, ex = hw * 0.2;
    final noseY = c.dy + hh * 0.12, mouthY = c.dy + hh * 0.28;

    // Barbe (sous la bouche)
    if (extra == 4) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, noseY + s * 0.01, s, s));
      canvas.drawPath(headPath, hairP);
      canvas.restore();
      canvas.drawOval(Rect.fromCenter(center: Offset(c.dx, mouthY), width: s * 0.17, height: s * 0.07), headP);
    }

    // Joues, taches de rousseur, nez
    final blush = Paint()..color = const Color(0x55FF6F7F);
    canvas.drawCircle(Offset(c.dx - ex * 1.3, noseY + s * 0.01), s * 0.035, blush);
    canvas.drawCircle(Offset(c.dx + ex * 1.3, noseY + s * 0.01), s * 0.035, blush);
    if (extra == 10) {
      final fr = Paint()..color = Color.lerp(skin, const Color(0xFF6D3B1E), 0.55)!;
      for (final sx in const [-1.0, 1.0]) {
        for (final o in const [Offset(-0.02, -0.01), Offset(0.015, -0.015), Offset(0, 0.012), Offset(0.03, 0.008)]) {
          canvas.drawCircle(Offset(c.dx + sx * (ex * 1.25 + o.dx * s), noseY + o.dy * s), s * 0.007, fr);
        }
      }
    }
    canvas.drawPath(Path()
      ..moveTo(c.dx - s * 0.02, noseY)
      ..quadraticBezierTo(c.dx, noseY + s * 0.025, c.dx + s * 0.02, noseY), Paint()
      ..color = skinD
      ..strokeWidth = s * 0.014
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke);

    // Yeux
    final line = Paint()
      ..color = dark
      ..strokeWidth = s * 0.022
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    void roundEye(Offset e, [double r = 0.045]) {
      canvas.drawCircle(e, s * r, Paint()..color = Colors.white);
      canvas.drawCircle(e.translate(0, s * 0.006), s * r * 0.58, Paint()..color = dark);
      canvas.drawCircle(e.translate(-s * 0.009, -s * 0.006), s * 0.008, Paint()..color = Colors.white);
    }
    void happyEye(Offset e) => canvas.drawPath(Path()
      ..moveTo(e.dx - s * 0.035, e.dy + s * 0.01)
      ..quadraticBezierTo(e.dx, e.dy - s * 0.04, e.dx + s * 0.035, e.dy + s * 0.01), line);
    for (final sx in const [-1.0, 1.0]) {
      final e = Offset(c.dx + sx * ex, eyeY);
      if (extra == 11 && sx > 0) continue; // cache-œil
      switch (a[4]) {
        case 0:
          canvas.drawCircle(e, s * 0.028, Paint()..color = dark);
          canvas.drawCircle(e.translate(-s * 0.008, -s * 0.008), s * 0.007, Paint()..color = Colors.white);
          break;
        case 1:
          roundEye(e);
          break;
        case 2:
          happyEye(e);
          break;
        case 3: // endormis
          canvas.drawArc(Rect.fromCircle(center: e, radius: s * 0.03), 0, pi, true, Paint()..color = dark);
          canvas.drawLine(e.translate(-s * 0.04, 0), e.translate(s * 0.04, 0), line);
          break;
        case 4: // clin d'œil
          if (sx < 0) {
            roundEye(e);
          } else {
            happyEye(e);
          }
          break;
        case 5: // manga
          canvas.drawOval(Rect.fromCenter(center: e, width: s * 0.055, height: s * 0.08), Paint()..color = dark);
          canvas.drawCircle(e.translate(-s * 0.01, -s * 0.016), s * 0.013, Paint()..color = Colors.white);
          canvas.drawCircle(e.translate(s * 0.01, s * 0.016), s * 0.006, Paint()..color = Colors.white);
          break;
        case 6: // étoiles
          final st = _star(e, s * 0.045);
          canvas.drawPath(st, Paint()..color = const Color(0xFFFFD54F));
          canvas.drawPath(st, Paint()
            ..color = dark
            ..strokeWidth = s * 0.008
            ..style = PaintingStyle.stroke);
          break;
        case 7: // fermés
          canvas.drawPath(Path()
            ..moveTo(e.dx - s * 0.035, e.dy - s * 0.008)
            ..quadraticBezierTo(e.dx, e.dy + s * 0.03, e.dx + s * 0.035, e.dy - s * 0.008), line);
          break;
        case 8: // fâché
          canvas.drawCircle(e.translate(0, s * 0.006), s * 0.026, Paint()..color = dark);
          canvas.drawLine(e.translate(sx * s * 0.045, -s * 0.03), e.translate(-sx * s * 0.035, -s * 0.004), line);
          break;
        case 9: // cœurs
          canvas.drawPath(_heart(e, s * 0.038), Paint()..color = const Color(0xFFE91E63));
          break;
        case 10: // pétillants
          roundEye(e, 0.053);
          canvas.drawCircle(e.translate(s * 0.012, s * 0.016), s * 0.006, Paint()..color = Colors.white);
          break;
        default: // cils
          roundEye(e);
          final lash = Paint()
            ..color = dark
            ..strokeWidth = s * 0.012
            ..strokeCap = StrokeCap.round;
          for (int k = 0; k < 3; k++) {
            final an = -pi / 2 + sx * (0.5 + k * 0.35);
            final p0 = e + Offset(cos(an) * s * 0.045, sin(an) * s * 0.045);
            canvas.drawLine(p0, e + Offset(cos(an) * s * 0.07, sin(an) * s * 0.07), lash);
          }
      }
    }

    // Bouche
    const lip = Color(0xFF8E2B2B);
    final mw = s * 0.07;
    final m = Offset(c.dx, mouthY);
    final ml = Paint()
      ..color = lip
      ..strokeWidth = s * 0.02
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    switch (a[5]) {
      case 0:
        canvas.drawPath(Path()
          ..moveTo(m.dx - mw, m.dy)
          ..quadraticBezierTo(m.dx, m.dy + s * 0.05, m.dx + mw, m.dy), ml);
        break;
      case 1:
      case 4:
      case 6:
        final w2 = a[5] == 6 ? mw * 1.15 : mw;
        final k = a[5] == 1 ? 0.11 : a[5] == 6 ? 0.14 : 0.08;
        final mp = Path()
          ..moveTo(m.dx - w2, m.dy)
          ..quadraticBezierTo(m.dx, m.dy + s * k, m.dx + w2, m.dy)
          ..close();
        canvas.drawPath(mp, Paint()..color = const Color(0xFF7A1F2B));
        canvas.save();
        canvas.clipPath(mp);
        if (a[5] != 4) {
          canvas.drawRect(Rect.fromLTWH(m.dx - w2, m.dy, w2 * 2, s * 0.018), Paint()..color = Colors.white);
        }
        if (a[5] == 6) {
          canvas.drawOval(Rect.fromCenter(center: m.translate(0, s * 0.07), width: s * 0.08, height: s * 0.05),
              Paint()..color = const Color(0xFFFF7A9A));
        }
        canvas.restore();
        if (a[5] == 4) {
          canvas.drawOval(Rect.fromCenter(center: m.translate(0, s * 0.04), width: s * 0.05, height: s * 0.05),
              Paint()..color = const Color(0xFFFF7A9A));
        }
        break;
      case 2:
        canvas.drawLine(m.translate(-mw * 0.7, s * 0.01), m.translate(mw * 0.7, s * 0.01), ml);
        break;
      case 3:
        canvas.drawOval(Rect.fromCenter(center: m.translate(0, s * 0.01), width: s * 0.045, height: s * 0.055),
            Paint()..color = const Color(0xFF7A1F2B));
        break;
      case 5:
        canvas.drawPath(Path()
          ..moveTo(m.dx - mw * 0.8, m.dy + s * 0.012)
          ..quadraticBezierTo(m.dx, m.dy + s * 0.028, m.dx + mw, m.dy - s * 0.02), ml);
        break;
      case 7: // grimace
        final r = RRect.fromRectAndRadius(Rect.fromCenter(center: m.translate(0, s * 0.01), width: mw * 2.1, height: s * 0.045),
            Radius.circular(s * 0.012));
        canvas.drawRRect(r, Paint()..color = Colors.white);
        for (int k = -2; k <= 2; k++) {
          canvas.drawLine(Offset(m.dx + k * mw * 0.35, r.top), Offset(m.dx + k * mw * 0.35, r.bottom), Paint()
            ..color = const Color(0x55000000)
            ..strokeWidth = s * 0.006);
        }
        canvas.drawLine(Offset(r.left, m.dy + s * 0.01), Offset(r.right, m.dy + s * 0.01), Paint()
          ..color = const Color(0x55000000)
          ..strokeWidth = s * 0.006);
        canvas.drawRRect(r, Paint()
          ..color = lip
          ..strokeWidth = s * 0.012
          ..style = PaintingStyle.stroke);
        break;
      case 8: // triste
        canvas.drawPath(Path()
          ..moveTo(m.dx - mw * 0.9, m.dy + s * 0.03)
          ..quadraticBezierTo(m.dx, m.dy - s * 0.02, m.dx + mw * 0.9, m.dy + s * 0.03), ml);
        break;
      case 9: // :3
        canvas.drawPath(Path()
          ..moveTo(m.dx - mw * 0.8, m.dy)
          ..quadraticBezierTo(m.dx - mw * 0.4, m.dy + s * 0.035, m.dx, m.dy)
          ..quadraticBezierTo(m.dx + mw * 0.4, m.dy + s * 0.035, m.dx + mw * 0.8, m.dy), ml);
        break;
      case 10: // sifflote
        canvas.drawOval(Rect.fromCenter(center: m.translate(mw * 0.45, s * 0.008), width: s * 0.03, height: s * 0.036),
            Paint()..color = const Color(0xFF7A1F2B));
        break;
      default: // rouge à lèvres
        canvas.drawPath(Path()
          ..moveTo(m.dx - mw, m.dy)
          ..quadraticBezierTo(m.dx - mw * 0.5, m.dy - s * 0.03, m.dx, m.dy - s * 0.008)
          ..quadraticBezierTo(m.dx + mw * 0.5, m.dy - s * 0.03, m.dx + mw, m.dy)
          ..quadraticBezierTo(m.dx, m.dy + s * 0.05, m.dx - mw, m.dy)
          ..close(), Paint()..color = const Color(0xFFD81B60));
        canvas.drawLine(m.translate(-mw * 0.8, 0), m.translate(mw * 0.8, 0), Paint()
          ..color = const Color(0xFF880E4F)
          ..strokeWidth = s * 0.008);
    }

    // Moustache
    if (extra == 3) {
      final y = (noseY + mouthY) / 2;
      for (final sx in const [-1.0, 1.0]) {
        canvas.drawPath(Path()
          ..moveTo(c.dx, y - s * 0.01)
          ..quadraticBezierTo(c.dx + sx * s * 0.06, y - s * 0.035, c.dx + sx * s * 0.095, y + s * 0.015)
          ..quadraticBezierTo(c.dx + sx * s * 0.045, y + s * 0.008, c.dx, y + s * 0.014)
          ..close(), hairP);
      }
    }

    // Cheveux (avant)
    void cap(double depth, [Paint? p]) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 0, s, head.top + hh * depth));
      canvas.drawOval(head.inflate(s * 0.025), p ?? hairP);
      canvas.restore();
    }
    switch (style) {
      case 1:
        cap(0.28);
        break;
      case 2: // en pics
        cap(0.26);
        for (int k = -2; k <= 2; k++) {
          final x = c.dx + k * hw * 0.18;
          canvas.drawPath(Path()
            ..moveTo(x - hw * 0.11, head.top + s * 0.05)
            ..lineTo(x + k * s * 0.012, head.top - s * 0.08)
            ..lineTo(x + hw * 0.11, head.top + s * 0.05)
            ..close(), hairP);
        }
        break;
      case 3: // raie sur le côté
        cap(0.24);
        canvas.drawPath(Path()
          ..moveTo(head.right + s * 0.015, head.top + hh * 0.12)
          ..quadraticBezierTo(c.dx + hw * 0.1, head.top + hh * 0.2, head.left - s * 0.015, head.top + hh * 0.4)
          ..lineTo(head.left, head.top + hh * 0.1)
          ..close(), hairP);
        break;
      case 4:
      case 9:
      case 13:
        cap(0.3);
        break;
      case 5:
        cap(0.33);
        break;
      case 6:
      case 17:
        cap(0.27);
        if (style == 17) { // en bataille
          for (int k = 0; k < 7; k++) {
            final an = pi * (1.1 + k * 0.13);
            final b = Offset(c.dx + cos(an) * hw * 0.5, c.dy - hh * 0.05 + sin(an) * hh * 0.5);
            final t = b + Offset(cos(an + (k.isEven ? 0.4 : -0.4)) * s * 0.07, sin(an + (k.isEven ? 0.4 : -0.4)) * s * 0.07);
            canvas.drawPath(Path()
              ..moveTo(b.dx - s * 0.03, b.dy + s * 0.01)
              ..lineTo(t.dx, t.dy)
              ..lineTo(b.dx + s * 0.03, b.dy + s * 0.01)
              ..close(), hairP);
          }
        }
        break;
      case 7:
        cap(0.22);
        break;
      case 8: // crête
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTRB(c.dx - s * 0.05, head.top - s * 0.1, c.dx + s * 0.05, head.top + hh * 0.2),
            Radius.circular(s * 0.04)), hairP);
        break;
      case 10: // bouclés
        cap(0.26);
        for (int k = 0; k <= 8; k++) {
          final an = pi * (1.0 + k / 8);
          canvas.drawCircle(Offset(c.dx + cos(an) * hw * 0.52, c.dy - hh * 0.04 + sin(an) * hh * 0.52), s * 0.045, hairP);
        }
        break;
      case 11: // rasés
        cap(0.2, Paint()..color = hairC.withOpacity(0.7));
        break;
      case 12:
        cap(0.3);
        break;
      case 14: // banane
        cap(0.24);
        canvas.drawOval(Rect.fromCenter(center: Offset(c.dx + hw * 0.08, head.top + s * 0.005), width: hw * 0.8, height: s * 0.15), hairP);
        break;
      case 15: // undercut
        cap(0.17, Paint()..color = hairC.withOpacity(0.55));
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(c.dx - hw * 0.2, 0, s, head.top + hh * 0.32));
        canvas.drawOval(head.inflate(s * 0.03), hairP);
        canvas.restore();
        break;
      case 16:
      case 18:
        cap(0.27);
        break;
      case 19:
        cap(0.4);
        break;
    }

    // Sourcils
    final brow = Paint()
      ..color = style == 0 && hairC.computeLuminance() > 0.5 ? skinD : hairC
      ..strokeWidth = s * 0.018
      ..strokeCap = StrokeCap.round;
    final by = eyeY - s * 0.075;
    final ang = a[4] == 8 ? s * 0.012 : 0.0; // fâché : sourcils froncés
    canvas.drawLine(Offset(c.dx - ex - s * 0.04, by + s * 0.006 - ang), Offset(c.dx - ex + s * 0.035, by - s * 0.004 + ang * 1.5), brow);
    canvas.drawLine(Offset(c.dx + ex - s * 0.035, by - s * 0.004 + ang * 1.5), Offset(c.dx + ex + s * 0.04, by + s * 0.006 - ang), brow);

    // Accessoires
    switch (extra) {
      case 1: // lunettes
        final gp = Paint()
          ..color = const Color(0xFF2A2A35)
          ..strokeWidth = s * 0.016
          ..style = PaintingStyle.stroke;
        canvas.drawCircle(Offset(c.dx - ex, eyeY), s * 0.06, gp);
        canvas.drawCircle(Offset(c.dx + ex, eyeY), s * 0.06, gp);
        canvas.drawLine(Offset(c.dx - ex + s * 0.06, eyeY), Offset(c.dx + ex - s * 0.06, eyeY), gp);
        break;
      case 2: // lunettes de soleil
        final sp = Paint()..color = const Color(0xFF111118);
        for (final sx in const [-1.0, 1.0]) {
          final r = Rect.fromCenter(center: Offset(c.dx + sx * ex, eyeY), width: s * 0.13, height: s * 0.09);
          canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(s * 0.03)), sp);
          canvas.drawLine(r.topLeft.translate(s * 0.03, s * 0.02), r.topLeft.translate(s * 0.06, s * 0.05), Paint()
            ..color = Colors.white.withOpacity(0.35)
            ..strokeWidth = s * 0.01);
        }
        canvas.drawLine(Offset(c.dx - ex + s * 0.06, eyeY - s * 0.01), Offset(c.dx + ex - s * 0.06, eyeY - s * 0.01), Paint()
          ..color = const Color(0xFF111118)
          ..strokeWidth = s * 0.016);
        break;
      case 5: // casquette
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, 0, s, head.top + hh * 0.3));
        canvas.drawOval(head.inflate(s * 0.035), Paint()..color = accent);
        canvas.restore();
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTRB(c.dx - hw * 0.1, head.top + hh * 0.24, head.right + s * 0.1, head.top + hh * 0.33),
            Radius.circular(s * 0.03)), Paint()..color = Color.lerp(accent, Colors.black, 0.25)!);
        canvas.drawCircle(Offset(c.dx, head.top - s * 0.025), s * 0.018, Paint()..color = Color.lerp(accent, Colors.white, 0.3)!);
        break;
      case 6: // casque audio
        canvas.drawArc(head.inflate(s * 0.05), pi * 1.05, pi * 0.9, false, Paint()
          ..color = const Color(0xFF263238)
          ..strokeWidth = s * 0.035
          ..style = PaintingStyle.stroke);
        for (final sx in const [-1.0, 1.0]) {
          final r = Rect.fromCenter(center: Offset(c.dx + sx * (hw / 2 + s * 0.01), c.dy), width: s * 0.08, height: s * 0.14);
          canvas.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(s * 0.03)), Paint()..color = const Color(0xFF263238));
          canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(s * 0.015), Radius.circular(s * 0.02)),
              Paint()..color = const Color(0xFF00E5FF));
        }
        break;
      case 7: // bandeau
        canvas.save();
        canvas.clipPath(Path()..addOval(head.inflate(s * 0.03)));
        canvas.drawRect(Rect.fromLTRB(0, head.top + hh * 0.2, s, head.top + hh * 0.2 + s * 0.05), Paint()..color = accent);
        canvas.restore();
        canvas.drawPath(Path()
          ..moveTo(head.right, head.top + hh * 0.24)
          ..lineTo(head.right + s * 0.07, head.top + hh * 0.18)
          ..lineTo(head.right + s * 0.06, head.top + hh * 0.36)
          ..close(), Paint()..color = accent);
        break;
      case 8: // couronne
        final gold = Paint()..color = const Color(0xFFFFC107);
        final cb = head.top + s * 0.03, cw = hw * 0.62;
        canvas.drawPath(Path()
          ..moveTo(c.dx - cw / 2, cb)
          ..lineTo(c.dx - cw / 2, cb - s * 0.1)
          ..lineTo(c.dx - cw / 4, cb - s * 0.05)
          ..lineTo(c.dx, cb - s * 0.12)
          ..lineTo(c.dx + cw / 4, cb - s * 0.05)
          ..lineTo(c.dx + cw / 2, cb - s * 0.1)
          ..lineTo(c.dx + cw / 2, cb)
          ..close(), gold);
        canvas.drawCircle(Offset(c.dx, cb - s * 0.03), s * 0.018, Paint()..color = const Color(0xFFE53935));
        canvas.drawCircle(Offset(c.dx - cw / 3, cb - s * 0.02), s * 0.012, Paint()..color = const Color(0xFF1E88E5));
        canvas.drawCircle(Offset(c.dx + cw / 3, cb - s * 0.02), s * 0.012, Paint()..color = const Color(0xFF43A047));
        break;
      case 9: // bonnet
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(0, 0, s, head.top + hh * 0.32));
        canvas.drawOval(head.inflate(s * 0.04).translate(0, -s * 0.03), Paint()..color = accent);
        canvas.restore();
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTRB(head.left - s * 0.03, head.top + hh * 0.22, head.right + s * 0.03, head.top + hh * 0.34),
            Radius.circular(s * 0.03)), Paint()..color = Color.lerp(accent, Colors.black, 0.2)!);
        canvas.drawCircle(Offset(c.dx, head.top - s * 0.07), s * 0.04, Paint()..color = Colors.white);
        break;
      case 11: // cache-œil
        final ep = Paint()..color = const Color(0xFF111118);
        canvas.drawLine(Offset(head.left - s * 0.01, head.top + hh * 0.3), Offset(head.right + s * 0.01, eyeY - s * 0.02), ep..strokeWidth = s * 0.014);
        canvas.drawOval(Rect.fromCenter(center: Offset(c.dx + ex, eyeY), width: s * 0.1, height: s * 0.085), Paint()..color = const Color(0xFF111118));
        break;
      case 12: // nœud
        final bp = Paint()..color = const Color(0xFFFF4FA3);
        final bc = Offset(head.right - hw * 0.12, head.top + s * 0.03);
        canvas.drawPath(Path()
          ..moveTo(bc.dx, bc.dy)
          ..lineTo(bc.dx - s * 0.07, bc.dy - s * 0.045)
          ..lineTo(bc.dx - s * 0.07, bc.dy + s * 0.045)
          ..close(), bp);
        canvas.drawPath(Path()
          ..moveTo(bc.dx, bc.dy)
          ..lineTo(bc.dx + s * 0.07, bc.dy - s * 0.045)
          ..lineTo(bc.dx + s * 0.07, bc.dy + s * 0.045)
          ..close(), bp);
        canvas.drawCircle(bc, s * 0.022, Paint()..color = const Color(0xFFC2185B));
        break;
      case 13: // chapeau haut de forme
        final hp = Paint()..color = const Color(0xFF16161E);
        canvas.drawRRect(RRect.fromRectAndRadius(
            Rect.fromLTRB(head.left - s * 0.06, head.top + hh * 0.1, head.right + s * 0.06, head.top + hh * 0.1 + s * 0.04),
            Radius.circular(s * 0.02)), hp);
        canvas.drawRect(Rect.fromLTRB(c.dx - hw * 0.34, head.top - s * 0.16, c.dx + hw * 0.34, head.top + hh * 0.11), hp);
        canvas.drawRect(Rect.fromLTRB(c.dx - hw * 0.34, head.top + hh * 0.02, c.dx + hw * 0.34, head.top + hh * 0.08),
            Paint()..color = accent);
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MiiPainter old) => _avCode(old.a) != _avCode(a);
}

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
  final int trailKind;
  final List<(double, double, double, int)> trailPts;
  final int weather, windDir;
  final double weatherAlpha, flash;
  final int theme; // 7 Night, 9 Matrix, 10 Realistic, 11 Frozen tower: drawn effects
  final bool disco; // thème Disco : lumières qui clignotent
  final ui.Image? turboImg;
  final int hero;
  final double? recordY; // y monde de la ligne du record (null = pas de record)
  final (double, double, String, int, bool)? ghost; // ghost: x, world y, name, hero, facing right
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
    this.theme = 0,
    this.trailKind = 0,
    this.trailPts = const [],
    this.weather = -1,
    this.weatherAlpha = 0,
    this.windDir = 1,
    this.flash = 0,
    required this.startY,
    required this.recordY,
    this.rivals = const [],
    this.ghost,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (_real) {
      _paintRealSky(canvas, size);
    } else if (_castle) {
      _paintCastle(canvas, size);
    } else if (_scene) {
      _paintSceneSky(canvas, size);
    } else {
      _paintBackground(canvas, size);
    }
    if (_night) _paintNightSky(canvas, size);
    if (_mx) _paintMatrixRain(canvas, size);
    if (disco) _paintDiscoLights(canvas, size);
    _paintRecordLine(canvas, size);
    _paintRivals(canvas, size);
    for (final p in plats) {
      final sy = p.y - camY;
      if (sy < -40 || sy > size.height + 40) continue;
      if (_real) {
        _paintRealPlat(canvas, p, Offset(p.x, sy));
      } else if (_castle) {
        _paintCastlePlat(canvas, p, Offset(p.x, sy));
      } else if (_scene) {
        _paintScenePlat(canvas, p, Offset(p.x, sy));
      } else {
        _paintCartridge(canvas, p, Offset(p.x, sy));
      }
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
    _paintGhost(canvas, size);
    _paintTrail(canvas);
    _paintHero(canvas, Offset(heroX, heroY - camY));
    if (_real || _night) _paintVignette(canvas, size);
    if (_castle) _paintSnowfall(canvas, size);
    if (_scene) _paintSceneFront(canvas, size);
    _paintWeather(canvas, size);
    if (crt) _paintCrt(canvas, size);
    if (disco) _paintDiscoPulse(canvas, size);
    if (slowmo) {
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF40C4FF).withOpacity(0.08));
    }
  }

  /// Thème Disco : boule à facettes, faisceaux de couleur, reflets et pulsation.
  // ── Thème « Tour gelée » : tour de château réaliste sous la neige ──────────
  bool get _castle => theme == 11;

  /// Stable pseudo-random (0..1) to place stones, snow, windows…
  static double _h(int a, int b) {
    var x = (a * 73856093) ^ (b * 19349663);
    x = (x ^ (x >> 13)) * 1274126177;
    x = x ^ (x >> 16);
    return (x & 0x7FFFFFFF) % 10000 / 10000;
  }

  void _paintCastle(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF16181D)); // mortar
    const rh = 26.0;
    final off = -camY * _parallax;
    final r0 = ((-off) / rh).floor() - 1, r1 = ((h - off) / rh).floor() + 1;
    final stone = Paint();
    final fx = Paint();
    final snow = Paint()..color = const Color(0xEBF0F6FF);
    for (int r = r0; r <= r1; r++) {
      final y = r * rh + off;
      var x = -_h(r, 1) * 40;
      var i = 0;
      while (x < w) {
        final sw = 38 + _h(r, i + 7) * 34;
        final v = _h(r, i);
        var cr = 74 + v * 36, cg = 80 + v * 34, cb = 92 + v * 32;
        if (_h(i, r + 3) < 0.25) {
          cr -= 10; cg -= 6; cb += 4;
        } else if (_h(i, r + 5) < 0.2) {
          cr += 12; cg += 6; cb -= 6;
        }
        stone.color = Color.fromARGB(255, cr.round(), cg.round(), cb.round());
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 1.5, y + 1.5, sw - 3, rh - 3), const Radius.circular(3)), stone);
        fx.color = Colors.white.withOpacity(0.10);
        canvas.drawRect(Rect.fromLTWH(x + 3, y + 2, sw - 6, 3), fx); // lit edge
        fx.color = Colors.black.withOpacity(0.22);
        canvas.drawRect(Rect.fromLTWH(x + 2, y + rh - 6, sw - 4, 4), fx); // shaded underside
        for (int k = 0; k < 4; k++) {
          fx.color = _h(k, r + i) < 0.5 ? Colors.black.withOpacity(0.18) : Colors.white.withOpacity(0.10);
          canvas.drawRect(Rect.fromLTWH(x + 4 + _h(r * 7 + k, i) * (sw - 8), y + 5 + _h(i * 3 + k, r) * (rh - 10), 2, 1.5), fx);
        }
        if (_h(r + 11, i) < 0.33) {
          // Snow settled on the stone
          final sw2 = sw * (0.4 + _h(i, r + 9) * 0.5);
          final sx = x + 2 + _h(r, i + 2) * (sw - sw2 - 4);
          canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(sx, y + 0.5, sw2, 3.2), const Radius.circular(2)), snow);
        }
        x += sw;
        i++;
      }
    }
    // Arrow slits lit from inside
    for (int k = ((-off) / 360).floor() - 1; k <= ((h - off) / 360).floor() + 1; k++) {
      final y = k * 360 + off + 120;
      final x = (0.25 + _h(k, 4) * 0.5) * w;
      final c = Offset(x, y + 22);
      canvas.drawRect(Rect.fromLTWH(x - 50, y - 30, 100, 104), Paint()
        ..shader = ui.Gradient.radial(c, 50, [const Color(0x59FFAA3C), const Color(0x00FFAA3C)]));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 6, y, 12, 46), const Radius.circular(6)),
          Paint()..color = const Color(0xFF1A1410));
      final flick = 0.85 + 0.15 * sin(time * 9 + k);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 3.5, y + 4, 7, 38), const Radius.circular(4)), Paint()
        ..shader = ui.Gradient.linear(Offset(0, y), Offset(0, y + 46),
            [const Color(0xFFFFCC66).withOpacity(flick), const Color(0xFFD9772A).withOpacity(flick)]));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 9, y - 3, 18, 4), const Radius.circular(2)), snow);
    }
    // Rounded tower shading
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(w, 0), [
        const Color(0xB3050A19), const Color(0x40050A19), const Color(0x14050A19), const Color(0x40050A19), const Color(0xB3050A19),
      ], [0, 0.2, 0.5, 0.8, 1]));
    // Snowy cornices with icicles (stage change)
    final kLo = max(1, (_heightAt(h + 40) / _tierStep).floor());
    final kHi = (_heightAt(-40) / _tierStep).ceil();
    for (int k = kLo; k <= kHi; k++) {
      final y = _syOfHeight(k * _tierStep.toDouble());
      if (y < -40 || y > h + 40) continue;
      canvas.drawRect(Rect.fromLTWH(0, y + 12, w, 8), Paint()..color = Colors.black.withOpacity(0.45));
      canvas.drawRect(Rect.fromLTWH(0, y, w, 14), Paint()
        ..shader = ui.Gradient.linear(Offset(0, y), Offset(0, y + 14), const [Color(0xFF9AA1AB), Color(0xFF565C66)]));
      final joint = Paint()..color = Colors.black.withOpacity(0.3);
      for (double x = 0; x < w; x += 22) {
        canvas.drawRect(Rect.fromLTWH(x, y, 1.5, 14), joint);
      }
      final drift = Path()..moveTo(0, y + 2);
      for (double x = 0; x <= w; x += 6) {
        drift.lineTo(x, y - 4 - (sin(x * 0.045 + k)).abs() * 6 - _h(x.toInt(), k) * 2);
      }
      drift
        ..lineTo(w, y + 3)
        ..close();
      canvas.drawPath(drift, Paint()
        ..shader = ui.Gradient.linear(Offset(0, y - 12), Offset(0, y + 3), const [Colors.white, Color(0xFFC9D8EE)]));
      for (int i = 0; i < w / 14; i++) {
        _icicle(canvas, i * 14 + _h(i, k) * 8, y + 14, 4 + _h(k, i) * 14, 2.5);
      }
    }
  }

  void _icicle(Canvas canvas, double x, double top, double len, double half) {
    canvas.drawPath(Path()
      ..moveTo(x - half, top)
      ..lineTo(x + half, top)
      ..lineTo(x, top + len)
      ..close(), Paint()
      ..shader = ui.Gradient.linear(Offset(0, top), Offset(0, top + len),
          [const Color(0xF2DCF0FF), const Color(0x1ADCF0FF)]));
  }

  /// Platforms: stone slab, iron-banded beam, ice block — all snowy
  void _paintCastlePlat(Canvas canvas, _Plat p, Offset o) {
    final op = p.broken ? 0.5 : 1.0;
    canvas.save();
    if (p.broken) {
      canvas.translate(o.dx + _platW / 2, o.dy + _platH / 2);
      canvas.rotate(0.25);
      canvas.translate(-(o.dx + _platW / 2), -(o.dy + _platH / 2));
    }
    final r = Rect.fromLTWH(o.dx, o.dy, _platW, _platH);
    canvas.drawRect(Rect.fromLTWH(o.dx - 3, o.dy + 8, _platW + 2, _platH), Paint()
      ..color = Colors.black.withOpacity(0.6 * op)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    final seed = (p.x * 7).toInt() + (p.y * 3).toInt();
    if (p.type == _PlatType.breakable) {
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
      canvas.drawRRect(rr, Paint()
        ..shader = ui.Gradient.linear(r.topLeft, r.bottomLeft,
            [const Color(0xE6D2F0FF).withOpacity(0.9 * op), const Color(0xD96EAAD7).withOpacity(0.85 * op)]));
      canvas.drawRect(Rect.fromLTWH(o.dx + 4, o.dy + 2, _platW - 20, 2), Paint()..color = Colors.white.withOpacity(0.6 * op));
      canvas.drawPath(Path()
        ..moveTo(o.dx + 22, o.dy)
        ..lineTo(o.dx + 28, o.dy + 6)
        ..lineTo(o.dx + 24, o.dy + 10)
        ..lineTo(o.dx + 31, o.dy + _platH)
        ..moveTo(o.dx + 46, o.dy)
        ..lineTo(o.dx + 41, o.dy + 7)
        ..lineTo(o.dx + 47, o.dy + _platH), Paint()
        ..color = const Color(0xFF285A8C).withOpacity(0.7 * op)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2);
    } else {
      final cols = p.type == _PlatType.moving
          ? const [Color(0xFF8A5F37), Color(0xFF5E3E22), Color(0xFF352212)]
          : const [Color(0xFF8C7F70), Color(0xFF5C5046), Color(0xFF2F2822)];
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(2.5)), Paint()
        ..shader = ui.Gradient.linear(r.topLeft, r.bottomLeft, [for (final c in cols) c.withOpacity(op)], [0, 0.5, 1]));
      if (p.type == _PlatType.moving) {
        final band = Paint()..color = const Color(0xFF2B2F35).withOpacity(op);
        final hi = Paint()..color = Colors.white.withOpacity(0.25 * op);
        for (final bx in [o.dx + 10, o.dx + _platW - 14]) {
          canvas.drawRect(Rect.fromLTWH(bx, o.dy, 4, _platH), band);
          canvas.drawRect(Rect.fromLTWH(bx, o.dy, 4, 1.5), hi);
        }
      } else {
        final fx = Paint();
        for (int k = 0; k < 5; k++) {
          fx.color = k.isOdd ? Colors.black.withOpacity(0.22 * op) : Colors.white.withOpacity(0.12 * op);
          canvas.drawRect(Rect.fromLTWH(o.dx + 5 + _h(k, seed) * (_platW - 10), o.dy + 4 + _h(seed, k) * 6, 2, 1.5), fx);
        }
        canvas.drawRect(Rect.fromLTWH(o.dx + _platW * 0.45, o.dy + 3, 1.2, _platH - 3),
            Paint()..color = Colors.black.withOpacity(0.3 * op));
      }
      for (int i = 0; i < 3; i++) {
        _icicle(canvas, o.dx + 8 + _h(i, seed) * (_platW - 16), o.dy + _platH, 4 + _h(seed, i) * 8, 2);
      }
    }
    // Snow layer slightly overhanging
    final cap = Path()..moveTo(o.dx - 3, o.dy + 2);
    for (int i = 0; i <= 10; i++) {
      final xx = o.dx - 3 + i * (_platW + 6) / 10;
      cap.lineTo(xx, o.dy - 4 - sin(i * 0.9 + o.dx) * 1.8 - (i > 0 && i < 10 ? 2.5 : 0));
    }
    cap
      ..lineTo(o.dx + _platW + 3, o.dy + 3)
      ..quadraticBezierTo(o.dx + _platW / 2, o.dy + 5, o.dx - 3, o.dy + 2)
      ..close();
    canvas.drawPath(cap, Paint()
      ..shader = ui.Gradient.linear(Offset(0, o.dy - 7), Offset(0, o.dy + 4),
          [Colors.white.withOpacity(op), const Color(0xFFC8D7EC).withOpacity(op)]));
    if (p.type == _PlatType.spring) {
      final cx = o.dx + _platW / 2;
      final path = Path()..moveTo(cx - 6, o.dy - 3);
      for (int i = 0; i < 4; i++) {
        path.lineTo(i.isEven ? cx + 6 : cx - 6, o.dy - 6 - i * 3);
      }
      canvas.drawPath(path, Paint()
        ..color = const Color(0xFF6E7B86)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke);
      canvas.drawPath(path, Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 10, o.dy - 20, 20, 5), const Radius.circular(2)),
          Paint()..color = const Color(0xFF9AA6B2));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 10, o.dy - 22, 20, 3), const Radius.circular(2)),
          Paint()..color = Colors.white);
    }
    canvas.restore();
  }

  /// Falling snow (3 layers) + cold mist + vignette
  void _paintSnowfall(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(Offset(0, h * 0.6), Offset(0, h),
          [const Color(0x00C8DCF5), const Color(0x2EC8DCF5)]));
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0x1A284682));
    const layers = [(70, 0.9, 18.0, 0.35), (50, 1.7, 34.0, 0.12), (18, 3.4, 60.0, 0.05)];
    final flake = Paint();
    for (int li = 0; li < layers.length; li++) {
      final (n, rad, spd, par) = layers[li];
      if (li == 2) flake.maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
      for (int i = 0; i < n; i++) {
        final sway = sin(time * (0.6 + _h(i, li) * 0.8) + i) * (8 + rad * 4);
        final y = (_h(li + 40, i) * (h + 40) + time * spd * (0.8 + _h(i, li + 60) * 0.5) - camY * par) % (h + 40) - 20;
        final x = (_h(i, li + 20) * w + sway + time * 6 * (li + 1)) % (w + 20) - 10;
        flake.color = Colors.white.withOpacity(0.55 + 0.35 * _h(i, li + 80));
        canvas.drawCircle(Offset(x, y), rad, flake);
      }
    }
    final c = size.center(Offset.zero);
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.radial(c, size.longestSide * 0.75,
          [Colors.transparent, const Color(0x80000514)], [0.5, 1]));
  }

  // ── Night / Matrix / Realistic themes ─────────────────────────────────────────
  bool get _night => theme == 7;
  bool get _mx => theme == 9;
  // ── Thèmes réalistes « scène » : 12 Jungle, 13 Plage, 14 Ville la nuit, 15 Canyon ──
  bool get _scene => theme >= 12 && theme <= 15;
  int get _sk => theme - 12;

  static const _sceneSky = <List<Color>>[
    [Color(0xFF2E6B5A), Color(0xFF8FC29A), Color(0xFFDDEFD0)], // jungle : brume verte
    [Color(0xFF35245E), Color(0xFFD9577A), Color(0xFFFFB46A)], // plage : coucher de soleil
    [Color(0xFF04050D), Color(0xFF111735), Color(0xFF34295A)], // ville : nuit
    [Color(0xFF2C6BB3), Color(0xFF97C4E6), Color(0xFFF5D79C)], // canyon : ciel brûlant
  ];

  /// Altitude (m) au centre de l'écran et passage progressif vers l'espace.
  double _sceneAlt(Size size) => max(0.0, (startY - camY - size.height / 2) / 10);
  double _sceneSpace(Size size) => ((_sceneAlt(size) - 4000) / 2500).clamp(0.0, 1.0);

  /// Position d'écran d'un décor qui se répète tous les [gap] px (défilement avec parallaxe [par]).
  double _rep(int k, double gap, double par, Size size) =>
      ((k * gap - camY * par) % (size.height + gap) + size.height + gap) % (size.height + gap) - gap;

  /// Silhouette de relief accrochée au sol de départ (disparaît en montant).
  Path? _ridge(Size size, double par, double Function(double x) hf) {
    final base = startY + 24 - camY * par;
    if (base - 260 > size.height) return null;
    final path = Path()..moveTo(0, size.height + 600);
    for (double x = 0; x <= size.width + 6; x += 6) {
      path.lineTo(x, base - hf(x));
    }
    return path
      ..lineTo(size.width, size.height + 600)
      ..close();
  }

  void _fillRidge(Canvas canvas, Path? p, Color top, Color bottom, double y0, double y1) {
    if (p == null) return;
    canvas.drawPath(p, Paint()..shader = ui.Gradient.linear(Offset(0, y0), Offset(0, y1), [top, bottom]));
  }

  void _paintSceneSky(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final space = _sceneSpace(size);
    final k = _sceneSky[_sk];
    Color sp(Color c) => Color.lerp(c, const Color(0xFF02030A), space)!;
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), [sp(k[0]), sp(k[1]), sp(k[2])], [0, 0.55, 1]));
    // Étoiles : toujours en ville, en altitude ailleurs
    final st = _sk == 2 ? max(0.7, space) : space;
    if (st > 0) {
      final p = Paint();
      for (int i = 0; i < 80; i++) {
        final sx = ((i * 7919) % 1000) / 1000 * w;
        final sy = (((i * 104729) % 1000) / 1000 * h - camY * 0.04) % h;
        p.color = Colors.white.withOpacity(st * (0.3 + 0.55 * (0.5 + 0.5 * sin(time * 2 + i))));
        canvas.drawCircle(Offset(sx, sy), i % 9 == 0 ? 1.4 : 0.8, p);
      }
    }
    switch (_sk) {
      case 0:
        _paintJungle(canvas, size, space);
        _paintJungleLife(canvas, size, space);
        break;
      case 1:
        _paintBeach(canvas, size, space);
        break;
      case 2:
        _paintCitySky(canvas, size);
        _paintCity(canvas, size);
        break;
      default:
        _paintCanyon(canvas, size, space);
    }
  }

  // Jungle : brume, collines, canopée, rayons de lumière, sol de fougères
  void _paintJungle(Canvas canvas, Size size, double space) {
    final w = size.width;
    final glow = Offset(w * 0.25, size.height * 0.1);
    canvas.drawCircle(glow, 220, Paint()
      ..shader = ui.Gradient.radial(glow, 220, [const Color(0xFFFFF6C8).withOpacity(0.45 * (1 - space)), Colors.transparent]));
    // Rayons obliques à travers la brume
    final ray = Paint()..color = const Color(0xFFFFF8D0).withOpacity(0.07 * (1 - space));
    for (int i = 0; i < 5; i++) {
      final x0 = w * (0.05 + i * 0.22) + sin(time * 0.3 + i) * 10;
      canvas.drawPath(Path()
        ..moveTo(x0, 0)
        ..lineTo(x0 + 26, 0)
        ..lineTo(x0 + 140, size.height)
        ..lineTo(x0 + 80, size.height)
        ..close(), ray);
    }
    final base = startY + 24;
    _fillRidge(canvas, _ridge(size, 0.15, (x) => 120 + 40 * sin(x * 0.012 + 0.7) + 22 * sin(x * 0.031)),
        const Color(0xFF5E8F75), const Color(0xFF3D6B55), base - camY * 0.15 - 180, base - camY * 0.15);
    // Canopée : couronnes d'arbres arrondies
    _fillRidge(canvas, _ridge(size, 0.32, (x) => 95 + 26 * sin(x * 0.045).abs() + 18 * sin(x * 0.11 + 1.3).abs() + 10 * sin(x * 0.27).abs()),
        const Color(0xFF2F6A45), const Color(0xFF1C4730), base - camY * 0.32 - 150, base - camY * 0.32);
    // Sol : terre sombre + fougères
    final gy = startY + 18 - camY;
    if (gy < size.height + 10) {
      canvas.drawRect(Rect.fromLTWH(0, gy, w, size.height - gy + 400), Paint()
        ..shader = ui.Gradient.linear(Offset(0, gy), Offset(0, gy + 110),
            const [Color(0xFF3F6B2E), Color(0xFF2A4A22), Color(0xFF2B2016)], [0, 0.2, 1]));
      final fern = Paint()
        ..color = const Color(0xFF5E9B3C)
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      for (double x = 6; x < w; x += 22) {
        for (int j = -2; j <= 2; j++) {
          canvas.drawLine(Offset(x, gy + 3), Offset(x + j * 5 + sin(time * 1.5 + x) * 1.5, gy - 10 + j.abs() * 3), fern);
        }
      }
    }
  }

  // Plage : soleil couchant sur la mer, nuages roses, sable
  void _paintBeach(Canvas canvas, Size size, double space) {
    final w = size.width;
    final hz = startY - 140 - camY * 0.2; // ligne d'horizon
    // Nuages en traînées roses
    final cl = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    for (int i = 0; i < 6; i++) {
      final y = _rep(i, 150, 0.12, size);
      final x = (((i * 7919) % 1000) / 1000 * (w + 200) + time * (5 + i)) % (w + 200) - 100;
      cl.color = const Color(0xFFFFC2B0).withOpacity(0.5 * (1 - space));
      canvas.drawOval(Rect.fromCenter(center: Offset(x, y), width: 150, height: 16), cl);
    }
    // Soleil posé sur l'horizon
    if (hz > -80 && hz < size.height + 120) {
      final sun = Offset(w * 0.5, hz - 8);
      canvas.drawCircle(sun, 200, Paint()
        ..shader = ui.Gradient.radial(sun, 200, [const Color(0xFFFFD27A).withOpacity(0.55), Colors.transparent]));
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, -1000, w, hz + 1000));
      canvas.drawCircle(sun, 48, Paint()
        ..shader = ui.Gradient.linear(sun.translate(0, -48), sun.translate(0, 48), const [Color(0xFFFFF1A8), Color(0xFFFF7A3D)]));
      canvas.restore();
      // Mer + reflet du soleil
      canvas.drawRect(Rect.fromLTWH(0, hz, w, size.height - hz + 600), Paint()
        ..shader = ui.Gradient.linear(Offset(0, hz), Offset(0, hz + 220), const [Color(0xFF5A4C8E), Color(0xFF1F2E5E)]));
      final refl = Paint()..color = const Color(0xFFFFC46B).withOpacity(0.7);
      for (int i = 0; i < 14; i++) {
        final y = hz + 6 + i * 9.0;
        final half = (40 - i * 2.2) * (0.7 + 0.3 * sin(time * 3 + i));
        if (half > 2) canvas.drawRect(Rect.fromLTWH(w * 0.5 - half, y, half * 2, 2), refl);
      }
    }
    // Sable + écume
    final gy = startY + 18 - camY;
    if (gy < size.height + 10) {
      canvas.drawRect(Rect.fromLTWH(0, gy, w, size.height - gy + 400), Paint()
        ..shader = ui.Gradient.linear(Offset(0, gy), Offset(0, gy + 90), const [Color(0xFFF3D39A), Color(0xFFD6A764)]));
      final foam = Paint()
        ..color = Colors.white.withOpacity(0.75)
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      final path = Path()..moveTo(0, gy + 2);
      for (double x = 0; x <= w; x += 8) {
        path.lineTo(x, gy + 2 + sin(x * 0.08 + time * 2) * 1.6);
      }
      canvas.drawPath(path, foam);
    }
    // Palmiers en ombre chinoise sur les côtés (plantés dans le sable)
    final py = startY + 22 - camY;
    if (py - 230 < size.height) {
      _paintPalm(canvas, Offset(8, py), true, space);
      _paintPalm(canvas, Offset(w - 8, py + 14), false, space);
    }
    // Mouettes
    final gull = Paint()
      ..color = const Color(0xFF2A1F3D).withOpacity(0.8 * (1 - space))
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 3; i++) {
      final x = (time * (22 + i * 7) + i * 140) % (w + 60) - 30;
      final y = size.height * (0.18 + i * 0.09) + sin(time * 1.3 + i) * 8;
      final f = 3 + sin(time * 8 + i) * 2;
      canvas.drawPath(Path()
        ..moveTo(x - 7, y - f)
        ..quadraticBezierTo(x - 3, y - 1, x, y)
        ..quadraticBezierTo(x + 3, y - 1, x + 7, y - f), gull);
    }
  }

  void _paintPalm(Canvas canvas, Offset foot, bool left, double space) {
    final c = const Color(0xFF241634).withOpacity(0.9 * (1 - space * 0.5));
    final s = left ? 1.0 : -1.0;
    final top = foot.translate(s * 26, -190);
    canvas.drawPath(Path()
      ..moveTo(foot.dx - 4, foot.dy)
      ..quadraticBezierTo(foot.dx + s * 2, foot.dy - 100, top.dx, top.dy)
      ..lineTo(top.dx + 3, top.dy + 2)
      ..quadraticBezierTo(foot.dx + s * 8, foot.dy - 100, foot.dx + 5, foot.dy)
      ..close(), Paint()..color = c);
    final leaf = Paint()
      ..color = c
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 6; i++) {
      final a = -pi / 2 + (i - 2.5) * 0.55 + sin(time * 1.2 + i) * 0.05;
      final end = top + Offset(cos(a) * 58, sin(a) * 30 + 26);
      canvas.drawPath(Path()
        ..moveTo(top.dx, top.dy)
        ..quadraticBezierTo(top.dx + cos(a) * 30, top.dy + sin(a) * 30 - 6, end.dx, end.dy), leaf);
    }
  }

  // Ville la nuit : lune, gratte-ciels éclairés, enseignes, rue mouillée
  void _paintCity(Canvas canvas, Size size) {
    final w = size.width;
    final moon = Offset(w * 0.8, size.height * 0.13);
    canvas.drawCircle(moon, 70, Paint()
      ..shader = ui.Gradient.radial(moon, 70, [const Color(0xFFE8ECFF).withOpacity(0.3), Colors.transparent]));
    canvas.drawCircle(moon, 20, Paint()..color = const Color(0xFFE9ECF5));
    // Faisceaux de projecteurs
    for (int i = 0; i < 2; i++) {
      final a = -pi / 2 + sin(time * 0.4 + i * 2) * 0.5;
      final o = Offset(w * (0.3 + i * 0.4), size.height + 40);
      canvas.drawPath(Path()
        ..moveTo(o.dx, o.dy)
        ..lineTo(o.dx + cos(a - 0.05) * 900, o.dy + sin(a - 0.05) * 900)
        ..lineTo(o.dx + cos(a + 0.05) * 900, o.dy + sin(a + 0.05) * 900)
        ..close(), Paint()..color = const Color(0xFFB0C4FF).withOpacity(0.05));
    }
    for (final (par, col, hmax, gap, seed) in const [
      (0.12, Color(0xFF1B2147), 170.0, 26.0, 3),
      (0.3, Color(0xFF0C1027), 230.0, 38.0, 7),
    ]) {
      final base = startY + 24 - camY * par;
      if (base - hmax - 40 > size.height) continue;
      for (double x = -10, k = 0; x < w + 10; x += gap, k++) {
        final r = ((k.toInt() * 7919 + seed * 131) % 1000) / 1000;
        final bw = gap - 3, bh = hmax * (0.45 + 0.55 * r);
        final rect = Rect.fromLTWH(x, base - bh, bw, bh + 600);
        canvas.drawRect(rect, Paint()..color = col);
        // Fenêtres éclairées (certaines clignotent)
        final win = Paint();
        for (double wy = base - bh + 8; wy < base - 6; wy += 9) {
          for (double wx = x + 4; wx < x + bw - 4; wx += 6) {
            final hsh = ((wx * 13 + wy * 7 + seed).toInt() * 2654435761) & 0xFFFF;
            if (hsh % 100 > 38) continue;
            final on = hsh % 7 != 0 || sin(time * 0.7 + hsh) > -0.6;
            if (!on) continue;
            win.color = (hsh % 3 == 0 ? const Color(0xFF9FD4FF) : const Color(0xFFFFD27A)).withOpacity(par > 0.2 ? 0.85 : 0.5);
            canvas.drawRect(Rect.fromLTWH(wx, wy, 2.6, 3.6), win);
          }
        }
        // Enseigne néon / feu rouge d'antenne
        if (par > 0.2 && r > 0.72) {
          final nc = r > 0.86 ? const Color(0xFFFF4FA3) : const Color(0xFF3FF1FF);
          final nr = Rect.fromLTWH(x + 3, base - bh * 0.6, bw - 6, 7);
          canvas.drawRect(nr.inflate(3), Paint()
            ..color = nc.withOpacity(0.35 + 0.15 * sin(time * 4 + r * 9))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
          canvas.drawRect(nr, Paint()..color = nc);
        }
        if (bh > hmax * 0.85) {
          canvas.drawLine(Offset(x + bw / 2, base - bh), Offset(x + bw / 2, base - bh - 14), Paint()
            ..color = col
            ..strokeWidth = 2);
          if (sin(time * 3 + k) > 0) canvas.drawCircle(Offset(x + bw / 2, base - bh - 15), 2, Paint()..color = const Color(0xFFFF3B3B));
        }
      }
    }
    // Rue mouillée + reflets
    final gy = startY + 18 - camY;
    if (gy < size.height + 10) {
      canvas.drawRect(Rect.fromLTWH(0, gy, w, size.height - gy + 400), Paint()
        ..shader = ui.Gradient.linear(Offset(0, gy), Offset(0, gy + 80), const [Color(0xFF262B3F), Color(0xFF0E1018)]));
      final dash = Paint()..color = const Color(0xFFFFD54F).withOpacity(0.8);
      for (double x = 10; x < w; x += 46) {
        canvas.drawRect(Rect.fromLTWH(x, gy + 26, 22, 3), dash);
      }
      for (int i = 0; i < 8; i++) {
        final x = ((i * 7919) % 1000) / 1000 * w;
        canvas.drawRect(Rect.fromLTWH(x, gy + 6, 3, 18), Paint()
          ..color = (i.isEven ? const Color(0xFFFFD27A) : const Color(0xFFFF4FA3)).withOpacity(0.25));
      }
    }
  }

  // Canyon : mesas en strates, soleil blanc, cactus, sable ocre
  void _paintCanyon(Canvas canvas, Size size, double space) {
    final w = size.width;
    final sun = Offset(w * 0.22, size.height * 0.12);
    canvas.drawCircle(sun, 190, Paint()
      ..shader = ui.Gradient.radial(sun, 190, [const Color(0xFFFFF6D8).withOpacity(0.6 * (1 - space)), Colors.transparent]));
    canvas.drawCircle(sun, 24, Paint()..color = Color.lerp(const Color(0xFFFFFBEA), const Color(0xFFFFE9A8), space)!);
    // Mesas : plateaux à bords abrupts
    double mesa(double x, double s, double hh) => 30 + hh * ((sin(x * 0.011 + s) - 0.05) * 4).clamp(0.0, 1.0) + 8 * sin(x * 0.05 + s);
    final base = startY + 24;
    final far = _ridge(size, 0.14, (x) => mesa(x, 0.4, 120));
    _fillRidge(canvas, far, const Color(0xFFD9A07A), const Color(0xFFC08060), base - camY * 0.14 - 160, base - camY * 0.14);
    final mid = _ridge(size, 0.3, (x) => mesa(x, 2.1, 150));
    _fillRidge(canvas, mid, const Color(0xFFB4562F), const Color(0xFF7A3418), base - camY * 0.3 - 190, base - camY * 0.3);
    if (mid != null) {
      // Strates horizontales sur les falaises
      canvas.save();
      canvas.clipPath(mid);
      final b = base - camY * 0.3;
      final strata = Paint()..color = const Color(0xFF5E2610).withOpacity(0.35);
      for (int i = 1; i < 9; i++) {
        canvas.drawRect(Rect.fromLTWH(0, b - i * 19.0, w, 3), strata);
      }
      canvas.restore();
    }
    // Sol ocre + cactus
    final gy = startY + 18 - camY;
    if (gy < size.height + 10) {
      canvas.drawRect(Rect.fromLTWH(0, gy, w, size.height - gy + 400), Paint()
        ..shader = ui.Gradient.linear(Offset(0, gy), Offset(0, gy + 90), const [Color(0xFFE2A866), Color(0xFFB4743E)]));
      final cactus = Paint()..color = const Color(0xFF3F6B34);
      for (final cx in [w * 0.12, w * 0.83]) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 5, gy - 46, 10, 48), const Radius.circular(5)), cactus);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx - 17, gy - 34, 7, 18), const Radius.circular(4)), cactus);
        canvas.drawRect(Rect.fromLTWH(cx - 14, gy - 20, 10, 5), cactus);
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(cx + 10, gy - 40, 7, 16), const Radius.circular(4)), cactus);
        canvas.drawRect(Rect.fromLTWH(cx + 4, gy - 28, 10, 5), cactus);
      }
      // Virevoltant qui roule
      final tx = (time * 40) % (w + 60) - 30;
      final tc = Offset(tx, gy - 7 - (sin(time * 6).abs() * 6));
      canvas.drawCircle(tc, 7, Paint()
        ..color = const Color(0xFF8A6A3E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4);
      canvas.drawLine(tc.translate(-6, 0), tc.translate(6, 0), Paint()..color = const Color(0xFF8A6A3E));
    }
  }

  // ── Jungle : lianes d'arrière-plan + singes qui se balancent de liane en liane ──
  void _paintJungleLife(Canvas canvas, Size size, double space) {
    final w = size.width, h = size.height;
    final fade = 1 - space;
    if (fade <= 0) return;
    // Guirlandes de lianes tendues d'un bord à l'autre (parallaxe lente)
    final garland = Paint()
      ..color = const Color(0xFF1F4A2B).withOpacity(0.75 * fade)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final gLeaf = Paint()..color = const Color(0xFF2F6A3C).withOpacity(0.8 * fade);
    for (int j = 0; j < 3; j++) {
      final y = _rep(j, 340, 0.45, size);
      final sag = 50.0 + (j % 2) * 30 + sin(time * 0.6 + j) * 4;
      final x0 = j.isEven ? -20.0 : w * 0.25, x1 = j.isEven ? w * 0.75 : w + 20;
      final ctrl = Offset((x0 + x1) / 2, y + sag * 2);
      canvas.drawPath(Path()
        ..moveTo(x0, y)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, x1, y), garland);
      for (double t = 0.08; t < 0.95; t += 0.09) {
        final mt = 1 - t;
        final p = Offset(mt * mt * x0 + 2 * mt * t * ctrl.dx + t * t * x1, mt * mt * y + 2 * mt * t * ctrl.dy + t * t * y);
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate(((t * 100).toInt()).isEven ? 0.9 : -0.9);
        canvas.drawOval(Rect.fromCenter(center: const Offset(0, 6), width: 6, height: 13), gLeaf);
        canvas.restore();
      }
    }
    // Lianes pendantes depuis la canopée (haut de l'écran)
    final hang = Paint()
      ..color = const Color(0xFF24502F).withOpacity(0.7 * fade)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (int i = 0; i < 9; i++) {
      final x0 = w * (i + 0.5) / 9 + ((i * 37) % 13) - 6;
      final len = 70.0 + ((i * 53) % 5) * 38;
      final path = Path()..moveTo(x0, -10);
      for (double d = 0; d <= len; d += 8) {
        path.lineTo(x0 + sin(d * 0.04 + time * 0.8 + i) * (d / len) * 6, d - 10);
      }
      canvas.drawPath(path, hang);
      for (double d = 20; d <= len; d += 26) {
        final p = Offset(x0 + sin(d * 0.04 + time * 0.8 + i) * (d / len) * 6, d - 10);
        canvas.save();
        canvas.translate(p.dx, p.dy);
        canvas.rotate((d ~/ 26).isEven ? 0.8 : -0.8);
        canvas.drawOval(Rect.fromCenter(center: const Offset(5, 0), width: 10, height: 4), gLeaf);
        canvas.restore();
      }
    }
    // Singes : un au loin (petit, sombre), un plus proche
    for (final (i, scale, col, lenF, speed, cycle) in const [
      (0, 0.8, Color(0xFF243A26), 0.22, 70.0, 13.0),
      (1, 1.15, Color(0xFF3A2614), 0.36, 95.0, 17.0),
    ]) {
      final len = h * lenF;
      final span = 2 * len * sin(0.9); // écart entre deux lianes
      final tt = (time + i * 6) % cycle;
      final pos = tt * speed;
      if (pos > w + 2 * span) continue; // pause entre deux passages
      final dir = ((time + i * 6) / cycle).floor().isEven ? 1.0 : -1.0;
      final n = (pos / span).floor();
      final u = pos / span - n;
      final a = -0.9 + 1.8 * u;
      final ax = -span / 2 + n * span;
      var anchor = Offset(ax, -10);
      var hand = anchor + Offset(sin(a) * len, cos(a) * len);
      var ang = a;
      if (dir < 0) {
        anchor = Offset(w - anchor.dx, anchor.dy);
        hand = Offset(w - hand.dx, hand.dy);
        ang = -a;
      }
      canvas.drawLine(anchor, hand, Paint()
        ..color = const Color(0xFF2B5A30).withOpacity(0.9 * fade)
        ..strokeWidth = 2.2);
      _drawMonkey(canvas, hand, ang, scale, col.withOpacity(fade), dir);
    }
  }

  /// Singe suspendu par une main au point [hand], le long d'une liane inclinée de [a].
  void _drawMonkey(Canvas canvas, Offset hand, double a, double s, Color c, double dir) {
    canvas.save();
    canvas.translate(hand.dx, hand.dy);
    canvas.rotate(-a * 0.6);
    canvas.scale(dir * s, s);
    final body = Paint()..color = c;
    final limb = Paint()
      ..color = c
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final light = Color.lerp(c, const Color(0xFFD9B48A), 0.45)!;
    // Bras accroché à la liane
    canvas.drawLine(Offset.zero, const Offset(1, 12), limb);
    // Queue enroulée
    canvas.drawPath(Path()
      ..moveTo(-4, 30)
      ..cubicTo(-16, 34, -20, 20, -13, 17)
      ..cubicTo(-9, 15, -8, 21, -11, 22), limb..strokeWidth = 2.2);
    limb.strokeWidth = 3.2;
    // Corps et jambes (balancées)
    final sw = sin(time * 5) * 2;
    canvas.drawOval(Rect.fromCenter(center: const Offset(0, 24), width: 13, height: 18), body);
    canvas.drawLine(const Offset(-3, 31), Offset(-6 + sw, 41), limb);
    canvas.drawLine(const Offset(3, 31), Offset(7 + sw, 39), limb);
    // Bras libre tendu vers l'avant
    canvas.drawLine(const Offset(4, 18), Offset(13, 12 + sw), limb);
    // Tête, oreilles, museau
    canvas.drawCircle(const Offset(3, 12), 6, body);
    canvas.drawCircle(const Offset(-2.5, 10), 2.4, body);
    canvas.drawCircle(const Offset(8.5, 10), 2.4, body);
    canvas.drawOval(Rect.fromCenter(center: const Offset(5, 14), width: 7, height: 5), Paint()..color = light);
    canvas.drawCircle(const Offset(5.5, 11), 0.9, Paint()..color = const Color(0xFF111111).withOpacity(c.opacity));
    canvas.restore();
  }

  // ── Ville la nuit : avion, montgolfières, hélicoptère, dirigeable ─────────
  void _paintCitySky(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final fade = 1 - _sceneSpace(size) * 0.8;
    // Défilement horizontal en boucle (sens alterné à chaque passage)
    (double, double) lane(double speed, double offset, double margin) {
      final period = (w + 2 * margin) / speed;
      final t = time + offset;
      final x = (t % period) * speed - margin;
      final dir = (t / period).floor().isEven ? 1.0 : -1.0;
      return (dir > 0 ? x : w - x, dir);
    }

    // Dirigeable avec bandeau lumineux
    {
      final (x, dir) = lane(14, 30, 90);
      final c = Offset(x, h * 0.42 + sin(time * 0.5) * 6);
      final hull = Rect.fromCenter(center: c, width: 120, height: 36);
      canvas.drawOval(hull, Paint()
        ..shader = ui.Gradient.linear(hull.topCenter, hull.bottomCenter,
            [const Color(0xFF6B7392).withOpacity(fade), const Color(0xFF2A2F45).withOpacity(fade)]));
      // Ailerons
      final tx = c.dx - dir * 58;
      canvas.drawPath(Path()
        ..moveTo(tx, c.dy)
        ..lineTo(tx - dir * 14, c.dy - 18)
        ..lineTo(tx - dir * 4, c.dy)
        ..lineTo(tx - dir * 14, c.dy + 18)
        ..close(), Paint()..color = const Color(0xFF3A4060).withOpacity(fade));
      // Nacelle
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate(0, 22), width: 24, height: 7),
          const Radius.circular(3)), Paint()..color = const Color(0xFF1C2033).withOpacity(fade));
      // Bandeau LED qui défile
      final band = Rect.fromCenter(center: c, width: 70, height: 9);
      canvas.save();
      canvas.clipRect(band);
      canvas.drawRect(band, Paint()..color = const Color(0xFF0B0E1A).withOpacity(fade));
      for (int k = 0; k < 16; k++) {
        final bx = band.left + ((k * 9 + time * 30 * dir) % 80 + 80) % 80 - 5;
        final col = [const Color(0xFFFF4FA3), const Color(0xFF3FF1FF), const Color(0xFFFFD54F)][k % 3];
        canvas.drawRect(Rect.fromLTWH(bx, band.top + 2, 5, 5), Paint()..color = col.withOpacity(0.9 * fade));
      }
      canvas.restore();
    }

    // Montgolfières (2), brûleur qui s'allume par moments
    for (final (i, speed, yf, scale, c1, c2) in const [
      (0, 9.0, 0.30, 1.0, Color(0xFFE53935), Color(0xFFFFCA28)),
      (1, 12.0, 0.55, 0.7, Color(0xFF1E88E5), Color(0xFFFFFFFF)),
    ]) {
      final (x, _) = lane(speed, i * 41.0, 60);
      final top = Offset(x, h * yf + sin(time * 0.7 + i) * 10);
      final burn = (sin(time * 1.3 + i * 2) > 0.35) ? 1.0 : 0.0;
      canvas.save();
      canvas.translate(top.dx, top.dy);
      canvas.scale(scale);
      final env = Path()
        ..moveTo(0, 0)
        ..cubicTo(-34, 0, -38, 34, -12, 58)
        ..lineTo(12, 58)
        ..cubicTo(38, 34, 34, 0, 0, 0)
        ..close();
      canvas.save();
      canvas.clipPath(env);
      final dark = 0.45 - 0.25 * burn; // assombri la nuit, éclairé par le brûleur
      for (int k = -4; k <= 4; k++) {
        final col = Color.lerp(k.isEven ? c1 : c2, Colors.black, dark)!;
        canvas.drawPath(Path()
          ..moveTo(0, -2)
          ..quadraticBezierTo(k * 9.0, 30, k * 3.0, 60)
          ..lineTo((k + 1) * 3.0, 60)
          ..quadraticBezierTo((k + 1) * 9.0, 30, 0, -2)
          ..close(), Paint()..color = col.withOpacity(fade));
      }
      canvas.drawRect(const Rect.fromLTWH(-40, 0, 80, 62), Paint()
        ..shader = ui.Gradient.radial(const Offset(0, 58), 50,
            [const Color(0xFFFFB74D).withOpacity(0.55 * burn * fade), Colors.transparent]));
      canvas.restore();
      // Cordes, nacelle, flamme
      final rope = Paint()
        ..color = const Color(0xFF8D6E63).withOpacity(fade)
        ..strokeWidth = 1;
      canvas.drawLine(const Offset(-11, 58), const Offset(-6, 70), rope);
      canvas.drawLine(const Offset(11, 58), const Offset(6, 70), rope);
      canvas.drawRect(const Rect.fromLTWH(-7, 70, 14, 9), Paint()..color = const Color(0xFF5D4037).withOpacity(fade));
      if (burn > 0) {
        canvas.drawOval(Rect.fromCenter(center: Offset(0, 64 + sin(time * 20) * 0.8), width: 5, height: 9),
            Paint()..color = const Color(0xFFFFE082).withOpacity(fade));
      }
      canvas.restore();
    }

    // Avion de ligne : feux de navigation rouge/vert + flash blanc
    {
      final (x, dir) = lane(70, 7, 50);
      final c = Offset(x, h * 0.16 + sin(time * 0.3) * 4);
      final sil = Paint()..color = const Color(0xFF2A3050).withOpacity(fade);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: 34, height: 5), const Radius.circular(3)), sil);
      canvas.drawPath(Path()
        ..moveTo(c.dx + dir * 2, c.dy)
        ..lineTo(c.dx - dir * 6, c.dy + 11)
        ..lineTo(c.dx - dir * 10, c.dy + 11)
        ..lineTo(c.dx - dir * 6, c.dy)
        ..close(), sil);
      canvas.drawPath(Path()
        ..moveTo(c.dx - dir * 13, c.dy)
        ..lineTo(c.dx - dir * 17, c.dy - 9)
        ..lineTo(c.dx - dir * 19, c.dy - 9)
        ..lineTo(c.dx - dir * 17, c.dy)
        ..close(), sil);
      // Hublots
      final win = Paint()..color = const Color(0xFFFFE6A0).withOpacity(0.8 * fade);
      for (int k = -3; k <= 3; k++) {
        canvas.drawCircle(c.translate(k * 3.5, -0.5), 0.7, win);
      }
      canvas.drawCircle(c.translate(-dir * 8, 10), 1.6, Paint()..color = const Color(0xFFFF3B3B).withOpacity(fade));
      canvas.drawCircle(c.translate(-dir * 17, -9), 1.4, Paint()..color = const Color(0xFF4CFF7A).withOpacity(fade));
      if (sin(time * 7) > 0.85) {
        canvas.drawCircle(c.translate(dir * 17, 0), 6, Paint()
          ..color = Colors.white.withOpacity(0.7 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      }
    }

    // Hélicoptère : rotor, feu rouge, projecteur balayant vers le bas
    {
      final (x, dir) = lane(45, 19, 60);
      final c = Offset(x, h * 0.66 + sin(time * 1.1) * 8);
      final beamA = pi / 2 + sin(time * 0.9) * 0.35;
      canvas.drawPath(Path()
        ..moveTo(c.dx, c.dy + 5)
        ..lineTo(c.dx + cos(beamA - 0.12) * 260, c.dy + sin(beamA - 0.12) * 260)
        ..lineTo(c.dx + cos(beamA + 0.12) * 260, c.dy + sin(beamA + 0.12) * 260)
        ..close(), Paint()
        ..shader = ui.Gradient.linear(c, c + Offset(cos(beamA) * 260, sin(beamA) * 260),
            [const Color(0xFFFFF6D0).withOpacity(0.22 * fade), Colors.transparent]));
      final sil = Paint()..color = const Color(0xFF1C2238).withOpacity(fade);
      canvas.drawOval(Rect.fromCenter(center: c, width: 22, height: 11), sil);
      canvas.drawRect(Rect.fromLTWH(dir > 0 ? c.dx - 26 : c.dx + 8, c.dy - 2, 18, 3), sil);
      canvas.drawRect(Rect.fromLTWH(c.dx - 1, c.dy - 9, 2, 4), sil);
      final rl = 26 * cos(time * 40).abs() + 4;
      canvas.drawLine(c.translate(-rl, -9), c.translate(rl, -9), Paint()
        ..color = const Color(0xFF8A93B8).withOpacity(0.7 * fade)
        ..strokeWidth = 1.4);
      canvas.drawOval(Rect.fromCenter(center: c.translate(dir * 5, -1), width: 7, height: 5),
          Paint()..color = const Color(0xFF9FD4FF).withOpacity(0.6 * fade));
      if (sin(time * 5) > 0) {
        canvas.drawCircle(c.translate(-dir * 24, -2), 1.8, Paint()..color = const Color(0xFFFF3B3B).withOpacity(fade));
      }
    }
  }

  /// Premier plan : lianes et feuilles (jungle), poussière (canyon), bruine (ville).
  void _paintSceneFront(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    switch (_sk) {
      case 0:
        final vine = Paint()
          ..color = const Color(0xFF2E5A2A)
          ..strokeWidth = 2.4
          ..style = PaintingStyle.stroke;
        final leaf = Paint()..color = const Color(0xFF4F8A3A);
        for (int i = 0; i < 7; i++) {
          final y0 = _rep(i, 190, 1.0, size);
          final len = 110.0 + (i % 3) * 60;
          final x0 = i.isEven ? 10.0 + i * 3 : w - 12.0 - i * 3;
          final path = Path()..moveTo(x0, y0);
          for (double d = 0; d <= len; d += 10) {
            path.lineTo(x0 + sin(d * 0.06 + time * 1.2 + i) * 5, y0 + d);
          }
          canvas.drawPath(path, vine);
          for (double d = 15; d <= len - 5; d += 22) {
            final p = Offset(x0 + sin(d * 0.06 + time * 1.2 + i) * 5, y0 + d);
            canvas.save();
            canvas.translate(p.dx, p.dy);
            canvas.rotate((d ~/ 22).isEven ? 0.7 : -0.7);
            canvas.drawOval(Rect.fromCenter(center: const Offset(6, 0), width: 12, height: 5), leaf);
            canvas.restore();
          }
        }
        // Feuilles qui tombent
        for (int j = 0; j < 7; j++) {
          final x = (j * 97 + time * 18 * (1 + j % 3) + sin(time + j) * 20) % w;
          final y = (j * 173 + time * (30 + j * 6)) % h;
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(time * 2 + j);
          canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 8, height: 4), Paint()..color = const Color(0xFF7FB348).withOpacity(0.8));
          canvas.restore();
        }
        break;
      case 2:
        final rain = Paint()
          ..color = const Color(0xFF9FB4FF).withOpacity(0.18)
          ..strokeWidth = 1;
        for (int j = 0; j < 40; j++) {
          final x = (j * 61.0 + time * 40) % w;
          final y = (j * 97.0 + time * 520) % (h + 20) - 20;
          canvas.drawLine(Offset(x, y), Offset(x - 3, y + 12), rain);
        }
        _paintVignette(canvas, size);
        break;
      case 3:
        final dust = Paint()..color = const Color(0xFFFFE2B0).withOpacity(0.35);
        for (int j = 0; j < 18; j++) {
          final x = (j * 83 + time * 25 * (1 + j % 2)) % w;
          final y = (j * 151 + sin(time * 0.8 + j) * 30) % h;
          canvas.drawCircle(Offset(x, y), 1.2 + (j % 3) * 0.5, dust);
        }
        break;
      default:
        break;
    }
  }

  /// Plateformes des thèmes « scène »
  void _paintScenePlat(Canvas canvas, _Plat p, Offset o) {
    final op = p.broken ? 0.5 : 1.0;
    canvas.save();
    if (p.broken) {
      canvas.translate(o.dx + _platW / 2, o.dy + _platH / 2);
      canvas.rotate(0.25);
      canvas.translate(-(o.dx + _platW / 2), -(o.dy + _platH / 2));
    }
    final r = Rect.fromLTWH(o.dx, o.dy, _platW, _platH);
    canvas.drawRRect(RRect.fromRectAndRadius(r.shift(const Offset(-4, 7)), const Radius.circular(4)), Paint()
      ..color = Colors.black.withOpacity(0.3 * op)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    final type = p.type;
    final seed = (p.x * 7).toInt() + (p.y * 3).toInt();
    // Couleurs (haut, milieu, bas) selon le thème et le type
    final List<Color> cols = switch ((_sk, type)) {
      (0, _PlatType.moving) => const [Color(0xFFB8DB72), Color(0xFF7FAF3E), Color(0xFF4E7A22)],      // bambou
      (0, _PlatType.breakable) => const [Color(0xFF7A5A3A), Color(0xFF55391F), Color(0xFF2F1E10)],   // tronc pourri
      (0, _) => const [Color(0xFFA6AC98), Color(0xFF747B66), Color(0xFF444A3A)],                       // pierre moussue
      (1, _PlatType.moving) => const [Color(0xFFFFFFFF), Color(0xFFE9F7FF), Color(0xFFBFDDEA)],      // planche de surf
      (1, _PlatType.breakable) => const [Color(0xFFC9C1B5), Color(0xFF9A9184), Color(0xFF6B6357)],   // bois flotté
      (1, _) => const [Color(0xFFF0CC90), Color(0xFFC99A5A), Color(0xFF8A6232)],                       // planches claires
      (2, _PlatType.moving) => const [Color(0xFFBFD3E0), Color(0xFF7F97A8), Color(0xFF4B5D6B)],      // plateforme d'élévateur
      (2, _PlatType.breakable) => const [Color(0xFF8A6A50), Color(0xFF5E4330), Color(0xFF3A271A)],   // grille rouillée
      (2, _) => const [Color(0xFFD9573A), Color(0xFFA83A22), Color(0xFF6B2112)],                       // poutrelle d'acier
      (_, _PlatType.moving) => const [Color(0xFFD8AE74), Color(0xFFAD8048), Color(0xFF6E4D25)],      // planche + cordes
      (_, _PlatType.breakable) => const [Color(0xFFA88C76), Color(0xFF7C624F), Color(0xFF4F3D30)],   // roche fendue
      (_, _) => const [Color(0xFFE8A86E), Color(0xFFBF6E3E), Color(0xFF7E3F1E)],                       // grès
    };
    final surf = _sk == 1 && type == _PlatType.moving;
    final rr = RRect.fromRectAndRadius(r, Radius.circular(surf ? _platH / 2 : 3));
    canvas.drawRRect(rr, Paint()
      ..shader = ui.Gradient.linear(r.topLeft, r.bottomLeft, [for (final c in cols) c.withOpacity(op)], [0, 0.45, 1]));
    canvas.save();
    canvas.clipRRect(rr);
    switch ((_sk, type)) {
      case (0, _PlatType.moving):
        for (double x = o.dx + 12; x < o.dx + _platW; x += 16) {
          canvas.drawRect(Rect.fromLTWH(x, o.dy, 2, _platH), Paint()..color = const Color(0xFF3E6418).withOpacity(0.7 * op));
        }
        break;
      case (0, _PlatType.normal) || (0, _PlatType.spring):
        final moss = Paint()..color = const Color(0xFF5F9A36).withOpacity(op);
        canvas.drawRect(Rect.fromLTWH(o.dx, o.dy, _platW, 3.5), moss);
        for (double x = o.dx + 3; x < o.dx + _platW; x += 7) {
          canvas.drawCircle(Offset(x, o.dy + 3.5), 2 + ((x + seed).toInt() % 3) * 0.6, moss);
        }
        break;
      case (1, _PlatType.moving):
        canvas.drawRect(Rect.fromLTWH(o.dx, o.dy + _platH / 2 - 2, _platW, 4), Paint()..color = const Color(0xFFFF6E5A).withOpacity(op));
        canvas.drawRect(Rect.fromLTWH(o.dx + _platW / 2 - 1, o.dy, 2, _platH), Paint()..color = const Color(0xFF29B6F6).withOpacity(op));
        break;
      case (1, _) || (3, _PlatType.moving):
        for (double x = o.dx + 15 + seed.abs() % 8; x < o.dx + _platW; x += 17) {
          canvas.drawLine(Offset(x, o.dy), Offset(x, o.dy + _platH), Paint()
            ..color = Colors.black.withOpacity(0.25 * op)
            ..strokeWidth = 1);
        }
        break;
      case (2, _PlatType.moving):
        final hz = Paint()..color = const Color(0xFFFFC107).withOpacity(op);
        for (double x = o.dx - 6; x < o.dx + _platW; x += 10) {
          canvas.drawPath(Path()
            ..moveTo(x, o.dy + _platH)
            ..lineTo(x + 5, o.dy + _platH)
            ..lineTo(x + 9, o.dy + _platH - 4)
            ..lineTo(x + 4, o.dy + _platH - 4)
            ..close(), hz);
        }
        break;
      case (2, _):
        // Âme de la poutrelle + rivets
        canvas.drawRect(Rect.fromLTWH(o.dx, o.dy + 4, _platW, _platH - 8), Paint()..color = Colors.black.withOpacity(0.18 * op));
        for (double x = o.dx + 6; x < o.dx + _platW; x += 12) {
          canvas.drawCircle(Offset(x, o.dy + 2.4), 1.2, Paint()..color = Colors.white.withOpacity(0.5 * op));
          canvas.drawCircle(Offset(x, o.dy + _platH - 2.4), 1.2, Paint()..color = Colors.white.withOpacity(0.5 * op));
        }
        break;
      case (3, _):
        final strata = Paint()..color = const Color(0xFF6E2E12).withOpacity(0.3 * op);
        canvas.drawRect(Rect.fromLTWH(o.dx, o.dy + 5, _platW, 1.6), strata);
        canvas.drawRect(Rect.fromLTWH(o.dx, o.dy + 10, _platW, 1.2), strata);
        break;
      default:
        break;
    }
    canvas.drawRect(Rect.fromLTWH(o.dx, o.dy, _platW, 1.4), Paint()..color = Colors.white.withOpacity(0.35 * op));
    canvas.restore();
    // Cordes (canyon, plateforme mobile)
    if (_sk == 3 && type == _PlatType.moving) {
      final rope = Paint()
        ..color = const Color(0xFF8D6E4A)
        ..strokeWidth = 1.4;
      canvas.drawLine(Offset(o.dx + 6, o.dy), Offset(o.dx + 6, o.dy - 30), rope);
      canvas.drawLine(Offset(o.dx + _platW - 6, o.dy), Offset(o.dx + _platW - 6, o.dy - 30), rope);
    }
    if (type == _PlatType.breakable) {
      canvas.drawPath(Path()
        ..moveTo(o.dx + 22, o.dy)
        ..lineTo(o.dx + 28, o.dy + 6)
        ..lineTo(o.dx + 24, o.dy + 10)
        ..lineTo(o.dx + 31, o.dy + _platH)
        ..moveTo(o.dx + 46, o.dy)
        ..lineTo(o.dx + 41, o.dy + 7)
        ..lineTo(o.dx + 47, o.dy + _platH), Paint()
        ..color = Colors.black.withOpacity(0.7 * op)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke);
    }
    if (type == _PlatType.spring) {
      final cx = o.dx + _platW / 2;
      final path = Path()..moveTo(cx - 6, o.dy);
      for (int i = 0; i < 4; i++) {
        path.lineTo(i.isEven ? cx + 6 : cx - 6, o.dy - 3 - i * 3);
      }
      canvas.drawPath(path, Paint()
        ..color = const Color(0xFF6E7B86)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke);
      canvas.drawPath(path, Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);
      final top = Rect.fromLTWH(cx - 10, o.dy - 17, 20, 5);
      canvas.drawRRect(RRect.fromRectAndRadius(top, const Radius.circular(2)), Paint()
        ..shader = ui.Gradient.linear(top.topLeft, top.bottomLeft, const [Color(0xFFF2F5F8), Color(0xFF7D8A96)]));
    }
    canvas.restore();
  }

  bool get _real => theme == 10;

  /// Night: darkened background, twinkling stars, moon, shooting star
  void _paintNightSky(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF050A20).withOpacity(0.66));
    final star = Paint();
    for (int i = 0; i < 80; i++) {
      final sx = ((i * 7919) % 1000) / 1000 * w;
      final base = ((i * 104729) % 1000) / 1000 * h;
      final sy = (base - camY * 0.08) % h;
      final tw = 0.5 + 0.5 * sin(time * (1.5 + i % 3) + i);
      star.color = Colors.white.withOpacity(0.2 + 0.7 * tw);
      canvas.drawCircle(Offset(sx, sy), i % 9 == 0 ? 1.7 : 1.0, star);
    }
    // Moon and halo
    final moon = Offset(w * 0.78, h * 0.15);
    canvas.drawCircle(moon, 90, Paint()
      ..shader = ui.Gradient.radial(moon, 90, [const Color(0x55FFF8E1), const Color(0x00FFF8E1)]));
    canvas.drawCircle(moon, 24, Paint()
      ..shader = ui.Gradient.radial(moon.translate(-6, -6), 30, [const Color(0xFFFFFDF0), const Color(0xFFD8D6C4)]));
    final crater = Paint()..color = const Color(0xFFBDBBA8).withOpacity(0.7);
    canvas.drawCircle(moon.translate(6, 4), 5, crater);
    canvas.drawCircle(moon.translate(-8, 8), 3, crater);
    canvas.drawCircle(moon.translate(2, -10), 2.5, crater);
    // Shooting star every ~7 s
    final t = time % 7;
    if (t < 0.7) {
      final k = t / 0.7;
      final a = Offset(w * (0.15 + 0.5 * k), h * (0.08 + 0.18 * k));
      canvas.drawLine(a, a.translate(-60, -22), Paint()
        ..shader = ui.Gradient.linear(a, a.translate(-60, -22),
            [Colors.white.withOpacity(0.9 * (1 - k)), Colors.white.withOpacity(0)])
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round);
    }
  }

  /// Matrix: falling code rain (pseudo glyphs)
  void _paintMatrixRain(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black.withOpacity(0.6));
    const cw = 14.0, ch = 14.0;
    final cols = (size.width / cw).ceil();
    final paint = Paint();
    for (int c = 0; c < cols; c++) {
      final speed = 80 + (c * 7919) % 140;
      final len = 7 + (c * 104729) % 11;
      final span = size.height + len * ch;
      final head = (time * speed + (c * 3571) % 997) % span;
      final x = c * cw + 3;
      for (int k = 0; k < len; k++) {
        final y = head - k * ch;
        if (y < -ch || y > size.height) continue;
        final g = (c * 31 + k * 17 + (k == 0 ? (time * 8).floor() : (time * 2).floor())) % 7;
        paint.color = (k == 0 ? const Color(0xFFD7FFD9) : const Color(0xFF00FF41))
            .withOpacity(k == 0 ? 0.9 : (1 - k / len) * 0.5);
        canvas.drawRect(Rect.fromLTWH(x, y, 8, 2), paint);
        canvas.drawRect(Rect.fromLTWH(x + (g.isEven ? 0 : 6), y, 2, 10), paint);
        if (g > 2) canvas.drawRect(Rect.fromLTWH(x, y + 3 + g, 8, 2), paint);
        if (g == 5) canvas.drawRect(Rect.fromLTWH(x + 3, y + 2, 2, 6), paint);
      }
    }
  }

  // Realistic sky: (altitude in pts, top colour, horizon colour)
  static const _skyKeys = <(double, Color, Color)>[
    (0.0, Color(0xFF3A7BD5), Color(0xFFCDE9F8)),
    (1500.0, Color(0xFF2B5DAE), Color(0xFFA6D4F2)),
    (3000.0, Color(0xFF3B2F6B), Color(0xFFF4A75C)), // sunset
    (4500.0, Color(0xFF121838), Color(0xFF5E4A8C)),
    (6500.0, Color(0xFF01020A), Color(0xFF0D1530)), // space
  ];

  /// Realistic: altitude-based sky, sun, mountains, clouds, ground
  void _paintRealSky(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final alt = max(0.0, (startY - camY - h / 2) / 10);
    var top = _skyKeys.last.$2, bot = _skyKeys.last.$3;
    for (int i = 0; i < _skyKeys.length - 1; i++) {
      final a = _skyKeys[i], b = _skyKeys[i + 1];
      if (alt <= b.$1) {
        final t = ((alt - a.$1) / (b.$1 - a.$1)).clamp(0.0, 1.0);
        top = Color.lerp(a.$2, b.$2, t)!;
        bot = Color.lerp(a.$3, b.$3, t)!;
        break;
      }
    }
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), [top, Color.lerp(top, bot, 0.55)!, bot], [0, 0.6, 1]));
    // Stars appear at altitude
    final space = ((alt - 3600) / 2400).clamp(0.0, 1.0);
    if (space > 0) {
      final sp = Paint();
      for (int i = 0; i < 90; i++) {
        final sx = ((i * 7919) % 1000) / 1000 * w;
        final sy = (((i * 104729) % 1000) / 1000 * h - camY * 0.05) % h;
        sp.color = Colors.white.withOpacity(space * (0.35 + 0.55 * (0.5 + 0.5 * sin(time * 2 + i))));
        canvas.drawCircle(Offset(sx, sy), i % 8 == 0 ? 1.5 : 0.9, sp);
      }
    }
    // Sun: wide halo + disc, whiter at altitude
    final sun = Offset(w * 0.8, h * 0.14);
    final warm = ((alt - 1800) / 1500).clamp(0.0, 1.0) * (1 - space);
    final halo = Color.lerp(const Color(0xFFFFF4C4), const Color(0xFFFFB25A), warm)!;
    canvas.drawCircle(sun, 170, Paint()
      ..shader = ui.Gradient.radial(sun, 170, [halo.withOpacity(0.45), halo.withOpacity(0.12), halo.withOpacity(0)], [0, 0.35, 1]));
    canvas.drawCircle(sun, 26, Paint()
      ..shader = ui.Gradient.radial(sun, 26, [Colors.white, Color.lerp(const Color(0xFFFFF3B0), const Color(0xFFFF9E40), warm)!]));
    // Slowly rotating light rays
    final ray = Paint()..color = halo.withOpacity(0.06 * (1 - space));
    for (int i = 0; i < 7; i++) {
      final a = time * 0.05 + i * pi * 2 / 7;
      canvas.drawPath(Path()
        ..moveTo(sun.dx, sun.dy)
        ..lineTo(sun.dx + cos(a - 0.05) * 600, sun.dy + sin(a - 0.05) * 600)
        ..lineTo(sun.dx + cos(a + 0.05) * 600, sun.dy + sin(a + 0.05) * 600)
        ..close(), ray);
    }
    // Mountains (2 layers, haze) then ground
    _paintRealMountains(canvas, size, 0.18, const Color(0xFF9DB4CC), 1.0, 0.7);
    final hz = startY - camY * 0.3;
    if (hz - 160 < size.height) {
      canvas.drawRect(Rect.fromLTWH(0, hz - 160, w, 220), Paint()
        ..shader = ui.Gradient.linear(Offset(0, hz - 160), Offset(0, hz + 60),
            [Colors.white.withOpacity(0), Colors.white.withOpacity(0.28)]));
    }
    _paintRealMountains(canvas, size, 0.35, const Color(0xFF5E7F6E), 0.7, 1.4);
    _paintRealClouds(canvas, size, space);
    _paintRealGround(canvas, size);
  }

  void _paintRealMountains(Canvas canvas, Size size, double par, Color c, double amp, double seed) {
    final w = size.width;
    final base = startY + 24 - camY * par;
    if (base - 170 * amp > size.height) return;
    final path = Path()..moveTo(0, size.height + 400);
    for (double x = 0; x <= w + 8; x += 8) {
      final y = base - (70 + 45 * sin(x * 0.011 + seed) + 28 * sin(x * 0.029 + seed * 2.3) + 12 * sin(x * 0.07 + seed)) * amp;
      path.lineTo(x, y);
    }
    path
      ..lineTo(w, size.height + 400)
      ..close();
    canvas.drawPath(path, Paint()
      ..shader = ui.Gradient.linear(Offset(0, base - 160 * amp), Offset(0, base + 40),
          [c, Color.lerp(c, Colors.black, 0.25)!]));
    // Snow on the far peaks
    if (par < 0.25) {
      canvas.save();
      canvas.clipPath(path);
      canvas.drawRect(Rect.fromLTWH(0, base - 200 * amp, w, 75 * amp), Paint()..color = Colors.white.withOpacity(0.55));
      canvas.restore();
    }
  }

  void _paintRealClouds(Canvas canvas, Size size, double space) {
    if (space >= 1) return;
    final w = size.width;
    final lo = _heightAt(size.height + 80), hi = _heightAt(-80);
    final blur = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);
    for (int i = max(1, (lo / 70).floor()); i <= (hi / 70).ceil(); i++) {
     for (int j = 0; j < 2; j++) {
      final k = i * 2 + j;
      final hpts = i * 70.0 + ((k * 37) % 35);
      final cy = _syOfHeight(hpts);
      final drift = time * (6 + (k * 13) % 10);
      final cx = ((k * 7919) % 1000) / 1000 * (w + 220) + drift;
      final x = cx % (w + 220) - 110;
      final s = (j == 0 ? 0.8 : 0.5) + ((k * 104729) % 100) / 100 * 0.6;
      final o = (1 - space) * 0.9;
      // Underside shadow then bright body
      blur.color = const Color(0xFFB8C4D0).withOpacity(o);
      canvas.drawOval(Rect.fromCenter(center: Offset(x, cy + 8 * s), width: 120 * s, height: 26 * s), blur);
      blur.color = Colors.white.withOpacity(o);
      for (final b in const [(-34.0, 2.0, 22.0), (-12.0, -8.0, 28.0), (14.0, -4.0, 25.0), (36.0, 4.0, 18.0), (0.0, 6.0, 24.0)]) {
        canvas.drawCircle(Offset(x + b.$1 * s, cy + b.$2 * s), b.$3 * s, blur);
      }
     }
    }
  }

  void _paintRealGround(Canvas canvas, Size size) {
    final gy = startY + 18 - camY;
    if (gy > size.height + 10) return;
    final r = Rect.fromLTWH(0, gy, size.width, size.height - gy + 400);
    canvas.drawRect(r, Paint()
      ..shader = ui.Gradient.linear(Offset(0, gy), Offset(0, gy + 120),
          [const Color(0xFF6DA544), const Color(0xFF3E6B2A), const Color(0xFF4A3424)], [0, 0.18, 1]));
    final blade = Paint()
      ..color = const Color(0xFF8CC65A)
      ..strokeWidth = 1.4;
    for (double x = 2; x < size.width; x += 5) {
      final hh = 4 + ((x * 13).toInt() % 6);
      canvas.drawLine(Offset(x, gy + 2), Offset(x + sin(time * 2 + x) * 1.2, gy - hh), blade);
    }
  }

  /// Realistic platform: wooden plank, steel beam, rotten wood, drop shadow
  void _paintRealPlat(Canvas canvas, _Plat p, Offset o) {
    final op = p.broken ? 0.5 : 1.0;
    canvas.save();
    if (p.broken) {
      canvas.translate(o.dx + _platW / 2, o.dy + _platH / 2);
      canvas.rotate(0.25);
      canvas.translate(-(o.dx + _platW / 2), -(o.dy + _platH / 2));
    }
    final r = Rect.fromLTWH(o.dx, o.dy, _platW, _platH);
    canvas.drawRRect(RRect.fromRectAndRadius(r.shift(const Offset(-5, 8)), const Radius.circular(4)), Paint()
      ..color = Colors.black.withOpacity(0.3 * op)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    final List<Color> cols;
    switch (p.type) {
      case _PlatType.moving:
        cols = const [Color(0xFFEEF2F6), Color(0xFF9AA6B2), Color(0xFF55606B)];
        break;
      case _PlatType.breakable:
        cols = const [Color(0xFF8D7B6A), Color(0xFF5D4A3C), Color(0xFF33251C)];
        break;
      default:
        cols = const [Color(0xFFD9A46A), Color(0xFFA8743F), Color(0xFF6B4423)];
    }
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(3));
    canvas.drawRRect(rr, Paint()
      ..shader = ui.Gradient.linear(r.topLeft, r.bottomLeft, [for (final c in cols) c.withOpacity(op)], [0, 0.45, 1]));
    canvas.save();
    canvas.clipRRect(rr);
    if (p.type == _PlatType.moving) {
      // Brushed steel + rivets
      final line = Paint()..color = Colors.white.withOpacity(0.12 * op)..strokeWidth = 0.8;
      for (double y = o.dy + 3; y < o.dy + _platH - 2; y += 2.5) {
        canvas.drawLine(Offset(o.dx, y), Offset(o.dx + _platW, y), line);
      }
      for (final rx in [o.dx + 6, o.dx + _platW - 6]) {
        final c = Offset(rx, o.dy + _platH / 2);
        canvas.drawCircle(c, 2.4, Paint()
          ..shader = ui.Gradient.radial(c.translate(-0.8, -0.8), 3, [Colors.white.withOpacity(op), const Color(0xFF4A545E).withOpacity(op)]));
      }
    } else {
      // Wood grain, plank joint, knot
      final seed = (p.x * 7).toInt() + (p.y * 3).toInt();
      final grain = Paint()
        ..color = const Color(0xFF4A2E16).withOpacity(0.35 * op)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9;
      for (int k = 0; k < 3; k++) {
        final gy = o.dy + 3.5 + k * 3.5;
        final path = Path()..moveTo(o.dx, gy);
        for (double x = 0; x <= _platW; x += 6) {
          path.lineTo(o.dx + x, gy + sin(x * 0.18 + seed + k * 1.7) * 0.9);
        }
        canvas.drawPath(path, grain);
      }
      final jx = o.dx + 16 + (seed.abs() % 36);
      canvas.drawLine(Offset(jx, o.dy), Offset(jx, o.dy + _platH), Paint()
        ..color = Colors.black.withOpacity(0.35 * op)
        ..strokeWidth = 1);
      canvas.drawOval(Rect.fromCenter(center: Offset(o.dx + 8 + (seed.abs() % 50), o.dy + 7), width: 5, height: 3),
          Paint()..color = const Color(0xFF3B2412).withOpacity(0.55 * op));
    }
    // Highlight on the top edge
    canvas.drawRect(Rect.fromLTWH(o.dx, o.dy, _platW, 1.6), Paint()..color = Colors.white.withOpacity(0.4 * op));
    canvas.restore();
    if (p.type == _PlatType.breakable) {
      final crack = Paint()
        ..color = Colors.black.withOpacity(0.7 * op)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawPath(Path()
        ..moveTo(o.dx + 22, o.dy)
        ..lineTo(o.dx + 28, o.dy + 6)
        ..lineTo(o.dx + 24, o.dy + 10)
        ..lineTo(o.dx + 31, o.dy + _platH)
        ..moveTo(o.dx + 46, o.dy)
        ..lineTo(o.dx + 41, o.dy + 7)
        ..lineTo(o.dx + 47, o.dy + _platH), crack);
    }
    if (p.type == _PlatType.spring) {
      // Chrome spring
      final cx = o.dx + _platW / 2;
      final path = Path()..moveTo(cx - 6, o.dy);
      for (int i = 0; i < 4; i++) {
        path.lineTo(i.isEven ? cx + 6 : cx - 6, o.dy - 3 - i * 3);
      }
      canvas.drawPath(path, Paint()
        ..color = const Color(0xFF6E7B86)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke);
      canvas.drawPath(path, Paint()
        ..color = Colors.white.withOpacity(0.8)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke);
      final top = Rect.fromLTWH(cx - 10, o.dy - 17, 20, 5);
      canvas.drawRRect(RRect.fromRectAndRadius(top, const Radius.circular(2)), Paint()
        ..shader = ui.Gradient.linear(top.topLeft, top.bottomLeft, const [Color(0xFFF2F5F8), Color(0xFF7D8A96)]));
    }
    canvas.restore();
  }

  /// Finishing: vignette (and blue tint at night)
  void _paintVignette(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.radial(c, size.longestSide * 0.75,
          [Colors.transparent, Colors.black.withOpacity(_night ? 0.55 : 0.32)], [0.55, 1]));
    if (_night) canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1A237E).withOpacity(0.10));
  }

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
    if (_real || _castle || _scene) {
      // Gold coin: metallic gradient + highlight
      canvas.drawCircle(Offset.zero, _coinR, Paint()
        ..shader = ui.Gradient.radial(const Offset(-2.5, -2.5), _coinR * 1.6,
            const [Color(0xFFFFF7CF), Color(0xFFF2C440), Color(0xFFA8780A)], [0, 0.45, 1]));
      canvas.drawCircle(Offset.zero, _coinR - 0.6, Paint()
        ..color = const Color(0xFF7A5606)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2);
      canvas.drawCircle(const Offset(-2.4, -2.6), 1.8, Paint()..color = Colors.white.withOpacity(0.85));
      canvas.restore();
      return;
    }
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
  /// #1 ghost: translucent hero + name
  // ── Jump trail + weather ─────────────────────────────
  void _paintTrail(Canvas canvas) {
    final n = trailPts.length;
    if (trailKind == 0 || n < 2) return;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (int i = 0; i < n; i++) {
      final p = trailPts[i];
      final age = ((time - p.$3) / 0.45).clamp(0.0, 1.0);
      final a = 1 - age;
      if (a <= 0) continue;
      final o = Offset(p.$1, p.$2 - camY);
      switch (trailKind) {
        case 1: // rainbow
          if (i == 0) break;
          final q = trailPts[i - 1];
          if ((q.$1 - p.$1).abs() > 80) break;
          paint
            ..color = HSVColor.fromAHSV(a, (time * 120 + i * 18) % 360, 0.85, 1).toColor()
            ..strokeWidth = 2 + 7 * a;
          canvas.drawLine(Offset(q.$1, q.$2 - camY), o, paint);
          break;
        case 2: // sparkles
          final s = 2 + 4 * a * (0.6 + 0.4 * sin(time * 20 + p.$4));
          paint
            ..color = (p.$4.isEven ? const Color(0xFFFFE082) : Colors.white).withOpacity(a)
            ..strokeWidth = 1.6;
          canvas.drawLine(o.translate(-s, 0), o.translate(s, 0), paint);
          canvas.drawLine(o.translate(0, -s), o.translate(0, s), paint);
          break;
        case 3: // falling retro pixels
          const cols = [Color(0xFFFF4081), Color(0xFF18FFFF), Color(0xFFFFEB3B), Color(0xFF76FF03)];
          paint.color = cols[p.$4 % 4].withOpacity(a);
          canvas.drawRect(Rect.fromCenter(center: o.translate(((p.$4 % 7) - 3).toDouble(), age * 22), width: 5, height: 5), paint);
          break;
        case 4: // flames
          paint
            ..color = Color.lerp(const Color(0xFFFFE57F), const Color(0xFFFF3D00), age)!.withOpacity(a * 0.85)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
          canvas.drawCircle(o.translate(0, -age * 6), 2 + 6 * a, paint);
          paint.maskFilter = null;
          break;
        case 5: // bubbles
          paint
            ..color = const Color(0xFF81D4FA).withOpacity(a * 0.8)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2;
          canvas.drawCircle(o.translate(((p.$4 % 5) - 2).toDouble(), -age * 26), 2 + age * 5, paint);
          paint.style = PaintingStyle.fill;
          break;
      }
    }
  }

  void _paintWeather(Canvas canvas, Size size) {
    if (weather < 0 || weatherAlpha <= 0) return;
    final w = size.width, h = size.height, a = weatherAlpha;
    final p = Paint()..strokeCap = StrokeCap.round;
    switch (weather) {
      case 0: // wind: horizontal gusts
        for (int i = 0; i < 22; i++) {
          final y = _h(i, 3) * h;
          final len = 30 + _h(i, 5) * 60;
          final x = (_h(i, 7) * (w + 200) + time * (380 + _h(i, 9) * 200) * windDir) % (w + 200) - 100;
          p
            ..color = Colors.white.withOpacity(0.22 * a)
            ..strokeWidth = 1.4;
          canvas.drawLine(Offset(x, y), Offset(x - len * windDir, y + sin(time * 3 + i) * 2), p);
        }
        break;
      case 1:
      case 2: // rain (and storm)
        if (weather == 2) {
          canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0A0F1E).withOpacity(0.35 * a));
        }
        p
          ..color = const Color(0xFFB3E5FC).withOpacity(0.38 * a)
          ..strokeWidth = 1.2;
        for (int i = 0; i < 110; i++) {
          final x = (_h(i, 11) * (w + 60) + time * 60) % (w + 60) - 30;
          final y = (_h(i, 13) * (h + 40) + time * (650 + _h(i, 17) * 250)) % (h + 40) - 20;
          canvas.drawLine(Offset(x, y), Offset(x - 4, y + 14), p);
        }
        if (flash > 0) {
          canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white.withOpacity((flash / 0.3).clamp(0.0, 1.0) * 0.65));
        }
        break;
      case 3: // fog: only the area around the hero is visible
        final c = Offset(heroX, heroY - camY - 20);
        canvas.drawRect(Offset.zero & size, Paint()
          ..shader = ui.Gradient.radial(c, 270, [
            const Color(0x00B0BEC5),
            const Color(0x00B0BEC5),
            const Color(0xFFB0BEC5).withOpacity(0.88 * a),
          ], [0, 0.4, 1]));
        break;
    }
  }

  void _paintGhost(Canvas canvas, Size size) {
    final g = ghost;
    if (g == null) return;
    final sy = g.$2 - camY;
    if (sy < -70 || sy > size.height + 20) return;
    canvas.saveLayer(Rect.fromLTWH(g.$1 - 50, sy - 70, 100, 80), Paint()..color = Colors.white.withOpacity(0.42));
    canvas.translate(g.$1, sy);
    _drawHero(canvas, min(max(g.$4, 0), _heroCount - 1), g.$5, time);
    canvas.restore();
    final tp = TextPainter(
      text: TextSpan(text: '👻 ${g.$3}',
          style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800,
              shadows: [Shadow(color: Colors.black, blurRadius: 4)])),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);
    tp.paint(canvas, Offset(g.$1 - tp.width / 2, sy - 62));
  }

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
