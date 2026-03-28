import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../widgets/back_handler.dart';

class FileManagerScreen extends StatefulWidget {
  final String initialPath;
  const FileManagerScreen({super.key, this.initialPath = '/userdata'});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  late String _currentPath;
  List<_FileItem> _items = [];
  bool _loading = false;
  String? _error;
  String? _downloading;
  bool _uploading = false;
  double _uploadProgress = 0.0;
  String _uploadingFileName = '';
  int _uploadCurrentFile = 0;
  int _uploadTotalFiles = 0;
  final List<String> _breadcrumbs = ['/userdata'];

  // Sélection multiple
  final Set<String> _selected = {};
  bool get _selectionMode => _selected.isNotEmpty;

  // Presse-papiers
  List<_FileItem> _clipboard = [];
  bool _clipboardIsCut = false;

  static const _imageExts = ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'];
  static const _videoExts = ['mp4', 'mkv', 'avi', 'mov', 'webm', 'flv', 'm4v'];
  static const _pdfExts = ['pdf'];
  static const _textExts = ['txt', 'cfg', 'conf', 'ini', 'log', 'sh', 'xml', 'json', 'yaml', 'yml', 'md'];
  static const _editableExts = ['cfg', 'conf', 'ini', 'txt', 'sh', 'xml', 'json', 'yaml', 'yml', 'md'];

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    TabBackHandler.register(5, _handleBack);
    // Réinitialise l'état upload au démarrage
    _uploading = false;
    _uploadProgress = 0.0;
    _uploadingFileName = '';
    _uploadCurrentFile = 0;
    _uploadTotalFiles = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().addListener(_onConnectionChange);
      final state = context.read<AppState>();
      if (state.isConnected) _loadDir(_currentPath);
    });
  }

  bool _handleBack() {
    if (_selected.isNotEmpty) {
      setState(() => _selected.clear());
      return true;
    }
    if (_currentPath != '/userdata') {
      Navigator.of(context).pop();
      return true;
    }
    return false;
  }

  void _onConnectionChange() {
    final state = context.read<AppState>();
    if (state.isConnected && _items.isEmpty && !_loading) {
      _loadDir(_currentPath);
    }
  }

  @override
  void dispose() {
    TabBackHandler.unregister(5);
    context.read<AppState>().removeListener(_onConnectionChange);
    super.dispose();
  }

  String _ext(String name) => name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool _isImage(String name) => _imageExts.contains(_ext(name));
  bool _isVideo(String name) => _videoExts.contains(_ext(name));
  bool _isText(String name) => _textExts.contains(_ext(name));
  bool _isEditable(String name) => _editableExts.contains(_ext(name));
  bool _isOpenable(String name) => _isImage(name) || _isVideo(name) || _isText(name);

  Future<void> _loadDir(String path) async {
    final state = context.read<AppState>();
    if (!state.isConnected) return;
    setState(() { _loading = true; _error = null; _selected.clear(); });
    try {
      final raw = await state.ssh.execute('ls -lA --time-style="+%d/%m/%Y" "$path" 2>/dev/null');
      final items = <_FileItem>[];
      for (final line in raw.split('\n')) {
        if (line.isEmpty || line.startsWith('total')) continue;
        final item = _FileItem.parse(line, path);
        if (item != null) items.add(item);
      }
      items.sort((a, b) {
        if (a.isDir && !b.isDir) return -1;
        if (!a.isDir && b.isDir) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      setState(() { _items = items; _currentPath = path; _loading = false; });
    } catch (e) {
      setState(() { _error = 'Erreur : $e'; _loading = false; });
    }
  }

  void _navigate(String path) {
    if (path == _currentPath) return;
    // Utilise Navigator.push pour que le bouton retour Android fonctionne naturellement
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FileManagerScreen(initialPath: path),
    ));
  }

  void _goUp() {
    if (_currentPath == '/userdata') return;
    Navigator.of(context).pop();
  }


  void _toggleSelect(_FileItem item) {
    setState(() {
      if (_selected.contains(item.fullPath)) {
        _selected.remove(item.fullPath);
      } else {
        _selected.add(item.fullPath);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selected.length == _items.length) {
        _selected.clear();
      } else {
        _selected.addAll(_items.map((i) => i.fullPath));
      }
    });
  }

  List<_FileItem> get _selectedItems =>
      _items.where((i) => _selected.contains(i.fullPath)).toList();

  void _onItemTap(_FileItem item) {
    if (_selectionMode) {
      _toggleSelect(item);
    } else if (item.isDir) {
      _navigate(item.fullPath);
    } else {
      _showFileOptions(item);
    }
  }

  void _onItemLongPress(_FileItem item) {
    if (!_selected.contains(item.fullPath)) {
      setState(() => _selected.add(item.fullPath));
    }
  }

  // ─── Actions sélection ───────────────────────────────────────────────────

  void _copySelected() {
    _clipboard = List.from(_selectedItems);
    _clipboardIsCut = false;
    setState(() => _selected.clear());
    _showSnack('${_clipboard.length} élément(s) copié(s)');
  }

  void _cutSelected() {
    _clipboard = List.from(_selectedItems);
    _clipboardIsCut = true;
    setState(() => _selected.clear());
    _showSnack('${_clipboard.length} élément(s) coupé(s)');
  }

  Future<void> _paste() async {
    if (_clipboard.isEmpty) return;
    setState(() => _loading = true);
    final state = context.read<AppState>();
    int success = 0;
    for (final item in _clipboard) {
      try {
        final dest = '$_currentPath/${item.name}';
        if (_clipboardIsCut) {
          await state.ssh.execute('mv "${item.fullPath}" "$dest"');
        } else {
          await state.ssh.execute('cp -r "${item.fullPath}" "$dest"');
        }
        success++;
      } catch (_) {}
    }
    if (_clipboardIsCut) _clipboard.clear();
    await _loadDir(_currentPath);
    _showSnack('$success élément(s) collé(s)');
  }

  Future<void> _renameSelected() async {
    if (_selectedItems.length != 1) return;
    final item = _selectedItems.first;
    final ctrl = TextEditingController(text: item.name);
    final newName = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Renommer'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Nouveau nom',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onSubmitted: (v) => Navigator.of(ctx, rootNavigator: true).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(null),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(ctrl.text.trim()),
            child: const Text('Renommer'),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty && newName != item.name) {
      setState(() => _loading = true);
      final state = context.read<AppState>();
      try {
        await state.ssh.execute('mv "${item.fullPath}" "$_currentPath/$newName"');
      } catch (_) {}
      await _loadDir(_currentPath);
    }
    setState(() => _selected.clear());
  }

  Future<void> _deleteSelected() async {
    final count = _selectedItems.length;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Supprimer ?'),
        content: Text('Supprimer $count élément(s) ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _loading = true);
      final state = context.read<AppState>();
      for (final item in _selectedItems) {
        try { await state.ssh.execute('rm -rf "${item.fullPath}"'); } catch (_) {}
      }
      await _loadDir(_currentPath);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: isError ? Colors.redAccent.shade700 : const Color(0xFF1C2230),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Future<void> _uploadFile() async {
    // withData: false pour éviter OOM sur gros fichiers — on lit via path
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (result == null || result.files.isEmpty) return;
    final state = context.read<AppState>();
    int success = 0;
    final total = result.files.length;

    setState(() {
      _uploading = true;
      _uploadProgress = 0.0;
      _uploadTotalFiles = total;
      _uploadCurrentFile = 0;
    });

    try {
      for (int i = 0; i < result.files.length; i++) {
        final file = result.files[i];
        try {
          final path = file.path;
          if (path == null) continue;
          setState(() {
            _uploadCurrentFile = i + 1;
            _uploadingFileName = file.name;
            _uploadProgress = 0.0;
          });
          // Stream depuis le disque sans charger en RAM
          await state.ssh.uploadFileFromPath(
            path,
            '$_currentPath/${file.name}',
            onProgress: (sent, fileTotal) {
              if (mounted) {
                setState(() => _uploadProgress = fileTotal > 0 ? sent / fileTotal : 0.0);
              }
            },
          );
          success++;
        } catch (_) {}
      }
    } finally {
      _resetUploadState();
    }
    await _loadDir(_currentPath);
    _showSnack('$success fichier(s) envoyé(s) !');
  }

  void _resetUploadState() {
    if (mounted) {
      setState(() {
        _uploading = false;
        _uploadProgress = 0.0;
        _uploadingFileName = '';
        _uploadCurrentFile = 0;
        _uploadTotalFiles = 0;
      });
    }
  }

  Future<void> _openFile(_FileItem item) async {
    final ext = _ext(item.name);
    final state = context.read<AppState>();
    final dir = await getTemporaryDirectory();
    final localFile = File('${dir.path}/${item.name}');

    if (_videoExts.contains(ext)) {
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
              Text('Chargement...', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
        )),
      );
      try {
        final sizeStr = await state.ssh.execute('stat -c%s "${item.fullPath}" 2>/dev/null');
        final totalSize = int.tryParse(sizeStr.trim()) ?? 0;
        await state.ssh.downloadFileToDisk(item.fullPath, localFile.path);
        if (!mounted) return;

        final controller = VideoPlayerController.file(localFile);
        await controller.initialize();

        if (!mounted) { controller.dispose(); return; }
        Navigator.of(context, rootNavigator: true).pop();
        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
          builder: (_) => _FmVideoPlayer(filePath: localFile.path, title: item.name, preloadedController: controller),
        ));
      } catch (e) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          _showSnack('Erreur : $e', isError: true);
        }
      }
      return;
    }

    setState(() => _downloading = item.name);
    try {
      if (_pdfExts.contains(ext)) {
        await state.ssh.downloadFileToDisk(item.fullPath, localFile.path);
      } else {
        final bytes = await state.ssh.downloadFile(item.fullPath);
        await localFile.writeAsBytes(bytes);
      }
      if (!mounted) return;

      if (_imageExts.contains(ext)) {
        final bytes = await localFile.readAsBytes();
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              title: Text(item.name, style: const TextStyle(fontSize: 14)),
            ),
            body: InteractiveViewer(
              minScale: 0.5,
              maxScale: 5.0,
              child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
            ),
          ),
        ));
      } else if (_pdfExts.contains(ext)) {
        Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
          builder: (_) => _FmPdfViewer(filePath: localFile.path, title: item.name),
        ));
      } else {
        await OpenFilex.open(localFile.path);
      }
    } catch (e) {
      _showSnack('Erreur : $e', isError: true);
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Future<void> _openEditor(_FileItem item) async {
    setState(() => _loading = true);
    String content;
    try {
      final state = context.read<AppState>();
      content = await state.ssh.readFile(item.fullPath);
    } catch (e) {
      content = '';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => _TextEditorScreen(
          filename: item.name,
          fullPath: item.fullPath,
          initialContent: content,
        ),
      ),
    );
  }

  void _showFileOptions(_FileItem item) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: const Color(0xFF1C2230),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Row(
                children: [
                  Icon(_iconForFile(item.name), color: _colorForFile(item.name), size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(item.name,
                    style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            if (_isEditable(item.name))
              ListTile(
                leading: const Icon(Icons.edit_rounded, color: Colors.amberAccent),
                title: const Text('Modifier', style: TextStyle(color: Colors.white70)),
                subtitle: const Text('Éditeur intégré + sauvegarde sur Batocera',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                onTap: () { Navigator.of(ctx, rootNavigator: true).pop(); _openEditor(item); },
              ),
            if (_isOpenable(item.name))
              ListTile(
                leading: Icon(
                  _isImage(item.name) ? Icons.image_rounded
                      : _isVideo(item.name) ? Icons.play_circle_rounded
                      : Icons.open_in_new_rounded,
                  color: Colors.greenAccent,
                ),
                title: Text(
                  _isImage(item.name) ? 'Voir l\'image'
                      : _isVideo(item.name) ? 'Lire la vidéo'
                      : 'Ouvrir sur le téléphone',
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () { Navigator.of(ctx, rootNavigator: true).pop(); _openFile(item); },
              ),
            if (_isText(item.name) && !_isEditable(item.name))
              ListTile(
                leading: const Icon(Icons.visibility_rounded, color: Colors.blueAccent),
                title: const Text('Voir dans l\'app', style: TextStyle(color: Colors.white70)),
                onTap: () { Navigator.of(ctx, rootNavigator: true).pop(); _viewFileInApp(item); },
              ),
            if (!_isOpenable(item.name))
              ListTile(
                leading: const Icon(Icons.visibility_rounded, color: Colors.blueAccent),
                title: const Text('Voir le contenu', style: TextStyle(color: Colors.white70)),
                onTap: () { Navigator.of(ctx, rootNavigator: true).pop(); _viewFileInApp(item); },
              ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: const Text('Supprimer', style: TextStyle(color: Colors.white70)),
              onTap: () {
                Navigator.of(ctx, rootNavigator: true).pop();
                setState(() => _selected.add(item.fullPath));
                _deleteSelected();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _viewFileInApp(_FileItem item) async {
    setState(() => _loading = true);
    String content;
    try {
      final state = context.read<AppState>();
      // Vérifie si texte puis lit sans bash -l
      final fileType = await state.ssh.execute('file "${item.fullPath}" | grep -o text || echo binary');
      if (fileType.contains('text')) {
        content = await state.ssh.readFile(item.fullPath);
      } else {
        content = '[Fichier binaire — aperçu non disponible]';
      }
    } catch (e) { content = 'Erreur : $e'; }
    finally { if (mounted) setState(() => _loading = false); }
    if (!mounted) return;
    final capturedContent = content;
    showModalBottomSheet(
      context: context, useRootNavigator: true, isScrollControlled: true,
      backgroundColor: const Color(0xFF1C2230),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.8, maxChildSize: 0.95, minChildSize: 0.4, expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(margin: const EdgeInsets.symmetric(vertical: 10), width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  const Icon(Icons.article_rounded, color: Colors.white38, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.name,
                    style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600))),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                    onPressed: () => Navigator.of(sheetCtx, rootNavigator: true).pop()),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(child: SingleChildScrollView(
              controller: scrollCtrl, padding: const EdgeInsets.all(16),
              child: SelectableText(capturedContent.isEmpty ? '(fichier vide)' : capturedContent,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70, height: 1.6)),
            )),
          ],
        ),
      ),
    );
  }

  IconData _iconForFile(String name) {
    final ext = _ext(name);
    return switch (ext) {
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' => Icons.image_rounded,
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' => Icons.movie_rounded,
      'mp3' || 'ogg' || 'wav' || 'flac' => Icons.music_note_rounded,
      'zip' || '7z' || 'tar' || 'gz' => Icons.folder_zip_rounded,
      'cfg' || 'conf' || 'ini' || 'txt' || 'log' => Icons.description_rounded,
      'sh' => Icons.terminal_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }

  Color _colorForFile(String name) {
    final ext = _ext(name);
    return switch (ext) {
      'png' || 'jpg' || 'jpeg' || 'gif' || 'webp' || 'bmp' => Colors.pinkAccent,
      'mp4' || 'mkv' || 'avi' || 'mov' || 'webm' => Colors.purpleAccent,
      'mp3' || 'ogg' || 'wav' || 'flac' => Colors.greenAccent,
      'zip' || '7z' || 'tar' || 'gz' => Colors.orangeAccent,
      'cfg' || 'conf' || 'ini' || 'txt' || 'log' => Colors.blueAccent,
      'sh' => Colors.tealAccent,
      _ => Colors.white38,
    };
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final accent = Theme.of(context).colorScheme.primary;
    final selCount = _selected.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 8, 12, 8),
              child: Row(
                children: [
                  if (_selectionMode) ...[
                    GestureDetector(
                      onTap: () => setState(() => _selected.clear()),
                      child: const Icon(Icons.close_rounded, color: Colors.white54),
                    ),
                    const SizedBox(width: 12),
                    Text('$selCount sélectionné(s)',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.select_all_rounded, color: Colors.white38, size: 20),
                      onPressed: _selectAll,
                      tooltip: 'Tout sélectionner',
                    ),
                  ] else ...[
                    Text('Fichiers', style: Theme.of(context).textTheme.headlineMedium),
                    const Spacer(),
                    if (_loading || _downloading != null || _uploading)
                      _uploading
                        ? SizedBox(
                            width: 160,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (_uploadTotalFiles > 1)
                                      Text(
                                        '$_uploadCurrentFile/$_uploadTotalFiles ',
                                        style: TextStyle(color: accent, fontSize: 10),
                                      ),
                                    Flexible(
                                      child: Text(
                                        'Upload: $_uploadingFileName',
                                        style: TextStyle(color: accent, fontSize: 10),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                LinearProgressIndicator(
                                  value: _uploadProgress,
                                  color: accent,
                                  backgroundColor: accent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  minHeight: 5,
                                ),
                                Text(
                                  '${(_uploadProgress * 100).toInt()}%',
                                  style: TextStyle(color: accent, fontSize: 10),
                                ),
                              ],
                            ),
                          )
                        : Row(children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text('Chargement...',
                                  style: TextStyle(color: accent, fontSize: 12)),
                            ),
                            SizedBox(width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: accent)),
                            const SizedBox(width: 8),
                          ])
                    else ...[
                      IconButton(
                        icon: Icon(Icons.upload_rounded, color: Colors.white38, size: 20),
                        onPressed: state.isConnected ? _uploadFile : null,
                        tooltip: 'Envoyer un fichier',
                      ),
                      IconButton(
                        icon: Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                        onPressed: state.isConnected ? () => _loadDir(_currentPath) : null,
                      ),
                    ],
                  ],
                ],
              ),
            ),

            // Breadcrumb
            SizedBox(
              height: 36,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _breadcrumbs.length,
                itemBuilder: (_, i) {
                  final crumb = _breadcrumbs[i];
                  final label = i == 0 ? 'userdata' : crumb.split('/').last;
                  final isLast = i == _breadcrumbs.length - 1;
                  return Row(
                    children: [
                      GestureDetector(
                        onTap: isLast ? null : () => _navigate(crumb),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: isLast ? accent.withOpacity(0.15) : Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: isLast ? accent.withOpacity(0.4) : Colors.transparent),
                          ),
                          child: Text(label, style: TextStyle(
                            color: isLast ? accent : Colors.white54,
                            fontSize: 12,
                            fontWeight: isLast ? FontWeight.w700 : FontWeight.w400,
                          )),
                        ),
                      ),
                      if (!isLast)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 16),
                        ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 8),

            if (_currentPath != '/userdata' && state.isConnected && !_selectionMode)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InkWell(
                  onTap: _goUp,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Icon(Icons.arrow_upward_rounded, color: Colors.white38, size: 18),
                      const SizedBox(width: 10),
                      const Text('..', style: TextStyle(color: Colors.white54, fontSize: 14, fontFamily: 'monospace')),
                    ]),
                  ),
                ),
              ),

            const SizedBox(height: 4),

            // Liste
            Expanded(
              child: !state.isConnected
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi_off_rounded, size: 48, color: Colors.white.withOpacity(0.15)),
                      const SizedBox(height: 12),
                      Text('Non connecté', style: Theme.of(context).textTheme.bodyMedium),
                    ]))
                  : _error != null
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => _loadDir(_currentPath),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Réessayer'),
                          ),
                        ]))
                      : _loading && _items.isEmpty
                          ? Center(child: CircularProgressIndicator(color: accent))
                          : _items.isEmpty
                              ? Center(child: Text('Dossier vide', style: Theme.of(context).textTheme.bodyMedium))
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                                  itemCount: _items.length,
                                  itemBuilder: (_, i) {
                                    final item = _items[i];
                                    final isSelected = _selected.contains(item.fullPath);
                                    return _FileListTile(
                                      item: item,
                                      isSelected: isSelected,
                                      selectionMode: _selectionMode,
                                      onTap: () => _onItemTap(item),
                                      onLongPress: () => _onItemLongPress(item),
                                      iconForFile: _iconForFile,
                                      colorForFile: _colorForFile,
                                      isOpenable: _isOpenable(item.name),
                                      isEditable: _isEditable(item.name),
                                      isDownloading: _downloading == item.name,
                                      accent: accent,
                                    );
                                  },
                                ),
            ),
          ],
        ),
      ),

      // Barre d'actions sélection
      bottomSheet: _selectionMode
          ? Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1C2230),
                border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
              ),
              padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + MediaQuery.of(context).padding.bottom),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                    _ActionBtn(
                      icon: Icons.copy_rounded,
                      label: 'Copier',
                      color: Colors.blueAccent,
                      onTap: _copySelected,
                    ),
                    _ActionBtn(
                      icon: Icons.content_cut_rounded,
                      label: 'Couper',
                      color: Colors.orangeAccent,
                      onTap: _cutSelected,
                    ),
                    if (_clipboard.isNotEmpty)
                      _ActionBtn(
                        icon: Icons.content_paste_rounded,
                        label: 'Coller',
                        color: Colors.greenAccent,
                        onTap: _paste,
                      ),
                    if (selCount == 1)
                      _ActionBtn(
                        icon: Icons.drive_file_rename_outline_rounded,
                        label: 'Renommer',
                        color: Colors.amberAccent,
                        onTap: _renameSelected,
                      ),
                    _ActionBtn(
                      icon: Icons.delete_rounded,
                      label: 'Supprimer',
                      color: Colors.redAccent,
                      onTap: _deleteSelected,
                    ),
                  ],
                ),
            )
          : _clipboard.isNotEmpty
              ? Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2230),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
                  ),
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.of(context).padding.bottom),
                  child: Row(
                      children: [
                        Icon(_clipboardIsCut ? Icons.content_cut_rounded : Icons.copy_rounded,
                            color: Colors.white38, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_clipboard.length} élément(s) ${_clipboardIsCut ? "coupé(s)" : "copié(s)"}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _paste,
                          icon: const Icon(Icons.content_paste_rounded, size: 16),
                          label: const Text('Coller ici'),
                          style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _clipboard.clear()),
                          child: const Text('Annuler', style: TextStyle(color: Colors.white38)),
                        ),
                      ],
                    ),
                )
              : null,
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─── Éditeur de texte ────────────────────────────────────────────────────────

class _TextEditorScreen extends StatefulWidget {
  final String filename;
  final String fullPath;
  final String initialContent;

  const _TextEditorScreen({
    required this.filename,
    required this.fullPath,
    required this.initialContent,
  });

  @override
  State<_TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends State<_TextEditorScreen> {
  late TextEditingController _ctrl;
  bool _saving = false;
  bool _modified = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialContent);
    _ctrl.addListener(() {
      if (!_modified && _ctrl.text != widget.initialContent) {
        setState(() => _modified = true);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final state = context.read<AppState>();
      final escaped = _ctrl.text.replaceAll("'", "'\\''");
      await state.ssh.execute("cat > '${widget.fullPath}' << 'BATOCERA_EOF'\n$escaped\nBATOCERA_EOF");
      setState(() { _modified = false; _saving = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Fichier sauvegardé !', style: TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1C2230),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erreur : $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_modified) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Modifications non sauvegardées'),
        content: const Text('Quitter sans sauvegarder ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitter', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx, false);
              await _save();
              if (mounted) Navigator.of(context).pop();
            },
            child: const Text('Sauvegarder'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return PopScope(
      canPop: !_modified,
      onPopInvoked: (didPop) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && context.mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0C10),
        appBar: AppBar(
          backgroundColor: const Color(0xFF161A22),
          elevation: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.filename,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
              Text(widget.fullPath,
                  style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4)),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
          actions: [
            if (_modified)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('Modifié', style: TextStyle(color: Colors.amberAccent, fontSize: 11)),
                  ),
                ),
              ),
            IconButton(
              icon: _saving
                  ? SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                  : Icon(Icons.save_rounded, color: _modified ? accent : Colors.white38),
              onPressed: _saving || !_modified ? null : _save,
            ),
          ],
        ),
        body: TextField(
          controller: _ctrl,
          maxLines: null,
          expands: true,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Colors.white70, height: 1.6),
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.all(16),
          ),
          keyboardType: TextInputType.multiline,
          autocorrect: false,
          enableSuggestions: false,
        ),
      ),
    );
  }
}

class _FileListTile extends StatelessWidget {
  final _FileItem item;
  final bool isSelected;
  final bool selectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final IconData Function(String) iconForFile;
  final Color Function(String) colorForFile;
  final bool isOpenable;
  final bool isEditable;
  final bool isDownloading;
  final Color accent;

  const _FileListTile({
    required this.item,
    required this.isSelected,
    required this.selectionMode,
    required this.onTap,
    required this.onLongPress,
    required this.iconForFile,
    required this.colorForFile,
    required this.isOpenable,
    required this.isEditable,
    required this.isDownloading,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? accent.withOpacity(0.12)
            : const Color(0xFF1C2230),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? accent.withOpacity(0.5) : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: selectionMode
                    ? Container(
                        key: const ValueKey('checkbox'),
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: isSelected ? accent : Colors.white.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: isSelected ? accent : Colors.white24,
                            width: 1.5,
                          ),
                        ),
                        child: isSelected
                            ? Icon(Icons.check_rounded, color: Colors.white, size: 20)
                            : null,
                      )
                    : Container(
                        key: const ValueKey('icon'),
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: item.isDir
                              ? accent.withOpacity(0.1)
                              : colorForFile(item.name).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: isDownloading
                            ? Padding(
                                padding: const EdgeInsets.all(8),
                                child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                              )
                            : Icon(
                                item.isDir ? Icons.folder_rounded : iconForFile(item.name),
                                color: item.isDir ? accent : colorForFile(item.name),
                                size: 20,
                              ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      item.isDir ? 'Dossier • ${item.date}' : '${item.size} • ${item.date}',
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (!selectionMode) ...[
                if (item.isDir)
                  const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 18)
                else if (isEditable)
                  Icon(Icons.edit_rounded, color: Colors.amberAccent.withOpacity(0.5), size: 16)
                else if (isOpenable)
                  Icon(Icons.open_in_new_rounded, color: accent.withOpacity(0.5), size: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FileItem {
  final String name;
  final String fullPath;
  final bool isDir;
  final String size;
  final String date;

  const _FileItem({
    required this.name, required this.fullPath,
    required this.isDir, required this.size, required this.date,
  });

  static _FileItem? parse(String line, String parent) {
    try {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 7) return null;
      final perms = parts[0];
      if (perms == 'total') return null;
      final isDir = perms.startsWith('d');
      final isLink = perms.startsWith('l');
      int dateIdx = -1;
      for (int i = 0; i < parts.length; i++) {
        if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(parts[i])) { dateIdx = i; break; }
      }
      if (dateIdx == -1 || dateIdx + 1 >= parts.length) return null;
      final date = parts[dateIdx];
      final size = _formatSize(int.tryParse(parts[dateIdx - 1]) ?? 0);
      final namePart = parts.sublist(dateIdx + 1).join(' ');
      final name = isLink && namePart.contains(' -> ') ? namePart.split(' -> ').first : namePart;
      if (name.isEmpty || name == '.' || name == '..') return null;
      return _FileItem(name: name, fullPath: '$parent/$name', isDir: isDir || isLink, size: size, date: date);
    } catch (_) { return null; }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

// ─── PDF Viewer ───────────────────────────────────────────────────────────────

class _FmPdfViewer extends StatefulWidget {
  final String filePath;
  final String title;
  const _FmPdfViewer({required this.filePath, required this.title});

  @override
  State<_FmPdfViewer> createState() => _FmPdfViewerState();
}

class _FmPdfViewerState extends State<_FmPdfViewer> {
  int _total = 0;
  int _current = 0;
  bool _ready = false;
  PDFViewController? _ctrl;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161A22),
        elevation: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          if (_total > 0) Text('Page ${_current + 1} / $_total', style: const TextStyle(fontSize: 11, color: Colors.white38)),
        ]),
        actions: [
          if (_total > 1) ...[
            IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, size: 18, color: Colors.white54),
                onPressed: _current > 0 ? () => _ctrl?.setPage(_current - 1) : null),
            IconButton(icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18, color: Colors.white54),
                onPressed: _current < _total - 1 ? () => _ctrl?.setPage(_current + 1) : null),
          ],
        ],
      ),
      body: Stack(children: [
        PDFView(
          filePath: widget.filePath,
          enableSwipe: true,
          fitPolicy: FitPolicy.BOTH,
          onRender: (p) => setState(() { _total = p ?? 0; _ready = true; }),
          onPageChanged: (p, t) => setState(() { _current = p ?? 0; _total = t ?? 0; }),
          onViewCreated: (c) => _ctrl = c,
        ),
        if (!_ready) Center(child: CircularProgressIndicator(color: accent)),
      ]),
    );
  }
}

// ─── Video Player ─────────────────────────────────────────────────────────────

class _FmVideoPlayer extends StatefulWidget {
  final String? filePath;
  final String? streamUrl;
  final String title;
  final VideoPlayerController? preloadedController;
  const _FmVideoPlayer({this.filePath, this.streamUrl, required this.title, this.preloadedController});

  @override
  State<_FmVideoPlayer> createState() => _FmVideoPlayerState();
}

class _FmVideoPlayerState extends State<_FmVideoPlayer> {
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
      _controller = (widget.streamUrl != null
          ? VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl!))
          : VideoPlayerController.file(File(widget.filePath!)))
        ..initialize().then((_) {
          if (mounted) { setState(() => _initialized = true); _controller.play(); }
        });
    }
    _controller.setLooping(false);
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
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
