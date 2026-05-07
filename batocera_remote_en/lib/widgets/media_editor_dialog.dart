import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'in_app_file_picker.dart';

/// Représente un nouveau média sélectionné par l'utilisateur (avant upload).
/// On ne lit PAS les bytes du fichier au moment du pick — la preview se fait
/// via Image.file (lazy decode), et l'upload SFTP via uploadFileFromPath.
/// Cela évite que MIUI indexe le fichier dans Pictures/ après readAsBytes().
class MediaPick {
  /// Chemin local du fichier choisi (ex /storage/emulated/0/Download/foo.png).
  final String localPath;
  /// Extension en minuscules sans le point (ex 'png', 'jpg').
  final String ext;

  const MediaPick({
    required this.localPath,
    required this.ext,
  });
}

/// Résultat d'une édition de médias : map des nouveaux fichiers + set des
/// balises à supprimer. L'UI garantit que `picks` et `deletions` ont des
/// clés disjointes (l'upload supersède la suppression et vice-versa).
class MediaEditResult {
  final Map<String, MediaPick> picks;
  final Set<String> deletions;
  const MediaEditResult({this.picks = const {}, this.deletions = const {}});
  bool get isEmpty => picks.isEmpty && deletions.isEmpty;
}

/// Dialog d'édition des médias d'un jeu (logo / jaquette / image).
///
/// Présente trois cadres avec preview + chemin existant + bouton upload.
/// Retourne une map des nouveaux fichiers sélectionnés (clé = tag balise),
/// ou null si l'utilisateur annule.
class MediaEditorDialog extends StatefulWidget {
  final String gameName;
  /// Chemins relatifs existants par tag (ex {'wheel': './media/wheels/foo.png'}).
  /// Une entrée absente ou vide = pas de média existant.
  final Map<String, String> existingPaths;
  /// Bytes pré-chargés des médias existants par tag (pour preview rapide).
  final Map<String, Uint8List?> existingBytes;
  /// Tag effectivement utilisé pour le logo : 'wheel' ou 'marquee' selon ce
  /// qui était déjà rempli dans le gamelist (ou 'wheel' par défaut).
  final String logoTag;

  const MediaEditorDialog({
    super.key,
    required this.gameName,
    required this.existingPaths,
    required this.existingBytes,
    required this.logoTag,
  });

  @override
  State<MediaEditorDialog> createState() => _MediaEditorDialogState();
}

class _MediaEditorDialogState extends State<MediaEditorDialog> {
  /// Nouveaux fichiers sélectionnés (par tag balise).
  final Map<String, MediaPick> _picks = {};
  /// Tags à supprimer (efface fichier sur Batocera + balise dans gamelist).
  final Set<String> _deletions = {};

  Future<void> _pickFile(String tag) async {
    // Chooser dialog between the 2 explorers.
    // - Builtin = in-app picker (no system intent, no MIUI duplication,
    //   limited to standard MediaStore folders).
    // - External = system FilePicker.platform (full access via SAF, but
    //   may trigger MIUI duplication in Pictures/ with a prefixed/timestamped
    //   filename for images selected from the gallery).
    final choice = await showDialog<String>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.folder_open_rounded, color: Color(0xFFE02020), size: 22),
          SizedBox(width: 8),
          Text('File source', style: TextStyle(fontSize: 15)),
        ]),
        content: const Text(
          'Which explorer to use to pick the image?',
          style: TextStyle(fontSize: 13),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(null),
            child: const Text('Cancel'),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            TextButton.icon(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop('builtin'),
              icon: const Icon(Icons.apps_rounded, size: 16, color: Color(0xFFE02020)),
              label: const Text('Builtin', style: TextStyle(color: Color(0xFFE02020))),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop('external'),
              icon: const Icon(Icons.open_in_browser_rounded, size: 16, color: Colors.white70),
              label: const Text('External', style: TextStyle(color: Colors.white70)),
            ),
          ]),
        ],
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'builtin') {
      await _pickFileBuiltin(tag);
    } else {
      await _pickFileExternal(tag);
    }
  }

  /// BUILTIN picker (no system intent → no MIUI duplication).
  Future<void> _pickFileBuiltin(String tag) async {
    try {
      final results = await Navigator.of(context, rootNavigator: true).push<List<InAppFilePickerResult>>(
        MaterialPageRoute(
          builder: (_) => const InAppFilePicker(
            // Images only, no multi-select here (one frame = one media)
            allowedExtensions: {'png','jpg','jpeg','webp','gif','bmp'},
            allowMultiple: false,
          ),
          fullscreenDialog: true,
        ),
      );
      if (results == null || results.isEmpty || !mounted) return;
      final result = results.first;
      setState(() {
        _picks[tag] = MediaPick(localPath: result.localPath, ext: result.ext);
        _deletions.remove(tag);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pick error: $e', style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// EXTERNAL picker (FilePicker.platform — system SAF, full access but
  /// may duplicate in Pictures/ via MIUI Gallery).
  Future<void> _pickFileExternal(String tag) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      final p = f.path;
      if (p == null) return;
      var ext = (f.extension ?? '').toLowerCase();
      if (ext.isEmpty) {
        final dot = f.name.lastIndexOf('.');
        if (dot > 0) ext = f.name.substring(dot + 1).toLowerCase();
      }
      if (ext.isEmpty) ext = 'png';
      if (!mounted) return;
      setState(() {
        _picks[tag] = MediaPick(localPath: p, ext: ext);
        _deletions.remove(tag);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Pick error: $e', style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  /// Demande confirmation avant marquage pour suppression.
  Future<void> _markDelete(String tag, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
          SizedBox(width: 8),
          Text('Confirmation', style: TextStyle(fontSize: 15)),
        ]),
        content: Text(
          'Delete media "$label"?\n\n'
          'The file will be erased on Batocera and the tag removed from the '
          'gamelist on save.',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            icon: const Icon(Icons.delete_outline_rounded, size: 16),
            label: const Text('Delete'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _deletions.add(tag);
      // Une suppression supersède un éventuel pick local
      _picks.remove(tag);
    });
  }

  /// Cadre identique à `_framedSection` du metadata_editor_dialog.
  Widget _framedSection({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE02020)),
          ),
        ),
        child: child,
      ),
    );
  }

  Widget _mediaRow({
    required String label,
    required String tag,
    required IconData icon,
  }) {
    final pick = _picks[tag];
    final existingPath = widget.existingPaths[tag];
    final existingBytes = widget.existingBytes[tag];

    final hasNewPick = pick != null;
    final hasExisting = existingPath != null && existingPath.isNotEmpty;
    final isDeleted = _deletions.contains(tag);

    // Sous-titre : pick > existing (barré si supprimé) > vide.
    final String? subtitle = hasNewPick
        ? pick.localPath.split('/').last
        : (hasExisting ? existingPath : null);

    final Color subtitleColor = isDeleted
        ? Colors.redAccent
        : (hasNewPick ? Colors.greenAccent : Colors.white70);
    final TextDecoration? subtitleDeco = isDeleted ? TextDecoration.lineThrough : null;

    // Choix de la preview :
    // - suppression marquée → placeholder
    // - nouveau pick → Image.file (lazy decode, n'indexe pas la galerie MIUI)
    // - existant → Image.memory avec les bytes déjà chargés par game_detail
    Widget previewChild;
    if (isDeleted) {
      previewChild = Icon(
        Icons.delete_outline_rounded,
        color: Colors.redAccent.withOpacity(0.6),
        size: 28,
      );
    } else if (hasNewPick) {
      previewChild = ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.file(
          File(pick.localPath),
          key: ValueKey(pick.localPath),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(icon, color: Colors.white24, size: 28),
        ),
      );
    } else if (existingBytes != null) {
      previewChild = ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.memory(existingBytes, fit: BoxFit.contain),
      );
    } else {
      previewChild = Icon(icon, color: Colors.white24, size: 28);
    }

    return _framedSection(
      label: label,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Preview (vignette 56x56) ou icône placeholder
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF0D0F14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: isDeleted ? Colors.redAccent.withOpacity(0.4) : Colors.white12),
            ),
            child: previewChild,
          ),
          const SizedBox(width: 10),
          // Chemin / nom de fichier
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 11,
                      decoration: subtitleDeco,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  )
                else
                  const Text(
                    'No image',
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                if (isDeleted) ...[
                  const SizedBox(height: 2),
                  const Text(
                    '(will be deleted)',
                    style: TextStyle(color: Colors.redAccent, fontSize: 10),
                  ),
                ] else if (hasNewPick) ...[
                  const SizedBox(height: 2),
                  const Text(
                    '(new, will be uploaded)',
                    style: TextStyle(color: Colors.greenAccent, fontSize: 10),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Bouton "↶" pour annuler la suppression marquée
          if (isDeleted)
            IconButton(
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Undo deletion',
              icon: const Icon(Icons.undo_rounded, color: Colors.white70),
              onPressed: () => setState(() => _deletions.remove(tag)),
            ),
          // Bouton "X" pour annuler la sélection (uniquement si nouveau pick)
          if (hasNewPick)
            IconButton(
              iconSize: 18,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              tooltip: 'Cancel selection',
              icon: const Icon(Icons.close_rounded, color: Colors.white54),
              onPressed: () => setState(() => _picks.remove(tag)),
            ),
          // Bouton "🗑" pour marquer la suppression du média existant
          if (hasExisting && !hasNewPick && !isDeleted)
            IconButton(
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: 'Delete media',
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              onPressed: () => _markDelete(tag, label),
            ),
          // Bouton upload (toujours présent)
          IconButton(
            iconSize: 22,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: hasExisting || hasNewPick ? 'Replace' : 'Choose a file',
            icon: const Icon(Icons.upload_file_rounded, color: Color(0xFFE02020)),
            onPressed: () => _pickFile(tag),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C2230),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      title: Row(children: [
        const Icon(Icons.image_rounded, color: Color(0xFFE02020), size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Media: ${widget.gameName}',
            style: const TextStyle(fontSize: 14, color: Colors.white),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _mediaRow(
                label: 'Logo',
                tag: widget.logoTag,
                icon: Icons.flag_rounded,
              ),
              _mediaRow(
                label: 'Cover',
                tag: 'thumbnail',
                icon: Icons.image_outlined,
              ),
              _mediaRow(
                label: 'Image',
                tag: 'image',
                icon: Icons.photo_rounded,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: (_picks.isEmpty && _deletions.isEmpty)
              ? null
              : () => Navigator.of(context, rootNavigator: true).pop(
                    MediaEditResult(picks: _picks, deletions: _deletions),
                  ),
          icon: const Icon(Icons.save_rounded, size: 16),
          label: const Text('Save'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE02020),
            disabledBackgroundColor: Colors.white12,
            disabledForegroundColor: Colors.white38,
          ),
        ),
      ],
    );
  }
}
