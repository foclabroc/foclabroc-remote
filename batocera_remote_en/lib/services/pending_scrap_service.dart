import 'dart:convert';
import 'ssh_service.dart';

/// Represents a scrap pending application to gamelist.
class PendingScrap {
  final String filePath;     // path of JSON on Batocera
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

  /// Human-readable list of tag types: ['video', 'screenshot'] etc.
  List<String> get tagLabels {
    final labels = <String>[];
    if (tags.containsKey('video')) labels.add('video');
    if (tags.containsKey('screenshot') || tags.containsKey('image')) {
      if (!labels.contains('screenshot')) labels.add('screenshot');
    }
    return labels;
  }
}

/// Service that manages the pending scrap lifecycle: save, list, apply to
/// gamelist.xml on Batocera + ES notification.
///
/// Why: ES overwrites gamelist.xml on game quit (with its memory state which
/// doesn't contain our script-added tags). So we store the tags on Batocera
/// and apply them when no game is running.
class PendingScrapService {
  static const String pendingDir =
      '/userdata/system/configs/foclabroc-remote/pending';

  final SshService ssh;

  PendingScrapService(this.ssh);

  /// Quotes for use as a single-quoted shell argument.
  String _shQ(String s) => "'${s.replaceAll("'", "'\\''")}'";

  /// Executes a direct SSH command (no bash -l -c wrapper).
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

  /// Writes text content to a remote file via base64.
  Future<void> _writeRemoteFile(String path, String content) async {
    final b64 = base64.encode(utf8.encode(content));
    final session = await ssh.client!.execute(
      "echo '$b64' | base64 -d > ${_shQ(path)}",
    );
    await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
    await session.done;
  }

  /// Asks EmulationStation to re-read gamelist.xml from disk.
  Future<void> reloadEsGamelist() async {
    try {
      await _execDirect("curl -s http://127.0.0.1:1234/reloadgames >/dev/null 2>&1");
    } catch (_) {}
  }

  /// Stores a pending scrap on Batocera.
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

  /// Lists the pending scrap file paths on Batocera.
  Future<List<String>> listPendingFiles() async {
    final raw = await _execDirect(
      'ls -1 ${_shQ(pendingDir)}/*.json 2>/dev/null',
    );
    return raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
  }

  /// Lists the pending scraps with details (for UI display).
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
        // Corrupt JSON: ignore
      }
    }
    return result;
  }

  /// Finalizes all pending: flushes ES memory state, applies tags to gamelist,
  /// reloads ES, removes processed pending files.
  Future<int> finalizePending() async {
    final files = await listPendingFiles();
    if (files.isEmpty) return 0;
    int processed = 0;

    // Step 1: flush ES in-memory state to disk (playtime/lastplayed/playcount)
    // BEFORE we touch the gamelist. Otherwise the 2nd reload would overwrite.
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

        // Always remove pending (avoid infinite retry on persistent error)
        await _execDirect('rm -f ${_shQ(file)}');
      } catch (_) {
        // On error: leave the pending in place for retry
      }
    }
    // Step 2: reload ES so it reads our modified gamelist
    if (processed > 0) await reloadEsGamelist();
    return processed;
  }

  /// Applies arbitrary tags to a system's gamelist.xml.
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

  /// Checks if a game is currently running (true = game in progress).
  Future<bool> isGameRunning() async {
    final raw = await _execDirect('curl -s http://127.0.0.1:1234/runningGame');
    return raw.isNotEmpty && !raw.contains('"msg"');
  }

  /// Kills the running game (used before finalize if user accepts).
  Future<void> killRunningGame() async {
    await _execDirect('curl -s http://127.0.0.1:1234/emukill');
    await Future.delayed(const Duration(seconds: 2));
  }
}
