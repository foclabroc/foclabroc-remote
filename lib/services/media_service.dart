import 'dart:convert';
import 'ssh_service.dart';

/// Service pour gérer les médias (logo/jaquette/image) d'un jeu :
/// - détecte le sous-dossier où sont stockés les médias d'un système (par tag)
/// - lit le chemin média existant pour un jeu donné
///
/// L'upload du fichier est fait directement via [SshService.uploadFileFromPath]
/// par l'appelant. L'écriture de la balise dans gamelist.xml est faite via
/// [MetadataService.writeMetadata] (qui accepte n'importe quelle balise).
class MediaService {
  final SshService ssh;
  MediaService(this.ssh);

  /// Conventions Batocera natives par défaut : tous les médias image vont
  /// dans `images/` (les vidéos dans `videos/`, mais on n'en gère pas ici).
  /// Utilisé uniquement quand le système est vierge — sinon detectMediaDir
  /// trouve la convention déjà en place.
  static const Map<String, String> defaultDirs = {
    'wheel':     'images',
    'marquee':   'images',
    'thumbnail': 'images',
    'image':     'images',
  };

  String _shQ(String s) => "'${s.replaceAll("'", "'\\''")}'";

  Future<String> _execDirect(String cmd) async {
    try {
      final session = await ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return utf8.decode(bytes).trim();
    } catch (_) { return ''; }
  }

  /// Détecte le sous-dossier média (relatif, ex "media/wheels") pour la balise
  /// [tag] dans le gamelist du système. Scanne plusieurs entrées pour trouver
  /// un dossier déjà utilisé, sinon retourne la convention par défaut.
  Future<String> detectMediaDir(String systemName, String tag) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    final raw = await _execDirect(
      "grep -oE '<$tag>[^<]+</$tag>' ${_shQ(gamelist)} 2>/dev/null | head -10",
    );
    for (final line in raw.split('\n')) {
      final m = RegExp('<$tag>([^<]+)</$tag>').firstMatch(line);
      if (m == null) continue;
      var p = m.group(1)!.trim();
      if (p.startsWith('./')) p = p.substring(2);
      final idx = p.lastIndexOf('/');
      if (idx > 0) return p.substring(0, idx);
    }
    return defaultDirs[tag] ?? 'images';
  }

  /// Détecte la convention "logo" du système : 'wheel' ou 'marquee', selon
  /// celui qui est le plus utilisé dans le gamelist. Si aucun des deux n'est
  /// présent, retourne 'wheel' (tag moderne par défaut).
  ///
  /// Exemple : sur un système avec 50 jeux en <marquee> et 1 en <wheel>,
  /// retourne 'marquee' pour rester cohérent avec la majorité.
  Future<String> detectLogoTag(String systemName) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    final wheelOut = await _execDirect(
      "grep -cE '<wheel>[^<]+</wheel>' ${_shQ(gamelist)} 2>/dev/null",
    );
    final marqueeOut = await _execDirect(
      "grep -cE '<marquee>[^<]+</marquee>' ${_shQ(gamelist)} 2>/dev/null",
    );
    final wheelCount   = int.tryParse(wheelOut.trim())   ?? 0;
    final marqueeCount = int.tryParse(marqueeOut.trim()) ?? 0;
    if (marqueeCount > wheelCount) return 'marquee';
    return 'wheel';
  }

  /// Lit la valeur de la balise [tag] (ex 'wheel', 'thumbnail', 'image') pour
  /// le jeu identifié par [romPath] dans le gamelist.xml. Retourne null si
  /// absent ou si le gamelist n'existe pas.
  ///
  /// Implémentation pure-shell, simple et robuste :
  /// 1) `grep -F -A 50 "<basename></path>"` : trouve la ligne <path>...rom</path>
  ///    (match LITTÉRAL via -F, pas de regex, pas de souci avec parenthèses)
  ///    et capture les 50 lignes suivantes — largement assez pour englober
  ///    le bloc <game> entier en pratique.
  /// 2) `sed '/<\/game>/q'` : tronque au premier </game> rencontré pour ne
  ///    pas déborder sur le jeu suivant.
  /// 3) `grep -oE '<tag>[^<]+</tag>'` puis `sed` pour extraire la valeur.
  ///
  /// Le suffixe `</path>` garantit qu'on match la balise <path> et pas
  /// n'importe quelle autre occurrence du basename (ex. dans un <name>).
  Future<String?> findExistingMedia(
      String systemName, String romPath, String tag) async {
    final gamelist = '/userdata/roms/$systemName/gamelist.xml';
    final romBase = romPath.split('/').last;
    final needle = '$romBase</path>';

    final cmd =
        'grep -F -A 50 -- ${_shQ(needle)} ${_shQ(gamelist)} 2>/dev/null '
        r'| sed -n ' "'1,/<\\/game>/p'" ' '
        '| grep -oE ${_shQ('<$tag>[^<]+</$tag>')} '
        '| head -1 '
        "| sed -E 's|<$tag>||;s|</$tag>||'";

    final out = await _execDirect(cmd);
    return out.trim().isEmpty ? null : out.trim();
  }

  /// Crée le dossier distant si besoin (mkdir -p).
  Future<void> ensureRemoteDir(String absPath) async {
    await _execDirect('mkdir -p ${_shQ(absPath)}');
  }

  /// Supprime un fichier distant (rm -f). Pas d'erreur si absent.
  Future<void> deleteRemoteFile(String absPath) async {
    await _execDirect('rm -f ${_shQ(absPath)}');
  }
}
