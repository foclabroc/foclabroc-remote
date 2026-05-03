import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/app_state.dart';
import 'game_detail_screen.dart';

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  List<Map<String, dynamic>> _systems = [];
  bool _loadingSystems = false;
  final Map<String, Uint8List> _logoCache = {};
  final TextEditingController _globalSearchCtrl = TextEditingController();
  String _globalSearch = '';
  List<Map<String, dynamic>> _allGames = [];
  final Map<String, int> _gameCounts = {};
  bool _loadingAllGames = false;
  bool _loadingRandom = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      state.addListener(_onConnectionChange);
      if (state.isConnected && _systems.isEmpty) _loadSystems();
    });
  }

  void _onConnectionChange() {
    final state = context.read<AppState>();
    if (state.isConnected && _systems.isEmpty && !_loadingSystems) _loadSystems();
  }

  @override
  void dispose() {
    context.read<AppState>().removeListener(_onConnectionChange);
    _globalSearchCtrl.dispose();
    super.dispose();
  }

  Future<String> _execDirect(String cmd) async {
    try {
      final state = context.read<AppState>();
      // 2>/dev/null bloque la bannière Batocera qui pollue stdout
      final session = await state.ssh.client!.execute('$cmd 2>/dev/null');
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return utf8.decode(bytes).trim();
    } catch (_) { return ''; }
  }

  bool _isValidImage(Uint8List bytes) {
    if (bytes.length < 8) return false;
    if (bytes[0] == 0x89 && bytes[1] == 0x50) return true; // PNG
    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true; // JPEG
    if (bytes[0] == 0x47 && bytes[1] == 0x49) return true; // GIF
    if (bytes[0] == 0x52 && bytes[1] == 0x49) return true; // WebP
    if (bytes[0] == 0x3C) return true;                      // SVG
    return false;
  }

  bool _isSvg(Uint8List bytes) => bytes.length > 4 && bytes[0] == 0x3C;


  // Convertit un SVG complexe en PNG via rsvg-convert sur Batocera
  Future<Uint8List?> _svgToPng(Uint8List svgBytes, String key, AppState state) async {
    try {
      final tmpSvg = '/tmp/logo_$key.svg';
      final tmpPng = '/tmp/logo_$key.png';
      final dir = await getTemporaryDirectory();
      final localSvg = File('${dir.path}/tmp_svg_$key.svg');
      await localSvg.writeAsBytes(svgBytes);
      await state.ssh.uploadFileFromPath(localSvg.path, tmpSvg);
      await _execDirect('rsvg-convert -w 120 -h 60 "$tmpSvg" -o "$tmpPng" 2>/dev/null');
      final pngBytes = await state.ssh.downloadFile(tmpPng);
      await _execDirect('rm -f "$tmpSvg" "$tmpPng"');
      return pngBytes.length > 100 ? pngBytes : null;
    } catch (_) { return null; }
  }

  /// Gets the remote mtime of a file (in Unix seconds).
  /// Returns -1 if undeterminable.
  Future<int> _remoteMTime(String path) async {
    try {
      final state = context.read<AppState>();
      // Direct filesystem path → stat
      if (path.startsWith('/usr/') || path.startsWith('/userdata/') || path.startsWith('/tmp/')) {
        final r = await _execDirect("stat -c %Y ${_shQ(path)} 2>/dev/null");
        return int.tryParse(r.trim()) ?? -1;
      }
      // ES API route → try Last-Modified via curl HEAD
      final url = 'http://127.0.0.1:1234$path';
      final session = await state.ssh.client!.execute('curl -sI --max-time 5 "$url" 2>/dev/null | grep -i "^last-modified" | head -1');
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      final header = utf8.decode(bytes).trim().toLowerCase();
      if (header.startsWith('last-modified:')) {
        final dateStr = header.substring(14).trim();
        try {
          final dt = HttpDate.parse(dateStr);
          return dt.millisecondsSinceEpoch ~/ 1000;
        } catch (_) {}
      }
      return -1;
    } catch (_) {
      return -1;
    }
  }

  String _shQ(String s) => "'${s.replaceAll("'", "'\\''")}'";

  Future<Uint8List?> _fetchImage(String path) => _fetchImageInternal(path, validateMtime: true);

  /// Variant without mtime validation: used for system logos, whose paths
  /// can return empty/404 temporarily (ES still loading, theme switching…).
  /// Keep existing cache as long as it's valid in size/format.
  Future<Uint8List?> _fetchImageNoMtime(String path) => _fetchImageInternal(path, validateMtime: false);

  Future<Uint8List?> _fetchImageInternal(String path, {required bool validateMtime}) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final cacheFolder = Directory('${cacheDir.path}/batocera_img_cache');
      if (!await cacheFolder.exists()) await cacheFolder.create(recursive: true);
      final key = md5.convert(utf8.encode(path)).toString();
      final cacheFile = File('${cacheFolder.path}/$key');
      final mtimeFile = File('${cacheFolder.path}/$key.mtime');

      // Check cache: size OK AND (if validateMtime) remote mtime == stored mtime
      if (await cacheFile.exists()) {
        final len = await cacheFile.length();
        if (len > 100) {
          final cached = await cacheFile.readAsBytes();
          if (_isValidImage(cached)) {
            if (!validateMtime) {
              // No mtime validation → cache always good as long as it exists
              return cached;
            }
            int storedMtime = -1;
            if (await mtimeFile.exists()) {
              storedMtime = int.tryParse((await mtimeFile.readAsString()).trim()) ?? -1;
            }
            final remoteMtime = await _remoteMTime(path);
            // Cache valid if we have stored mtime AND it matches
            if (remoteMtime > 0 && storedMtime > 0 && remoteMtime == storedMtime) {
              return cached;
            }
            // Cache valid if we have stored mtime AND remote mtime is indeterminable (API route)
            // → trust the cache since we can't verify
            if (remoteMtime == -1 && storedMtime > 0) {
              return cached;
            }
            // Otherwise (no stored mtime OR mtime differs): invalidate and re-download
          }
        }
        // Invalid / stale cache → remove
        try { await cacheFile.delete(); } catch (_) {}
        try { if (await mtimeFile.exists()) await mtimeFile.delete(); } catch (_) {}
      }

      final state = context.read<AppState>();
      Uint8List result;

      if (path.startsWith('/usr/') || path.startsWith('/userdata/')) {
        // Filesystem path → SFTP direct
        result = await state.ssh.downloadFile(path);
      } else {
        // ES API route → curl
        final url = 'http://127.0.0.1:1234$path';
        final session = await state.ssh.client!.execute('curl -s --max-time 8 "$url"');
        final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
        await session.done;
        result = Uint8List.fromList(bytes);
      }

      if (result.length > 100) {
        // Complex SVG (>50KB) → convert to PNG via rsvg-convert
        if (_isSvg(result)) {
          final png = await _svgToPng(result, key, state);
          if (png != null) {
            await cacheFile.writeAsBytes(png);
            // Save mtime for future validation
            if (validateMtime) {
              final mt = await _remoteMTime(path);
              if (mt > 0) await mtimeFile.writeAsString(mt.toString());
            }
            return png;
          }
        }
        if (_isValidImage(result)) {
          await cacheFile.writeAsBytes(result);
          // Save mtime for future validation
          if (validateMtime) {
            final mt = await _remoteMTime(path);
            if (mt > 0) await mtimeFile.writeAsString(mt.toString());
          }
        }
        return result;
      }
      return null;
    } catch (_) { return null; }
  }

  Future<void> _loadSystems() async {
    setState(() => _loadingSystems = true);
    try {
      // Clear in-memory game cache to force fresh fetch.
      // ES serves from its memory; to pick up gamelist.xml changes, the
      // pending scraps dialog at startup triggers reloadgames when relevant,
      // without interrupting the user.
      _allGames = [];
      final raw = await _execDirect('curl -s http://127.0.0.1:1234/systems');
      final list = jsonDecode(raw) as List;
final systems = list
          .map((s) => s as Map<String, dynamic>)
          .where((s) => s['visible'] == 'true' && s['name'] != 'all' && s['name'] != 'recordings' && s['name'] != 'imageviewer' && s['name'] != 'favorites' && s['name'] != 'recent' && s['name'] != 'flatpak' && s['name'] != 'odcommander')
          .toList();
      systems.sort((a, b) => (a['fullname'] ?? '').toString()
          .compareTo((b['fullname'] ?? '').toString()));
      setState(() { _systems = systems; _loadingSystems = false; });
      await _loadLogos(systems);
      _loadGameCounts(systems);
    } catch (_) {
      setState(() => _loadingSystems = false);
    }
  }

  Future<void> _loadGameCounts(List<Map<String, dynamic>> systems) async {
    // Si les jeux sont déjà en cache, on compte directement sans SSH
    if (_allGames.isNotEmpty) {
      _computeCountsFromCache();
      return;
    }
    // Sinon on charge depuis l'API système par système
    for (final sys in systems) {
      if (!mounted) break;
      try {
        final sysName = sys['name'].toString();
        final raw = await _execDirect(
          "curl -s http://127.0.0.1:1234/systems/$sysName/games | python3 -c \"import json,sys; d=json.load(sys.stdin); print(len([g for g in d if g.get('hidden') != 'true']))\""
        );
        final count = int.tryParse(raw.trim());
        if (count != null && mounted) {
          setState(() => _gameCounts[sys['name'].toString()] = count);
        }
      } catch (_) {}
    }
  }

  void _computeCountsFromCache() {
    final counts = <String, int>{};
    for (final g in _allGames) {
      final sysName = g['_systemName']?.toString() ?? '';
      if (sysName.isNotEmpty) counts[sysName] = (counts[sysName] ?? 0) + 1;
    }
    if (mounted) setState(() => _gameCounts.addAll(counts));
  }

  Future<File> _getCacheFile() async {
    final dir = await getTemporaryDirectory();
    return File('${dir.path}/batocera_all_games_cache.json');
  }

  Future<void> _loadAllGames() async {
    if (_loadingAllGames || _allGames.isNotEmpty) return;
    setState(() => _loadingAllGames = true);

    // Essaie de charger depuis le cache d'abord
    try {
      final cacheFile = await _getCacheFile();
      if (await cacheFile.exists()) {
        final cached = jsonDecode(await cacheFile.readAsString()) as List;
        if (cached.isNotEmpty) {
          final games = cached.map((g) => g as Map<String, dynamic>).toList();
          if (mounted) {
            setState(() { _allGames = games; _loadingAllGames = false; });
            _computeCountsFromCache();
          }
          return;
        }
      }
    } catch (_) {}

    // Pas de cache — charge depuis l'API
    final all = <Map<String, dynamic>>[];
    for (final sys in _systems) {
      if (!mounted) break;
      try {
        final raw = await _execDirect('curl -s http://127.0.0.1:1234/systems/${sys['name']}/games');
        final list = (jsonDecode(raw) as List)
            .map((g) => g as Map<String, dynamic>)
            .where((g) => g['hidden'] != 'true')
            .map((g) => {...g, '_systemName': sys['name'], '_systemFullname': sys['fullname'] ?? sys['name']})
            .toList();
        all.addAll(list);
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 100));
    }
    all.sort((a, b) => (a['name'] ?? '').toString().compareTo((b['name'] ?? '').toString()));

    // Sauvegarde le cache
    try {
      final cacheFile = await _getCacheFile();
      await cacheFile.writeAsString(jsonEncode(all));
    } catch (_) {}

    if (mounted) {
      setState(() { _allGames = all; _loadingAllGames = false; });
      _computeCountsFromCache();
    }
  }

  Future<void> _pickRandom() async {
    if (_loadingRandom) return;
    setState(() => _loadingRandom = true);

    if (_allGames.isEmpty) await _loadAllGames();

    if (!mounted || _allGames.isEmpty) {
      setState(() => _loadingRandom = false);
      return;
    }

    final game = _allGames[Random().nextInt(_allGames.length)];
    setState(() => _loadingRandom = false);

    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameDetailScreen(
        game: game,
        fetchImage: _fetchImage,
        systemLogo: _logoCache[game['_systemName']?.toString() ?? ''],
        allGames: _allGames,
      ),
    ));
  }

  Future<void> _loadLogos(List<Map<String, dynamic>> systems) async {
    const batchSize = 5;
    for (int i = 0; i < systems.length; i += batchSize) {
      if (!mounted) return;
      final batch = systems.skip(i).take(batchSize).toList();
      await Future.wait(batch.map((sys) async {
        final sysName = sys['name']?.toString() ?? '';
        if (sysName.isEmpty) return;

        final sysNameL = sysName.toLowerCase();

        // 1) Try ES API paths first (priority to current theme's logo).
        // No mtime validation: if API responds, take it; otherwise fallback.
        final apiPaths = <String>[
          if ((sys['logo']?.toString() ?? '').isNotEmpty) sys['logo'].toString(),
          '/systems/$sysName/logo',
        ];
        for (final logoPath in apiPaths) {
          final bytes = await _fetchImageNoMtime(logoPath);
          if (mounted && bytes != null) {
            setState(() => _logoCache[sysName] = bytes);
            return;
          }
        }

        // 2) If API gave nothing AND we already have an in-memory cache → keep old
        if (_logoCache.containsKey(sysName)) return;

        // 3) Otherwise fallback to default theme files (es-theme-carbon)
        final fsPaths = <String>[
          '/usr/share/emulationstation/themes/es-theme-carbon/art/logos/$sysNameL.svg',
          '/usr/share/emulationstation/themes/es-theme-carbon/art/logos/$sysNameL.png',
        ];
        for (final logoPath in fsPaths) {
          final bytes = await _fetchImageNoMtime(logoPath);
          if (mounted && bytes != null) {
            setState(() => _logoCache[sysName] = bytes);
            break;
          }
        }
      }));
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 8, 24, 0),
              child: Row(
                children: [
                  Text('Library', style: Theme.of(context).textTheme.headlineMedium),
                  const Spacer(),
                  if (state.isConnected)
                    _loadingRandom
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38))
                        : GestureDetector(
                            onTap: _pickRandom,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.casino_rounded, color: Colors.white54, size: 20),
                                SizedBox(height: 2),
                                Text('Random',
                                    style: TextStyle(color: Colors.white38, fontSize: 9)),
                              ],
                            ),
                          ),
                  const SizedBox(width: 12),
                  if (_loadingSystems)
                    SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                  else
                    GestureDetector(
                      onTap: state.isConnected ? () async {
                        try { final f = await _getCacheFile(); if (await f.exists()) await f.delete(); } catch (_) {}
                        try {
                          final cacheDir = await getTemporaryDirectory();
                          final logoFolder = Directory('${cacheDir.path}/batocera_img_cache');
                          if (await logoFolder.exists()) await logoFolder.delete(recursive: true);
                        } catch (_) {}
                        setState(() { _allGames = []; _logoCache.clear(); _systems = []; });
                        _loadSystems();
                      } : null,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                          const SizedBox(height: 2),
                          const Text('Refresh',
                              style: TextStyle(color: Colors.white24, fontSize: 9)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  controller: _globalSearchCtrl,
                  onChanged: (v) {
                    setState(() => _globalSearch = v);
                    if (v.isNotEmpty && _allGames.isEmpty) _loadAllGames();
                  },
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search all games...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                    suffixIcon: _globalSearch.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                            onPressed: () { _globalSearchCtrl.clear(); setState(() => _globalSearch = ''); })
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: !state.isConnected
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi_off_rounded, size: 48, color: Colors.white.withOpacity(0.1)),
                      const SizedBox(height: 12),
                      Text('Not connected', style: Theme.of(context).textTheme.bodyMedium),
                    ]))
                  : _globalSearch.isNotEmpty
                      ? _buildGlobalResults(accent)
                  : _loadingSystems && _systems.isEmpty
                      ? Center(child: CircularProgressIndicator(color: accent))
                      : _systems.isEmpty
                          ? Center(child: ElevatedButton.icon(
                              onPressed: _loadSystems,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Load systems'),
                            ))
                          : Column(children: [
                              if (_gameCounts.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                                  child: Text(
                                    'Total : ${_gameCounts.values.fold(0, (a, b) => a + b)} games',
                                    style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              Expanded(
                                child: GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 3,
                                    childAspectRatio: 1.2,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 16,
                                  ),
                                  itemCount: _systems.length,
                                  itemBuilder: (_, i) {
                                    final sys = _systems[i];
                                    final sysName = sys['name'].toString();
                                    return _SystemCard(
                                      key: ValueKey(sysName),
                                      system: sys,
                                      logo: _logoCache[sysName],
                                      accent: accent,
                                      gameCount: _gameCounts[sysName],
                                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => _GamesListScreen(
                                          systemName: sysName,
                                          fullname: sys['fullname'] ?? sysName,
                                          fetchImage: _fetchImage,
                                          execDirect: _execDirect,
                                          systemLogo: _logoCache[sysName],
                                          allGames: _allGames,
                                        ),
                                      )),
                                    );
                                  },
                                ),
                              ),
                            ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalResults(Color accent) {
    if (_loadingAllGames && _allGames.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircularProgressIndicator(color: accent),
        const SizedBox(height: 12),
        const Text('Loading all games...', style: TextStyle(color: Colors.white38, fontSize: 12)),
      ]));
    }
    final q = _globalSearch.toLowerCase();
    final results = _allGames.where((g) =>
        (g['name'] ?? '').toString().toLowerCase().contains(q)).toList();
    if (results.isEmpty) return Center(child: Text('No results for "$_globalSearch"',
        style: Theme.of(context).textTheme.bodyMedium));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: results.length,
      itemBuilder: (_, i) {
        final game = results[i];
        final sysFull = game['_systemFullname']?.toString() ?? '';
        final isFav = game['favorite'] == 'true';
        final hasAch = game['cheevosId'] != null && game['cheevosId'].toString().isNotEmpty && game['cheevosId'].toString() != '0';
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => GameDetailScreen(
                game: game,
                fetchImage: _fetchImage,
                systemLogo: _logoCache[game['_systemName']?.toString() ?? ''],
                allGames: _allGames,
              ),
            )),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(game['name']?.toString() ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                  Row(children: [
                    Text(sysFull, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                    if (isFav) ...[const SizedBox(width: 6), const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 11)],
                    if (hasAch) ...[const SizedBox(width: 4), const Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 11)],
                  ]),
                ])),
                GestureDetector(
                  onTap: () async {
                    final running = await _execDirect('curl -s http://127.0.0.1:1234/runningGame');
                    if (running.isNotEmpty && !running.contains('"msg"')) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Closing current game...', style: TextStyle(color: Colors.white)),
                          backgroundColor: Color(0xFF1C2230),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 3),
                        ));
                      }
                      await _execDirect('curl -s http://127.0.0.1:1234/emukill');
                      await Future.delayed(const Duration(seconds: 2));
                    }
                    final state = context.read<AppState>();
                    state.markLaunchingGame(); // block pending finalization during launch
                    final session = await state.ssh.client!.execute('curl -s -X POST http://127.0.0.1:1234/launch -d "${game['path'] ?? ''}"');
                    await session.done;
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: accent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.play_arrow_rounded, color: accent, size: 18),
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }
}

bool _isSvgBytes(Uint8List bytes) => bytes.isNotEmpty && bytes[0] == 0x3C;

// ─── System Card ──────────────────────────────────────────────────────────────

class _SystemCard extends StatelessWidget {
  final Map<String, dynamic> system;
  final Uint8List? logo;
  final VoidCallback onTap;
  final Color accent;
  final int? gameCount;

  const _SystemCard({
    super.key,
    required this.system,
    required this.logo,
    required this.onTap,
    required this.accent,
    this.gameCount,
  });

  @override
  Widget build(BuildContext context) {
    final name = system['fullname'] ?? system['name'] ?? '';
    final countStr = gameCount != null ? '$gameCount' : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox.expand(
            child: Card(
              margin: EdgeInsets.zero,
              color: const Color(0xFF3D4F6B),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Center(
                    child: logo != null
                        ? (_isSvgBytes(logo!) ? SizedBox(width: 100, height: 36, child: ClipRect(child: SvgPicture.memory(logo!, fit: BoxFit.contain, allowDrawingOutsideViewBox: false))) : Image.memory(logo!, fit: BoxFit.contain))
                        : Text(
                            name.toString().toUpperCase(),
                            style: TextStyle(color: accent, fontSize: 10,
                                fontWeight: FontWeight.w700, letterSpacing: 0.5),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (countStr != null)
            Positioned(
              bottom: -8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.lightBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$countStr games',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Liste des jeux ───────────────────────────────────────────────────────────

class _GamesListScreen extends StatefulWidget {
  final String systemName;
  final String fullname;
  final Future<Uint8List?> Function(String) fetchImage;
  final Future<String> Function(String) execDirect;
  final Uint8List? systemLogo;
  final List<Map<String, dynamic>>? allGames;

  const _GamesListScreen({
    required this.systemName,
    required this.fullname,
    required this.fetchImage,
    required this.execDirect,
    this.systemLogo,
    this.allGames,
  });

  @override
  State<_GamesListScreen> createState() => _GamesListScreenState();
}

class _GamesListScreenState extends State<_GamesListScreen> {
  List<Map<String, dynamic>> _games = [];
  bool _loading = true;
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadGames();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGames() async {
    setState(() => _loading = true);
    try {
      final raw = await widget.execDirect(
          'curl -s http://127.0.0.1:1234/systems/${widget.systemName}/games');
      final list = jsonDecode(raw) as List;
      final games = list
          .map((g) => g as Map<String, dynamic>)
          .where((g) => g['hidden'] != 'true')
          .toList();
      games.sort((a, b) => (a['name'] ?? '').toString()
          .compareTo((b['name'] ?? '').toString()));
      setState(() { _games = games; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _launchGame(String path) async {
    try {
      final running = await widget.execDirect('curl -s http://127.0.0.1:1234/runningGame');
      if (running.isNotEmpty && !running.contains('"msg"')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Closing current game...', style: TextStyle(color: Colors.white)),
            backgroundColor: Color(0xFF1C2230),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ));
        }
        await widget.execDirect('curl -s http://127.0.0.1:1234/emukill');
        await Future.delayed(const Duration(seconds: 2));
      }
      // Utilise client SSH direct pour éviter les problèmes de quoting
      final state = context.read<AppState>();
      state.markLaunchingGame(); // block pending finalization during launch
      final session = await state.ssh.client!.execute('curl -s -X POST http://127.0.0.1:1234/launch -d "$path"');
      await session.done;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Lancement du jeu...', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF1C2230),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _games;
    return _games.where((g) =>
        (g['name'] ?? '').toString().toLowerCase()
            .contains(_search.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final games = _filtered;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white54),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(widget.fullname,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20),
                    overflow: TextOverflow.ellipsis)),
                if (_loading)
                  SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                else
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                    onPressed: _loadGames,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ]),
            ),
            if (_games.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 18),
                      suffixIcon: _search.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Colors.white38, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _search = '');
                              })
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading && _games.isEmpty
                  ? Center(child: CircularProgressIndicator(color: accent))
                  : games.isEmpty
                      ? Center(child: Text(
                          _search.isNotEmpty ? 'No results' : 'No games',
                          style: Theme.of(context).textTheme.bodyMedium))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          itemCount: games.length,
                          itemBuilder: (_, i) {
                            final game = games[i];
                            final name = game['name']?.toString() ?? '';
                            final isFav = game['favorite'] == 'true';
                            final hasAchievements = game['cheevosId'] != null &&
                                game['cheevosId'].toString().isNotEmpty &&
                                game['cheevosId'].toString() != '0';
                            final playcount = int.tryParse(
                                game['playcount']?.toString() ?? '0') ?? 0;
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                              child: InkWell(
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => GameDetailScreen(
                                      game: game,
                                      fetchImage: widget.fetchImage,
                                      systemLogo: widget.systemLogo,
                                      allGames: widget.allGames,
                                    ),
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(16),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  child: Row(children: [
                                    Expanded(child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(name,
                                            style: const TextStyle(
                                                color: Colors.white, fontSize: 14,
                                                fontWeight: FontWeight.w500),
                                            overflow: TextOverflow.ellipsis),
                                        Row(children: [
                                            if (isFav) ...[
                                              const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 11),
                                              const SizedBox(width: 3),
                                            ],
                                            if (hasAchievements) ...[
                                              const Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 11),
                                              const SizedBox(width: 3),
                                            ],
                                            if ((game['manual'] ?? '').toString().isNotEmpty) ...[
                                              const Icon(Icons.menu_book_rounded, color: Colors.blueAccent, size: 11),
                                              const SizedBox(width: 3),
                                            ],
                                            if ((game['map'] ?? '').toString().isNotEmpty) ...[
                                              const Icon(Icons.map_rounded, color: Colors.greenAccent, size: 11),
                                              const SizedBox(width: 3),
                                            ],
                                            if (playcount > 0)
                                              Text('Played $playcount times',
                                                  style: const TextStyle(color: Colors.white24, fontSize: 10)),
                                          ]),
                                      ],
                                    )),
                                    GestureDetector(
                                      onTap: () => _launchGame(game['path'] ?? ''),
                                      behavior: HitTestBehavior.opaque,
                                      child: Container(
                                        width: 32, height: 32,
                                        decoration: BoxDecoration(
                                          color: accent.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(Icons.play_arrow_rounded,
                                            color: accent, size: 18),
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
