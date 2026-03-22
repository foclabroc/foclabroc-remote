import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_state.dart';

class RunningGameScreen extends StatefulWidget {
  const RunningGameScreen({super.key});

  @override
  State<RunningGameScreen> createState() => _RunningGameScreenState();
}

class _RunningGameScreenState extends State<RunningGameScreen> {
  Map<String, String> _gameInfo = {};
  bool _loading = false;
  String _playTime = '';
  Uint8List? _imageBytes;
  Uint8List? _wheelBytes;
  Timer? _autoRefresh;
  Timer? _timeRefresh;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (state.isConnected) _fetchGameInfo();
    });
    _autoRefresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && context.read<AppState>().isConnected) _fetchGameInfo();
    });
    _timeRefresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<AppState>().isConnected && _gameInfo.isNotEmpty) {
        _fetchPlayTime();
      }
    });
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _timeRefresh?.cancel();
    super.dispose();
  }

  Future<String> _execDirect(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return utf8.decode(bytes).trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _fetchPlayTime() async {
    try {
      final t = await _execDirect(
        "ps -o etime= -C emulatorlauncher 2>/dev/null | head -1 | tr -d '[:blank:]'",
      );
      if (mounted && t.isNotEmpty) setState(() => _playTime = t);
    } catch (_) {}
  }

  Future<Uint8List?> _fetchImageDirect(String path) async {
    try {
      if (path.isEmpty || path == 'null') return null;
      final state = context.read<AppState>();
      final url = path.startsWith('http') ? path : 'http://127.0.0.1:1234$path';
      final tmp = '/tmp/img_${DateTime.now().millisecondsSinceEpoch}';
      await _execDirect('curl -s "$url" -o "$tmp"');
      await Future.delayed(const Duration(milliseconds: 100));
      final bytes = await state.ssh.downloadFile(tmp);
      await _execDirect('rm -f "$tmp"');
      return bytes.isNotEmpty ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchGameInfo() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final raw = await _execDirect('curl -s http://127.0.0.1:1234/runningGame 2>/dev/null');

      if (raw.isEmpty) {
        setState(() { _gameInfo = {}; _imageBytes = null; _wheelBytes = null; _playTime = ''; _loading = false; });
        return;
      }

      final info = <String, String>{};
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        for (final f in ['name', 'systemName', 'emulator', 'core', 'image', 'wheel', 'manual', 'cheevosId']) {
          final v = json[f];
          if (v != null && v.toString().isNotEmpty && v.toString() != 'null') {
            info[f] = v.toString();
          }
        }
      } catch (_) {}

      if (info['name'] == null) {
        setState(() { _gameInfo = {}; _imageBytes = null; _wheelBytes = null; _playTime = ''; _loading = false; });
        return;
      }

      final newName = info['name'] ?? '';
      final oldName = _gameInfo['name'] ?? '';
      setState(() { _gameInfo = info; _loading = false; });

      if (newName != oldName) {
        _imageBytes = null;
        _wheelBytes = null;
        _fetchPlayTime();

        if (info.containsKey('wheel')) {
          _fetchImageDirect(info['wheel']!).then((bytes) {
            if (mounted && bytes != null) setState(() => _wheelBytes = bytes);
            if (info.containsKey('image')) {
              _fetchImageDirect(info['image']!).then((bytes2) {
                if (mounted && bytes2 != null) setState(() => _imageBytes = bytes2);
              });
            }
          });
        } else if (info.containsKey('image')) {
          _fetchImageDirect(info['image']!).then((bytes) {
            if (mounted && bytes != null) setState(() => _imageBytes = bytes);
          });
        }
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _showManual() async {
    final path = _gameInfo['manual'];
    if (path == null) return;

    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Chargement du manuel...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final bytes = await _fetchImageDirect(path);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impossible de charger le manuel', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ));
        return;
      }

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/manual_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => _PdfViewerScreen(filePath: file.path, title: _gameInfo['name'] ?? 'Manuel'),
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Future<void> _openRetroAchievements() async {
    final id = _gameInfo['cheevosId'];
    if (id == null) return;
    final url = Uri.parse('https://retroachievements.org/game/$id');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Future<void> _stopGame(AppState state) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Arrêter le jeu ?'),
        content: const Text('Le jeu en cours va être fermé.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Arrêter'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await state.ssh.execute('batocera-es-swissknife --emukill');
      await Future.delayed(const Duration(seconds: 2));
      await _fetchGameInfo();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final accent = Theme.of(context).colorScheme.primary;
    final hasGame = _gameInfo.isNotEmpty;
    final hasManual = _gameInfo.containsKey('manual');
    final hasCheevos = _gameInfo.containsKey('cheevosId');

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Jeu en cours', style: Theme.of(context).textTheme.headlineMedium),
                      Text('Auto 5s', style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 10)),
                    ],
                  ),
                  const Spacer(),
                  if (_loading)
                    SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                  else
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                      onPressed: _fetchGameInfo,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: !state.isConnected
                  ? _EmptyState(icon: Icons.wifi_off_rounded, message: 'Non connecté')
                  : !hasGame
                      ? _EmptyState(icon: Icons.sports_esports_outlined, message: 'Aucun jeu en cours')
                      : SingleChildScrollView(
                          child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Column(
                            children: [

                              // ── Wheel (logo) ──────────────────────────────
                              if (_wheelBytes != null)
                                Container(
                                  width: double.infinity, height: 56,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.black),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Image.memory(_wheelBytes!, fit: BoxFit.contain),
                                  ),
                                )
                              else if (_gameInfo.containsKey('wheel'))
                                Container(
                                  width: double.infinity, height: 56,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFF1C2230)),
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
                                ),

                              // ── Image 16/9 ────────────────────────────────
                              if (_imageBytes != null)
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.black),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: AspectRatio(
                                      aspectRatio: 16 / 9,
                                      child: Image.memory(_imageBytes!, fit: BoxFit.cover),
                                    ),
                                  ),
                                )
                              else if (_gameInfo.containsKey('image'))
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFF1C2230)),
                                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
                                  ),
                                ),

                              // ── Infos jeu ─────────────────────────────────
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(color: const Color(0xFF1C2230), borderRadius: BorderRadius.circular(10)),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            _PulsingDot(color: Colors.greenAccent),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                _gameInfo['name'] ?? 'Jeu inconnu',
                                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ]),
                                          if (_gameInfo['systemName'] != null)
                                            Text(_gameInfo['systemName']!.toUpperCase(),
                                                style: TextStyle(color: accent, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        if (_playTime.isNotEmpty)
                                          Row(children: [
                                            Icon(Icons.timer_rounded, size: 12, color: Colors.greenAccent),
                                            const SizedBox(width: 4),
                                            Text(_playTime, style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                                          ]),
                                        if (_gameInfo['emulator'] != null)
                                          Text(_gameInfo['emulator']!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                        if (_gameInfo['core'] != null)
                                          Text(_gameInfo['core']!, style: const TextStyle(color: Colors.white24, fontSize: 10)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 8),

                              // ── Boutons ───────────────────────────────────
                              Row(
                                children: [
                                  if (hasManual)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: OutlinedButton.icon(
                                          onPressed: _showManual,
                                          icon: const Icon(Icons.picture_as_pdf_rounded, size: 14),
                                          label: const Text('Manuel', style: TextStyle(fontSize: 12)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.blueAccent,
                                            side: const BorderSide(color: Colors.blueAccent),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (hasCheevos)
                                    Expanded(
                                      child: Padding(
                                        padding: EdgeInsets.only(right: 6, left: hasManual ? 0 : 0),
                                        child: OutlinedButton.icon(
                                          onPressed: _openRetroAchievements,
                                          icon: const Icon(Icons.emoji_events_rounded, size: 14),
                                          label: const Text('Achievements', style: TextStyle(fontSize: 12)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.amberAccent,
                                            side: const BorderSide(color: Colors.amberAccent),
                                            padding: const EdgeInsets.symmetric(vertical: 8),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(left: (hasManual || hasCheevos) ? 6 : 0),
                                      child: OutlinedButton.icon(
                                        onPressed: () => _stopGame(state),
                                        icon: const Icon(Icons.stop_circle_rounded, size: 14),
                                        label: const Text('Arrêter', style: TextStyle(fontSize: 12)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.redAccent,
                                          side: const BorderSide(color: Colors.redAccent),
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Visionneuse PDF ─────────────────────────────────────────────────────────

class _PdfViewerScreen extends StatefulWidget {
  final String filePath;
  final String title;
  const _PdfViewerScreen({required this.filePath, required this.title});

  @override
  State<_PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<_PdfViewerScreen> {
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  PDFViewController? _controller;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161A22),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                overflow: TextOverflow.ellipsis),
            if (_totalPages > 0)
              Text('Page ${_currentPage + 1} / $_totalPages',
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ],
        ),
        actions: [
          if (_totalPages > 1) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white54, size: 18),
              onPressed: _currentPage > 0 ? () => _controller?.setPage(_currentPage - 1) : null,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white54, size: 18),
              onPressed: _currentPage < _totalPages - 1 ? () => _controller?.setPage(_currentPage + 1) : null,
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          PDFView(
            filePath: widget.filePath,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageFling: true,
            pageSnap: true,
            defaultPage: 0,
            fitPolicy: FitPolicy.BOTH,
            onRender: (pages) => setState(() { _totalPages = pages ?? 0; _isReady = true; }),
            onPageChanged: (page, total) => setState(() { _currentPage = page ?? 0; _totalPages = total ?? 0; }),
            onViewCreated: (controller) => _controller = controller,
            onError: (error) => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Erreur PDF : $error', style: const TextStyle(color: Colors.white)), backgroundColor: Colors.redAccent),
            ),
          ),
          if (!_isReady)
            Center(child: CircularProgressIndicator(color: accent)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: Colors.white.withOpacity(0.1)),
          const SizedBox(height: 16),
          Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 16)),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(width: 8, height: 8, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle)),
    );
  }
}
