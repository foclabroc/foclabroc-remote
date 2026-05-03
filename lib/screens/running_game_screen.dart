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
  bool _imageTried = false;
  bool _wheelTried = false;
  Timer? _autoRefresh;
  Timer? _timeRefresh;
  Timer? _statsRefresh;

  // Stats système
  double _cpuTemp = 0;
  double _cpuUsage = 0;
  int _ramUsed = 0;
  int _ramTotal = 0;
  List<int> _prevCpu = [];

  // Capture vidéo 30s
  bool _capturing = false;
  int _captureRemaining = 0;
  Timer? _captureTimer;
  bool _captureCancelled = false;

  // Pending scrap tracking (to finalize when the game ends)
  bool _hasPendingScrap = false;
  String? _previousRomPath; // pour détecter la transition running → idle
  Timer? _finalizeTimer;    // débounce de la finalisation pour éviter race avec relaunch
  bool _finalizing = false; // évite réentrance

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (state.isConnected) {
        _fetchGameInfo();
        // Si l'app a été tuée pendant qu'un scrap était pending et qu'aucun jeu
        // ne tourne actuellement → finalise.
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _gameInfo.isEmpty) _autoFinalizePending();
        });
      }
    });
    _autoRefresh = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && context.read<AppState>().isConnected) _fetchGameInfo();
    });
    _timeRefresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<AppState>().isConnected && _gameInfo.isNotEmpty) {
        _fetchPlayTime();
      }
    });
    // Stats CPU/RAM toutes les 3s
    _statsRefresh = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && context.read<AppState>().isConnected) _fetchStats();
    });
  }

  Future<void> _fetchStats() async {
    await Future.wait([_fetchCpuTemp(), _fetchCpuUsage(), _fetchRam()]);
    if (mounted) setState(() {});
  }

  Future<void> _fetchCpuTemp() async {
    final raw = await _execDirect(
      'cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo 0');
    final numLine = raw.split('\n').lastWhere(
        (l) => RegExp(r'^\d+$').hasMatch(l.trim()), orElse: () => '0');
    final val = int.tryParse(numLine.trim()) ?? 0;
    _cpuTemp = val > 1000 ? val / 1000.0 : val.toDouble();
  }

  Future<void> _fetchCpuUsage() async {
    final raw = await _execDirect('cat /proc/stat');
    final cpuLine = raw.split('\n').firstWhere(
        (l) => l.startsWith('cpu '), orElse: () => '');
    if (cpuLine.isEmpty) return;
    final parts = cpuLine.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.length < 5) return;
    try {
      final values = parts.skip(1).map(int.parse).toList();
      final idle = values[3] + (values.length > 4 ? values[4] : 0);
      final total = values.reduce((a, b) => a + b);
      if (_prevCpu.length == 2) {
        final diffTotal = total - _prevCpu[0];
        final diffIdle  = idle  - _prevCpu[1];
        if (diffTotal > 0) _cpuUsage = ((diffTotal - diffIdle) / diffTotal * 100).clamp(0.0, 100.0);
      }
      _prevCpu = [total, idle];
    } catch (_) {}
  }

  Future<void> _fetchRam() async {
    final raw = await _execDirect('cat /proc/meminfo');
    int total = 0, available = 0;
    for (final line in raw.split('\n')) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final val = int.tryParse(parts[1]) ?? 0;
      if (line.startsWith('MemTotal')) total = val;
      if (line.startsWith('MemAvailable')) available = val;
    }
    _ramTotal = total ~/ 1024;
    _ramUsed  = (total - available) ~/ 1024;
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    _timeRefresh?.cancel();
    _statsRefresh?.cancel();
    _captureTimer?.cancel();
    _finalizeTimer?.cancel();
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
      // 1. Cherche emulatorlauncher (la plupart des émulateurs)
      String t = await _execDirect(
        "ps -o etime= -C emulatorlauncher 2>/dev/null | head -1 | tr -d '[:blank:]'",
      );
      // 2. Si vide, cherche les émulateurs qui se lancent directement (Switch, PS3...)
      if (t.isEmpty) {
        const directProcs = [
          'ryujinx', 'yuzu', 'suyu', 'torzu',
          'rpcs3', 'xemu', 'cemu', 'ppsspp', 'dolphin-emu',
        ];
        for (final proc in directProcs) {
          t = await _execDirect(
            "ps -o etime= -C $proc 2>/dev/null | head -1 | tr -d '[:blank:]'",
          );
          if (t.isNotEmpty) break;
        }
      }
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
        for (final f in ['name', 'systemName', 'emulator', 'core', 'image', 'wheel', 'manual', 'cheevosId', 'developer', 'players', 'rating', 'genre', 'path']) {
          final v = json[f];
          if (v != null && v.toString().isNotEmpty && v.toString() != 'null') {
            info[f] = v.toString();
          }
        }
      } catch (_) {}

      if (info['name'] == null) {
        // Transition jeu en cours → aucun jeu : programme la finalisation
        // dans 1s. Court débounce car le flag isLaunchingGame d'AppState
        // protège déjà des relaunches via l'app.
        if (_previousRomPath != null) {
          _previousRomPath = null;
          _finalizeTimer?.cancel();
          _finalizeTimer = Timer(const Duration(seconds: 1), () {
            if (mounted && _gameInfo.isEmpty && !_finalizing) {
              _autoFinalizePending();
            }
          });
        }
        setState(() { _gameInfo = {}; _imageBytes = null; _wheelBytes = null; _playTime = ''; _loading = false; });
        return;
      }

      final newName = info['name'] ?? '';
      final oldName = _gameInfo['name'] ?? '';
      // Un jeu tourne → annuler toute finalisation en attente + clear le flag
      // launching (le launch a réussi puisque le jeu apparaît).
      if (_finalizeTimer?.isActive ?? false) _finalizeTimer?.cancel();
      context.read<AppState>().clearLaunchingGame();
      _previousRomPath = info['path']; // tracker l'état "running"
      setState(() { _gameInfo = info; _loading = false; });

      if (newName != oldName) {
        _imageBytes = null;
        _wheelBytes = null;
        _imageTried = false;
        _wheelTried = false;
        _fetchPlayTime();
        _reloadImages(info);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  /// Recharge wheel + image depuis l'API (après changement de jeu ou scrap).
  /// Reset les flags et bytes avant de refetcher.
  void _reloadImages(Map<String, String> info) {
    setState(() {
      _imageBytes = null;
      _wheelBytes = null;
      _imageTried = false;
      _wheelTried = false;
    });

    if (info.containsKey('wheel')) {
      _fetchImageDirect(info['wheel']!).then((bytes) {
        if (!mounted) return;
        setState(() {
          if (bytes != null) _wheelBytes = bytes;
          _wheelTried = true;
        });
        if (info.containsKey('image')) {
          _fetchImageDirect(info['image']!).then((bytes2) {
            if (!mounted) return;
            setState(() {
              if (bytes2 != null) _imageBytes = bytes2;
              _imageTried = true;
            });
          });
        }
      });
    } else if (info.containsKey('image')) {
      _fetchImageDirect(info['image']!).then((bytes) {
        if (!mounted) return;
        setState(() {
          if (bytes != null) _imageBytes = bytes;
          _imageTried = true;
        });
      });
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
      // Arrêt propre via hotkeygen (fonctionne pour tous les émulateurs dont Switch)
      await state.ssh.execute('hotkeygen --send exit');
      await Future.delayed(const Duration(seconds: 3));
      // Si le jeu tourne encore, force kill via l'API ES
      final stillRunning = await _execDirect('curl -s http://127.0.0.1:1234/runningGame 2>/dev/null');
      if (stillRunning.isNotEmpty && stillRunning != 'null') {
        await state.ssh.execute('curl -s http://127.0.0.1:1234/emukill');
        await Future.delayed(const Duration(seconds: 2));
      }
      await _fetchGameInfo();
    }
  }

  // ─── Capture vidéo 30s avec déplacement vers dossier vidéos du système ────

  /// Échappe une string pour usage en argument shell entre simples quotes.
  String _shQ(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// Sanitize un nom de jeu pour en faire un nom de fichier sûr.
  String _sanitizeFilename(String name) {
    var s = name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) s = 'capture';
    return s;
  }

  /// Détecte le sous-dossier vidéos du système (./media/videos ou ./videos).
  /// Retourne le chemin relatif sans slash final, ex "media/videos".
  Future<String> _detectVideosDir(String systemName) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    final raw = await _execDirect(
      "grep -oE '<video>[^<]+</video>' ${_shQ(gamelist)} 2>/dev/null | head -5",
    );
    for (final line in raw.split('\n')) {
      final m = RegExp(r'<video>([^<]+)</video>').firstMatch(line);
      if (m == null) continue;
      var p = m.group(1)!.trim();
      if (p.startsWith('./')) p = p.substring(2);
      final idx = p.lastIndexOf('/');
      if (idx > 0) return p.substring(0, idx);
    }
    return 'media/videos';
  }

  /// Cherche le `<video>` du jeu courant dans gamelist.xml.
  /// Retourne le chemin relatif (ex "./media/videos/sonic.mkv") ou null.
  Future<String?> _findExistingVideo(String systemName, String romPath) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    final romBase = romPath.split('/').last;
    const script = r'''
import xml.etree.ElementTree as ET, sys, os
try:
    t = ET.parse(sys.argv[1])
    rb = sys.argv[2]
    for g in t.findall("game"):
        p = g.find("path")
        if p is not None and p.text and os.path.basename(p.text) == rb:
            v = g.find("video")
            if v is not None and v.text and v.text.strip():
                print(v.text.strip())
                sys.exit(0)
except Exception:
    pass
''';
    // Écrit le script dans /tmp, l'exécute, le supprime — évite les pb de quoting bash
    final tmpScript = '/tmp/.batoremote_findvid_${DateTime.now().millisecondsSinceEpoch}.py';
    await _writeRemoteFile(tmpScript, script);
    final out = await _execDirect(
      'python3 ${_shQ(tmpScript)} ${_shQ(gamelist)} ${_shQ(romBase)} 2>/dev/null; rm -f ${_shQ(tmpScript)}',
    );
    return out.trim().isEmpty ? null : out.trim();
  }

  /// Écrit du contenu texte dans un fichier distant via base64 (safe pour scripts).
  Future<void> _writeRemoteFile(String path, String content) async {
    final b64 = base64.encode(utf8.encode(content));
    final state = context.read<AppState>();
    final session = await state.ssh.client!.execute(
      "echo '$b64' | base64 -d > ${_shQ(path)}",
    );
    await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
    await session.done;
  }

  /// Met à jour gamelist.xml : ajoute/remplace le <video> du jeu courant.
  Future<bool> _updateGamelistVideo(
      String systemName, String romPath, String videoRelPath) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    final romBase = romPath.split('/').last;
    final gameName = _gameInfo['name'] ?? romBase;
    const script = r'''
import xml.etree.ElementTree as ET, sys, os
gl = sys.argv[1]; rb = sys.argv[2]; videoPath = sys.argv[3]; gameName = sys.argv[4]
try:
    if not os.path.exists(gl):
        root = ET.Element("gameList")
        tree = ET.ElementTree(root)
    else:
        tree = ET.parse(gl)
        root = tree.getroot()
    target = None
    for g in root.findall("game"):
        p = g.find("path")
        if p is not None and p.text and os.path.basename(p.text) == rb:
            target = g; break
    if target is None:
        target = ET.SubElement(root, "game")
        pe = ET.SubElement(target, "path"); pe.text = "./" + rb
        ne = ET.SubElement(target, "name"); ne.text = gameName
    ve = target.find("video")
    if ve is None:
        ve = ET.SubElement(target, "video")
    ve.text = videoPath
    try:
        ET.indent(tree, space="\t")  # Python 3.9+ : re-indente proprement tout l'arbre
    except AttributeError:
        pass  # Fallback silencieux pour Python <3.9
    tree.write(gl, encoding="utf-8", xml_declaration=True)
    print("OK")
except Exception as e:
    print("ERR:" + str(e))
''';
    final tmpScript = '/tmp/.batoremote_updgl_${DateTime.now().millisecondsSinceEpoch}.py';
    await _writeRemoteFile(tmpScript, script);
    final result = await _execDirect(
      'python3 ${_shQ(tmpScript)} ${_shQ(gamelist)} ${_shQ(romBase)} ${_shQ(videoRelPath)} ${_shQ(gameName)} 2>&1; rm -f ${_shQ(tmpScript)}',
    );
    return result.contains('OK');
  }

  /// Demande à EmulationStation de relire les gamelist.xml depuis le disque
  /// (équivalent du bouton "Reload" du menu web ES). ES n'écrit pas pendant
  /// cet appel, donc nos modifications sont préservées.
  Future<void> _reloadEsGamelist() =>
      context.read<AppState>().pendingService.reloadEsGamelist();

  // ─── Système de scraps "pending" ──────────────────────────────────────────
  // Quand l'utilisateur scrappe pendant un jeu, on ne peut pas écrire dans
  // gamelist.xml immédiatement car ES écrasera nos balises au quit du jeu
  // (il réécrit le fichier depuis sa mémoire pour mettre à jour gametime/
  // lastplayed/playcount). On stocke donc les balises dans /userdata/system
  // et on les applique automatiquement quand le jeu se termine.
  // La logique métier est dans PendingScrapService (lib/services/).

  /// Wrapper pour la sauvegarde d'un pending (utilisé depuis _finishCapture
  /// et _scrapScreenshot).
  Future<bool> _savePending({
    required String systemName,
    required String romPath,
    required String gameName,
    required Map<String, String> tags,
  }) async {
    return context.read<AppState>().pendingService.savePending(
      systemName: systemName,
      romPath: romPath,
      gameName: gameName,
      tags: tags,
    );
  }

  /// Auto-finalisation : appelée à la transition jeu → idle ou au démarrage.
  Future<void> _autoFinalizePending() async {
    if (_finalizing) return; // évite réentrance
    final state = context.read<AppState>();
    // Si un launch est en cours via l'app, on ne finalise pas maintenant :
    // reloadgames annulerait le launch. On retentera quand le launch sera
    // confirmé (jeu détecté → flag clear) puis sortie du nouveau jeu.
    if (state.isLaunchingGame) return;
    _finalizing = true;
    try {
      // Re-check tardif : un jeu a-t-il été lancé entre la transition et
      // l'expiration du débounce ?
      if (_gameInfo.isNotEmpty) return;
      final files = await state.pendingService.listPendingFiles();
      if (files.isEmpty) return;
      final n = await state.pendingService.finalizePending();
      if (mounted) {
        setState(() => _hasPendingScrap = false);
        if (n > 0) {
          _showSuccess(n == 1
              ? 'Scrap finalisé dans le gamelist'
              : '$n scraps finalisés dans le gamelist');
        }
      }
    } finally {
      _finalizing = false;
    }
  }

  /// Workflow complet : capture 30s + déplacement + update gamelist.
  Future<void> _captureVideo30s(AppState state) async {
    if (_capturing) return;
    final gameName = _gameInfo['name'] ?? '';
    final systemName = _gameInfo['systemName'] ?? '';
    final romPath = _gameInfo['path'] ?? '';
    if (gameName.isEmpty || systemName.isEmpty || romPath.isEmpty) {
      _showError('Infos du jeu incomplètes');
      return;
    }

    // Cherche une vidéo existante : si oui, on récupère son nom pour réutiliser exactement
    // le même chemin (et garder la cohérence avec le gamelist).
    final existingVideo = await _findExistingVideo(systemName, romPath);
    String? overridePath; // null = on génère <gameName>.mkv
    if (existingVideo != null) {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Text('Vidéo existante'),
          content: Text(
            'Le jeu "$gameName" a déjà une vidéo :\n$existingVideo\n\n'
            'La remplacer (le nom de fichier sera conservé) ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
              child: const Text('Remplacer'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      overridePath = existingVideo; // on réutilisera ce nom exact
    }

    setState(() {
      _capturing = true;
      _captureCancelled = false;
      _captureRemaining = 30;
    });
    try {
      await state.ssh.startRecord();
    } catch (e) {
      if (mounted) _showError('Erreur démarrage : $e');
      setState(() => _capturing = false);
      return;
    }

    _captureTimer = Timer.periodic(const Duration(seconds: 1), (t) async {
      if (!mounted) { t.cancel(); return; }
      if (_captureCancelled) { t.cancel(); return; }
      setState(() => _captureRemaining--);
      if (_captureRemaining <= 0) {
        t.cancel();
        await _finishCapture(state, gameName, systemName, romPath, overridePath);
      }
    });
  }

  Future<void> _cancelCapture(AppState state) async {
    _captureCancelled = true;
    _captureTimer?.cancel();
    setState(() => _capturing = false);
    try {
      await state.ssh.execute('batocera-record stop');
      await Future.delayed(const Duration(milliseconds: 500));
      // client.execute() direct car la commande contient des single quotes
      final s = await state.ssh.client!.execute(
        "mkv=\$(ls -t /userdata/recordings/*.mkv 2>/dev/null | grep -v '\\.tmp\\.mkv\$' | head -1); "
        "[ -n \"\$mkv\" ] && rm -f \"\$mkv\" \"\${mkv%.mkv}.tmp.mkv\" 2>/dev/null",
      );
      await s.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await s.done;
      _showSuccess('Capture annulée');
    } catch (_) {}
  }

  Future<void> _finishCapture(AppState state, String gameName,
      String systemName, String romPath, String? overridePath) async {
    // UI optimiste : on sort du mode "capturing" tout de suite pour que le
    // compteur disparaisse, puis on affiche un snackbar provisoire pendant
    // que le post-traitement (stop, mv, pending) se fait en arrière-plan.
    if (mounted) setState(() => _capturing = false);
    _showInfo('Traitement de la vidéo…');

    try {
      await state.ssh.execute('batocera-record stop');

      // Détermine destDir, fileName, destPath, videoRelPath en fonction du cas
      final String videosDir;
      final String fileName;
      if (overridePath != null) {
        // Réutilise le chemin exact de la vidéo existante (relatif au système)
        var rel = overridePath;
        if (rel.startsWith('./')) rel = rel.substring(2);
        final lastSlash = rel.lastIndexOf('/');
        if (lastSlash > 0) {
          videosDir = rel.substring(0, lastSlash);
          fileName = rel.substring(lastSlash + 1);
        } else {
          videosDir = await _detectVideosDir(systemName);
          fileName = rel;
        }
      } else {
        videosDir = await _detectVideosDir(systemName);
        fileName = '${_sanitizeFilename(gameName)}.mkv';
      }
      final destDir = '/userdata/roms/$systemName/$videosDir';
      final destPath = '$destDir/$fileName';

      // Courte attente de la fin du remux ffmpeg (max ~3s) pour éviter la race
      // entre notre `mv` et le `mv` du remux. Au-delà on tue ffmpeg et on prend
      // le fichier source non-réindexé (lecture linéaire OK, seek dégradé).
      bool ffmpegRunning = true;
      for (int i = 0; i < 6 && ffmpegRunning; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final r = await _execDirect(
          "pgrep -f 'ffmpeg.*tmp.mkv' >/dev/null 2>&1 && echo R || echo D");
        ffmpegRunning = r.contains('R');
      }
      if (ffmpegRunning) {
        // ffmpeg pas encore fini → on le tue pour éviter la race au mv
        await _execDirect("pkill -9 -f 'ffmpeg.*tmp.mkv' 2>/dev/null; rm -f /userdata/recordings/*.tmp.mkv 2>/dev/null");
      }

      final mkv = await _execDirect(
        "ls -t /userdata/recordings/*.mkv 2>/dev/null | grep -v '\\.tmp\\.mkv\$' | head -1",
      );
      if (mkv.trim().isEmpty) {
        _showError('Fichier capture introuvable');
        return;
      }

      // mkdir + mv via client.execute() direct pour éviter le wrapping bash -l -c '...'
      // qui casserait le quoting des chemins contenant des espaces ou apostrophes.
      final src = mkv.trim();
      final mvSession = await state.ssh.client!.execute(
        'mkdir -p ${_shQ(destDir)} && mv -f ${_shQ(src)} ${_shQ(destPath)}',
      );
      await mvSession.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await mvSession.done;

      // Met à jour gamelist.xml uniquement si nouvelle vidéo (sinon le chemin n'a pas changé)
      // On ne peut PAS écrire dans gamelist.xml directement pendant qu'un jeu tourne :
      // ES réécrit le fichier au quit avec son état mémoire et nos balises sont perdues.
      // On stocke donc en pending et on applique au quit du jeu (auto-détecté).
      if (overridePath == null) {
        final videoRelPath = './$videosDir/$fileName';
        await _savePending(
          systemName: systemName,
          romPath: romPath,
          gameName: gameName,
          tags: {'video': videoRelPath},
        );
        if (mounted) setState(() => _hasPendingScrap = true);
      }

      if (mounted) {
        if (overridePath == null) {
          _showSuccess('Vidéo enregistrée : $videosDir/$fileName\n'
              'Sera finalisée à la sortie du jeu');
        } else {
          _showSuccess('Vidéo remplacée : $videosDir/$fileName');
        }
      }
    } catch (e) {
      if (mounted) _showError('Erreur : $e');
    }
  }

  // ─── Scrap screenshot ─────────────────────────────────────────────────────

  /// Détecte le sous-dossier images du système (./media/screenshots ou ./images).
  /// Retourne le chemin relatif sans slash final.
  Future<String> _detectImagesDir(String systemName) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    // On regarde plusieurs balises image susceptibles de pointer vers le dossier
    final raw = await _execDirect(
      "grep -oE '<(image|screenshot|thumbnail)>[^<]+</\\1>' ${_shQ(gamelist)} 2>/dev/null | head -10",
    );
    for (final line in raw.split('\n')) {
      final m = RegExp(r'<(?:image|screenshot|thumbnail)>([^<]+)<').firstMatch(line);
      if (m == null) continue;
      var p = m.group(1)!.trim();
      if (p.startsWith('./')) p = p.substring(2);
      final idx = p.lastIndexOf('/');
      if (idx > 0) return p.substring(0, idx);
    }
    return 'media/screenshots'; // convention par défaut Batocera moderne
  }

  /// Cherche les chemins existants `<image>` et `<screenshot>` dans gamelist.xml.
  /// Retourne (imagePath, screenshotPath) — null si absent.
  Future<(String?, String?)> _findExistingImages(String systemName, String romPath) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    final romBase = romPath.split('/').last;
    const script = r'''
import xml.etree.ElementTree as ET, sys, os
try:
    t = ET.parse(sys.argv[1])
    rb = sys.argv[2]
    for g in t.findall("game"):
        p = g.find("path")
        if p is not None and p.text and os.path.basename(p.text) == rb:
            img = g.find("image")
            scr = g.find("screenshot")
            print((img.text if img is not None and img.text else "") + "\n" +
                  (scr.text if scr is not None and scr.text else ""))
            sys.exit(0)
except Exception:
    pass
print("\n")
''';
    final tmpScript = '/tmp/.batoremote_findimg_${DateTime.now().millisecondsSinceEpoch}.py';
    await _writeRemoteFile(tmpScript, script);
    final out = await _execDirect(
      'python3 ${_shQ(tmpScript)} ${_shQ(gamelist)} ${_shQ(romBase)} 2>/dev/null; rm -f ${_shQ(tmpScript)}',
    );
    final lines = out.split('\n');
    final img = (lines.isNotEmpty && lines[0].trim().isNotEmpty) ? lines[0].trim() : null;
    final scr = (lines.length > 1 && lines[1].trim().isNotEmpty) ? lines[1].trim() : null;
    return (img, scr);
  }

  /// Met à jour les balises <image> et <screenshot> du jeu dans gamelist.xml.
  Future<bool> _updateGamelistImages(
      String systemName, String romPath, String imageRelPath, String screenshotRelPath) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    final romBase = romPath.split('/').last;
    final gameName = _gameInfo['name'] ?? romBase;
    const script = r'''
import xml.etree.ElementTree as ET, sys, os
gl = sys.argv[1]; rb = sys.argv[2]; imgPath = sys.argv[3]; scrPath = sys.argv[4]; gameName = sys.argv[5]
try:
    if not os.path.exists(gl):
        root = ET.Element("gameList")
        tree = ET.ElementTree(root)
    else:
        tree = ET.parse(gl)
        root = tree.getroot()
    target = None
    for g in root.findall("game"):
        p = g.find("path")
        if p is not None and p.text and os.path.basename(p.text) == rb:
            target = g; break
    if target is None:
        target = ET.SubElement(root, "game")
        pe = ET.SubElement(target, "path"); pe.text = "./" + rb
        ne = ET.SubElement(target, "name"); ne.text = gameName
    for tag, val in (("image", imgPath), ("screenshot", scrPath)):
        e = target.find(tag)
        if e is None:
            e = ET.SubElement(target, tag)
        e.text = val
    try:
        ET.indent(tree, space="\t")
    except AttributeError:
        pass
    tree.write(gl, encoding="utf-8", xml_declaration=True)
    print("OK")
except Exception as e:
    print("ERR:" + str(e))
''';
    final tmpScript = '/tmp/.batoremote_updimg_${DateTime.now().millisecondsSinceEpoch}.py';
    await _writeRemoteFile(tmpScript, script);
    final result = await _execDirect(
      'python3 ${_shQ(tmpScript)} ${_shQ(gamelist)} ${_shQ(romBase)} ${_shQ(imageRelPath)} ${_shQ(screenshotRelPath)} ${_shQ(gameName)} 2>&1; rm -f ${_shQ(tmpScript)}',
    );
    return result.contains('OK');
  }

  /// Workflow complet screenshot : capture + déplacement + update gamelist (image + screenshot).
  Future<void> _scrapScreenshot(AppState state) async {
    if (_capturing) return;
    final gameName = _gameInfo['name'] ?? '';
    final systemName = _gameInfo['systemName'] ?? '';
    final romPath = _gameInfo['path'] ?? '';
    if (gameName.isEmpty || systemName.isEmpty || romPath.isEmpty) {
      _showError('Infos du jeu incomplètes');
      return;
    }

    // 1. Vérifier si <image> ou <screenshot> existe → confirmation
    final (existingImg, existingScr) = await _findExistingImages(systemName, romPath);
    final hasAny = existingImg != null || existingScr != null;
    if (hasAny) {
      final shown = existingScr ?? existingImg ?? '';
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Text('Image existante'),
          content: Text(
            'Le jeu "$gameName" a déjà une image scrapée :\n$shown\n\n'
            'La remplacer (le nom de fichier sera conservé) ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
              child: const Text('Remplacer'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _capturing = true); // bloque le menu pendant le scrap

    try {
      // 2. Lance le screenshot Batocera
      // batocera-screenshot dépose un png dans /userdata/screenshots avec timestamp
      // On note la liste avant pour identifier le nouveau fichier après
      final beforeRaw = await _execDirect(
        "ls -t /userdata/screenshots/*.png 2>/dev/null | head -5",
      );
      final beforeSet = beforeRaw.split('\n').map((s) => s.trim()).toSet();

      await state.ssh.screenshot();
      await Future.delayed(const Duration(milliseconds: 1200));

      // 3. Trouver le nouveau png
      final afterRaw = await _execDirect(
        "ls -t /userdata/screenshots/*.png 2>/dev/null | head -5",
      );
      String? newShot;
      for (final line in afterRaw.split('\n')) {
        final p = line.trim();
        if (p.isEmpty) continue;
        if (!beforeSet.contains(p)) { newShot = p; break; }
      }
      if (newShot == null) {
        _showError('Screenshot introuvable');
        if (mounted) setState(() => _capturing = false);
        return;
      }

      // 4. Déterminer destDir + fileName (réutilise existant, sinon génère)
      String? overrideRel = existingScr ?? existingImg;
      final String imagesDir;
      final String fileName;
      if (overrideRel != null) {
        var rel = overrideRel;
        if (rel.startsWith('./')) rel = rel.substring(2);
        final lastSlash = rel.lastIndexOf('/');
        if (lastSlash > 0) {
          imagesDir = rel.substring(0, lastSlash);
          fileName = rel.substring(lastSlash + 1);
        } else {
          imagesDir = await _detectImagesDir(systemName);
          fileName = rel;
        }
      } else {
        imagesDir = await _detectImagesDir(systemName);
        fileName = '${_sanitizeFilename(gameName)}-screenshot.png';
      }
      final destDir = '/userdata/roms/$systemName/$imagesDir';
      final destPath = '$destDir/$fileName';

      // 5. mkdir + mv (client.execute() direct pour éviter le wrapping bash)
      final mvSession = await state.ssh.client!.execute(
        'mkdir -p ${_shQ(destDir)} && mv -f ${_shQ(newShot)} ${_shQ(destPath)}',
      );
      await mvSession.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await mvSession.done;

      final relPath = './$imagesDir/$fileName';
      // Si <image>/<screenshot> existaient déjà : pas besoin de toucher au gamelist
      // (on a juste écrasé le fichier sur disque, le chemin est inchangé).
      // Sinon on stocke en pending pour appliquer au quit du jeu (cf. note dans _finishCapture).
      final isNewEntry = (existingImg == null && existingScr == null);
      if (isNewEntry) {
        await _savePending(
          systemName: systemName,
          romPath: romPath,
          gameName: gameName,
          tags: {'image': relPath, 'screenshot': relPath},
        );
        if (mounted) setState(() => _hasPendingScrap = true);
      }

      // Charge le nouveau PNG directement via SFTP (depuis destPath) pour éviter
      // tout cache de l'API EmulationStation qui n'a pas encore vu le nouveau gamelist.
      Uint8List? newBytes;
      try {
        newBytes = await state.ssh.downloadFile(destPath);
      } catch (_) {}

      if (mounted) {
        if (isNewEntry) {
          _showSuccess('Screenshot enregistré : $imagesDir/$fileName\n'
              'Sera finalisé à la sortie du jeu');
        } else {
          _showSuccess('Screenshot remplacé : $imagesDir/$fileName');
        }
        // Met à jour _gameInfo (chemins) et injecte directement les bytes pour
        // afficher le nouveau visuel sans repasser par l'API ES.
        final updated = Map<String, String>.from(_gameInfo);
        updated['image'] = relPath;
        updated['screenshot'] = relPath;
        setState(() {
          _gameInfo = updated;
          if (newBytes != null && newBytes.isNotEmpty) {
            _imageBytes = newBytes;
            _imageTried = true;
          } else {
            _reloadImages(updated); // fallback si SFTP a échoué
          }
        });
      }
    } catch (e) {
      if (mounted) _showError('Erreur : $e');
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_rounded, color: Colors.redAccent, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: const Color(0xFF1C2230),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: const Color(0xFF1C2230),
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _showInfo(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const SizedBox(
          width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.lightBlueAccent),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: const Color(0xFF1C2230),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
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
              padding: const EdgeInsets.fromLTRB(64, 8, 24, 0),
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
                              else if (_gameInfo.containsKey('wheel') && !_wheelTried)
                                Container(
                                  width: double.infinity, height: 56,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFF1C2230)),
                                  child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
                                )
                              else
                                // Cas : balise <wheel> absente du gamelist OU chargement raté
                                Container(
                                  width: double.infinity, height: 56,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    color: const Color(0xFF1C2230),
                                    border: Border.all(color: Colors.white12),
                                  ),
                                  child: const Center(
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.image_not_supported_rounded, size: 16, color: Colors.white38),
                                        SizedBox(width: 8),
                                        Text('Logo indisponible',
                                            style: TextStyle(color: Colors.white38, fontSize: 12)),
                                      ],
                                    ),
                                  ),
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
                                      child: Image.memory(_imageBytes!, fit: BoxFit.contain),
                                    ),
                                  ),
                                )
                              else if (_gameInfo.containsKey('image') && !_imageTried)
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFF1C2230)),
                                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
                                  ),
                                )
                              else
                                // Cas : balise <image> absente du gamelist OU chargement raté
                                AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      color: const Color(0xFF1C2230),
                                      border: Border.all(color: Colors.white12),
                                    ),
                                    child: const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.image_not_supported_rounded, size: 32, color: Colors.white38),
                                          SizedBox(height: 6),
                                          Text('Image indisponible',
                                              style: TextStyle(color: Colors.white38, fontSize: 12)),
                                        ],
                                      ),
                                    ),
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
                                          if (_gameInfo['developer'] != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Row(children: [
                                                Icon(Icons.code_rounded, size: 11, color: Colors.white38),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(_gameInfo['developer']!,
                                                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 1),
                                                ),
                                              ]),
                                            ),
                                          if (_gameInfo['genre'] != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Row(children: [
                                                Icon(Icons.category_rounded, size: 11, color: Colors.white38),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(_gameInfo['genre']!,
                                                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                                                      overflow: TextOverflow.ellipsis,
                                                      maxLines: 2),
                                                ),
                                              ]),
                                            ),
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
                                        if (_gameInfo['rating'] != null)
                                          Row(children: [
                                            Icon(Icons.star_rounded, size: 12, color: Colors.amberAccent),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${((double.tryParse(_gameInfo['rating']!) ?? 0) * 100).toStringAsFixed(0)}%',
                                              style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                          ]),
                                        if (_gameInfo['players'] != null)
                                          Row(children: [
                                            Icon(Icons.people_rounded, size: 12, color: Colors.white38),
                                            const SizedBox(width: 4),
                                            Text('${_gameInfo['players']} joueur(s)',
                                                style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
                                        child: OutlinedButton(
                                          onPressed: _showManual,
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.blueAccent,
                                            side: const BorderSide(color: Colors.blueAccent),
                                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.picture_as_pdf_rounded, size: 14),
                                              SizedBox(width: 6),
                                              Flexible(child: Text('Manuel',
                                                  style: TextStyle(fontSize: 12),
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (hasCheevos)
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: OutlinedButton(
                                          onPressed: _openRetroAchievements,
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.amberAccent,
                                            side: const BorderSide(color: Colors.amberAccent),
                                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.emoji_events_rounded, size: 14),
                                              SizedBox(width: 6),
                                              Flexible(child: Text('Achievements',
                                                  style: TextStyle(fontSize: 12),
                                                  overflow: TextOverflow.ellipsis,
                                                  maxLines: 1)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(left: (hasManual || hasCheevos) ? 6 : 0),
                                      child: OutlinedButton(
                                        onPressed: () => _stopGame(state),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.redAccent,
                                          side: const BorderSide(color: Colors.redAccent),
                                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.stop_circle_rounded, size: 14),
                                            SizedBox(width: 6),
                                            Flexible(child: Text('Arrêter',
                                                style: TextStyle(fontSize: 12),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              // ── Stats CPU / RAM ───────────────────────────
                              if (_cpuTemp > 0 || _cpuUsage > 0 || _ramTotal > 0) ...[
                                const SizedBox(height: 12),
                                Row(children: [
                                  if (_cpuTemp > 0)
                                    Expanded(child: _StatChip(
                                      icon: Icons.thermostat_rounded,
                                      label: '${_cpuTemp.toStringAsFixed(1)}°C',
                                      color: _cpuTemp < 60 ? const Color(0xFF50FA7B)
                                           : _cpuTemp < 80 ? Colors.orangeAccent
                                           : Colors.redAccent,
                                    )),
                                  if (_cpuTemp > 0 && _cpuUsage > 0) const SizedBox(width: 8),
                                  if (_cpuUsage > 0)
                                    Expanded(child: _StatChip(
                                      icon: Icons.developer_board_rounded,
                                      label: 'CPU ${_cpuUsage.toStringAsFixed(0)}%',
                                      color: _cpuUsage < 60 ? const Color(0xFF50FA7B)
                                           : _cpuUsage < 85 ? Colors.orangeAccent
                                           : Colors.redAccent,
                                    )),
                                ]),
                                if (_ramTotal > 0) ...[
                                  const SizedBox(height: 8),
                                  _StatChip(
                                    icon: Icons.storage_rounded,
                                    label: '$_ramUsed Mo / $_ramTotal Mo',
                                    color: Colors.cyanAccent,
                                    fullWidth: true,
                                  ),
                                ],
                              ],

                              // ── Bouton scrap (vidéo / screenshot) ────────
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: _capturing
                                    ? OutlinedButton.icon(
                                        onPressed: () => _cancelCapture(state),
                                        icon: const Icon(Icons.cancel_rounded, size: 14),
                                        label: Text(
                                          'Annuler capture (${_captureRemaining}s)',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.orangeAccent,
                                          side: const BorderSide(color: Colors.orangeAccent),
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      )
                                    : PopupMenuButton<String>(
                                        tooltip: '',
                                        color: const Color(0xFF1C2230),
                                        position: PopupMenuPosition.over,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(10),
                                          side: const BorderSide(color: Color(0xFFE02020)),
                                        ),
                                        onSelected: (v) {
                                          if (v == 'video') _captureVideo30s(state);
                                          if (v == 'screenshot') _scrapScreenshot(state);
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(
                                            value: 'video',
                                            child: Row(children: [
                                              Icon(Icons.videocam_rounded, size: 16, color: Color(0xFFE02020)),
                                              SizedBox(width: 10),
                                              Text('Scrap vidéo auto 30s', style: TextStyle(color: Colors.white)),
                                            ]),
                                          ),
                                          PopupMenuItem(
                                            value: 'screenshot',
                                            child: Row(children: [
                                              Icon(Icons.photo_camera_rounded, size: 16, color: Color(0xFFE02020)),
                                              SizedBox(width: 10),
                                              Text('Scrap screenshot auto', style: TextStyle(color: Colors.white)),
                                            ]),
                                          ),
                                        ],
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 8),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: const Color(0xFFE02020)),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.auto_awesome_rounded, size: 14, color: Color(0xFFE02020)),
                                              SizedBox(width: 8),
                                              Text(
                                                'Scrap auto…',
                                                style: TextStyle(fontSize: 12, color: Color(0xFFE02020), fontWeight: FontWeight.w600),
                                              ),
                                              SizedBox(width: 4),
                                              Icon(Icons.arrow_drop_up_rounded, size: 18, color: Color(0xFFE02020)),
                                            ],
                                          ),
                                        ),
                                      ),
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

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool fullWidth;
  const _StatChip({required this.icon, required this.label, required this.color, this.fullWidth = false});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: fullWidth ? double.infinity : null,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
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
