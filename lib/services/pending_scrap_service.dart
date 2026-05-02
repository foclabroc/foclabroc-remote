import 'dart:convert';
import 'ssh_service.dart';

/// Représente un scrap en attente d'application au gamelist.
class PendingScrap {
  final String filePath;     // chemin du JSON sur Batocera
  final String systemName;
  final String romPath;
  final String romBase;
  final String gameName;
  final Map<String, String> tags; // ex {video: ./videos/foo.mkv, image: ...}
  final DateTime? timestamp;

  const PendingScrap({
    required this.filePath,
    required this.systemName,
    required this.romPath,
    required this.romBase,
    required this.gameName,
    required this.tags,
    this.timestamp,
  });

  /// Liste lisible des balises : ['vidéo', 'screenshot'] etc.
  List<String> get tagLabels {
    final labels = <String>[];
    if (tags.containsKey('video')) labels.add('vidéo');
    if (tags.containsKey('screenshot') || tags.containsKey('image')) {
      if (!labels.contains('screenshot')) labels.add('screenshot');
    }
    return labels;
  }
}

/// Service qui gère le cycle de vie des scraps "pending" : sauvegarde,
/// listage, application au gamelist.xml côté Batocera + notification ES.
///
/// Pourquoi : ES écrase le gamelist.xml au quit du jeu (avec son état
/// mémoire qui ne contient pas nos balises ajoutées par script). On stocke
/// donc les balises côté Batocera et on les applique quand aucun jeu ne tourne.
class PendingScrapService {
  static const String pendingDir =
      '/userdata/system/configs/foclabroc-remote/pending';

  final SshService ssh;

  PendingScrapService(this.ssh);

  /// Échappe pour usage en argument shell entre simples quotes.
  String _shQ(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// Exécute une commande SSH directe (pas de wrapper bash -l -c).
  Future<String> _execDirect(String cmd) async {
    try {
      final session = await ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return utf8.decode(bytes).trim();
    } catch (_) {
      return '';
    }
  }

  /// Écrit du contenu texte dans un fichier distant via base64.
  Future<void> _writeRemoteFile(String path, String content) async {
    final b64 = base64.encode(utf8.encode(content));
    final session = await ssh.client!.execute(
      "echo '$b64' | base64 -d > ${_shQ(path)}",
    );
    await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
    await session.done;
  }

  /// Demande à EmulationStation de relire les gamelist.xml depuis le disque.
  Future<void> reloadEsGamelist() async {
    try {
      await _execDirect("curl -s http://127.0.0.1:1234/reloadgames >/dev/null 2>&1");
    } catch (_) {}
  }

  /// Stocke un scrap pending sur Batocera.
  Future<bool> savePending({
    required String systemName,
    required String romPath,
    required String gameName,
    required Map<String, String> tags,
  }) async {
    try {
      final payload = {
        'systemName': systemName,
        'romPath': romPath,
        'romBase': romPath.split('/').last,
        'gameName': gameName,
        'tags': tags,
        'timestamp': DateTime.now().toIso8601String(),
      };
      final json = jsonEncode(payload);
      final id = '${systemName}_${DateTime.now().millisecondsSinceEpoch}';
      final file = '$pendingDir/$id.json';
      await _execDirect('mkdir -p ${_shQ(pendingDir)}');
      await _writeRemoteFile(file, json);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Liste les chemins des scraps pending sur Batocera.
  Future<List<String>> listPendingFiles() async {
    final raw = await _execDirect(
      'ls -1 ${_shQ(pendingDir)}/*.json 2>/dev/null',
    );
    return raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
  }

  /// Liste les scraps pending avec leurs détails (pour affichage UI).
  Future<List<PendingScrap>> listPending() async {
    final files = await listPendingFiles();
    final result = <PendingScrap>[];
    for (final file in files) {
      try {
        final bytes = await ssh.downloadFile(file);
        final json = utf8.decode(bytes);
        final data = jsonDecode(json) as Map<String, dynamic>;
        result.add(PendingScrap(
          filePath: file,
          systemName: data['systemName'] as String? ?? '',
          romPath: data['romPath'] as String? ?? '',
          romBase: data['romBase'] as String? ?? '',
          gameName: data['gameName'] as String? ?? '',
          tags: Map<String, String>.from(data['tags'] as Map? ?? {}),
          timestamp: DateTime.tryParse(data['timestamp'] as String? ?? ''),
        ));
      } catch (_) {
        // JSON corrompu : on ignore
      }
    }
    return result;
  }

  /// Finalise tous les pending : flush l'état mémoire ES, applique les balises
  /// au gamelist, recharge ES, supprime les pending traités.
  Future<int> finalizePending() async {
    final files = await listPendingFiles();
    if (files.isEmpty) return 0;
    int processed = 0;

    // Étape 1 : flush l'état mémoire ES sur disque (playtime/lastplayed/playcount)
    // AVANT qu'on touche au gamelist. Sinon le 2e reload écraserait nos balises.
    await reloadEsGamelist();
    await Future.delayed(const Duration(seconds: 1));

    for (final file in files) {
      try {
        final bytes = await ssh.downloadFile(file);
        final json = utf8.decode(bytes);
        final data = jsonDecode(json) as Map<String, dynamic>;
        final systemName = data['systemName'] as String? ?? '';
        final romPath = data['romPath'] as String? ?? '';
        final gameName = data['gameName'] as String? ?? '';
        final tags = Map<String, String>.from(data['tags'] as Map? ?? {});
        if (systemName.isEmpty || romPath.isEmpty) continue;

        final ok = await _applyTagsToGamelist(systemName, romPath, gameName, tags);
        if (ok) processed++;

        // Supprime le pending dans tous les cas (sinon boucle infinie)
        await _execDirect('rm -f ${_shQ(file)}');
      } catch (_) {
        // En cas d'erreur on laisse le pending pour retry
      }
    }
    // Étape 2 : reload ES pour qu'il lise notre gamelist modifié
    if (processed > 0) await reloadEsGamelist();
    return processed;
  }

  /// Applique des balises arbitraires au gamelist.xml d'un système.
  Future<bool> _applyTagsToGamelist(
      String systemName, String romPath, String gameName, Map<String, String> tags) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    final romBase = romPath.split('/').last;
    final tagsJson = jsonEncode(tags);
    const script = r'''
import xml.etree.ElementTree as ET, sys, os, json
gl = sys.argv[1]; rb = sys.argv[2]; gameName = sys.argv[3]; tagsJson = sys.argv[4]
try:
    tags = json.loads(tagsJson)
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
    for tag, val in tags.items():
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
    final tmpScript = '/tmp/.batoremote_apply_${DateTime.now().millisecondsSinceEpoch}.py';
    await _writeRemoteFile(tmpScript, script);
    final result = await _execDirect(
      'python3 ${_shQ(tmpScript)} ${_shQ(gamelist)} ${_shQ(romBase)} ${_shQ(gameName)} ${_shQ(tagsJson)} 2>&1; rm -f ${_shQ(tmpScript)}',
    );
    return result.contains('OK');
  }

  /// Vérifie si un jeu tourne actuellement (true = jeu en cours).
  Future<bool> isGameRunning() async {
    final raw = await _execDirect('curl -s http://127.0.0.1:1234/runningGame');
    return raw.isNotEmpty && !raw.contains('"msg"');
  }

  /// Tue le jeu en cours (utilisé avant finalize si l'utilisateur accepte).
  Future<void> killRunningGame() async {
    await _execDirect('curl -s http://127.0.0.1:1234/emukill');
    await Future.delayed(const Duration(seconds: 2));
  }
}
