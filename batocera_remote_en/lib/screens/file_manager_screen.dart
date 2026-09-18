import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../widgets/back_handler.dart';
import '../widgets/in_app_file_picker.dart';

/// Thrown from a transfer's (download or upload) `onProgress` callback to
/// interrupt it immediately (as soon as the next packet arrives) when the
/// user cancels, without waiting for the current file to finish.
class _TransferCancelledException implements Exception {
  const _TransferCancelledException();
}

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
  double? _downloadProgress; // 0.0 à 1.0, null = indéterminé
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
  static const _audioExts = ['mp3', 'wav', 'ogg', 'flac', 'm4a', 'opus', 'aac'];
  static const _pdfExts = ['pdf'];
  static const _textExts = ['txt', 'cfg', 'conf', 'ini', 'log', 'sh', 'xml', 'json', 'yaml', 'yml', 'md'];
  static const _editableExts = ['txt', 'cfg', 'conf', 'ini', 'log', 'sh', 'xml', 'json', 'yaml', 'yml', 'md'];

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
      Navigator.maybePop(context);
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
  bool _isAudio(String name) => _audioExts.contains(_ext(name));
  bool _isText(String name) => _textExts.contains(_ext(name));
  bool _isEditable(String name) => _editableExts.contains(_ext(name));
  bool _isOpenable(String name) => _isImage(name) || _isVideo(name) || _isAudio(name) || _isText(name);

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
      setState(() { _error = 'Error: $e'; _loading = false; });
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
    Navigator.maybePop(context);
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
    _showSnack('${_clipboard.length} item(s) copied');
  }

  void _cutSelected() {
    _clipboard = List.from(_selectedItems);
    _clipboardIsCut = true;
    setState(() => _selected.clear());
    _showSnack('${_clipboard.length} item(s) cut');
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
    _showSnack('$success item(s) pasted');
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
        title: const Text('Rename'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'New name',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onSubmitted: (v) => Navigator.of(ctx, rootNavigator: true).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(null),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(ctrl.text.trim()),
            child: const Text('Rename'),
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

  /// Recursively lists every file in a remote folder, with its size, in a
  /// SINGLE SSH command (one network round-trip, even if the folder has
  /// many subfolders).
  ///
  /// Uses `find ... -exec stat -c "%s %n" {} \;` rather than
  /// `find -printf`: BusyBox (used on Batocera) doesn't support `-printf`
  /// (a GNU extension), but `-exec` + `stat -c` are already used elsewhere
  /// in the app and work on both.
  ///
  /// The command's output is wrapped between two unique markers: on some
  /// configs, Batocera's shell can return its system banner (CPU/RAM/
  /// features...) mixed into the command's stdout, and each banner line
  /// would otherwise be wrongly parsed as a "file" below. Keeping only what
  /// is strictly between the two markers eliminates that noise, whatever
  /// its exact source.
  ///
  /// Returns a list of (path relative to the folder, size in bytes).
  Future<List<MapEntry<String, int>>> _listFolderRecursive(String folderPath) async {
    final state = context.read<AppState>();
    final marker = 'FOCLABROC_FIND_${DateTime.now().microsecondsSinceEpoch}';
    final cmd = 'echo $marker; '
        'find "$folderPath" -type f -exec stat -c "%s %n" {} \\; 2>/dev/null; '
        'echo ${marker}_END';
    final out = await state.ssh.execute(cmd);

    // Strictly isolate what's between the two markers.
    final startIdx = out.indexOf(marker);
    final endIdx = out.indexOf('${marker}_END');
    if (startIdx < 0 || endIdx < 0 || endIdx <= startIdx) return const [];
    final body = out.substring(startIdx + marker.length, endIdx);

    final prefix = folderPath.endsWith('/') ? folderPath : '$folderPath/';
    final result = <MapEntry<String, int>>[];
    for (final rawLine in body.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final spaceIdx = line.indexOf(' ');
      if (spaceIdx < 0) continue;
      // Extra safety net: a valid line always starts with a number (the
      // size). Any line that doesn't match this format is skipped instead
      // of producing a bogus "file" with an absurd name.
      final size = int.tryParse(line.substring(0, spaceIdx));
      if (size == null) continue;
      final fullPath = line.substring(spaceIdx + 1);
      final rel = fullPath.startsWith(prefix)
          ? fullPath.substring(prefix.length)
          : fullPath.split('/').last;
      if (rel.isNotEmpty) result.add(MapEntry(rel, size));
    }
    return result;
  }

  Future<void> _downloadSelected() async {
    if (_selected.isEmpty) return;
    final state = context.read<AppState>();
    final selectedFiles = _items.where((it) => _selected.contains(it.fullPath) && !it.isDir).toList();
    final selectedFolders = _items.where((it) => _selected.contains(it.fullPath) && it.isDir).toList();
    if (selectedFiles.isEmpty && selectedFolders.isEmpty) {
      _showSnack('Select at least one file or folder');
      return;
    }

    // Unified queue: files selected directly + files found recursively in
    // selected folders. `size` = 0 for direct files (fetched on the fly
    // during download, as before); already known for folder files (via the
    // grouped stat).
    final queue = <({String remotePath, String localRelPath, int size})>[];
    for (final f in selectedFiles) {
      queue.add((remotePath: f.fullPath, localRelPath: f.name, size: 0));
    }

    // Selected folders: recursive listing BEFORE starting anything, so we
    // can show a summary and ask for confirmation (only in this case — a
    // plain file download stays immediate, no extra step, as before).
    if (selectedFolders.isNotEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        useRootNavigator: true,
        builder: (_) => const Center(child: Card(
          child: Padding(padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: Colors.purpleAccent),
              SizedBox(height: 16),
              Text('Scanning folder...', style: TextStyle(color: Colors.white70)),
            ]),
          ),
        )),
      );

      for (final folder in selectedFolders) {
        try {
          final entries = await _listFolderRecursive(folder.fullPath);
          for (final e in entries) {
            queue.add((
              remotePath: '${folder.fullPath}/${e.key}',
              localRelPath: '${folder.name}/${e.key}',
              size: e.value,
            ));
          }
        } catch (_) {
          // An unreadable folder doesn't block the others
        }
      }

      if (mounted) Navigator.of(context, rootNavigator: true).pop(); // close "Scanning..."
      if (!mounted) return;

      final folderFilesCount = queue.length - selectedFiles.length;
      final totalBytes = queue.fold<int>(0, (a, e) => a + e.size);
      final proceed = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.folder_zip_rounded, color: Colors.purpleAccent, size: 22),
            SizedBox(width: 8),
            Text('Download folder(s)?', style: TextStyle(fontSize: 15)),
          ]),
          content: Text(
            '${selectedFolders.length} folder${selectedFolders.length > 1 ? "s" : ""} · '
            '$folderFilesCount file${folderFilesCount > 1 ? "s" : ""}'
            '${selectedFiles.isNotEmpty ? " + ${selectedFiles.length} file(s) selected" : ""}\n'
            'Estimated total size: ${_FileItem._formatSize(totalBytes)}',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('Download'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) return;
    }

    const downloadsPath = '/storage/emulated/0/Download';
    final downloadsDir = Directory(downloadsPath);
    if (!await downloadsDir.exists()) await downloadsDir.create(recursive: true);

    // Before downloading anything, note which top-level folders (one per
    // selected source folder) don't exist yet on the phone. If the
    // operation is cancelled, those can be deleted entirely (recursively)
    // without any risk of erasing files that were already there before
    // this operation — a safety net on top of the per-file deletion, in
    // case that alone isn't enough (e.g. access restrictions depending on
    // the Android version).
    final freshTopFolders = <String>{};
    for (final folder in selectedFolders) {
      final topDir = Directory('$downloadsPath/${folder.name}');
      if (!await topDir.exists()) freshTopFolders.add(topDir.path);
    }

    // Progress variables shared with the dialog.
    // fileProgress = progress of the current file (0..1)
    // globalProgress = progress across the whole queue (0..1), based on the
    // current file's index + its progress fraction — stays meaningful even
    // when a file's size isn't known in advance (files selected directly,
    // not from a folder).
    double fileProgress = 0.0;
    double globalProgress = 0.0;
    String currentName = queue.isNotEmpty ? queue.first.localRelPath : '';
    int currentIdx = 1;
    // Becomes true as soon as the user confirms cancellation. Checked in
    // onProgress to interrupt the current transfer on the next packet
    // received, without waiting for the file to finish.
    bool cancelled = false;

    // Reference to the DIALOG's own setState (not the main screen's). The
    // dialog lives in a separate route/overlay: calling
    // _FileManagerScreenState's setState does NOT refresh it, which is why
    // the progress bar used to stay stuck on "1" throughout the download.
    StateSetter? dialogSetState;

    /// Asks for confirmation before cancelling (potentially long transfer,
    /// better to avoid an accidental tap).
    Future<void> requestCancel() async {
      final confirm = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
            SizedBox(width: 8),
            Text('Cancel download?', style: TextStyle(fontSize: 15)),
          ]),
          content: const Text(
            'The current transfer will be interrupted and the files already '
            'downloaded during this operation will be deleted.',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
              child: const Text('Keep downloading'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        cancelled = true;
        if (mounted) dialogSetState?.call(() {});
      }
    }

    // Progress dialog: a bar for the current file + a global bar for the
    // whole queue below it.
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          dialogSetState = setDlgState;
          return AlertDialog(
            backgroundColor: const Color(0xFF1C2230),
            // Fixed width: prevents the box from resizing during the
            // transfer (the filename or the % text could otherwise change
            // the content's natural width).
            content: SizedBox(
              width: 280,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.download_rounded, color: Colors.purpleAccent, size: 32),
                const SizedBox(height: 12),
                Text(
                  cancelled
                      ? 'Cancelling...'
                      : (queue.length > 1 ? 'File $currentIdx/${queue.length}' : 'Downloading...'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(currentName,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: fileProgress > 0 ? fileProgress : null,
                  color: Colors.purpleAccent,
                  backgroundColor: Colors.purple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
                // Always shown (never conditionally hidden): showing/hiding
                // this text based on fileProgress used to change the
                // dialog's height on every file → a flicker effect.
                const SizedBox(height: 4),
                Text('${(fileProgress * 100).toInt()}%',
                  style: const TextStyle(color: Colors.purpleAccent, fontSize: 11)),
                // Global bar: only useful when there's more than one file
                // (otherwise it would duplicate the single file's bar).
                // `queue.length` never changes during the dialog's
                // lifetime, so this condition never causes flicker.
                if (queue.length > 1) ...[
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Overall progress',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: globalProgress,
                    color: Colors.greenAccent,
                    backgroundColor: Colors.greenAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 4),
                  Text('${(globalProgress * 100).toInt()}%',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
                ],
              ]),
            ),
            actions: [
              TextButton(
                onPressed: cancelled ? null : requestCancel,
                child: Text('Cancel',
                  style: TextStyle(color: cancelled ? Colors.white24 : Colors.redAccent)),
              ),
            ],
          );
        },
      ),
    );

    final saved = <String>[];
    final failed = <String>[];
    // Folders created during THIS download (for cleanup if cancelled) and
    // the path of the file currently being written (to delete the partial
    // one if there is one at the moment of cancellation).
    final createdDirs = <String>{};
    String? partialFilePath;

    for (int idx = 0; idx < queue.length; idx++) {
      if (cancelled) break;
      final entry = queue[idx];
      currentName = entry.localRelPath;
      currentIdx = idx + 1;
      fileProgress = 0.0;
      globalProgress = idx / queue.length;
      // Refreshes the dialog for the current file's name/index (the
      // refresh during the transfer itself happens further below, in
      // onProgress).
      if (mounted) dialogSetState?.call(() {});

      try {
        // Size already known for files coming from a folder (grouped stat
        // during the scan); otherwise fetched on the fly as before.
        int totalSize = entry.size;
        if (totalSize == 0) {
          final sizeStr = await state.ssh.execute('stat -c%s "${entry.remotePath}" 2>/dev/null');
          totalSize = int.tryParse(sizeStr.trim()) ?? 0;
        }

        final destFile = File('$downloadsPath/${entry.localRelPath}');
        partialFilePath = destFile.path;
        // Recreates the local folder structure (subfolders) before writing.
        final destDir = destFile.parent;
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }
        createdDirs.add(destDir.path);

        await state.ssh.downloadFileToDisk(
          entry.remotePath,
          destFile.path,
          onProgress: totalSize > 0 ? (bytes) {
            // Checked on every packet received: interrupts the transfer as
            // soon as possible after cancellation is confirmed, without
            // waiting for the file to finish.
            if (cancelled) throw const _TransferCancelledException();
            fileProgress = (bytes / totalSize).clamp(0.0, 1.0);
            globalProgress = ((idx + fileProgress) / queue.length).clamp(0.0, 1.0);
            if (mounted) dialogSetState?.call(() {});
          } : null,
        );
        saved.add(entry.localRelPath);
        partialFilePath = null; // this file is complete, no longer "partial"
      } on _TransferCancelledException {
        break;
      } catch (e) {
        // Failures are accumulated instead of one snackbar per file: with
        // many files (recursive folder), several snackbars would chain/
        // overwrite each other too fast to be readable. A single summary
        // is shown at the end.
        failed.add(entry.localRelPath);
      }
    }

    // ── Cancellation: full rollback (already-downloaded files + partial
    // file deleted, empty subfolders created during the operation cleaned
    // up) ──────────────────────────────────────────────────────────────
    if (cancelled) {
      // File being written at the moment of cancellation.
      if (partialFilePath != null) {
        try { await File(partialFilePath).delete(); } catch (_) {}
      }
      // Files already completed successfully during this operation.
      for (final rel in saved) {
        try { await File('$downloadsPath/$rel').delete(); } catch (_) {}
      }
      // Subfolders created during this operation: best-effort deletion from
      // deepest to shallowest, only if they're now empty
      // (Directory.delete() without recursive fails otherwise, which is
      // the intended behavior — we never delete a folder that would still
      // contain something).
      final sortedDirs = createdDirs.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final dir in sortedDirs) {
        try { await Directory(dir).delete(); } catch (_) {}
      }
      // Safety net: if the top-level folder (one per selected source
      // folder) did NOT exist before this operation, delete it entirely
      // and recursively, no matter what's left inside it. This guarantees
      // full cleanup even if the per-file deletion above failed for some
      // items (e.g. access restriction depending on the Android version)
      // — safely, since we know it didn't exist before: all of its content
      // necessarily comes from this operation.
      for (final topDir in freshTopFolders) {
        try { await Directory(topDir).delete(recursive: true); } catch (_) {}
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() { _downloading = null; _downloadProgress = null; _selected.clear(); });
        _showSnack('Download cancelled', isError: true);
      }
      return;
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      // Clear the selection: the transfer is done, keeping folders/files
      // checked no longer makes sense (consistent with other actions —
      // deletion, etc. — which also exit selection mode when finished).
      setState(() { _downloading = null; _downloadProgress = null; _selected.clear(); });
      final parts = <String>[];
      if (saved.isNotEmpty) {
        parts.add(saved.length == 1
            ? '${saved.first} downloaded'
            : '${saved.length} files downloaded');
      }
      if (failed.isNotEmpty) {
        parts.add('${failed.length} failed');
      }
      if (parts.isNotEmpty) {
        _showSnack(
          '${parts.join(' · ')} to Downloads',
          isError: saved.isEmpty && failed.isNotEmpty,
        );
      }
    }
  }


  Future<void> _deleteSelected() async {
    final count = _selectedItems.length;
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Delete?'),
        content: Text('Delete $count item(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
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
    // Open the in-app file picker directly (multi-select via long-press).
    final results = await Navigator.of(context, rootNavigator: true).push<List<InAppFilePickerResult>>(
      MaterialPageRoute(
        builder: (_) => const InAppFilePicker(allowMultiple: true),
        fullscreenDialog: true,
      ),
    );
    if (results == null || results.isEmpty || !mounted) return;
    final files = results.map((r) => (
      path: r.localPath,
      name: r.localPath.split('/').last,
    )).toList();

    final state = context.read<AppState>();
    int success = 0;
    final total = files.length;

    setState(() {
      _uploading = true;
      _uploadProgress = 0.0;
      _uploadTotalFiles = total;
      _uploadCurrentFile = 0;
    });

    try {
      for (int i = 0; i < files.length; i++) {
        final file = files[i];
        setState(() {
          _uploadCurrentFile = i + 1;
          _uploadingFileName = file.name;
          _uploadProgress = 0.0;
        });

        // Try the upload up to 2 times: if the 1st attempt fails (typically
        // SSH timeout after the user kept the app in background while
        // picking files), trigger a silent reconnect then retry.
        bool uploaded = false;
        for (int attempt = 0; attempt < 2 && !uploaded; attempt++) {
          if (attempt > 0) {
            // Before retrying: make sure the SSH connection is alive
            final ok = await state.ensureConnected();
            if (!ok) break; // reconnect failed, give up on this file
            if (mounted) setState(() => _uploadProgress = 0.0);
          }
          try {
            await state.ssh.uploadFileFromPath(
              file.path,
              '$_currentPath/${file.name}',
              onProgress: (sent, fileTotal) {
                if (mounted) {
                  setState(() => _uploadProgress = fileTotal > 0 ? sent / fileTotal : 0.0);
                }
              },
            );
            uploaded = true;
          } catch (_) {
            // 1st attempt failed → loop to reconnect and retry
          }
        }
        if (uploaded) success++;
      }
    } finally {
      _resetUploadState();
    }
    await _loadDir(_currentPath);
    _showSnack('$success file(s) uploaded!');
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

  /// Uploads a whole folder from the phone to Batocera, with a confirmation
  /// summary, double progress bar (file + global), a Cancel button and full
  /// rollback if cancelled — same logic as the folder download
  /// (_downloadSelected), for the reverse direction.
  Future<void> _uploadFolder() async {
    // 1) Pick a LOCAL folder via the in-app picker's dedicated mode.
    final folderResult = await Navigator.of(context, rootNavigator: true).push<InAppFolderPickerResult>(
      MaterialPageRoute(
        builder: (_) => const InAppFilePicker(pickFolderMode: true),
        fullscreenDialog: true,
      ),
    );
    if (folderResult == null || !mounted) return;

    // 2) Recursively list every LOCAL file in the chosen folder. The
    //    phone's own filesystem directly via dart:io — no SSH here.
    //    Uses FileSystemEntity.typeSync (not `entity is File`): just like
    //    the picker itself, `is File`/`is Directory` can be wrong on
    //    Android because of symlinks.
    final localFiles = <({String localPath, String relPath, int size})>[];
    try {
      final localDir = Directory(folderResult.path);
      await for (final entity in localDir.list(recursive: true, followLinks: false)) {
        FileSystemEntityType type;
        try {
          type = FileSystemEntity.typeSync(entity.path, followLinks: true);
        } catch (_) {
          continue;
        }
        if (type != FileSystemEntityType.file) continue;
        final rel = entity.path.substring(folderResult.path.length + 1);
        int size = 0;
        try { size = await File(entity.path).length(); } catch (_) {}
        localFiles.add((localPath: entity.path, relPath: rel, size: size));
      }
    } catch (e) {
      if (mounted) _showSnack('Error reading folder: $e', isError: true);
      return;
    }
    if (localFiles.isEmpty) {
      if (mounted) _showSnack('Empty folder');
      return;
    }
    if (!mounted) return;

    // 3) Summary + confirmation before starting anything.
    final totalBytes = localFiles.fold<int>(0, (a, f) => a + f.size);
    final proceed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.drive_folder_upload_rounded, color: Colors.purpleAccent, size: 22),
          SizedBox(width: 8),
          Text('Upload folder?', style: TextStyle(fontSize: 15)),
        ]),
        content: Text(
          '${folderResult.name}\n'
          '${localFiles.length} file${localFiles.length > 1 ? "s" : ""} · '
          'Estimated total size: ${_FileItem._formatSize(totalBytes)}',
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            icon: const Icon(Icons.upload_rounded, size: 16),
            label: const Text('Upload'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final state = context.read<AppState>();
    final remoteBase = '$_currentPath/${folderResult.name}';

    // Checks BEFORE any upload whether the destination folder already
    // exists on Batocera — if it doesn't, it can be deleted entirely as a
    // safety net if the operation is cancelled (like freshTopFolders for
    // download, but on the remote side).
    bool remoteTopExisted = false;
    try {
      final checkOut = await state.ssh.execute('[ -d "$remoteBase" ] && echo 1 || echo 0');
      remoteTopExisted = checkOut.trim() == '1';
    } catch (_) {}
    if (!mounted) return;

    // Progress variables shared with the dialog (see _downloadSelected for
    // the role of each one).
    double fileProgress = 0.0;
    double globalProgress = 0.0;
    String currentName = localFiles.first.relPath;
    int currentIdx = 1;
    bool cancelled = false;
    StateSetter? dialogSetState;

    Future<void> requestCancel() async {
      final confirm = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
            SizedBox(width: 8),
            Text('Cancel upload?', style: TextStyle(fontSize: 15)),
          ]),
          content: const Text(
            'The current transfer will be interrupted and the files already '
            'uploaded during this operation will be deleted on Batocera.',
            style: TextStyle(fontSize: 13, color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
              child: const Text('Keep uploading'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      if (confirm == true) {
        cancelled = true;
        if (mounted) dialogSetState?.call(() {});
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) {
          dialogSetState = setDlgState;
          return AlertDialog(
            backgroundColor: const Color(0xFF1C2230),
            content: SizedBox(
              width: 280,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.drive_folder_upload_rounded, color: Colors.purpleAccent, size: 32),
                const SizedBox(height: 12),
                Text(
                  cancelled
                      ? 'Cancelling...'
                      : (localFiles.length > 1 ? 'File $currentIdx/${localFiles.length}' : 'Uploading...'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(currentName,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: fileProgress > 0 ? fileProgress : null,
                  color: Colors.purpleAccent,
                  backgroundColor: Colors.purple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
                const SizedBox(height: 4),
                Text('${(fileProgress * 100).toInt()}%',
                  style: const TextStyle(color: Colors.purpleAccent, fontSize: 11)),
                if (localFiles.length > 1) ...[
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Overall progress',
                      style: TextStyle(color: Colors.white38, fontSize: 11)),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: globalProgress,
                    color: Colors.greenAccent,
                    backgroundColor: Colors.greenAccent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    minHeight: 8,
                  ),
                  const SizedBox(height: 4),
                  Text('${(globalProgress * 100).toInt()}%',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 11)),
                ],
              ]),
            ),
            actions: [
              TextButton(
                onPressed: cancelled ? null : requestCancel,
                child: Text('Cancel',
                  style: TextStyle(color: cancelled ? Colors.white24 : Colors.redAccent)),
              ),
            ],
          );
        },
      ),
    );

    final saved = <String>[]; // relative paths uploaded successfully
    final failed = <String>[];
    final createdRemoteDirs = <String>{};
    String? partialRemotePath;

    for (int idx = 0; idx < localFiles.length; idx++) {
      if (cancelled) break;
      final f = localFiles[idx];
      currentName = f.relPath;
      currentIdx = idx + 1;
      fileProgress = 0.0;
      globalProgress = idx / localFiles.length;
      if (mounted) dialogSetState?.call(() {});

      try {
        final remotePath = '$remoteBase/${f.relPath}';
        partialRemotePath = remotePath;
        final lastSlash = remotePath.lastIndexOf('/');
        final remoteDir = lastSlash > 0 ? remotePath.substring(0, lastSlash) : remoteBase;
        if (!createdRemoteDirs.contains(remoteDir)) {
          await state.ssh.execute('mkdir -p "$remoteDir"');
          createdRemoteDirs.add(remoteDir);
        }

        await state.ssh.uploadFileFromPath(
          f.localPath,
          remotePath,
          onProgress: (sent, fileTotal) {
            // Checked on every packet sent: interrupts the transfer as
            // soon as possible after cancellation is confirmed.
            if (cancelled) throw const _TransferCancelledException();
            fileProgress = fileTotal > 0 ? (sent / fileTotal).clamp(0.0, 1.0) : 0.0;
            globalProgress = ((idx + fileProgress) / localFiles.length).clamp(0.0, 1.0);
            if (mounted) dialogSetState?.call(() {});
          },
        );
        saved.add(f.relPath);
        partialRemotePath = null; // this file is complete
      } on _TransferCancelledException {
        break;
      } catch (e) {
        // Failures are accumulated instead of one snackbar per file (same
        // reasoning as for download).
        failed.add(f.relPath);
      }
    }

    // ── Cancellation: full rollback on BATOCERA's side (already-uploaded
    // files + partial file deleted via SSH, empty remote folders created
    // during the operation cleaned up) ──────────────────────────────────
    if (cancelled) {
      if (partialRemotePath != null) {
        try { await state.ssh.execute('rm -f "$partialRemotePath"'); } catch (_) {}
      }
      for (final rel in saved) {
        try { await state.ssh.execute('rm -f "$remoteBase/$rel"'); } catch (_) {}
      }
      // Remote folders created during this operation: best-effort deletion
      // from deepest to shallowest — `rmdir` (without -r) fails silently
      // if the folder still contains something, which is the intended
      // behavior.
      final sortedDirs = createdRemoteDirs.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final dir in sortedDirs) {
        try { await state.ssh.execute('rmdir "$dir" 2>/dev/null'); } catch (_) {}
      }
      // Safety net: if the top-level destination folder did NOT exist
      // before this operation, delete it entirely and recursively on
      // Batocera, no matter what's left inside it — safely, since we know
      // it didn't exist before.
      if (!remoteTopExisted) {
        try { await state.ssh.execute('rm -rf "$remoteBase"'); } catch (_) {}
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _showSnack('Upload cancelled', isError: true);
      }
      await _loadDir(_currentPath);
      return;
    }

    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      final parts = <String>[];
      if (saved.isNotEmpty) {
        parts.add(saved.length == 1
            ? '${saved.first} uploaded'
            : '${saved.length} files uploaded');
      }
      if (failed.isNotEmpty) {
        parts.add('${failed.length} failed');
      }
      if (parts.isNotEmpty) {
        _showSnack(
          '${parts.join(' · ')} to Batocera',
          isError: saved.isEmpty && failed.isNotEmpty,
        );
      }
    }
    await _loadDir(_currentPath);
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
              Text('Loading...', style: TextStyle(fontSize: 12, color: Colors.white70)),
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
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _FmVideoPlayer(filePath: localFile.path, title: item.name, preloadedController: controller),
        ));
      } catch (e) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          _showSnack('Error: $e', isError: true);
        }
      }
      return;
    }

    if (_audioExts.contains(ext)) {
      // In-app audio player: we reuse VideoPlayerController which also
      // handles pure audio streams (no need for an audioplayers dependency).
      // The dedicated _FmAudioPlayer UI shows a large icon instead of the
      // video frame.
      showDialog(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (_) => const Center(child: Card(
          child: Padding(padding: EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.music_note_rounded, color: Colors.greenAccent, size: 32),
              SizedBox(height: 16),
              CircularProgressIndicator(color: Colors.greenAccent),
              SizedBox(height: 12),
              Text('Loading...', style: TextStyle(fontSize: 12, color: Colors.white70)),
            ]),
          ),
        )),
      );
      try {
        await state.ssh.downloadFileToDisk(item.fullPath, localFile.path);
        if (!mounted) return;

        final controller = VideoPlayerController.file(localFile);
        await controller.initialize();

        if (!mounted) { controller.dispose(); return; }
        Navigator.of(context, rootNavigator: true).pop();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _FmAudioPlayer(title: item.name, preloadedController: controller),
        ));
      } catch (e) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).pop();
          _showSnack('Error: $e', isError: true);
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
      _showSnack('Error: $e', isError: true);
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
                title: const Text('Edit', style: TextStyle(color: Colors.white70)),
                subtitle: const Text('Built-in editor + save to Batocera',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                onTap: () { Navigator.of(ctx, rootNavigator: true).pop(); _openEditor(item); },
              ),
            if (_isOpenable(item.name) && !_isText(item.name))
              ListTile(
                leading: Icon(
                  _isImage(item.name) ? Icons.image_rounded
                      : _isVideo(item.name) ? Icons.play_circle_rounded
                      : _isAudio(item.name) ? Icons.music_note_rounded
                      : Icons.open_in_new_rounded,
                  color: Colors.greenAccent,
                ),
                title: Text(
                  _isImage(item.name) ? 'View image'
                      : _isVideo(item.name) ? 'Play video'
                      : _isAudio(item.name) ? 'Play audio'
                      : 'Open',
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () { Navigator.of(ctx, rootNavigator: true).pop(); _openFile(item); },
              ),
            if (_isText(item.name))
              ListTile(
                leading: const Icon(Icons.visibility_rounded, color: Colors.blueAccent),
                title: const Text('View content', style: TextStyle(color: Colors.white70)),
                onTap: () { Navigator.of(ctx, rootNavigator: true).pop(); _viewFileInApp(item); },
              ),
            ListTile(
              leading: const Icon(Icons.download_rounded, color: Colors.purpleAccent),
              title: const Text('Download', style: TextStyle(color: Colors.white70)),
              subtitle: const Text('Save to Downloads folder',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () {
                Navigator.of(ctx, rootNavigator: true).pop();
                setState(() { _selected.clear(); _selected.add(item.fullPath); });
                _downloadSelected();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_rounded, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.white70)),
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
      // Known text extensions → read directly without binary check.
      // BusyBox `file` on Batocera may misidentify some text files (e.g. .log).
      final knownText = _isText(item.name) || _isEditable(item.name);
      bool isText = knownText;
      if (!knownText) {
        final fileType = await state.ssh.execute('file "${item.fullPath}" | grep -o text || echo binary');
        isText = fileType.contains('text');
      }
      if (isText) {
        content = await state.ssh.readFile(item.fullPath);
      } else {
        content = '[Binary file — preview not available]';
      }
    } catch (e) { content = 'Error: $e'; }
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
              controller: scrollCtrl, padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
              child: SelectableText(capturedContent.isEmpty ? '(empty file)' : capturedContent,
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
      resizeToAvoidBottomInset: false,
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
                    Text('$selCount selected',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.select_all_rounded, color: Colors.white38, size: 20),
                      onPressed: _selectAll,
                      tooltip: 'Select all',
                    ),
                  ] else ...[
                    Text('Files', style: Theme.of(context).textTheme.headlineMedium),
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
                        : _downloading != null
                          ? SizedBox(
                              width: 160,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'DL: $_downloading',
                                    style: const TextStyle(color: Colors.purpleAccent, fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  LinearProgressIndicator(
                                    value: _downloadProgress,
                                    color: Colors.purpleAccent,
                                    backgroundColor: Colors.purple.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    minHeight: 5,
                                  ),
                                  if (_downloadProgress != null)
                                    Text(
                                      '\${(_downloadProgress! * 100).toInt()}%',
                                      style: const TextStyle(color: Colors.purpleAccent, fontSize: 10),
                                    ),
                                ],
                              ),
                            )
                          : Row(children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text('Loading...',
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
                        tooltip: 'Upload file',
                      ),
                      IconButton(
                        icon: Icon(Icons.drive_folder_upload_rounded, color: Colors.white38, size: 20),
                        onPressed: state.isConnected ? _uploadFolder : null,
                        tooltip: 'Upload folder',
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
                      Text('Not connected', style: Theme.of(context).textTheme.bodyMedium),
                    ]))
                  : _error != null
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: () => _loadDir(_currentPath),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Retry'),
                          ),
                        ]))
                      : _loading && _items.isEmpty
                          ? Center(child: CircularProgressIndicator(color: accent))
                          : _items.isEmpty
                              ? Center(child: Text('Empty folder', style: Theme.of(context).textTheme.bodyMedium))
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
                      label: 'Copy',
                      color: Colors.blueAccent,
                      onTap: _copySelected,
                    ),
                    _ActionBtn(
                      icon: Icons.content_cut_rounded,
                      label: 'Cut',
                      color: Colors.orangeAccent,
                      onTap: _cutSelected,
                    ),
                    if (_clipboard.isNotEmpty)
                      _ActionBtn(
                        icon: Icons.content_paste_rounded,
                        label: 'Paste',
                        color: Colors.greenAccent,
                        onTap: _paste,
                      ),
                    if (selCount == 1)
                      _ActionBtn(
                        icon: Icons.drive_file_rename_outline_rounded,
                        label: 'Rename',
                        color: Colors.amberAccent,
                        onTap: _renameSelected,
                      ),
                    _ActionBtn(
                      icon: Icons.download_rounded,
                      label: 'Download',
                      color: Colors.purpleAccent,
                      onTap: _downloadSelected,
                    ),
                    _ActionBtn(
                      icon: Icons.delete_rounded,
                      label: 'Delete',
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
                            '${_clipboard.length} item(s) ${_clipboardIsCut ? "cut" : "copied"}',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _paste,
                          icon: const Icon(Icons.content_paste_rounded, size: 16),
                          label: const Text('Paste here'),
                          style: TextButton.styleFrom(foregroundColor: Colors.greenAccent),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _clipboard.clear()),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
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
          content: const Text('File saved!', style: TextStyle(color: Colors.white)),
          backgroundColor: const Color(0xFF1C2230),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e', style: const TextStyle(color: Colors.white)),
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
        title: const Text('Unsaved changes'),
        content: const Text('Quit without saving?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quit', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx, false);
              await _save();
              if (mounted) Navigator.maybePop(context);
            },
            child: const Text('Save'),
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
          if (shouldPop && context.mounted) Navigator.maybePop(context);
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
                    child: const Text('Modified', style: TextStyle(color: Colors.amberAccent, fontSize: 11)),
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
        body: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
          child: TextField(
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
                      item.isDir ? 'Folder • ${item.date}' : '${item.size} • ${item.date}',
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
  @override
  void initState() {
    super.initState();
    if (widget.preloadedController != null) {
      _controller = widget.preloadedController!;
      _controller.play();
    } else {
      _controller = (widget.streamUrl != null
          ? VideoPlayerController.networkUrl(Uri.parse(widget.streamUrl!))
          : VideoPlayerController.file(File(widget.filePath!)))
        ..initialize().then((_) {
          if (mounted) { setState(() {}); _controller.play(); }
        });
    }
    _controller.setLooping(false);
    // Listener pour rebuild quand isInitialized change
    _controller.addListener(() { if (mounted) setState(() {}); });
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
      body: _controller.value.isInitialized
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
// ─── Audio Player ─────────────────────────────────────────────────────────────

class _FmAudioPlayer extends StatefulWidget {
  final String title;
  final VideoPlayerController preloadedController;
  const _FmAudioPlayer({required this.title, required this.preloadedController});
  @override
  State<_FmAudioPlayer> createState() => _FmAudioPlayerState();
}

class _FmAudioPlayerState extends State<_FmAudioPlayer> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.preloadedController;
    _controller.setLooping(false);
    _controller.play();
    _controller.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    final position = value.position;
    final duration = value.duration;
    final accent = Theme.of(context).colorScheme.primary;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161A22),
        elevation: 0,
        title: Text(widget.title,
            style: const TextStyle(fontSize: 14),
            overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Column(children: [
          // Large central "cover" (music note icon) + filename
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C2230),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.greenAccent.withOpacity(0.15),
                          blurRadius: 30,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.music_note_rounded,
                      color: Colors.greenAccent,
                      size: 100,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Interactive progress slider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: accent,
                inactiveTrackColor: Colors.white12,
                thumbColor: accent,
                overlayColor: accent.withOpacity(0.2),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: (v) {
                  if (duration.inMilliseconds > 0) {
                    _controller.seekTo(Duration(
                      milliseconds: (v * duration.inMilliseconds).toInt(),
                    ));
                  }
                },
              ),
            ),
          ),
          // Position / total duration
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_fmtDuration(position),
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
                Text(_fmtDuration(duration),
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Controls: -10s / play-pause / +10s
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white70, size: 32),
                onPressed: () {
                  final newPos = position - const Duration(seconds: 10);
                  _controller.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
                },
              ),
              const SizedBox(width: 16),
              IconButton(
                iconSize: 56,
                icon: Icon(
                  value.isPlaying ? Icons.pause_circle_rounded : Icons.play_circle_rounded,
                  color: Colors.greenAccent,
                ),
                onPressed: () =>
                    value.isPlaying ? _controller.pause() : _controller.play(),
              ),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white70, size: 32),
                onPressed: () {
                  final newPos = position + const Duration(seconds: 10);
                  _controller.seekTo(newPos > duration ? duration : newPos);
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
