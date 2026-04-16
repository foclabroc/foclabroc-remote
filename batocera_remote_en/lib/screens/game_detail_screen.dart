import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_state.dart';

class GameDetailScreen extends StatefulWidget {
  final Map<String, dynamic> game;
  final Future<Uint8List?> Function(String) fetchImage;
  final Uint8List? systemLogo;
  final List<Map<String, dynamic>>? allGames;
  final Future<Uint8List?> Function(String)? getSystemLogo;

  const GameDetailScreen({
    super.key,
    required this.game,
    required this.fetchImage,
    this.systemLogo,
    this.allGames,
    this.getSystemLogo,
  });

  @override
  State<GameDetailScreen> createState() => _GameDetailScreenState();
}

class _GameDetailScreenState extends State<GameDetailScreen> {
  Uint8List? _imageBytes;
  Uint8List? _thumbBytes;
  Uint8List? _wheelBytes;

  void _pickRandom() {
    final all = widget.allGames;
    if (all == null || all.isEmpty) return;
    final game = all[Random().nextInt(all.length)];
    final sysName = game['_systemName']?.toString() ?? '';
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GameDetailScreen(
        game: game,
        fetchImage: widget.fetchImage,
        allGames: widget.allGames,
        getSystemLogo: widget.getSystemLogo,
        systemLogo: null, // sera chargé async si getSystemLogo fourni
      ),
    ));
  }

  @override
  void initState() {
    super.initState();
    _loadImages();
  }

  Future<Uint8List?> _fetchCached(String path) async {
    // widget.fetchImage gère déjà le cache
    return await widget.fetchImage(path);
  }

  Future<void> _loadImages() async {
    final wheel = widget.game['wheel']?.toString();
    final marquee = widget.game['marquee']?.toString();
    final logoPath = (wheel != null && wheel.isNotEmpty) ? wheel
        : (marquee != null && marquee.isNotEmpty) ? marquee : null;
    final thumb = widget.game['thumbnail']?.toString();
    final img = widget.game['image']?.toString();

    // Charge tout en parallèle — les noms tmp sont basés sur le hash donc pas de collision
    await Future.wait([
      if (logoPath != null && logoPath.isNotEmpty)
        _fetchCached(logoPath).then((bytes) {
          if (mounted && bytes != null) setState(() => _wheelBytes = bytes);
        }),
      if (thumb != null && thumb.isNotEmpty)
        _fetchCached(thumb).then((bytes) {
          if (mounted && bytes != null) setState(() => _thumbBytes = bytes);
        }),
      if (img != null && img.isNotEmpty)
        _fetchCached(img).then((bytes) {
          if (mounted && bytes != null) setState(() => _imageBytes = bytes);
        }),
    ]);
  }

  void _showMedia(Uint8List bytes) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          ),
        ),
        body: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
        ),
      ),
    ));
  }

  Future<void> _openVideo() async {
    final path = widget.game['video']?.toString();
    if (path == null || path.isEmpty) return;

    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: Card(
        child: Padding(padding: EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.movie_rounded, color: Colors.purpleAccent, size: 32),
            SizedBox(height: 16),
            CircularProgressIndicator(color: Colors.purpleAccent),
            SizedBox(height: 12),
            Text('Loading...', style: TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
        ),
      )),
    );

    try {
      final state = context.read<AppState>();
      final dir = await getTemporaryDirectory();
      final localPath = '${dir.path}/vid_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final url = 'http://127.0.0.1:1234$path';

      // Cherche le vrai chemin SFTP via curl + header ou direct download
      final tmpPath = '/tmp/foc_v_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await state.ssh.execute('curl -s "$url" -o "$tmpPath"');
      if (!mounted) return;
      await state.ssh.downloadFileToDisk(tmpPath, localPath);
      state.ssh.execute('rm -f "$tmpPath"');
      if (!mounted) return;

      final controller = VideoPlayerController.file(File(localPath));
      await controller.initialize();
      if (!mounted) { controller.dispose(); return; }
      Navigator.of(context, rootNavigator: true).pop();

      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        builder: (_) => _VideoPlayerScreen(
          filePath: localPath,
          title: widget.game['name']?.toString() ?? '',
          preloadedController: controller,
        ),
      ));
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Future<void> _openManual() async {
    final path = widget.game['manual']?.toString();
    if (path == null || path.isEmpty) return;
    await _openFileViewer(path, 'Manual - ${widget.game['name'] ?? ''}');
  }

  Future<void> _openMap() async {
    final path = widget.game['map']?.toString();
    if (path == null || path.isEmpty) return;
    await _openFileViewer(path, 'Map - ${widget.game['name'] ?? ''}');
  }

  Future<void> _openFileViewer(String path, String title) async {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => const Center(child: Card(
        child: Padding(padding: EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading...'),
          ]),
        ),
      )),
    );

    try {
      final bytes = await _fetchCached(path);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (bytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to load file', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ));
        return;
      }

      final isPdf = bytes.length > 4 &&
          bytes[0] == 0x25 && bytes[1] == 0x50 &&
          bytes[2] == 0x44 && bytes[3] == 0x46;

      if (isPdf) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/viewer_${DateTime.now().millisecondsSinceEpoch}.pdf');
        await file.writeAsBytes(bytes);
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
          builder: (_) => _PdfViewerScreen(filePath: file.path, title: title),
        ));
      } else {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: const Color(0xFF161A22),
              title: Text(title, style: const TextStyle(fontSize: 15)),
            ),
            body: InteractiveViewer(
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
          ),
        ));
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final game = widget.game;
    final name = game['name'] ?? 'Unknown game';
    final cheevosId = game['cheevosId']?.toString();
    final hasRA = cheevosId != null && cheevosId != 'null' && cheevosId.isNotEmpty;
    final hasManual = game['manual'] != null && game['manual'].toString().isNotEmpty;
    final hasMap = game['map'] != null && game['map'].toString().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161A22),
        elevation: 0,
        title: Text(name.toString(),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
        actions: [
          if (widget.allGames != null && widget.allGames!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.casino_rounded, color: Colors.white54, size: 20),
              onPressed: _pickRandom,
              tooltip: 'Random game',
            ),
          if (hasRA)
            IconButton(
              icon: const Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 20),
              onPressed: () => launchUrl(
                Uri.parse('https://retroachievements.org/game/$cheevosId'),
                mode: LaunchMode.externalApplication,
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo système + Wheel / Marquee
            if (_wheelBytes != null || widget.systemLogo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Container(
                  width: double.infinity, height: 60,
                  decoration: BoxDecoration(
                    color: const Color(0xFF3D4F6B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    if (widget.systemLogo != null)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: widget.systemLogo![0] == 0x3C
                            ? SizedBox(width: 60, height: 40, child: SvgPicture.memory(widget.systemLogo!, fit: BoxFit.contain))
                            : Image.memory(widget.systemLogo!, fit: BoxFit.contain, width: 60),
                      ),
                    if (widget.systemLogo != null && _wheelBytes != null)
                      Container(width: 1, height: 40, color: Colors.white10),
                    if (_wheelBytes != null)
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showMedia(_wheelBytes!),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(_wheelBytes!, fit: BoxFit.contain),
                          ),
                        ),
                      ),
                    if (widget.systemLogo == null && _wheelBytes == null)
                      const SizedBox.shrink(),
                  ]),
                ),
              ),

            // Thumbnail + Image côte à côte
            if (_thumbBytes != null || _imageBytes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Row(children: [
                  if (_thumbBytes != null)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showMedia(_thumbBytes!),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_thumbBytes!, fit: BoxFit.contain, height: 160),
                        ),
                      ),
                    ),
                  if (_thumbBytes != null && _imageBytes != null) const SizedBox(width: 8),
                  if (_imageBytes != null)
                    Expanded(
                      flex: _thumbBytes != null ? 2 : 1,
                      child: GestureDetector(
                        onTap: () => _showMedia(_imageBytes!),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.memory(_imageBytes!, fit: BoxFit.contain, height: 160),
                        ),
                      ),
                    ),
                ]),
              ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis, maxLines: 2),
                  const SizedBox(height: 6),

                  Wrap(spacing: 12, children: [
                    if (game['genre'] != null)
                      _InfoChip(label: game['genre'].toString(), icon: Icons.category_rounded),
                    if (game['developer'] != null)
                      _InfoChip(label: game['developer'].toString(), icon: Icons.code_rounded),
                    if (game['publisher'] != null)
                      _InfoChip(label: game['publisher'].toString(), icon: Icons.business_rounded),
                    if (game['releasedate'] != null && game['releasedate'].toString().length >= 4)
                      _InfoChip(label: game['releasedate'].toString().substring(0, 4), icon: Icons.calendar_today_rounded),
                    if (game['favorite'] == 'true')
                      _InfoChip(label: 'Favorite', icon: Icons.star_rounded, color: Colors.amberAccent),
                    _InfoChip(
                      label: int.tryParse(game['playcount']?.toString() ?? '0') == 0
                          ? 'Never played' : 'Played ${game['playcount']} times',
                      icon: Icons.play_circle_rounded,
                    ),
                  ]),

                  if (game['desc'] != null && game['desc'].toString().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(game['desc'].toString(),
                        style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.6)),
                  ],

                  const SizedBox(height: 16),

                  // Boutons
                  Row(children: [
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final state = context.read<AppState>();
                          final gamePath = game['path']?.toString() ?? '';
                          try {
                            final running = await state.ssh.execute('curl -s http://127.0.0.1:1234/runningGame');
                            if (running.isNotEmpty && !running.contains('"msg"')) {
                              await state.ssh.execute('curl -s http://127.0.0.1:1234/emukill');
                              await Future.delayed(const Duration(seconds: 2));
                            }
                            final session = await state.ssh.client!.execute('curl -s -X POST http://127.0.0.1:1234/launch -d "$gamePath"');
                            await session.done;
                          } catch (_) {}
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Launching...', style: TextStyle(color: Colors.white)),
                            backgroundColor: Color(0xFF1C2230),
                            behavior: SnackBarBehavior.floating,
                          ));
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: const Text('Launch', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    if (hasManual) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openManual,
                          icon: const Icon(Icons.menu_book_rounded, size: 16),
                          label: const Text('Manual'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blueAccent,
                            side: const BorderSide(color: Colors.blueAccent),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                    if (hasMap) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _openMap,
                          icon: const Icon(Icons.map_rounded, size: 16),
                          label: const Text('Map'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.greenAccent,
                            side: const BorderSide(color: Colors.greenAccent),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ]),

                  // Bouton vidéo
                  if (game['video'] != null && game['video'].toString().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openVideo,
                        icon: const Icon(Icons.play_circle_outline_rounded, size: 18, color: Colors.purpleAccent),
                        label: const Text('Watch video', style: TextStyle(color: Colors.purpleAccent)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.purpleAccent,
                          side: const BorderSide(color: Colors.purpleAccent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],

                  if (hasRA) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse('https://retroachievements.org/game/$cheevosId'),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.emoji_events_rounded, size: 18, color: Colors.amberAccent),
                        label: const Text('View on RetroAchievements',
                            style: TextStyle(color: Colors.amberAccent)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.amberAccent,
                          side: const BorderSide(color: Colors.amberAccent),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Info Chip ────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color? color;
  const _InfoChip({required this.label, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white38;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: c),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: TextStyle(color: c, fontSize: 11), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

// ─── PDF Viewer ───────────────────────────────────────────────────────────────

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
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
              overflow: TextOverflow.ellipsis),
          if (_totalPages > 0)
            Text('Page ${_currentPage + 1} / $_totalPages',
                style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ]),
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
      body: Stack(children: [
        PDFView(
          filePath: widget.filePath,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          fitPolicy: FitPolicy.BOTH,
          onRender: (pages) => setState(() { _totalPages = pages ?? 0; _isReady = true; }),
          onPageChanged: (page, total) => setState(() { _currentPage = page ?? 0; _totalPages = total ?? 0; }),
          onViewCreated: (controller) => _controller = controller,
        ),
        if (!_isReady) Center(child: CircularProgressIndicator(color: accent)),
      ]),
    );
  }
}

// ─── Video Player ─────────────────────────────────────────────────────────────

class _VideoPlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final VideoPlayerController? preloadedController;
  const _VideoPlayerScreen({required this.filePath, required this.title, this.preloadedController});

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.preloadedController != null) {
      _controller = widget.preloadedController!;
      _initialized = true;
      _controller.play();
    } else {
      _controller = VideoPlayerController.file(File(widget.filePath))
        ..initialize().then((_) {
          if (mounted) {
            setState(() => _initialized = true);
            _controller.play();
          }
        });
    }
    _controller.setLooping(true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 15)),
      ),
      body: _initialized
          ? SafeArea(
              child: Column(children: [
                Expanded(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  ),
                ),
                VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: accent,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 28),
                      onPressed: () => _controller.seekTo(_controller.value.position - const Duration(seconds: 10)),
                    ),
                    ValueListenableBuilder(
                      valueListenable: _controller,
                      builder: (_, value, __) => IconButton(
                        iconSize: 44,
                        icon: Icon(value.isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded, color: Colors.white),
                        onPressed: () => value.isPlaying ? _controller.pause() : _controller.play(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 28),
                      onPressed: () => _controller.seekTo(_controller.value.position + const Duration(seconds: 10)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ]),
            )
          : Center(child: CircularProgressIndicator(color: accent)),
    );
  }
}
