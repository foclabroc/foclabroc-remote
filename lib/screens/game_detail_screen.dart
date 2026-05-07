import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:video_player/video_player.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_state.dart';
import '../services/metadata_service.dart';
import '../widgets/metadata_editor_dialog.dart';
import '../widgets/media_editor_dialog.dart';

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
  bool _imageTried = false;
  bool _thumbTried = false;
  bool _wheelTried = false;

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
          if (mounted) setState(() {
            if (bytes != null) _wheelBytes = bytes;
            _wheelTried = true;
          });
        })
      else
        Future.value(null).then((_) {
          if (mounted) setState(() => _wheelTried = true);
        }),
      if (thumb != null && thumb.isNotEmpty)
        _fetchCached(thumb).then((bytes) {
          if (mounted) setState(() {
            if (bytes != null) _thumbBytes = bytes;
            _thumbTried = true;
          });
        })
      else
        Future.value(null).then((_) {
          if (mounted) setState(() => _thumbTried = true);
        }),
      if (img != null && img.isNotEmpty)
        _fetchCached(img).then((bytes) {
          if (mounted) setState(() {
            if (bytes != null) _imageBytes = bytes;
            _imageTried = true;
          });
        })
      else
        Future.value(null).then((_) {
          if (mounted) setState(() => _imageTried = true);
        }),
    ]);
  }

  /// Invalide le cache disque local des médias de ce jeu puis relance
  /// _loadImages. Les paths dans widget.game sont fiables (mis à jour lors
  /// du save de _editMedia avec les chemins qu'on vient d'uploader nous-
  /// mêmes), inutile de refetch l'API : ça créait des disparitions d'images
  /// quand l'API retournait un JSON où les nouvelles balises n'apparaissent
  /// pas encore (ES pas synchro après reloadEsGamelist).
  Future<void> _refreshImages() async {
    // 1) Efface le cache disque local pour forcer un re-download HTTP.
    try {
      final cacheDir = await getTemporaryDirectory();
      final cacheFolder = Directory('${cacheDir.path}/batocera_img_cache');
      if (await cacheFolder.exists()) {
        final paths = <String?>[
          widget.game['wheel']?.toString(),
          widget.game['marquee']?.toString(),
          widget.game['thumbnail']?.toString(),
          widget.game['image']?.toString(),
        ];
        for (final p in paths) {
          if (p == null || p.isEmpty) continue;
          final key = md5.convert(utf8.encode(p)).toString();
          final f = File('${cacheFolder.path}/$key');
          final mtime = File('${cacheFolder.path}/$key.mtime');
          if (await f.exists()) { try { await f.delete(); } catch (_) {} }
          if (await mtime.exists()) { try { await mtime.delete(); } catch (_) {} }
        }
      }
    } catch (_) {}
    if (!mounted) return;

    // 2) Reset des bytes + relance _loadImages. Pour les paths /userdata/
    //    (post-save de _editMedia), _fetchImage passe en SFTP direct donc
    //    pas besoin d'attendre ES. Pour les paths route API ES (chemins
    //    initiaux du jeu), un retry immédiat suffit dans la grande majorité
    //    des cas.
    setState(() {
      _wheelBytes = null;
      _thumbBytes = null;
      _imageBytes = null;
      _wheelTried = false;
      _thumbTried = false;
      _imageTried = false;
    });
    await _loadImages();
  }

  Future<void> _editMetadata() async {
    final game = widget.game;
    final systemName = game['_systemName']?.toString() ?? '';
    final romPath = game['path']?.toString() ?? '';
    final gameName = game['name']?.toString() ?? '';
    if (systemName.isEmpty || romPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Infos jeu incomplètes'),
        backgroundColor: Color(0xFF1C2230),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final state = context.read<AppState>();
    final svc = MetadataService(state.ssh);

    // 1) Construit les valeurs initiales depuis les données déjà en mémoire (rapide)
    final initial = <String, String>{};
    for (final k in MetadataService.editableTags) {
      final v = game[k]?.toString() ?? '';
      if (v.isNotEmpty) initial[k] = v;
    }

    // 2) Lit le XML pour les balises qu'ES n'expose pas dans son API JSON
    //    (par ex. region). Les valeurs du XML écrasent celles de l'API
    //    car elles sont autoritatives.
    try {
      final fromXml = await svc.readMetadata(systemName, romPath);
      for (final k in MetadataService.editableTags) {
        final v = fromXml[k];
        if (v != null && v.isNotEmpty) initial[k] = v;
      }
    } catch (_) {}
    if (!mounted) return;

    // 3) Ouvre le dialog d'édition
    final changes = await showDialog<Map<String, String>>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => MetadataEditorDialog(
        initialValues: initial,
        gameName: gameName.isNotEmpty ? gameName : romPath.split('/').last,
      ),
    );
    if (changes == null || changes.isEmpty || !mounted) return;

    // 3) Si un jeu tourne, demande confirmation pour le fermer
    final running = await svc.isGameRunning();
    if (!mounted) return;
    if (running) {
      final confirm = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
            SizedBox(width: 8),
            Text('Jeu en cours', style: TextStyle(fontSize: 15)),
          ]),
          content: const Text(
            'Un jeu est en cours.\n'
            'Pour sauvegarder les métadonnées, il faut le fermer.\n\n'
            'Continuer ?',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE02020)),
              child: const Text('Fermer le jeu et sauvegarder'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Fermeture du jeu en cours...', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF1C2230),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ));
      await svc.killRunningGame();
      if (!mounted) return;
    }

    // 4) Backup horodaté du gamelist
    final backupOk = await svc.backupGamelist(systemName);
    if (!mounted) return;

    // 5) Vérifie s'il y a des pending à appliquer ici. Si oui (ou si on a
    //    tué un jeu juste avant), on doit demander à ES de flusher son
    //    état mémoire (playtime/lastplayed/playcount) AVANT d'écrire au
    //    gamelist, sinon ES écraserait nos balises au prochain dump.
    final pendingFiles = await state.pendingService.listPendingFiles();
    if (!mounted) return;
    final hasPending = pendingFiles.isNotEmpty;

    if (running || hasPending) {
      await svc.reloadEsGamelist();
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
    }

    // 6) Applique les pending (sans reload : on en fera un seul en fin)
    int pendingApplied = 0;
    if (hasPending) {
      try {
        pendingApplied = await state.pendingService.applyPendingNoReload();
      } catch (_) {}
      if (!mounted) return;
    }

    // 7) Reload ES d'abord pour qu'il flush les playtime en mémoire sur disque,
    //    puis écriture, puis reload ES pour qu'il prenne en compte nos modifs.
    await svc.reloadEsGamelist();
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    final ok = await svc.writeMetadata(systemName, romPath, gameName, changes);
    if (!mounted) return;

    // 8) Reload ES (final) pour faire prendre en compte côté Batocera
    if (ok) await svc.reloadEsGamelist();
    if (!mounted) return;

    // 9) Applique les changements en mémoire pour rafraîchir l'affichage
    //    immédiatement (pas besoin de retourner à la liste pour recharger)
    if (ok) {
      setState(() {
        for (final entry in changes.entries) {
          if (entry.value.isEmpty) {
            widget.game.remove(entry.key);
          } else {
            widget.game[entry.key] = entry.value;
          }
        }
      });
    }

    // Notification utilisateur
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(ok ? Icons.check_circle_rounded : Icons.error_rounded,
            color: ok ? Colors.greenAccent : Colors.redAccent, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(
          ok
              ? 'Métadonnées sauvegardées'
                  '${backupOk ? " (backup créé)" : ""}'
                  '${pendingApplied > 0 ? " · $pendingApplied pending appliqué${pendingApplied > 1 ? "s" : ""}" : ""}'
              : 'Échec de la sauvegarde',
          style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: const Color(0xFF1C2230),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
  }

  /// Sanitize un nom de jeu pour en faire un nom de fichier sûr
  /// (mêmes règles que `running_game_screen._sanitizeFilename`).
  String _sanitizeFilename(String name) {
    var s = name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) s = 'game';
    return s;
  }

  /// Suffixe utilisé dans le nom de fichier généré pour chaque type de média
  /// quand on doit créer un nouveau fichier (système vierge ou nouveau tag).
  /// Convention Batocera native : ex. fightmix-image.png, fightmix-thumb.png.
  static const Map<String, String> _suffixForTag = {
    'wheel':     'wheel',
    'marquee':   'marquee',
    'thumbnail': 'thumb',
    'image':     'image',
  };

  Future<void> _editMedia() async {
    final game = widget.game;
    final systemName = game['_systemName']?.toString() ?? '';
    final romPath = game['path']?.toString() ?? '';
    final gameName = game['name']?.toString() ?? '';
    if (systemName.isEmpty || romPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Infos jeu incomplètes'),
        backgroundColor: Color(0xFF1C2230),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final state = context.read<AppState>();
    final mediaSvc = state.mediaService;
    final metaSvc = state.metadataService;

    // 1) Détermine le tag à utiliser pour le logo. Règle :
    //    - on regarde d'abord la convention DU SYSTÈME (majorité wheel/marquee
    //      dans le gamelist) — évite qu'un jeu isolé en <wheel> dans un système
    //      majoritairement <marquee> impose 'wheel' aux nouveaux jeux scrappés.
    //    - mais si CE jeu a déjà un logo dans l'autre tag, on respecte ce qui
    //      existe pour ne pas créer un doublon dans son entrée.
    final wheelExisting   = await mediaSvc.findExistingMedia(systemName, romPath, 'wheel');
    final marqueeExisting = await mediaSvc.findExistingMedia(systemName, romPath, 'marquee');
    final String logoTag;
    if (wheelExisting != null && marqueeExisting == null) {
      logoTag = 'wheel';
    } else if (marqueeExisting != null && wheelExisting == null) {
      logoTag = 'marquee';
    } else {
      // soit les deux, soit aucun → on suit la majorité du système
      logoTag = await mediaSvc.detectLogoTag(systemName);
    }
    final logoExisting = (logoTag == 'wheel') ? wheelExisting : marqueeExisting;

    final thumbExisting = await mediaSvc.findExistingMedia(systemName, romPath, 'thumbnail');
    final imageExisting = await mediaSvc.findExistingMedia(systemName, romPath, 'image');
    if (!mounted) return;

    // 2) Ouvre le dialog avec les chemins + bytes existants (pour preview rapide
    //    sans nouveau fetch — on réutilise ceux déjà chargés par _loadImages).
    final result = await showDialog<MediaEditResult>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (_) => MediaEditorDialog(
        gameName: gameName.isNotEmpty ? gameName : romPath.split('/').last,
        logoTag: logoTag,
        existingPaths: {
          if (logoExisting != null)  logoTag:    logoExisting,
          if (thumbExisting != null) 'thumbnail': thumbExisting,
          if (imageExisting != null) 'image':    imageExisting,
        },
        existingBytes: {
          logoTag:     _wheelBytes,
          'thumbnail': _thumbBytes,
          'image':     _imageBytes,
        },
      ),
    );
    if (result == null || result.isEmpty || !mounted) return;
    final picks = result.picks;
    final deletions = result.deletions;

    // 3) Si un jeu tourne, demande confirmation pour le fermer (même logique
    //    que pour les métadonnées : ES écrasera le gamelist au quit du jeu).
    final running = await metaSvc.isGameRunning();
    if (!mounted) return;
    if (running) {
      final confirm = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
            SizedBox(width: 8),
            Text('Jeu en cours', style: TextStyle(fontSize: 15)),
          ]),
          content: const Text(
            'Un jeu est en cours.\n'
            'Pour sauvegarder les médias, il faut le fermer.\n\n'
            'Continuer ?',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE02020)),
              child: const Text('Fermer le jeu et sauvegarder'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Fermeture du jeu en cours...', style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF1C2230),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ));
      await metaSvc.killRunningGame();
      if (!mounted) return;
    }

    // 4) Backup horodaté du gamelist (même logique que _editMetadata)
    final backupOk = await metaSvc.backupGamelist(systemName);
    if (!mounted) return;

    // 5) Flush ES si jeu tué ou pending présents (pour ne pas écraser nos balises)
    final pendingFiles = await state.pendingService.listPendingFiles();
    if (!mounted) return;
    final hasPending = pendingFiles.isNotEmpty;
    if (running || hasPending) {
      await metaSvc.reloadEsGamelist();
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
    }

    // 6) Applique les pending sans reload (un seul reload final)
    int pendingApplied = 0;
    if (hasPending) {
      try {
        pendingApplied = await state.pendingService.applyPendingNoReload();
      } catch (_) {}
      if (!mounted) return;
    }

    // 7) Upload des fichiers et construction des balises à écrire.
    //    `tagsToWrite` contient les chemins relatifs `./media/...` qui vont
    //    dans gamelist.xml (format Batocera standard).
    //    `absPathsByTag` contient les chemins absolus filesystem qui vont
    //    dans widget.game (consommés par _fetchImage qui détecte /userdata/
    //    et bascule en SFTP direct — indépendant du cache ES, donc fiable
    //    immédiatement après save).
    final tagsToWrite = <String, String>{};
    final absPathsByTag = <String, String>{};
    int uploaded = 0;
    int deleted = 0;
    final List<String> failures = [];

    for (final entry in picks.entries) {
      final tag  = entry.key;
      final pick = entry.value;
      try {
        // Détermine dossier + nom de fichier de destination
        String? existingRel;
        if (tag == logoTag) existingRel = logoExisting;
        if (tag == 'thumbnail') existingRel = thumbExisting;
        if (tag == 'image')     existingRel = imageExisting;

        final String relDir;
        final String fileName;
        if (existingRel != null && existingRel.isNotEmpty) {
          // Réutilise le chemin existant (overwrite : même nom = même balise)
          var rel = existingRel;
          if (rel.startsWith('./')) rel = rel.substring(2);
          final lastSlash = rel.lastIndexOf('/');
          if (lastSlash > 0) {
            relDir   = rel.substring(0, lastSlash);
            fileName = rel.substring(lastSlash + 1);
          } else {
            relDir   = await mediaSvc.detectMediaDir(systemName, tag);
            fileName = rel;
          }
        } else {
          relDir = await mediaSvc.detectMediaDir(systemName, tag);
          // On déduit l'extension depuis le path local (on ne lit pas les bytes)
          final ext = pick.ext.isNotEmpty ? pick.ext : 'png';
          final suffix = _suffixForTag[tag] ?? tag;
          fileName = '${_sanitizeFilename(gameName)}-$suffix.$ext';
        }

        final destDir  = '/userdata/roms/$systemName/$relDir';
        final destPath = '$destDir/$fileName';
        final relPath  = './$relDir/$fileName';

        await mediaSvc.ensureRemoteDir(destDir);
        await state.ssh.uploadFileFromPath(pick.localPath, destPath);

        tagsToWrite[tag]    = relPath;
        absPathsByTag[tag]  = destPath; // chemin absolu pour _fetchImage SFTP
        uploaded++;
      } catch (e) {
        failures.add(tag);
      }
    }
    if (!mounted) return;

    // 7b) Suppressions : rm du fichier sur disque + balise vide dans gamelist
    //     (writeMetadata supprime la balise quand val == "").
    for (final tag in deletions) {
      try {
        String? existingRel;
        if (tag == logoTag) existingRel = logoExisting;
        if (tag == 'thumbnail') existingRel = thumbExisting;
        if (tag == 'image')     existingRel = imageExisting;
        if (existingRel != null && existingRel.isNotEmpty) {
          var rel = existingRel;
          if (rel.startsWith('./')) rel = rel.substring(2);
          final absPath = '/userdata/roms/$systemName/$rel';
          await mediaSvc.deleteRemoteFile(absPath);
        }
        tagsToWrite[tag] = ''; // efface la balise dans gamelist
        deleted++;
      } catch (_) {
        failures.add(tag);
      }
    }
    if (!mounted) return;

    // 8) Écriture des balises dans gamelist.xml.
    //    D'abord reload ES pour qu'il flush les playtime en mémoire sur disque,
    //    puis écriture, puis reload ES pour qu'il prenne en compte nos modifs.
    bool writeOk = true;
    if (tagsToWrite.isNotEmpty) {
      await metaSvc.reloadEsGamelist();
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      writeOk = await metaSvc.writeMetadata(systemName, romPath, gameName, tagsToWrite);
      if (!mounted) return;
      if (writeOk) await metaSvc.reloadEsGamelist();
      if (!mounted) return;
    }

    // 9) Met à jour widget.game (chemins) puis re-fetch les médias depuis
    //    Batocera. On évite tout readAsBytes du fichier local pour empêcher
    //    MIUI d'indexer l'image dans la galerie Pictures/.
    if (writeOk && tagsToWrite.isNotEmpty) {
      setState(() {
        for (final entry in tagsToWrite.entries) {
          if (entry.value.isEmpty) {
            // Suppression : on retire la clé de widget.game
            widget.game.remove(entry.key);
          } else {
            // Upload : on stocke le chemin ABSOLU filesystem (pas le ./media/...
            // qui va dans gamelist.xml). _fetchImage détecte /userdata/ et
            // bascule en SFTP direct, indépendant du cache HTTP d'ES — donc
            // l'image est dispo immédiatement après upload.
            final abs = absPathsByTag[entry.key];
            if (abs != null) widget.game[entry.key] = abs;
          }
        }
      });
      // Refresh : invalide le cache disque local + relance _loadImages.
      // Avec les chemins /userdata/ ci-dessus, _fetchImage utilise SFTP
      // direct → pas besoin d'attendre qu'ES re-serve le gamelist.
      await _refreshImages();
      if (!mounted) return;
    }

    // Notification utilisateur
    final totalChanges = uploaded + deleted;
    final ok = writeOk && totalChanges > 0 && failures.isEmpty;
    final partial = totalChanges > 0 && (failures.isNotEmpty || !writeOk);
    final parts = <String>[];
    if (uploaded > 0) {
      parts.add('$uploaded envoyé${uploaded > 1 ? "s" : ""}');
    }
    if (deleted > 0) {
      parts.add('$deleted supprimé${deleted > 1 ? "s" : ""}');
    }
    final summary = parts.join(' · ');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
          ok ? Icons.check_circle_rounded : (partial ? Icons.warning_amber_rounded : Icons.error_rounded),
          color: ok ? Colors.greenAccent : (partial ? Colors.orangeAccent : Colors.redAccent),
          size: 18,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(
          ok
              ? '$summary'
                  '${backupOk ? " (backup créé)" : ""}'
                  '${pendingApplied > 0 ? " · $pendingApplied pending appliqué${pendingApplied > 1 ? "s" : ""}" : ""}'
              : (totalChanges == 0
                  ? 'Échec de la sauvegarde'
                  : '$summary'
                    '${failures.isNotEmpty ? " · ${failures.length} en erreur" : " · écriture gamelist échouée"}'),
          style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: const Color(0xFF1C2230),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
    ));
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
            Text('Chargement...', style: TextStyle(fontSize: 12, color: Colors.white70)),
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
          content: Text('Erreur : $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  Future<void> _openManual() async {
    final path = widget.game['manual']?.toString();
    if (path == null || path.isEmpty) return;
    await _openFileViewer(path, 'Manuel - ${widget.game['name'] ?? ''}');
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
            Text('Chargement...'),
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
          content: Text('Impossible de charger le fichier', style: TextStyle(color: Colors.white)),
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
          content: Text('Erreur : $e', style: const TextStyle(color: Colors.white)),
          backgroundColor: Colors.redAccent,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final game = widget.game;
    final name = game['name'] ?? 'Jeu inconnu';
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
              tooltip: 'Jeu aléatoire',
            ),
          if (hasRA)
            IconButton(
              icon: const Icon(Icons.emoji_events_rounded, color: Colors.amberAccent, size: 20),
              onPressed: () => launchUrl(
                Uri.parse('https://retroachievements.org/game/$cheevosId'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white54, size: 20),
            onPressed: _refreshImages,
            tooltip: 'Actualiser les médias',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Logo système + Wheel / Marquee (toujours affiché)
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
                  if (widget.systemLogo != null)
                    Container(width: 1, height: 40, color: Colors.white10),
                  Expanded(
                    child: _wheelBytes != null
                        ? GestureDetector(
                            onTap: () => _showMedia(_wheelBytes!),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(_wheelBytes!, fit: BoxFit.contain),
                            ),
                          )
                        : Center(
                            child: _wheelTried
                                ? const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.image_not_supported_rounded, size: 14, color: Colors.white38),
                                      SizedBox(width: 6),
                                      Text('Logo indisponible',
                                          style: TextStyle(color: Colors.white38, fontSize: 11)),
                                    ],
                                  )
                                : const SizedBox(width: 14, height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24)),
                          ),
                  ),
                ]),
              ),
            ),

            // Thumbnail + Image côte à côte (avec placeholders si absents)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 160,
                    child: _thumbBytes != null
                        ? GestureDetector(
                            onTap: () => _showMedia(_thumbBytes!),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(_thumbBytes!, fit: BoxFit.contain, height: 160),
                            ),
                          )
                        : _MediaPlaceholder(
                            tried: _thumbTried,
                            label: 'Jaquette indisponible',
                            iconSize: 28,
                            fontSize: 11,
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 160,
                    child: _imageBytes != null
                        ? GestureDetector(
                            onTap: () => _showMedia(_imageBytes!),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(_imageBytes!, fit: BoxFit.contain, height: 160),
                            ),
                          )
                        : _MediaPlaceholder(
                            tried: _imageTried,
                            label: 'Image indisponible',
                            iconSize: 32,
                            fontSize: 12,
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
                      _InfoChip(label: 'Favori', icon: Icons.star_rounded, color: Colors.amberAccent),
                    _InfoChip(
                      label: int.tryParse(game['playcount']?.toString() ?? '0') == 0
                          ? 'Jamais joué' : 'Joué ${game['playcount']} fois',
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
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('Fermeture du jeu en cours...', style: TextStyle(color: Colors.white)),
                                  backgroundColor: Color(0xFF1C2230),
                                  behavior: SnackBarBehavior.floating,
                                  duration: Duration(seconds: 3),
                                ));
                              }
                              await state.ssh.execute('curl -s http://127.0.0.1:1234/emukill');
                              await Future.delayed(const Duration(seconds: 2));
                            }
                            state.markLaunchingGame(); // bloque finalisation pending
                            final session = await state.ssh.client!.execute('curl -s -X POST http://127.0.0.1:1234/launch -d "$gamePath"');
                            await session.done;
                          } catch (_) {}
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Lancement...', style: TextStyle(color: Colors.white)),
                            backgroundColor: Color(0xFF1C2230),
                            behavior: SnackBarBehavior.floating,
                          ));
                        },
                        icon: const Icon(Icons.play_arrow_rounded, size: 22),
                        label: const Text('Lancer', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
                          label: const Text('Manuel'),
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
                        label: const Text('Voir la vidéo', style: TextStyle(color: Colors.purpleAccent)),
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
                        label: const Text('Voir sur RetroAchievements',
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

                  // Bouton "Éditer métadonnées" — toujours affiché en bas
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _editMetadata,
                      icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFFE02020)),
                      label: const Text('Éditer métadonnées',
                          style: TextStyle(color: Color(0xFFE02020))),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE02020),
                        side: const BorderSide(color: Color(0xFFE02020)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  // Bouton "Éditer médias" — sous "Éditer métadonnées"
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _editMedia,
                      icon: const Icon(Icons.image_rounded, size: 18, color: Color(0xFFE02020)),
                      label: const Text('Éditer médias',
                          style: TextStyle(color: Color(0xFFE02020))),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE02020),
                        side: const BorderSide(color: Color(0xFFE02020)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
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

/// Placeholder pour un média absent ou en cours de chargement.
class _MediaPlaceholder extends StatelessWidget {
  final bool tried;
  final String label;
  final double iconSize;
  final double fontSize;

  const _MediaPlaceholder({
    required this.tried,
    required this.label,
    this.iconSize = 28,
    this.fontSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFF1C2230),
        border: Border.all(color: Colors.white12),
      ),
      child: Center(
        child: tried
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image_not_supported_rounded, size: iconSize, color: Colors.white38),
                  const SizedBox(height: 6),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: fontSize)),
                ],
              )
            : const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purpleAccent)),
      ),
    );
  }
}
