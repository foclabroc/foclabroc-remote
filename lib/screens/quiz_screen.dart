import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_state.dart';
import 'quiz_audio_service.dart';

// ─── Constantes ───────────────────────────────────────────────────────────────

const _kBestScoreKey = 'quiz_screenshot_best_score';
const _totalQuestions = 10;
const _timePerQuestion = 20;

// ─── Page d'accueil Quiz ──────────────────────────────────────────────────────

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _bestScore = 0;
  bool _loadingBest = true;

  @override
  void initState() {
    super.initState();
    _loadBestScore();
  }

  Future<void> _loadBestScore() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _bestScore = prefs.getInt(_kBestScoreKey) ?? 0;
      _loadingBest = false;
    });
  }

  void _onGameFinished(int score) async {
    final prefs = await SharedPreferences.getInstance();
    if (score > _bestScore) {
      await prefs.setInt(_kBestScoreKey, score);
    }
    if (mounted) setState(() => _bestScore = score > _bestScore ? score : _bestScore);
  }

  void _startGame() {
    final state = context.read<AppState>();
    if (!state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Connecte-toi à Batocera d\'abord',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF1C2230),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    Navigator.of(context, rootNavigator: false).push(
      MaterialPageRoute(
        builder: (_) => _QuizGameScreen(onFinished: _onGameFinished),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final connected = context.watch<AppState>().isConnected;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(64, 8, 24, 0),
            child: Row(children: [
              Text('Quiz Rétro',
                  style: Theme.of(context).textTheme.headlineMedium),
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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent.withOpacity(0.1),
                      ),
                      child: Icon(Icons.quiz_rounded, size: 56, color: accent),
                    ),
                    const SizedBox(height: 16),
                    const Text('Reconnais le jeu !',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    const Text(
                      'Un screenshot s\'affiche,\ntrouve le jeu parmi 4 propositions.',
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
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 26),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Meilleur score',
                            style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
                        const SizedBox(height: 2),
                        _loadingBest
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent))
                            : Text(
                                _bestScore == 0 ? '— pts' : '$_bestScore pts',
                                style: const TextStyle(color: Colors.amberAccent, fontSize: 28, fontWeight: FontWeight.w900)),
                      ]),
                    ),
                    if (_bestScore > 0)
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(
                          '${((_bestScore / (_totalQuestions * (_timePerQuestion + 10))) * 100).clamp(0, 100).round()}%',
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                        const Text('précision', style: TextStyle(color: Colors.white38, fontSize: 10)),
                      ]),
                  ]),
                ),

                const SizedBox(height: 16),

                // Règles
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2230),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(children: [
                    _RuleRow(icon: Icons.image_rounded, color: Colors.cyanAccent,
                        text: '$_totalQuestions screenshots à identifier'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.timer_rounded, color: Colors.orangeAccent,
                        text: '$_timePerQuestion secondes par question'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.star_rounded, color: Colors.amberAccent,
                        text: 'Points = 10 + bonus temps (max ${10 + _timePerQuestion} pts)'),
                    const SizedBox(height: 10),
                    _RuleRow(icon: Icons.local_fire_department_rounded, color: Colors.deepOrangeAccent,
                        text: 'Série de bonnes réponses = bonus 🔥'),
                  ]),
                ),

                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _startGame,
                    icon: Icon(connected ? Icons.play_arrow_rounded : Icons.wifi_off_rounded),
                    label: Text(
                      connected ? 'Nouvelle partie' : 'Non connecté',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      backgroundColor: connected ? accent : Colors.white12,
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

class _RuleRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _RuleRow({required this.icon, required this.color, required this.text});
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.white60, fontSize: 13))),
      ]);
}

// ─── Écran de jeu ─────────────────────────────────────────────────────────────

class _QuizGameScreen extends StatefulWidget {
  final void Function(int score) onFinished;
  const _QuizGameScreen({required this.onFinished});
  @override
  State<_QuizGameScreen> createState() => _QuizGameScreenState();
}

class _QuizGameScreenState extends State<_QuizGameScreen> {
  List<Map<String, dynamic>> _allGames = [];
  bool _loadingGames = true;

  Uint8List? _currentImage;
  bool _loadingImage = false;
  Map<String, dynamic> _correctGame = {};
  List<Map<String, dynamic>> _choices = [];

  int _current = 0;
  int? _selectedIndex;
  bool _answered = false;
  int _score = 0;
  int _streak = 0;
  int _bestStreak = 0;
  List<bool> _answers = [];
  int _timeLeft = _timePerQuestion;
  Timer? _timer;
  bool _gameOver = false;

  final _rng = Random();

  @override
  void initState() {
    super.initState();
    _loadGamesAndStart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Données ───────────────────────────────────────────────────────────────

  Future<String> _execDirect(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return utf8.decode(bytes).trim();
    } catch (_) { return ''; }
  }

  Future<File> _getCacheFile() async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/batocera_all_games_cache.json');
  }

  Future<Uint8List?> _fetchImage(String path) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final cacheFolder = Directory('${cacheDir.path}/batocera_img_cache');
      if (!await cacheFolder.exists()) await cacheFolder.create(recursive: true);
      final key = md5.convert(utf8.encode(path)).toString();
      final cacheFile = File('${cacheFolder.path}/$key');
      if (await cacheFile.exists()) return await cacheFile.readAsBytes();
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute('curl -s "http://127.0.0.1:1234$path"');
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      final result = Uint8List.fromList(bytes);
      if (result.isNotEmpty) { await cacheFile.writeAsBytes(result); return result; }
      return null;
    } catch (_) { return null; }
  }

  Future<void> _loadGamesAndStart() async {
    setState(() => _loadingGames = true);

    // Réutilise le cache de games_screen
    try {
      final cacheFile = await _getCacheFile();
      if (await cacheFile.exists()) {
        final cached = jsonDecode(await cacheFile.readAsString()) as List;
        if (cached.isNotEmpty) {
          _allGames = cached
              .map((g) => g as Map<String, dynamic>)
              .where((g) => g['image'] != null && g['image'].toString().isNotEmpty)
              .toList();
        }
      }
    } catch (_) {}

    // Pas de cache → charge depuis l'API
    if (_allGames.isEmpty) {
      try {
        final rawSystems = await _execDirect('curl -s http://127.0.0.1:1234/systems');
        if (rawSystems.isNotEmpty) {
          final systems = (jsonDecode(rawSystems) as List)
              .map((s) => s as Map<String, dynamic>)
              .where((s) => s['visible'] == 'true' &&
                  !['all', 'recordings', 'imageviewer', 'favorites', 'recent', 'flatpak', 'odcommander']
                      .contains(s['name']))
              .toList();
          final all = <Map<String, dynamic>>[];
          for (final sys in systems) {
            if (!mounted) break;
            try {
              final raw = await _execDirect('curl -s http://127.0.0.1:1234/systems/${sys['name']}/games');
              if (raw.isEmpty) continue;
              final list = (jsonDecode(raw) as List)
                  .map((g) => g as Map<String, dynamic>)
                  .where((g) => g['hidden'] != 'true')
                  .map((g) => {...g, '_systemName': sys['name'], '_systemFullname': sys['fullname'] ?? sys['name']})
                  .toList();
              all.addAll(list);
            } catch (_) {}
            await Future.delayed(const Duration(milliseconds: 80));
          }
          if (all.isNotEmpty) {
            try { final f = await _getCacheFile(); await f.writeAsString(jsonEncode(all)); } catch (_) {}
          }
          _allGames = all
              .where((g) => g['image'] != null && g['image'].toString().isNotEmpty)
              .toList();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    if (_allGames.length < 4) { setState(() => _loadingGames = false); return; }
    setState(() => _loadingGames = false);
    _nextQuestion();
  }

  // ── Logique ───────────────────────────────────────────────────────────────

  void _nextQuestion() {
    _timer?.cancel();
    if (_current >= _totalQuestions) { _endGame(); return; }

    final correct = _allGames[_rng.nextInt(_allGames.length)];
    final correctSys = correct['_systemName']?.toString() ?? '';

    var pool = _allGames
        .where((g) => g['name'] != correct['name'] && g['_systemName'] == correctSys)
        .toList();
    if (pool.length < 3) {
      pool = _allGames.where((g) => g['name'] != correct['name']).toList();
    }
    pool.shuffle(_rng);
    final choices = [correct, ...pool.take(3)]..shuffle(_rng);

    setState(() {
      _correctGame = correct;
      _choices = choices;
      _selectedIndex = null;
      _answered = false;
      _currentImage = null;
      _loadingImage = true;
      _timeLeft = _timePerQuestion;
    });

    _fetchImage(correct['image'].toString()).then((bytes) {
      if (mounted) setState(() { _currentImage = bytes; _loadingImage = false; });
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _timeLeft--);
      if (_timeLeft <= 5 && _timeLeft > 0) QuizAudio.tick();
      if (_timeLeft <= 0) { t.cancel(); _onAnswer(-1); }
    });
  }

  void _onAnswer(int index) {
    if (_answered) return;
    _timer?.cancel();
    final correct = index == _choices.indexOf(_correctGame);
    if (correct) {
      _score += 10 + _timeLeft;
      _streak++;
      if (_streak > _bestStreak) _bestStreak = _streak;
      QuizAudio.correct();
    } else if (index == -1) {
      QuizAudio.timeout();
    } else {
      QuizAudio.wrong();
    }
    _answers.add(correct);
    setState(() { _selectedIndex = index; _answered = true; });
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      setState(() => _current++);
      _current >= _totalQuestions ? _endGame() : _nextQuestion();
    });
  }

  void _endGame() {
    _timer?.cancel();
    widget.onFinished(_score);
    setState(() => _gameOver = true);
    final pct = (_answers.isEmpty ? 0 : _answers.where((a) => a).length * 100 ~/ _answers.length);
    if (pct >= 70) {
      QuizAudio.win();
    } else if (pct < 50) {
      QuizAudio.lose();
    }
  }

  Future<void> _confirmQuit() async {
    _timer?.cancel();
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Quitter la partie ?'),
        content: const Text('Ta progression sera perdue.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Continuer')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Quitter')),
        ],
      ),
    );
    if (!mounted) return;
    if (quit == true) {
      Navigator.of(context).pop();
    } else {
      // Reprend le timer
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted) { t.cancel(); return; }
        setState(() => _timeLeft--);
        if (_timeLeft <= 0) { t.cancel(); _onAnswer(-1); }
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    if (_loadingGames) return _buildLoading(accent);
    if (_allGames.length < 4) return _buildNotEnough();
    if (_gameOver) return _buildGameOver(accent);
    return _buildGame(accent);
  }

  Widget _buildLoading(Color accent) => Scaffold(
    body: SafeArea(
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: accent),
        const SizedBox(height: 20),
        const Text('Chargement de ta bibliothèque...',
            style: TextStyle(color: Colors.white54, fontSize: 14)),
      ])),
    ),
  );

  Widget _buildNotEnough() => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.image_not_supported_rounded, size: 64, color: Colors.white12),
            const SizedBox(height: 16),
            const Text(
              'Pas assez de jeux avec screenshots\npour générer un quiz.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 15),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ajoute des médias via le scraper Batocera.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white24, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Retour'),
            ),
          ]),
        ),
      ),
    ),
  );

  Widget _buildGame(Color accent) {
    final timerRatio = _timeLeft / _timePerQuestion;
    final timerColor = _timeLeft > 10
        ? const Color(0xFF50FA7B)
        : _timeLeft > 5 ? Colors.orangeAccent : Colors.redAccent;
    final correctIndex = _choices.indexOf(_correctGame);

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: _confirmQuit,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white54, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text('${_current + 1} / $_totalQuestions',
                        style: const TextStyle(color: Colors.white38, fontSize: 11)),
                    const Spacer(),
                    Row(children: [
                      const Icon(Icons.star_rounded, color: Color(0xFFE02020), size: 13),
                      const SizedBox(width: 3),
                      Text('$_score', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                    ]),
                    if (_streak >= 2) ...[
                      const SizedBox(width: 10),
                      Row(children: [
                        const Icon(Icons.local_fire_department_rounded, color: Colors.orangeAccent, size: 13),
                        Text(' x$_streak', style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontWeight: FontWeight.w700)),
                      ]),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _current / _totalQuestions,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation(accent),
                      minHeight: 3,
                    ),
                  ),
                ]),
              ),
            ]),
          ),

          const SizedBox(height: 6),

          // Timer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              Icon(Icons.timer_rounded, size: 13, color: timerColor),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: timerRatio,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(timerColor),
                    minHeight: 5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$_timeLeft s', style: TextStyle(color: timerColor, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),

          const SizedBox(height: 8),

          // Screenshot
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  color: const Color(0xFF0A0C10),
                  child: _loadingImage
                      ? Center(child: CircularProgressIndicator(color: accent, strokeWidth: 2))
                      : _currentImage != null
                          ? Image.memory(_currentImage!, fit: BoxFit.contain)
                          : const Icon(Icons.broken_image_rounded, color: Colors.white12, size: 48),
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Hint système
          if (!_answered)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Système : ${_correctGame['_systemFullname'] ?? _correctGame['_systemName'] ?? '?'}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          const SizedBox(height: 8),

          // Choix A B C D
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                children: List.generate(_choices.length, (i) {
                  final isCorrect = i == correctIndex;
                  final isSelected = i == _selectedIndex;
                  Color bg = const Color(0xFF1C2230);
                  Color border = Colors.white12;
                  Color text = Colors.white70;
                  IconData? trailing;
                  if (_answered) {
                    if (isCorrect) { bg = Colors.green.withOpacity(0.18); border = Colors.greenAccent; text = Colors.greenAccent; trailing = Icons.check_circle_rounded; }
                    else if (isSelected) { bg = Colors.redAccent.withOpacity(0.18); border = Colors.redAccent; text = Colors.redAccent; trailing = Icons.cancel_rounded; }
                    else { text = Colors.white24; border = Colors.white10; }
                  }
                  final name = _cleanName(_choices[i]['name']?.toString() ?? '?');
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: GestureDetector(
                        onTap: _answered ? null : () => _onAnswer(i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: bg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: border),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Row(children: [
                            Container(
                              width: 26, height: 26,
                              decoration: BoxDecoration(
                                color: _answered && isCorrect
                                    ? Colors.greenAccent.withOpacity(0.2)
                                    : _answered && isSelected
                                        ? Colors.redAccent.withOpacity(0.2)
                                        : Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Center(child: Text(['A', 'B', 'C', 'D'][i],
                                  style: TextStyle(color: text, fontSize: 11, fontWeight: FontWeight.w700))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(name,
                                style: TextStyle(color: text, fontSize: 13, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis, maxLines: 1)),
                            if (trailing != null) Icon(trailing, color: text, size: 18),
                          ]),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildGameOver(Color accent) {
    final correct = _answers.where((a) => a).length;
    final pct = (correct / _totalQuestions * 100).round();
    final emoji = pct >= 90 ? '🏆' : pct >= 70 ? '🎮' : pct >= 50 ? '👾' : '💀';
    final msg = pct >= 90 ? 'Expert en screenshots !' : pct >= 70 ? 'Sacré connaisseur !' : pct >= 50 ? 'Pas mal du tout !' : 'T\'as besoin de jouer plus... 😅';
    final scoreColor = pct >= 70 ? Colors.greenAccent : pct >= 50 ? Colors.orangeAccent : Colors.redAccent;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 0, 0, 16),
              child: Row(children: [
                Text('Résultats', style: Theme.of(context).textTheme.headlineMedium),
              ]),
            ),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: scoreColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: scoreColor.withOpacity(0.3)),
              ),
              child: Column(children: [
                Text(emoji, style: const TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(msg, style: TextStyle(color: scoreColor, fontSize: 16, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Text('$_score pts', style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w900)),
                Text('$pct% de bonnes réponses', style: TextStyle(color: scoreColor.withOpacity(0.7), fontSize: 13)),
              ]),
            ),

            const SizedBox(height: 16),

            Row(children: [
              _StatCard(label: 'Bonnes\nréponses', value: '$correct/$_totalQuestions', color: Colors.greenAccent, icon: Icons.check_rounded),
              const SizedBox(width: 10),
              _StatCard(label: 'Meilleure\nsérie', value: 'x$_bestStreak', color: Colors.orangeAccent, icon: Icons.local_fire_department_rounded),
              const SizedBox(width: 10),
              _StatCard(label: 'Score\ntotal', value: '$_score', color: accent, icon: Icons.star_rounded),
            ]),

            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFF1C2230), borderRadius: BorderRadius.circular(16)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('RÉCAPITULATIF', style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
                const SizedBox(height: 12),
                Wrap(spacing: 6, runSpacing: 6,
                  children: List.generate(_answers.length, (i) => Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: _answers[i] ? Colors.greenAccent.withOpacity(0.15) : Colors.redAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _answers[i] ? Colors.greenAccent.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5)),
                    ),
                    child: Center(child: Text('${i + 1}',
                        style: TextStyle(color: _answers[i] ? Colors.greenAccent : Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w700))),
                  )),
                ),
              ]),
            ),

            const SizedBox(height: 20),

            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.home_rounded),
                  label: const Text('Accueil'),
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
                  onPressed: () {
                    setState(() {
                      _current = 0; _score = 0; _streak = 0; _bestStreak = 0;
                      _answers = []; _gameOver = false; _loadingGames = true;
                    });
                    _loadGamesAndStart();
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Rejouer', style: TextStyle(fontWeight: FontWeight.w700)),
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

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _cleanName(String raw) => raw
    .replaceAll(RegExp(r'\s*\(.*?\)\s*'), '')
    .replaceAll(RegExp(r'\s*\[.*?\]\s*'), '')
    .trim();

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;
  const _StatCard({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10), textAlign: TextAlign.center),
      ]),
    ),
  );
}
