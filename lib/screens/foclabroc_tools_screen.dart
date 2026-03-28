import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';

// ─── Foclabroc Tools ─────────────────────────────────────────────────────────

class FoclabroctoolsScreen extends StatelessWidget {
  const FoclabroctoolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 8, 24, 0),
              child: Text('Foclabroc Tools',
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _FoclabrocToolCard(
                    icon: Icons.view_in_ar_rounded,
                    title: 'NES3D',
                    subtitle: 'Installe le pack NES 3D\n(détection automatique V40/41/42/43)',
                    color: Colors.tealAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _Nes3dInstallScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _FoclabrocToolCard(
                    icon: Icons.tv_rounded,
                    title: 'Pack Kodi',
                    subtitle: 'Installe le pack Kodi Foclabroc\n(Vstream, IPTV...)',
                    color: Colors.deepPurpleAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _KodiInstallScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _FoclabrocToolCard(
                    icon: Icons.music_note_rounded,
                    title: 'Pack Music',
                    subtitle: '39 musiques OST pour EmulationStation\n(lecture aléatoire)',
                    color: Colors.pinkAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _MusicPackInstallScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _FoclabrocToolCard(
                    icon: Icons.videogame_asset_rounded,
                    title: 'Jeux Windows',
                    subtitle: '21 fangames & remakes gratuits\npour Batocera Windows',
                    color: Colors.orangeAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _WindowsGamesScreen(),
                    )),
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

// ─── Card ─────────────────────────────────────────────────────────────────────

class _FoclabrocToolCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;

  const _FoclabrocToolCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(color: Colors.white, fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white24),
          ]),
        ),
      ),
    );
  }
}

// ─── NES3D Install ────────────────────────────────────────────────────────────

class _Nes3dInstallScreen extends StatefulWidget {
  const _Nes3dInstallScreen();

  @override
  State<_Nes3dInstallScreen> createState() => _Nes3dInstallScreenState();
}

class _Nes3dInstallScreenState extends State<_Nes3dInstallScreen> {
  bool _running = false;
  String _log = '';

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) {
      return '';
    }
  }

  void _appendLog(String msg) => setState(() => _log += '$msg\n');

  Future<void> _launch() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.view_in_ar_rounded, color: Colors.tealAccent, size: 22),
          SizedBox(width: 10),
          Flexible(child: Text('Installer NES3D ?', overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Télécharge et installe le pack NES3D adapté à votre version de Batocera.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 14),
                SizedBox(width: 6),
                Expanded(child: Text(
                  'Espace requis : ~3.8 Go. Les anciens fichiers NES3D seront supprimés.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                )),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
            child: const Text('Installer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _running = true; _log = ''; });

    // 1. Détecter la version
    _appendLog('🔍 Détection de la version de Batocera...');
    final versionRaw = await _exec(
        "batocera-es-swissknife --version | awk '{print \$1}' | sed -E 's/^([0-9]+).*/\\1/'");
    final version = int.tryParse(versionRaw.trim()) ?? 0;
    if (version == 0) {
      _appendLog('❌ Impossible de détecter la version de Batocera.');
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Batocera V$version détecté.");

    // 2. URL selon version
    String archiveUrl;
    if (version <= 40) {
      archiveUrl = 'https://github.com/foclabroc/toolbox/releases/download/Fichiers/3d.zip';
    } else if (version == 41) {
      archiveUrl = 'https://github.com/foclabroc/toolbox/releases/download/Fichiers/3d-41.zip';
    } else if (version == 42) {
      archiveUrl = 'https://github.com/foclabroc/toolbox/releases/download/Fichiers/3d-42.zip';
    } else {
      archiveUrl = 'https://github.com/foclabroc/toolbox/releases/download/Fichiers/3d-43.zip';
    }
    final archiveName = archiveUrl.split('/').last;
    _appendLog("📦 Archive : $archiveName");

    // 3. Espace disque
    _appendLog('\n💾 Vérification espace disque...');
    final freeRaw = await _exec("df -m /userdata | awk 'NR==2 {print \$4}'");
    final freeMb = int.tryParse(freeRaw.trim()) ?? 0;
    const requiredMb = 3800;
    if (freeMb < requiredMb) {
      _appendLog("❌ Espace insuffisant : $freeMb Mo / $requiredMb Mo requis.");
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Espace OK : $freeMb Mo disponibles.");

    // 4. Suppression anciens fichiers
    _appendLog('\n🗑️ Suppression des anciens fichiers NES3D...');
    await _exec(
      'rm -f /userdata/system/configs/evmapy/3dnes.keys '
      '/userdata/system/configs/emulationstation/es_features_3dnes.cfg '
      '/userdata/system/configs/emulationstation/es_systems_3dnes.cfg && '
      'rm -rf /userdata/system/3dnes /userdata/system/nes3d '
      '/userdata/roms/nes3d /userdata/system/wine-bottles/3dnes '
      '/userdata/system/wine-bottles/nes3d',
    );
    _appendLog('✅ Anciens fichiers supprimés.');

    // 5. Téléchargement
    _appendLog("\n⬇️ Téléchargement de $archiveName...");
    _appendLog('  (peut prendre plusieurs minutes)');

    // Lance wget en background + flag quand terminé
    await _exec('rm -f "/userdata/$archiveName" /tmp/_wget_nes3d_done');
    await _exec('wget -q --tries=3 --timeout=120 -O "/userdata/$archiveName" "$archiveUrl" && touch /tmp/_wget_nes3d_done || touch /tmp/_wget_nes3d_done &');

    // Récupère la taille totale attendue
    final totalRaw = await _exec(
        'wget --spider "$archiveUrl" 2>&1 | grep "Content-Length" | awk \'{print \$2}\' | tail -1');
    final totalBytes = int.tryParse(totalRaw.trim()) ?? 0;
    final totalMb = totalBytes > 0 ? (totalBytes / 1024 / 1024).toStringAsFixed(0) : '?';

    // Poll jusqu'au flag de fin
    while (true) {
      if (!mounted) break;
      await Future.delayed(const Duration(seconds: 1));
      final sizeNowRaw = await _exec('stat -c%s "/userdata/$archiveName" 2>/dev/null || echo 0');
      final sizeNow = int.tryParse(sizeNowRaw.trim()) ?? 0;
      final nowMb = (sizeNow / 1024 / 1024).toStringAsFixed(1);
      final pct = totalBytes > 0 ? (sizeNow * 100 ~/ totalBytes) : 0;
      final bar = totalBytes > 0 ? '$pct%' : '$nowMb Mo';
      setState(() {
        final lines = _log.split('\n');
        if (lines.length >= 2 && lines[lines.length - 2].startsWith('  ↓')) {
          lines[lines.length - 2] = '  ↓ $nowMb / $totalMb Mo  [$bar]';
          _log = lines.join('\n');
        } else {
          _log += '  ↓ $nowMb / $totalMb Mo  [$bar]\n';
        }
      });
      // Vérifie le flag de fin
      final done = await _exec('[ -f /tmp/_wget_nes3d_done ] && echo yes || echo no');
      if (done.trim() == 'yes') break;
    }
    await _exec('rm -f /tmp/_wget_nes3d_done');
    if (!mounted) return;

    final sizeRaw = await _exec('stat -c%s "/userdata/$archiveName" 2>/dev/null || echo 0');
    final size = int.tryParse(sizeRaw.trim()) ?? 0;
    if (size < 1000000) {
      _appendLog('❌ Téléchargement échoué.');
      await _exec('rm -f "/userdata/$archiveName"');
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Téléchargement terminé (${(size / 1024 / 1024).toStringAsFixed(0)} Mo).");

    // 6. Extraction
    _appendLog('\n📦 Extraction en cours...');
    await _exec('unzip -o "/userdata/$archiveName" -d "/userdata/" 2>&1');
    if (!mounted) return;
    _appendLog('✅ Extraction terminée.');

    // 7. Nettoyage
    _appendLog('\n🧹 Nettoyage...');
    await _exec('rm -f "/userdata/$archiveName"');

    // 8. Rechargement
    _appendLog('🔄 Rechargement de la liste des jeux...');
    await _exec('curl -s http://127.0.0.1:1234/reloadgames');

    _appendLog('\n✅ Installation NES3D terminée !');
    setState(() => _running = false);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('NES3D installé !')),
          ]),
          content: const Text(
            'Le pack NES3D a été installé avec succès.\nLa liste des jeux a été rechargée.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      if (mounted) setState(() => _log = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 24, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white54),
                ),
                const SizedBox(width: 12),
                Text('NES3D',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontSize: 22)),
              ]),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.view_in_ar_rounded, color: Colors.tealAccent, size: 20),
                      SizedBox(width: 8),
                      Text('Pack NES 3D',
                          style: TextStyle(color: Colors.tealAccent,
                              fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
                    const SizedBox(height: 10),
                    const Text(
                      'Détecte automatiquement votre version de Batocera et télécharge le pack correspondant.',
                      style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final v in ['V40', 'V41', 'V42', 'V43+'])
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.tealAccent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.tealAccent.withOpacity(0.25)),
                          ),
                          child: Text(v,
                              style: const TextStyle(color: Colors.tealAccent,
                                  fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.storage_rounded, color: Colors.orangeAccent, size: 14),
                        SizedBox(width: 6),
                        Text('Espace requis : ~3.8 Go',
                            style: TextStyle(color: Colors.orangeAccent, fontSize: 11)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _running ? null : _launch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          disabledBackgroundColor: Colors.white12,
                        ),
                        icon: _running
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.download_rounded),
                        label: Text(_running ? 'Installation en cours...' : 'Installer NES3D'),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            if (_running) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    backgroundColor: Color(0x14FFFFFF),
                    valueColor: AlwaysStoppedAnimation(Colors.tealAccent),
                    minHeight: 4,
                  ),
                ),
              ),
            ],
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0C10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(_log,
                          style: const TextStyle(fontFamily: 'monospace',
                              fontSize: 10, color: Colors.white70, height: 1.5)),
                    ),
                  ),
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ─── Kodi Install ─────────────────────────────────────────────────────────────

class _KodiInstallScreen extends StatefulWidget {
  const _KodiInstallScreen();

  @override
  State<_KodiInstallScreen> createState() => _KodiInstallScreenState();
}

class _KodiInstallScreenState extends State<_KodiInstallScreen> {
  bool _running = false;
  String _log = '';

  static const _zipUrl =
      'https://github.com/foclabroc/toolbox/releases/download/Fichiers/kodi.zip';
  static const _kodiDir = '/userdata/system/.kodi';
  static const _tmpZip = '/tmp/kodi_pack.zip';

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes =
          await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) {
      return '';
    }
  }

  void _appendLog(String msg) => setState(() => _log += '$msg\n');

  Future<void> _launch() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.tv_rounded, color: Colors.deepPurpleAccent, size: 22),
          SizedBox(width: 10),
          Flexible(child: Text('Installer le pack Kodi ?',
              overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Installe le pack Kodi Foclabroc (Vstream, IPTV...).',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded,
                    color: Colors.redAccent, size: 14),
                SizedBox(width: 6),
                Expanded(child: Text(
                  'Le dossier .kodi sera entièrement supprimé et remplacé.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 11),
                )),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                foregroundColor: Colors.white),
            child: const Text('Installer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _running = true; _log = ''; });

    // 1. Suppression ancien dossier
    _appendLog('🗑️ Suppression de $_kodiDir...');
    await _exec('rm -rf "$_kodiDir"');
    _appendLog('✅ Dossier supprimé.');

    // 2. Téléchargement avec progression
    _appendLog('\n⬇️ Téléchargement du pack Kodi...');
    _appendLog('  (peut prendre plusieurs minutes)');

    await _exec('rm -f $_tmpZip /tmp/_kodi_wget_done');
    await _exec('wget -q --tries=3 --timeout=120 -O "$_tmpZip" "$_zipUrl" && touch /tmp/_kodi_wget_done || touch /tmp/_kodi_wget_done &');

    final totalRaw = await _exec(
        'wget --spider "$_zipUrl" 2>&1 | grep "Content-Length" | awk \'{print \$2}\' | tail -1');
    final totalBytes = int.tryParse(totalRaw.trim()) ?? 0;
    final totalMb = totalBytes > 0 ? (totalBytes / 1024 / 1024).toStringAsFixed(0) : '?';

    while (true) {
      if (!mounted) break;
      await Future.delayed(const Duration(seconds: 1));
      final sizeNowRaw = await _exec('stat -c%s "$_tmpZip" 2>/dev/null || echo 0');
      final sizeNow = int.tryParse(sizeNowRaw.trim()) ?? 0;
      final nowMb = (sizeNow / 1024 / 1024).toStringAsFixed(1);
      final pct = totalBytes > 0 ? (sizeNow * 100 ~/ totalBytes) : 0;
      final bar = totalBytes > 0 ? '$pct%' : '$nowMb Mo';
      setState(() {
        final lines = _log.split('\n');
        if (lines.length >= 2 && lines[lines.length - 2].startsWith('  ↓')) {
          lines[lines.length - 2] = '  ↓ $nowMb / $totalMb Mo  [$bar]';
          _log = lines.join('\n');
        } else {
          _log += '  ↓ $nowMb / $totalMb Mo  [$bar]\n';
        }
      });
      final done = await _exec('[ -f /tmp/_kodi_wget_done ] && echo yes || echo no');
      if (done.trim() == 'yes') break;
    }
    await _exec('rm -f /tmp/_kodi_wget_done');
    if (!mounted) return;

    final sizeRaw = await _exec('stat -c%s "$_tmpZip" 2>/dev/null || echo 0');
    final size = int.tryParse(sizeRaw.trim()) ?? 0;
    if (size < 100000) {
      _appendLog('❌ Téléchargement échoué.');
      await _exec('rm -f "$_tmpZip"');
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Téléchargement terminé (${(size / 1024 / 1024).toStringAsFixed(0)} Mo).");

    // 3. Extraction
    _appendLog('\n📦 Extraction en cours...');
    await _exec('unzip -o "$_tmpZip" -d /userdata/system/ 2>&1');
    if (!mounted) return;
    _appendLog('✅ Extraction terminée.');

    // 4. Nettoyage
    _appendLog('\n🧹 Nettoyage...');
    await _exec('rm -f "$_tmpZip"');

    _appendLog('\n✅ Pack Kodi installé avec succès !');
    setState(() => _running = false);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Pack Kodi installé !')),
          ]),
          content: const Text(
            'Le pack Kodi a été installé avec succès.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          actions: [
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK')),
          ],
        ),
      );
      if (mounted) setState(() => _log = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 24, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white54),
                ),
                const SizedBox(width: 12),
                Text('Pack Kodi',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontSize: 22)),
              ]),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Row(children: [
                      Icon(Icons.tv_rounded,
                          color: Colors.deepPurpleAccent, size: 20),
                      SizedBox(width: 8),
                      Text('Pack Kodi Foclabroc',
                          style: TextStyle(
                              color: Colors.deepPurpleAccent,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                    ]),
                    const SizedBox(height: 10),
                    const Text(
                      'Installe la configuration Kodi de Foclabroc avec Vstream, IPTV et autres extensions préconfigurées.',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in ['Vstream', 'IPTV', 'Extensions'])
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.deepPurpleAccent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color:
                                    Colors.deepPurpleAccent.withOpacity(0.25)),
                          ),
                          child: Text(e,
                              style: const TextStyle(
                                  color: Colors.deepPurpleAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: Colors.redAccent.withOpacity(0.2)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.warning_amber_rounded,
                            color: Colors.redAccent, size: 14),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Remplace entièrement le dossier .kodi existant',
                            style: TextStyle(
                                color: Colors.redAccent, fontSize: 11),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _running ? null : _launch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurpleAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          disabledBackgroundColor: Colors.white12,
                        ),
                        icon: _running
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.download_rounded),
                        label: Text(_running
                            ? 'Installation en cours...'
                            : 'Installer le pack Kodi'),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            if (_running) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    backgroundColor: Color(0x14FFFFFF),
                    valueColor:
                        AlwaysStoppedAnimation(Colors.deepPurpleAccent),
                    minHeight: 4,
                  ),
                ),
              ),
            ],
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0C10),
                      borderRadius: BorderRadius.circular(10),
                      border:
                          Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(_log,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: Colors.white70,
                              height: 1.5)),
                    ),
                  ),
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ─── Music Pack Install ───────────────────────────────────────────────────────

class _MusicPackInstallScreen extends StatefulWidget {
  const _MusicPackInstallScreen();

  @override
  State<_MusicPackInstallScreen> createState() => _MusicPackInstallScreenState();
}

class _MusicPackInstallScreenState extends State<_MusicPackInstallScreen> {
  bool _running = false;
  String _log = '';

  static const _zipUrl =
      'https://github.com/foclabroc/toolbox/releases/download/Fichiers/ost-pack.zip';
  static const _tmpZip = '/tmp/ost-pack.zip';
  static const _destDir = '/userdata';
  static const _installDir = '/userdata/music';

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes =
          await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) {
      return '';
    }
  }

  void _appendLog(String msg) => setState(() => _log += '$msg\n');

  Future<void> _launch() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.music_note_rounded, color: Colors.pinkAccent, size: 22),
          SizedBox(width: 10),
          Flexible(child: Text('Installer le Pack Music ?',
              overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ajoute 39 musiques de jeux vidéo dans /userdata/music pour une lecture aléatoire dans EmulationStation.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.pinkAccent.withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.pinkAccent.withOpacity(0.2)),
              ),
              child: const Row(children: [
                Icon(Icons.info_rounded, color: Colors.pinkAccent, size: 14),
                SizedBox(width: 6),
                Expanded(child: Text(
                  'Les musiques existantes dans /userdata/music ne seront pas supprimées.',
                  style: TextStyle(color: Colors.pinkAccent, fontSize: 11),
                )),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pinkAccent,
                foregroundColor: Colors.white),
            child: const Text('Installer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _running = true; _log = ''; });

    // 1. Téléchargement avec progression
    _appendLog('⬇️ Téléchargement du Pack Music...');
    _appendLog('  (39 titres OST)');

    await _exec('rm -f $_tmpZip /tmp/_music_wget_done');
    await _exec('wget -q --tries=3 --timeout=120 -O "$_tmpZip" "$_zipUrl" && touch /tmp/_music_wget_done || touch /tmp/_music_wget_done &');

    final totalRaw = await _exec(
        'wget --spider "$_zipUrl" 2>&1 | grep "Content-Length" | awk \'{print \$2}\' | tail -1');
    final totalBytes = int.tryParse(totalRaw.trim()) ?? 0;
    final totalMb = totalBytes > 0 ? (totalBytes / 1024 / 1024).toStringAsFixed(0) : '?';

    while (true) {
      if (!mounted) break;
      await Future.delayed(const Duration(seconds: 1));
      final sizeNowRaw = await _exec('stat -c%s "$_tmpZip" 2>/dev/null || echo 0');
      final sizeNow = int.tryParse(sizeNowRaw.trim()) ?? 0;
      final nowMb = (sizeNow / 1024 / 1024).toStringAsFixed(1);
      final pct = totalBytes > 0 ? (sizeNow * 100 ~/ totalBytes) : 0;
      final bar = totalBytes > 0 ? '$pct%' : '$nowMb Mo';
      setState(() {
        final lines = _log.split('\n');
        if (lines.length >= 2 && lines[lines.length - 2].startsWith('  ↓')) {
          lines[lines.length - 2] = '  ↓ $nowMb / $totalMb Mo  [$bar]';
          _log = lines.join('\n');
        } else {
          _log += '  ↓ $nowMb / $totalMb Mo  [$bar]\n';
        }
      });
      final done = await _exec('[ -f /tmp/_music_wget_done ] && echo yes || echo no');
      if (done.trim() == 'yes') break;
    }
    await _exec('rm -f /tmp/_music_wget_done');
    if (!mounted) return;

    final sizeRaw = await _exec('stat -c%s "$_tmpZip" 2>/dev/null || echo 0');
    final size = int.tryParse(sizeRaw.trim()) ?? 0;
    if (size < 100000) {
      _appendLog('❌ Téléchargement échoué.');
      await _exec('rm -f "$_tmpZip"');
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Téléchargement terminé (${(size / 1024 / 1024).toStringAsFixed(0)} Mo).");

    // 2. Extraction
    _appendLog('\n📦 Extraction dans $_installDir...');
    await _exec('unzip -o "$_tmpZip" -d "$_destDir" 2>&1');
    if (!mounted) return;
    _appendLog('✅ Extraction terminée.');

    // 3. Nettoyage
    _appendLog('\n🧹 Nettoyage...');
    await _exec('rm -f "$_tmpZip"');

    // 4. Rechargement
    _appendLog('🔄 Rechargement de la liste des jeux...');
    await _exec('curl -s http://127.0.0.1:1234/reloadgames');

    _appendLog('\n✅ Pack Music installé avec succès !');
    setState(() => _running = false);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Pack Music installé !')),
          ]),
          content: const Text(
            'Le Pack Music a été installé avec succès.\n39 musiques disponibles dans EmulationStation.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          actions: [
            ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK')),
          ],
        ),
      );
      if (mounted) setState(() => _log = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 24, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white54),
                ),
                const SizedBox(width: 12),
                Text('Pack Music',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontSize: 22)),
              ]),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Row(children: [
                      Icon(Icons.music_note_rounded,
                          color: Colors.pinkAccent, size: 20),
                      SizedBox(width: 8),
                      Text('Pack Music Foclabroc',
                          style: TextStyle(
                              color: Colors.pinkAccent,
                              fontWeight: FontWeight.w700,
                              fontSize: 15)),
                    ]),
                    const SizedBox(height: 10),
                    const Text(
                      'Pack de 39 musiques de jeux vidéo pour EmulationStation.\nLecture aléatoire dans le menu principal.',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in ['39 titres OST', 'EmulationStation', 'Lecture aléatoire'])
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.pinkAccent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: Colors.pinkAccent.withOpacity(0.25)),
                          ),
                          child: Text(e,
                              style: const TextStyle(
                                  color: Colors.pinkAccent,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.pinkAccent.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: Colors.pinkAccent.withOpacity(0.2)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.folder_rounded,
                            color: Colors.pinkAccent, size: 14),
                        SizedBox(width: 6),
                        Text('Destination : /userdata/music',
                            style: TextStyle(
                                color: Colors.pinkAccent, fontSize: 11, fontFamily: 'monospace')),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _running ? null : _launch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pinkAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          disabledBackgroundColor: Colors.white12,
                        ),
                        icon: _running
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.download_rounded),
                        label: Text(_running
                            ? 'Installation en cours...'
                            : 'Installer le Pack Music'),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            if (_running) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    backgroundColor: Color(0x14FFFFFF),
                    valueColor: AlwaysStoppedAnimation(Colors.pinkAccent),
                    minHeight: 4,
                  ),
                ),
              ),
            ],
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0A0C10),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.06)),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: Text(_log,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: Colors.white70,
                              height: 1.5)),
                    ),
                  ),
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ─── Windows Games ────────────────────────────────────────────────────────────

class _WindowsGamesScreen extends StatefulWidget {
  const _WindowsGamesScreen();
  @override
  State<_WindowsGamesScreen> createState() => _WindowsGamesScreenState();
}

class _WindowsGamesScreenState extends State<_WindowsGamesScreen> {
  bool _installing = false;
  String? _installingGame;
  String _log = '';

  static const _baseUrl =
      'https://raw.githubusercontent.com/foclabroc/toolbox/refs/heads/main/windows';

  static const _baseImgUrl =
      'https://raw.githubusercontent.com/foclabroc/toolbox/refs/heads/main/_images';
  static const _winDir = '/userdata/roms/windows';

  static const _games = [
    {'name': 'Celeste 64',             'desc': 'Le retour de Madeline mais en 3D.',                                 'size': '39.8 Mo',  'git': 'c64',          'script': 'c64.sh'},
    {'name': 'Celeste pico8',          'desc': 'Aidez Madeline à survivre au mont Celeste.',                        'size': '14.8 Mo',  'git': 'celeste',      'script': 'celeste.sh'},
    {'name': 'Crash Bandicoot bit',    'desc': 'Fan-Made avec éditeur de stage personnalisé.',                      'size': '230 Mo',   'git': 'cbit',         'script': 'cbit.sh'},
    {'name': 'Donkey Kong Advanced',   'desc': 'Un remake du jeu d\'arcade classique.',                            'size': '19.4 Mo',  'git': 'dka',          'script': 'dka.sh'},
    {'name': 'TMNT Rescue Palooza',    'desc': 'Beat-em-up dans l\'univers des Tortues Ninja.',                    'size': '168 Mo',   'git': 'tmntrp',       'script': 'tmntrp.sh'},
    {'name': 'Spelunky',               'desc': 'Jeu de plates-formes 2D, incarnez un spéléologue.',                'size': '24.2 Mo',  'git': 'spelunky',     'script': 'spelunky.sh'},
    {'name': 'Sonic Triple Trouble',   'desc': 'Fangame du jeu Game Gear Sonic Triple Trouble.',                    'size': '115 Mo',   'git': 'stt',          'script': 'stt.sh'},
    {'name': 'Pokemon Uranium',        'desc': 'Fangame Pokémon dans la région de Tandor.',                         'size': '332 Mo',   'git': 'pokeura',      'script': 'pokeura.sh'},
    {'name': 'MiniDoom 2',             'desc': 'DOOM transformé en jeu de plateforme d\'action.',                 'size': '114 Mo',   'git': 'minidoom2',    'script': 'minidoom2.sh'},
    {'name': 'AM2R',                   'desc': 'Another Metroid 2 Remake, remake non officiel.',                    'size': '85.6 Mo',  'git': 'am2r',         'script': 'am2r.sh'},
    {'name': 'Megaman X II',           'desc': 'Mega Man X Innocent Impulse FanGame style 8bits.',                  'size': '354 Mo',   'git': 'mmxii',        'script': 'mmxii.sh'},
    {'name': 'Super Tux Kart',         'desc': 'Mario Kart like open source avec mode online.',                     'size': '662 Mo',   'git': 'supertuxkart', 'script': 'supertuxkart.sh'},
    {'name': 'Streets of Rage R 5.2',  'desc': 'Remake de Street Of Rage 1/2/3 pour Windows.',                     'size': '331 Mo',   'git': 'sorr52',       'script': 'sorr52.sh'},
    {'name': 'Megaman 2.5D',           'desc': 'Fangame de Mega Man en 2.5D pour Windows.',                        'size': '855 Mo',   'git': 'megaman25',    'script': 'megaman25.sh'},
    {'name': 'Sonic Smackdown',        'desc': 'Fangame de combat dans l\'univers Sonic.',                        'size': '1.6 Go',   'git': 'sonicsmash',   'script': 'sonicsmash.sh'},
    {'name': 'Maldita Castilla',       'desc': 'Fanmade dans le style de Ghouls\'n Ghosts.',                      'size': '60.2 Mo',  'git': 'maldita',      'script': 'maldita.sh'},
    {'name': 'Super Smash Crusade',    'desc': 'Fanmade Super Smash Bros Crusade.',                                 'size': '1.45 Go',  'git': 'supersc',      'script': 'supersc.sh'},
    {'name': 'Rayman Redemption',      'desc': 'Fanmade Rayman Redemption.',                                        'size': '976 Mo',   'git': 'raymanr',      'script': 'raymanr.sh'},
    {'name': 'Power Bomberman',        'desc': 'Fanmade de Bomberman.',                                             'size': '616 Mo',   'git': 'powerb',       'script': 'powerb.sh'},
    {'name': 'Mushroom Kingdom Fusion','desc': 'Fanmade Mario croisé avec de nombreuses franchises.',               'size': '962 Mo',   'git': 'mushkf',       'script': 'mushkf.sh'},
    {'name': 'Dr. Robotnik\'s Racers','desc': 'Fanmade Mario Kart like dans l\'univers de Sonic.',               'size': '698 Mo',   'git': 'drrobo',       'script': 'drrobo.sh'},
  ];

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  Future<String> _execStream(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute('stdbuf -oL $cmd');
      String pending = '';
      await for (final chunk in session.stdout) {
        final text = String.fromCharCodes(chunk);
        pending += text;
        final lines = pending.split('\n');
        pending = lines.removeLast();
        for (final line in lines) {
          final t = line.trim();
          if (t.isNotEmpty && mounted) setState(() => _log += '  $t\n');
        }
      }
      if (pending.trim().isNotEmpty && mounted) {
        setState(() => _log += '  ${pending.trim()}\n');
      }
      await session.done;
      return '';
    } catch (_) { return ''; }
  }

  void _appendLog(String msg) => setState(() => _log += '$msg\n');

  Future<void> _installGame(Map<String, String> game) async {
    final name = game['name']!;
    final size = game['size']!;
    final git  = game['git']!;
    final script = game['script']!;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Row(children: [
          const Icon(Icons.videogame_asset_rounded, color: Colors.orangeAccent, size: 22),
          const SizedBox(width: 10),
          Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(game['desc']!,
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.5)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orangeAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.storage_rounded, color: Colors.orangeAccent, size: 14),
              const SizedBox(width: 6),
              Text('Taille : $size', style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
            child: const Text('Installer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _installing = true; _installingGame = name; _log = ''; });

    // 1. Récupère l'URL de téléchargement depuis le script bash
    _appendLog('🔍 Récupération de l\'URL...');
    final scriptUrl = '$_baseUrl/$script';
    final urlRaw = await _exec(
      'curl -sL "$scriptUrl" | grep -m1 \'URL_TELECHARGEMENT=\' | head -1 | sed \'s/.*URL_TELECHARGEMENT="\\(.*\\)"/\\1/\''
    );
    final fileUrl = urlRaw.trim();
    if (fileUrl.isEmpty || !fileUrl.startsWith('http')) {
      _appendLog('❌ Impossible de récupérer l\'URL depuis le script.');
      setState(() { _installing = false; _installingGame = null; });
      return;
    }
    _appendLog('✅ URL : $fileUrl');

    // Récupère aussi l'URL du fichier .keys si présent
    final keyUrlRaw = await _exec(
      'curl -sL "$scriptUrl" | grep -m1 \'URL_TELECHARGEMENT_KEY=\' | head -1 | sed \'s/.*URL_TELECHARGEMENT_KEY="\\(.*\\)"/\\1/\''
    );
    final keyUrl = keyUrlRaw.trim();

    // Récupère le GIT_NAME depuis le script (utilisé pour les images)
    final gitNameRaw = await _exec(
      'curl -sL "$scriptUrl" | grep -m1 \'GIT_NAME=\' | head -1 | sed \'s/.*GIT_NAME="\\(.*\\)"/\\1/\''
    );
    final gitName = gitNameRaw.trim().isNotEmpty ? gitNameRaw.trim() : git;

    final fileName = fileUrl.split('/').last;
    final destFile = '$_winDir/$fileName';
    final ext = fileName.contains('.wsquashfs') ? 'wsquashfs' : 'zip';

    // Télécharge le script sur Batocera et extrait les métadonnées directement (pas de transit Dart)
    await _exec('curl -sL "$scriptUrl" > /tmp/_wgame_script.sh 2>/dev/null');
    await _exec('grep -m1 "^DESC=" /tmp/_wgame_script.sh | cut -d\'"\' -f2 > /tmp/_game_desc.txt');
    await _exec('grep -m1 "^DEV=" /tmp/_wgame_script.sh | cut -d\'"\' -f2 > /tmp/_game_dev.txt');
    await _exec('grep -m1 "^PUBLISH=" /tmp/_wgame_script.sh | cut -d\'"\' -f2 > /tmp/_game_pub.txt');
    await _exec('grep -m1 "^GENRE=" /tmp/_wgame_script.sh | cut -d\'"\' -f2 > /tmp/_game_genre.txt');
    await _exec('grep -m1 "^GAME_FILE_FINAL=" /tmp/_wgame_script.sh | cut -d\'"\' -f2 > /tmp/_game_file_final.txt');
    final gameFileFinal = (await _exec('cat /tmp/_game_file_final.txt')).trim();
    // Détermine le path gamelist : GAME_FILE_FINAL en priorité, sinon fileName (wsquashfs) ou git (zip)
    String gameFinalStr;
    if (gameFileFinal.isNotEmpty) {
      gameFinalStr = './$gameFileFinal';
    } else if (ext == 'wsquashfs') {
      gameFinalStr = './$fileName';
    } else {
      gameFinalStr = './$git';
    }
    _appendLog('📝 Path gamelist : $gameFinalStr');

    // 2. Supprime l'ancien fichier si existant
    _appendLog('🗑️ Suppression de l\'ancienne version...');
    await _exec('rm -f "$destFile" "$_winDir/$git" 2>/dev/null; rm -rf "$_winDir/${git}_dir" 2>/dev/null');

    // 2. Téléchargement avec progression
    _appendLog("\n⬇️ Téléchargement de $name...");
    _appendLog('  ($size)');

    await _exec('rm -f /tmp/_wgame_done');
    await _exec('curl -sL --retry 3 --max-time 600 -o "$destFile" "$fileUrl" && touch /tmp/_wgame_done || touch /tmp/_wgame_done &');

    final totalRaw = await _exec(
        'curl -sIL "$fileUrl" | grep -i content-length | tail -1 | awk \'{print \$2}\' | tr -d \$\'\\r\'');
    final totalBytes = int.tryParse(totalRaw.trim()) ?? 0;
    final totalMb = totalBytes > 0 ? (totalBytes / 1024 / 1024).toStringAsFixed(0) : '?';

    while (true) {
      if (!mounted) break;
      await Future.delayed(const Duration(seconds: 1));
      final sizeNowRaw = await _exec('stat -c%s "$destFile" 2>/dev/null || echo 0');
      final sizeNow = int.tryParse(sizeNowRaw.trim()) ?? 0;
      final nowMb = (sizeNow / 1024 / 1024).toStringAsFixed(1);
      final pct = totalBytes > 0 ? (sizeNow * 100 ~/ totalBytes) : 0;
      final bar = totalBytes > 0 ? '$pct%' : '$nowMb Mo';
      setState(() {
        final lines = _log.split('\n');
        if (lines.length >= 2 && lines[lines.length - 2].startsWith('  ↓')) {
          lines[lines.length - 2] = '  ↓ $nowMb / $totalMb Mo  [$bar]';
          _log = lines.join('\n');
        } else {
          _log += '  ↓ $nowMb / $totalMb Mo  [$bar]\n';
        }
      });
      final done = await _exec('[ -f /tmp/_wgame_done ] && echo yes || echo no');
      if (done.trim() == 'yes') break;
    }
    await _exec('rm -f /tmp/_wgame_done');
    if (!mounted) return;

    final szRaw = await _exec('stat -c%s "$destFile" 2>/dev/null || echo 0');
    final sz = int.tryParse(szRaw.trim()) ?? 0;
    if (sz < 100000) {
      _appendLog('❌ Téléchargement échoué.');
      await _exec('rm -f "$destFile"');
      setState(() { _installing = false; _installingGame = null; });
      return;
    }
    _appendLog("✅ Téléchargement terminé (\${(sz / 1024 / 1024).toStringAsFixed(0)} Mo).");

    // 3. Extraction si zip
    if (ext == 'zip') {
      _appendLog('\n📦 Extraction...');
      await _exec('unzip -o "$destFile" -d "$_winDir/" 2>&1 && rm -f "$destFile"');
      if (!mounted) return;
      _appendLog('✅ Extraction terminée.');
    }

    // 4. Téléchargement du fichier .keys si présent
    if (keyUrl.isNotEmpty && keyUrl.startsWith('http')) {
      _appendLog('\n🔑 Téléchargement du fichier .keys...');
      final keyFileName = keyUrl.split('/').last;
      await _exec('curl -sL "$keyUrl" -o "$_winDir/$keyFileName"');
      _appendLog('✅ Fichier .keys téléchargé.');
    }

    // 5. Téléchargement images + vidéo gamelist
    _appendLog('\n🖼️ Téléchargement des images...');
    final imgDir = '$_winDir/images';
    final vidDir = '$_winDir/videos';
    await _exec('mkdir -p "$imgDir" "$vidDir"');
    await _exec('curl -sL -o "$imgDir/$gitName-s.png" "$_baseImgUrl/$gitName-s.png" 2>/dev/null');
    await _exec('curl -sL -o "$imgDir/$gitName-w.png" "$_baseImgUrl/$gitName-w.png" 2>/dev/null');
    await _exec('curl -sL -o "$imgDir/$gitName-b.png" "$_baseImgUrl/$gitName-b.png" 2>/dev/null');
    await _exec('curl -sL -o "$vidDir/$gitName-v.mp4" "$_baseImgUrl/$gitName-v.mp4" 2>/dev/null');
    if (!mounted) return;

    // 6. Mise à jour gamelist
    _appendLog('📋 Mise à jour du gamelist...');
    final gamelistFile = '$_winDir/gamelist.xml';
    final xmlBin = '/userdata/system/pro/extra/xmlstarlet';
    final xmlLink = '/usr/bin/xmlstarlet';
    final gameFinal = gameFinalStr;
    await _exec('[ -f "$gamelistFile" ] || echo \'<?xml version="1.0" encoding="UTF-8"?><gameList></gameList>\' > "$gamelistFile"');
    await _exec('[ -f "$xmlBin" ] || (mkdir -p /userdata/system/pro/extra && curl -sL "https://github.com/foclabroc/toolbox/raw/refs/heads/main/app/xmlstarlet" -o "$xmlBin" && chmod +x "$xmlBin" && ln -sf "$xmlBin" "$xmlLink")');
    await _exec('[ -L "$xmlLink" ] || ln -sf "$xmlBin" "$xmlLink"');
    // Écrit gameFinal et name dans des fichiers temp pour gérer les espaces/apostrophes
    await _exec('printf "%s" "$gameFinal" > /tmp/_game_path.txt');
    await _exec('printf "%s" "$name" > /tmp/_game_name.txt');
    // Écrit le script xmlstarlet via printf (évite les problèmes de heredoc SSH)
    await _exec('printf "#!/bin/bash\\n" > /tmp/_xmladd.sh');
    await _exec('printf "GL=\\"%s\\"\\n" "$gamelistFile" >> /tmp/_xmladd.sh');
    await _exec('printf "GP=\\"\$(cat /tmp/_game_path.txt)\\"\\n" >> /tmp/_xmladd.sh');
    await _exec('printf "GN=\\"\$(cat /tmp/_game_name.txt)\\"\\n" >> /tmp/_xmladd.sh');
    await _exec('printf "DESC=\\"\$(cat /tmp/_game_desc.txt)\\"\\n" >> /tmp/_xmladd.sh');
    await _exec('printf "DEV=\\"\$(cat /tmp/_game_dev.txt)\\"\\n" >> /tmp/_xmladd.sh');
    await _exec('printf "PUB=\\"\$(cat /tmp/_game_pub.txt)\\"\\n" >> /tmp/_xmladd.sh');
    await _exec('printf "GENRE=\\"\$(cat /tmp/_game_genre.txt)\\"\\n" >> /tmp/_xmladd.sh');
    await _exec('printf "IMG=\\"./images/$gitName-s.png\\"\\n" >> /tmp/_xmladd.sh');
    await _exec('printf "VID=\\"./videos/$gitName-v.mp4\\"\\n" >> /tmp/_xmladd.sh');
    await _exec('printf "MARQ=\\"./images/$gitName-w.png\\"\\n" >> /tmp/_xmladd.sh');
    await _exec('printf "THUMB=\\"./images/$gitName-b.png\\"\\n" >> /tmp/_xmladd.sh');
    await _exec('printf "xmlstarlet ed -L -d \\"/gameList/game[path=\\\\\\"\\\$GP\\\\\\"]\\" \\"\\\$GL\\" 2>/dev/null\\n" >> /tmp/_xmladd.sh');
    await _exec('printf "xmlstarlet ed -L -s \\"/gameList\\" -t elem -n \\"game\\" -v \\"\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"path\\" -v \\"\\\$GP\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"name\\" -v \\"\\\$GN\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"desc\\" -v \\"\\\$DESC\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"image\\" -v \\"\\\$IMG\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"video\\" -v \\"\\\$VID\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"marquee\\" -v \\"\\\$MARQ\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"thumbnail\\" -v \\"\\\$THUMB\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"rating\\" -v \\"1.00\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"developer\\" -v \\"\\\$DEV\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"publisher\\" -v \\"\\\$PUB\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"genre\\" -v \\"\\\$GENRE\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"lang\\" -v \\"fr\\" -s \\"/gameList/game[last()]\\" -t elem -n \\"region\\" -v \\"eu\\" \\"\\\$GL\\" 2>/dev/null || true\\n" >> /tmp/_xmladd.sh');
    await _exec('chmod +x /tmp/_xmladd.sh && bash /tmp/_xmladd.sh');
    await _exec('rm -f /tmp/_game_desc.txt /tmp/_game_dev.txt /tmp/_game_pub.txt /tmp/_game_genre.txt /tmp/_game_file_final.txt /tmp/_game_path.txt /tmp/_game_name.txt /tmp/_xmladd.sh /tmp/_wgame_script.sh');

    // 6. Rechargement
    _appendLog('🔄 Rechargement de la liste des jeux...');
    await _exec('curl -s http://127.0.0.1:1234/reloadgames');

    _appendLog("\n✅ $name installe avec succes !");
    setState(() { _installing = false; _installingGame = null; });

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Installation terminée !')),
          ]),
          content: Text('$name a été installé avec succès.',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      if (mounted) setState(() => _log = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 24, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white54),
                ),
                const SizedBox(width: 12),
                Text('Jeux Windows',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
                const Spacer(),
                if (_installing)
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
              child: Text('${_games.length} jeux disponibles',
                  style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ),
            Expanded(
              child: Column(children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    itemCount: _games.length,
                    itemBuilder: (_, i) {
                      final g = _games[i];
                      final isInstalling = _installingGame == g['name'];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _installing ? null : () => _installGame(g),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(children: [
                              Container(
                                width: 38, height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: isInstalling
                                    ? const Padding(
                                        padding: EdgeInsets.all(9),
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent))
                                    : const Icon(Icons.videogame_asset_rounded,
                                        color: Colors.orangeAccent, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(g['name']!,
                                    style: TextStyle(
                                        color: _installing && !isInstalling ? Colors.white38 : Colors.white,
                                        fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(g['desc']!,
                                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ])),
                              const SizedBox(width: 8),
                              Text(g['size']!,
                                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 10,
                                      fontWeight: FontWeight.w600)),
                              const SizedBox(width: 6),
                              const Icon(Icons.download_rounded, size: 16, color: Colors.white24),
                            ]),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                if (_installing) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: const LinearProgressIndicator(
                        backgroundColor: Color(0x14FFFFFF),
                        valueColor: AlwaysStoppedAnimation(Colors.orangeAccent),
                        minHeight: 4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                ],
                if (_log.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 130),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0C10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: Text(_log,
                            style: const TextStyle(fontFamily: 'monospace',
                                fontSize: 10, color: Colors.white70, height: 1.5)),
                      ),
                    ),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
