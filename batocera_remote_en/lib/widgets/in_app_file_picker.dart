import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Résultat d'une sélection : chemin local + extension (en minuscules sans
/// le point).
class InAppFilePickerResult {
  final String localPath;
  final String ext;
  const InAppFilePickerResult({required this.localPath, required this.ext});
}

/// Picker de fichiers **interne à l'app** : ne déclenche aucun intent système,
/// donc évite la duplication MIUI dans `Pictures/` (le picker système copie
/// le fichier sélectionné, ce qui peut déclencher l'indexation MediaStore).
///
/// Demande les permissions media (Android 13+) ou storage (< 13) au runtime
/// avant de lister les fichiers.
///
/// Limité aux dossiers standards Android :
/// `Pictures/`, `DCIM/`, `Download/`, `Documents/`, `Movies/`.
///
/// Filtres :
/// - [allowedExtensions] vide ou null = TOUS fichiers acceptés
/// - sinon, filtre sur ces extensions (minuscules, sans le point)
///
/// Mode :
/// - tap simple = sélection unique → retourne 1 résultat
/// - long-press = active le mode multi → tap = toggle, bouton OK (n) en
///   AppBar pour valider → retourne N résultats
class InAppFilePicker extends StatefulWidget {
  /// Extensions acceptées (minuscules, sans le point).
  /// Vide ou null = tous fichiers.
  final Set<String>? allowedExtensions;
  /// Autoriser la multi-sélection (par défaut true).
  /// Si false, le tap ferme directement le picker avec le fichier choisi.
  final bool allowMultiple;

  const InAppFilePicker({
    super.key,
    this.allowedExtensions,
    this.allowMultiple = true,
  });

  @override
  State<InAppFilePicker> createState() => _InAppFilePickerState();
}

/// Raccourcis vers les dossiers Android standards.
class _Shortcut {
  final String label;
  final String path;
  final IconData icon;
  const _Shortcut(this.label, this.path, this.icon);
}

const List<_Shortcut> _shortcuts = [
  _Shortcut('Pictures',  '/storage/emulated/0/Pictures',  Icons.image_rounded),
  _Shortcut('DCIM',      '/storage/emulated/0/DCIM',      Icons.camera_alt_rounded),
  _Shortcut('Downloads', '/storage/emulated/0/Download', Icons.download_rounded),
  _Shortcut('Documents', '/storage/emulated/0/Documents', Icons.description_rounded),
  _Shortcut('Movies',    '/storage/emulated/0/Movies',    Icons.movie_rounded),
];

/// Extensions images (pour décider si afficher une miniature ou une icône).
const Set<String> _imageExts = {'png','jpg','jpeg','webp','gif','bmp'};

/// Mapping extension → icône Material affichée dans la grille.
IconData _iconForExt(String ext) {
  if (_imageExts.contains(ext)) return Icons.image_rounded;
  switch (ext) {
    case 'mp4': case 'mkv': case 'avi': case 'mov': case 'webm':
    case 'm4v': case 'flv': case 'wmv':
      return Icons.movie_rounded;
    case 'mp3': case 'wav': case 'ogg': case 'flac': case 'm4a':
    case 'opus': case 'aac':
      return Icons.audiotrack_rounded;
    case 'zip': case 'rar': case '7z': case 'tar': case 'gz': case 'xz':
    case 'bz2': case 'zst':
      return Icons.archive_rounded;
    case 'pdf':            return Icons.picture_as_pdf_rounded;
    case 'txt': case 'md': case 'log': case 'cfg': case 'ini': case 'conf':
    case 'yml': case 'yaml': case 'json': case 'xml':
      return Icons.description_rounded;
    case 'apk':            return Icons.android_rounded;
    case 'iso': case 'img': case 'bin': case 'cue': case 'chd':
      return Icons.album_rounded;
    case 'sh': case 'bat': case 'py': case 'dart': case 'js':
      return Icons.code_rounded;
  }
  return Icons.insert_drive_file_rounded;
}

/// Entrée du listing : path complet + nom + type (dossier ou fichier).
class _Entry {
  final String path;
  final String name;
  final bool isDir;
  const _Entry({required this.path, required this.name, required this.isDir});
}

/// État de la vérification des permissions.
enum _PermState { checking, granted, denied, permanentlyDenied }

class _InAppFilePickerState extends State<InAppFilePicker> {
  // ── Permissions ──
  _PermState _permState = _PermState.checking;

  // ── Navigation ──
  final List<String> _stack = [];
  List<_Entry> _entries = [];
  bool _loading = false;
  String? _error;

  // ── Multi-sélection ──
  bool _multiMode = false;
  final Set<String> _selected = {};

  String? get _currentPath => _stack.isEmpty ? null : _stack.last;

  @override
  void initState() {
    super.initState();
    _checkAndRequestPermissions();
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Permissions
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _checkAndRequestPermissions() async {
    setState(() => _permState = _PermState.checking);

    bool granted = false;
    bool permanent = false;

    if (Platform.isAndroid) {
      // Essayer d'abord les permissions granulaires (Android 13+ / API 33+).
      // Sur API < 33, ces permissions retournent permanentlyDenied car elles
      // n'existent pas → on fallback sur Permission.storage.
      final mediaStatuses = await [
        Permission.photos,
        Permission.videos,
        Permission.audio,
      ].request();

      final mediaGranted = mediaStatuses.values.every(
        (s) => s.isGranted || s.isLimited,
      );

      if (mediaGranted) {
        granted = true;
      } else {
        // API < 33 ou media refusées : essayer storage classique
        final storageStatus = await Permission.storage.request();
        if (storageStatus.isGranted || storageStatus.isLimited) {
          granted = true;
        } else {
          // Vérifier si l'une des permissions est refusée définitivement
          permanent = mediaStatuses.values.any((s) => s.isPermanentlyDenied) ||
              storageStatus.isPermanentlyDenied;
        }
      }
    } else {
      final status = await Permission.storage.request();
      granted = status.isGranted || status.isLimited;
      permanent = status.isPermanentlyDenied;
    }

    if (!mounted) return;
    if (granted) {
      setState(() => _permState = _PermState.granted);
    } else if (permanent) {
      setState(() => _permState = _PermState.permanentlyDenied);
    } else {
      setState(() => _permState = _PermState.denied);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Filesystem
  // ─────────────────────────────────────────────────────────────────────────

  bool _isAccepted(String name) {
    final allowed = widget.allowedExtensions;
    if (allowed == null || allowed.isEmpty) return true;
    final dot = name.lastIndexOf('.');
    if (dot < 0) return false;
    return allowed.contains(name.substring(dot + 1).toLowerCase());
  }

  Future<void> _enter(String path) async {
    setState(() {
      _stack.add(path);
      _loading = true;
      _error = null;
      _entries = [];
    });
    await _loadCurrentDir();
  }

  Future<void> _loadCurrentDir() async {
    final p = _currentPath;
    if (p == null) return;
    try {
      final dir = Directory(p);
      if (!await dir.exists()) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Folder not found';
        });
        return;
      }
      final list = await dir.list(followLinks: false).toList();
      final filtered = <_Entry>[];
      for (final e in list) {
        final name = e.path.split('/').last;
        if (name.startsWith('.')) continue;
        FileSystemEntityType type;
        try {
          type = FileSystemEntity.typeSync(e.path, followLinks: true);
        } catch (_) {
          continue;
        }
        if (type == FileSystemEntityType.directory) {
          filtered.add(_Entry(path: e.path, name: name, isDir: true));
        } else if (type == FileSystemEntityType.file && _isAccepted(name)) {
          filtered.add(_Entry(path: e.path, name: name, isDir: false));
        }
      }
      filtered.sort((a, b) {
        final aIsDir = a.isDir ? 0 : 1;
        final bIsDir = b.isDir ? 0 : 1;
        if (aIsDir != bIsDir) return aIsDir - bIsDir;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _entries = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Read error : $e';
      });
    }
  }

  void _goBack() {
    if (_multiMode) {
      setState(() {
        _multiMode = false;
        _selected.clear();
      });
      return;
    }
    if (_stack.isEmpty) {
      Navigator.of(context).pop(null);
      return;
    }
    setState(() {
      _stack.removeLast();
      _entries = [];
      _error = null;
    });
    if (_stack.isNotEmpty) _loadCurrentDir();
  }

  InAppFilePickerResult _toResult(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    final ext = (dot > 0 ? name.substring(dot + 1) : '').toLowerCase();
    return InAppFilePickerResult(localPath: path, ext: ext);
  }

  void _selectFileSingle(String path) {
    Navigator.of(context).pop(<InAppFilePickerResult>[_toResult(path)]);
  }

  void _toggleSelect(String path) {
    setState(() {
      if (_selected.contains(path)) {
        _selected.remove(path);
      } else {
        _selected.add(path);
      }
    });
  }

  void _enterMultiMode(String path) {
    if (!widget.allowMultiple) return;
    setState(() {
      _multiMode = true;
      _selected.add(path);
    });
  }

  void _confirmMulti() {
    final results = _selected.map(_toResult).toList();
    Navigator.of(context).pop(results);
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  UI
  // ─────────────────────────────────────────────────────────────────────────

  /// Écran affiché quand les permissions ne sont pas accordées.
  Widget _buildPermissionScreen() {
    final isPermanent = _permState == _PermState.permanentlyDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_off_rounded, color: Colors.white38, size: 64),
            const SizedBox(height: 16),
            Text(
              isPermanent
                  ? 'Permission permanently denied'
                  : 'Permission required',
              style: const TextStyle(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              isPermanent
                  ? 'Open the app settings to allow file access.'
                  : 'The picker needs access to your files to display them.',
              style: const TextStyle(color: Colors.white54, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (isPermanent)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE02020),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.settings_rounded, size: 18),
                label: const Text('Open settings'),
                onPressed: () async {
                  await openAppSettings();
                  // Au retour des paramètres, re-check
                  if (mounted) _checkAndRequestPermissions();
                },
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE02020),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                onPressed: _checkAndRequestPermissions,
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel',
                style: TextStyle(color: Colors.white38),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShortcutsHome() {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _shortcuts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final s = _shortcuts[i];
        return Material(
          color: const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _enter(s.path),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Icon(s.icon, color: const Color(0xFFE02020), size: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.label, style: const TextStyle(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600,
                      )),
                      Text(s.path, style: const TextStyle(
                        color: Colors.white38, fontSize: 11,
                      )),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDirView() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFE02020)));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)));
    }
    if (_entries.isEmpty) {
      return const Center(child: Text(
        'No file in this folder',
        style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
      ));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.85,
      ),
      itemCount: _entries.length,
      itemBuilder: (_, i) {
        final e = _entries[i];
        if (e.isDir) {
          return _buildFolderTile(e);
        } else {
          return _buildFileTile(e);
        }
      },
    );
  }

  Widget _buildFolderTile(_Entry e) {
    return Material(
      color: const Color(0xFF1C2230),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _enter(e.path),
        child: Column(
          children: [
            const Expanded(
              child: Center(
                child: Icon(Icons.folder_rounded, color: Color(0xFFE02020), size: 48),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                e.name,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileTile(_Entry e) {
    final name = e.name;
    final dot = name.lastIndexOf('.');
    final ext = (dot > 0 ? name.substring(dot + 1) : '').toLowerCase();
    final isImage = _imageExts.contains(ext);
    final isSelected = _multiMode && _selected.contains(e.path);

    return Material(
      color: const Color(0xFF1C2230),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          if (_multiMode) {
            _toggleSelect(e.path);
          } else {
            _selectFileSingle(e.path);
          }
        },
        onLongPress: () {
          if (!_multiMode) _enterMultiMode(e.path);
          else _toggleSelect(e.path);
        },
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    child: isImage
                        ? Image.file(
                            File(e.path),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            cacheWidth: 300,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(_iconForExt(ext), color: Colors.white24, size: 40),
                            ),
                          )
                        : Center(
                            child: Icon(_iconForExt(ext), color: Colors.white38, size: 40),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    name,
                    style: const TextStyle(color: Colors.white70, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
            if (isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE02020).withOpacity(0.25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE02020), width: 2),
                  ),
                ),
              ),
            if (isSelected)
              const Positioned(
                top: 4, right: 4,
                child: Icon(Icons.check_circle_rounded, color: Color(0xFFE02020), size: 22),
              ),
          ],
        ),
      ),
    );
  }

  String _buildTitle() {
    if (_multiMode) {
      return '${_selected.length} selected';
    }
    if (_currentPath == null) return 'Choose a file';
    final p = _currentPath!;
    for (final s in _shortcuts) {
      if (p == s.path) return s.label;
      if (p.startsWith('${s.path}/')) {
        final sub = p.substring(s.path.length + 1);
        return '${s.label} / $sub';
      }
    }
    return p.split('/').last;
  }

  /// Contenu principal selon l'état des permissions.
  Widget _buildBody() {
    switch (_permState) {
      case _PermState.checking:
        return const Center(
          child: CircularProgressIndicator(color: Color(0xFFE02020)),
        );
      case _PermState.denied:
      case _PermState.permanentlyDenied:
        return _buildPermissionScreen();
      case _PermState.granted:
        return _stack.isEmpty ? _buildShortcutsHome() : _buildDirView();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_multiMode) { _goBack(); return false; }
        if (_stack.isEmpty) return true;
        _goBack();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0F14),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1C2230),
          elevation: 0,
          leading: IconButton(
            icon: Icon(_multiMode ? Icons.close_rounded : Icons.arrow_back_rounded),
            onPressed: _goBack,
          ),
          title: Text(
            _buildTitle(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            if (_multiMode)
              TextButton.icon(
                onPressed: _selected.isEmpty ? null : _confirmMulti,
                icon: const Icon(Icons.check_rounded, size: 18, color: Color(0xFFE02020)),
                label: Text(
                  'OK (${_selected.length})',
                  style: const TextStyle(color: Color(0xFFE02020), fontSize: 13),
                ),
              )
            else if (_stack.isNotEmpty && _permState == _PermState.granted)
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: _loadCurrentDir,
                tooltip: 'Refresh',
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }
}
