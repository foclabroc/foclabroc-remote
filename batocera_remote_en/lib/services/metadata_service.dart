import 'dart:convert';
import 'ssh_service.dart';

/// Service de modification des métadonnées dans gamelist.xml.
///
/// - Lit les métadonnées d'un jeu (en lisant le gamelist.xml directement)
/// - Sauvegarde des modifications avec backup horodaté
/// - Notifie ES via reloadgames (appelant responsable)
class MetadataService {
  final SshService ssh;
  MetadataService(this.ssh);

  String _shQ(String s) => "'${s.replaceAll("'", "'\\''")}'";

  Future<String> _execDirect(String cmd) async {
    try {
      final session = await ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return utf8.decode(bytes).trim();
    } catch (_) { return ''; }
  }

  Future<void> _writeRemoteFile(String path, String content) async {
    final b64 = base64.encode(utf8.encode(content));
    final session = await ssh.client!.execute(
      "echo '$b64' | base64 -d > ${_shQ(path)}",
    );
    await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
    await session.done;
  }

  /// Liste des balises éditables prises en charge.
  static const List<String> editableTags = [
    'name', 'desc', 'genre', 'rating', 'releasedate',
    'developer', 'publisher', 'players', 'lang', 'region', 'favorite',
  ];

  /// Lit les métadonnées actuelles d'un jeu depuis gamelist.xml.
  /// Renvoie une map des balises présentes (les absentes ne sont pas dans la map).
  Future<Map<String, String>> readMetadata(String systemName, String romPath) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    final romBase = romPath.split('/').last;

    const script = r'''
import xml.etree.ElementTree as ET, sys, os, json
gl = sys.argv[1]; rb = sys.argv[2]
tags = ['name','desc','genre','rating','releasedate','developer','publisher','players','lang','region','favorite']
out = {}
try:
    if os.path.exists(gl):
        t = ET.parse(gl)
        for g in t.getroot().findall('game'):
            p = g.find('path')
            if p is not None and p.text and os.path.basename(p.text) == rb:
                for tag in tags:
                    e = g.find(tag)
                    if e is not None and e.text is not None:
                        out[tag] = e.text
                break
except Exception:
    pass
print(json.dumps(out))
''';
    final tmpScript = '/tmp/.batoremote_read_${DateTime.now().millisecondsSinceEpoch}.py';
    await _writeRemoteFile(tmpScript, script);
    final result = await _execDirect(
      'python3 ${_shQ(tmpScript)} ${_shQ(gamelist)} ${_shQ(romBase)} 2>&1; rm -f ${_shQ(tmpScript)}',
    );
    try {
      final data = jsonDecode(result) as Map<String, dynamic>;
      return data.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  /// Creates a backup of gamelist.xml:
  /// /userdata/roms/<system>/backup_gamelist.xml (overwritten on each save)
  /// The backup date is added as a comment at the start of the file.
  Future<bool> backupGamelist(String systemName) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    final backup = '/userdata/roms/$systemName/backup_gamelist.xml';
    final now = DateTime.now();
    final ts = '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
    final pyScript = '''
import sys, re
src_path, dst_path, ts = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    src = open(src_path, 'r', encoding='utf-8').read()
    cmt = '<!-- backup created on ' + ts + ' -->\\n'
    if re.match(r'\\s*<\\?xml', src):
        out = re.sub(r'(<\\?xml[^?]*\\?>\\n?)', lambda m: m.group(1) + cmt, src, count=1)
    else:
        out = cmt + src
    open(dst_path, 'w', encoding='utf-8').write(out)
    print('OK')
except Exception as e:
    print('NO:' + str(e))
''';
    final scriptB64 = base64.encode(utf8.encode(pyScript));
    final result = await _execDirect(
      '[ -f ${_shQ(gamelist)} ] && '
      'echo $scriptB64 | base64 -d | python3 - ${_shQ(gamelist)} ${_shQ(backup)} ${_shQ(ts)} '
      '|| echo NO',
    );
    return result.contains('OK');
  }

  /// Écrit/met à jour les balises métadonnées d'un jeu dans gamelist.xml.
  /// Une valeur vide supprime la balise. Toute autre valeur est définie.
  Future<bool> writeMetadata(
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
        existing = target.find(tag)
        # Special case: favorite=false is equivalent to the tag being absent.
        # Batocera/ES treats a game without <favorite> as not-a-favorite.
        if tag == "favorite" and val.lower() == "false":
            if existing is not None:
                target.remove(existing)
            continue
        if val == "":
            # Valeur vide → supprime la balise
            if existing is not None:
                target.remove(existing)
        else:
            if existing is None:
                existing = ET.SubElement(target, tag)
            existing.text = val
    try:
        ET.indent(tree, space="\t")
    except AttributeError:
        pass
    tree.write(gl, encoding="utf-8", xml_declaration=True)
    print("OK")
except Exception as e:
    print("ERR:" + str(e))
''';
    final tmpScript = '/tmp/.batoremote_meta_${DateTime.now().millisecondsSinceEpoch}.py';
    await _writeRemoteFile(tmpScript, script);
    final result = await _execDirect(
      'python3 ${_shQ(tmpScript)} ${_shQ(gamelist)} ${_shQ(romBase)} ${_shQ(gameName)} ${_shQ(tagsJson)} 2>&1; rm -f ${_shQ(tmpScript)}',
    );
    return result.contains('OK');
  }

  /// Demande à ES de relire les gamelist.xml depuis le disque.
  Future<void> reloadEsGamelist() async {
    try {
      await _execDirect("curl -s http://127.0.0.1:1234/reloadgames >/dev/null 2>&1");
    } catch (_) {}
  }

  /// Vérifie si un jeu tourne actuellement.
  Future<bool> isGameRunning() async {
    final raw = await _execDirect('curl -s http://127.0.0.1:1234/runningGame');
    return raw.isNotEmpty && !raw.contains('"msg"');
  }

  /// Tue le jeu en cours.
  Future<void> killRunningGame() async {
    await _execDirect('curl -s http://127.0.0.1:1234/emukill');
    await Future.delayed(const Duration(seconds: 2));
  }
}
