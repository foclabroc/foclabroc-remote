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
                    subtitle: 'Install the NES 3D pack\n(auto-detects V40/41/42/43)',
                    color: Colors.tealAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _Nes3dInstallScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _FoclabrocToolCard(
                    icon: Icons.tv_rounded,
                    title: 'Pack Kodi',
                    subtitle: 'Install the Foclabroc Kodi pack\n(Vstream, IPTV...)',
                    color: Colors.deepPurpleAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _KodiInstallScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _FoclabrocToolCard(
                    icon: Icons.music_note_rounded,
                    title: 'Pack Music',
                    subtitle: '39 OST tracks for EmulationStation\n(random play)',
                    color: Colors.pinkAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _MusicPackInstallScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _FoclabrocToolCard(
                    icon: Icons.videogame_asset_rounded,
                    title: 'Windows Games',
                    subtitle: '21 free fangames & remakes\nfor Batocera Windows',
                    color: Colors.orangeAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _WindowsGamesScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _FoclabrocToolCard(
                    icon: Icons.play_circle_rounded,
                    title: 'YouTube TV',
                    subtitle: 'Install YouTube TV in Ports\n(Batocera x86_64)',
                    color: Colors.redAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _YoutubeTvInstallScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _FoclabrocToolCard(
                    icon: Icons.build_rounded,
                    title: 'Foclabroc Toolbox → Ports',
                    subtitle: 'Install the Toolbox in Ports\nto access it from Batocera',
                    color: Colors.amberAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _FoclabrocToolboxInstallScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _FoclabrocToolCard(
                    icon: Icons.archive_rounded,
                    title: 'RGSX',
                    subtitle: 'Install RetroGameSets game downloader\nin Ports',
                    color: Colors.cyanAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _RgsxInstallScreen(),
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
          Flexible(child: Text('Install NES3D ?', overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Downloads and installs the NES3D pack for your Batocera version.',
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
                  'Required space: ~3.8 GB. Old NES3D files will be deleted.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                )),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _running = true; _log = ''; });

    // 1. Détecter la version
    _appendLog('🔍 Detecting Batocera version...');
    final versionRaw = await _exec(
        "batocera-es-swissknife --version | awk '{print \$1}' | sed -E 's/^([0-9]+).*/\\1/'");
    final version = int.tryParse(versionRaw.trim()) ?? 0;
    if (version == 0) {
      _appendLog('❌ Unable to detect Batocera version.');
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Batocera V$version detected.");

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
    _appendLog("📦 Archive: $archiveName");

    // 3. Espace disque
    _appendLog('\n💾 Checking disk space...');
    final freeRaw = await _exec("df -m /userdata | awk 'NR==2 {print \$4}'");
    final freeMb = int.tryParse(freeRaw.trim()) ?? 0;
    const requiredMb = 3800;
    if (freeMb < requiredMb) {
      _appendLog("❌ Not enough space: $freeMb MB / $requiredMb MB required.");
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Enough space: $freeMb MB available.");

    // 4. Suppression anciens fichiers
    _appendLog('\n🗑️ Removing old NES3D files...');
    await _exec(
      'rm -f /userdata/system/configs/evmapy/3dnes.keys '
      '/userdata/system/configs/emulationstation/es_features_3dnes.cfg '
      '/userdata/system/configs/emulationstation/es_systems_3dnes.cfg && '
      'rm -rf /userdata/system/3dnes /userdata/system/nes3d '
      '/userdata/roms/nes3d /userdata/system/wine-bottles/3dnes '
      '/userdata/system/wine-bottles/nes3d',
    );
    _appendLog('✅ Old files removed.');

    // 5. Téléchargement
    _appendLog("\n⬇️ Downloading $archiveName...");
    _appendLog('  (may take several minutes)');

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
      final bar = totalBytes > 0 ? '$pct%' : '$nowMb MB';
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
      _appendLog('❌ Download failed.');
      await _exec('rm -f "/userdata/$archiveName"');
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Download complete (${(size / 1024 / 1024).toStringAsFixed(0)} MB).");

    // 6. Extraction
    _appendLog('\n📦 Extracting...');
    await _exec('unzip -o "/userdata/$archiveName" -d "/userdata/" 2>&1');
    if (!mounted) return;
    _appendLog('✅ Extraction complete.');

    // 7. Nettoyage
    _appendLog('\n🧹 Cleaning up...');
    await _exec('rm -f "/userdata/$archiveName"');

    // 8. Rechargement
    _appendLog('🔄 Reloading game list...');
    await _exec('curl -s http://127.0.0.1:1234/reloadgames');

    _appendLog('\n✅ NES3D installation complete!');
    setState(() => _running = false);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('NES3D installed!')),
          ]),
          content: const Text(
            'NES3D pack installed successfully.\nGame list has been reloaded.',
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
                  onTap: () => Navigator.maybePop(context),
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
                      'Automatically detects your Batocera version and downloads the matching pack.',
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
                        label: Text(_running ? 'Installing...' : 'Install NES3D'),
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
          Flexible(child: Text('Install Kodi Pack ?',
              overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Installs the Foclabroc Kodi pack (Vstream, IPTV...).',
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
                  'The .kodi folder will be completely deleted and replaced.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 11),
                )),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurpleAccent,
                foregroundColor: Colors.white),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _running = true; _log = ''; });

    // 1. Suppression ancien dossier
    _appendLog('🗑️ Suppression de $_kodiDir...');
    await _exec('rm -rf "$_kodiDir"');
    _appendLog('✅ Folder removed.');

    // 2. Téléchargement avec progression
    _appendLog('\n⬇️ Downloading Kodi pack...');
    _appendLog('  (may take several minutes)');

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
      final bar = totalBytes > 0 ? '$pct%' : '$nowMb MB';
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
      _appendLog('❌ Download failed.');
      await _exec('rm -f "$_tmpZip"');
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Download complete (${(size / 1024 / 1024).toStringAsFixed(0)} MB).");

    // 3. Extraction
    _appendLog('\n📦 Extracting...');
    await _exec('unzip -o "$_tmpZip" -d /userdata/system/ 2>&1');
    if (!mounted) return;
    _appendLog('✅ Extraction complete.');

    // 4. Nettoyage
    _appendLog('\n🧹 Cleaning up...');
    await _exec('rm -f "$_tmpZip"');

    _appendLog('\n✅ Kodi pack installed successfully!');
    setState(() => _running = false);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Kodi pack installed!')),
          ]),
          content: const Text(
            'The Kodi pack was installed successfully.',
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
                  onTap: () => Navigator.maybePop(context),
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
                      'Installs Foclabroc\'s Kodi config with Vstream, IPTV and other add-ons.',
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
                            'Completely replaces the existing .kodi folder',
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
                            ? 'Install in progress...'
                            : 'Install Kodi Pack'),
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
          Flexible(child: Text('Install Music Pack ?',
              overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Adds 39 video game tracks to /userdata/music for random playback in EmulationStation.',
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
                  'Existing music in /userdata/music will not be deleted.',
                  style: TextStyle(color: Colors.pinkAccent, fontSize: 11),
                )),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pinkAccent,
                foregroundColor: Colors.white),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _running = true; _log = ''; });

    // 1. Téléchargement avec progression
    _appendLog('⬇️ Downloading Music Pack...');
    _appendLog('  (39 OST tracks)');

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
      final bar = totalBytes > 0 ? '$pct%' : '$nowMb MB';
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
      _appendLog('❌ Download failed.');
      await _exec('rm -f "$_tmpZip"');
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Download complete (${(size / 1024 / 1024).toStringAsFixed(0)} MB).");

    // 2. Extraction
    _appendLog('\n📦 Extraction dans $_installDir...');
    await _exec('unzip -o "$_tmpZip" -d "$_destDir" 2>&1');
    if (!mounted) return;
    _appendLog('✅ Extraction complete.');

    // 3. Nettoyage
    _appendLog('\n🧹 Cleaning up...');
    await _exec('rm -f "$_tmpZip"');

    // 4. Rechargement
    _appendLog('🔄 Reloading game list...');
    await _exec('curl -s http://127.0.0.1:1234/reloadgames');

    _appendLog('\n✅ Music Pack installed successfully!');
    setState(() => _running = false);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Music Pack installed!')),
          ]),
          content: const Text(
            'Music Pack installed successfully.\n39 tracks available in EmulationStation.',
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
                  onTap: () => Navigator.maybePop(context),
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
                      'Pack of 39 video game tracks for EmulationStation.\nRandom playback in the main menu.',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in ['39 OST tracks', 'EmulationStation', 'Random play'])
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
                            ? 'Install in progress...'
                            : 'Install Music Pack'),
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
    {'name': 'Celeste 64',             'desc': 'Madeline\'s return but in 3D.',                                 'size': '39.8 MB',  'git': 'c64',          'script': 'c64.sh'},
    {'name': 'Celeste pico8',          'desc': 'Help Madeline survive Celeste Mountain.',                        'size': '14.8 MB',  'git': 'celeste',      'script': 'celeste.sh'},
    {'name': 'Crash Bandicoot bit',    'desc': 'Fan-Made with custom stage editor.',                      'size': '230 MB',   'git': 'cbit',         'script': 'cbit.sh'},
    {'name': 'Donkey Kong Advanced',   'desc': 'A remake of the classic arcade game.',                            'size': '19.4 MB',  'git': 'dka',          'script': 'dka.sh'},
    {'name': 'TMNT Rescue Palooza',    'desc': 'Beat-em-up in the TMNT universe.',                    'size': '168 MB',   'git': 'tmntrp',       'script': 'tmntrp.sh'},
    {'name': 'Spelunky',               'desc': '2D platformer, play as a spelunker.',                'size': '24.2 MB',  'git': 'spelunky',     'script': 'spelunky.sh'},
    {'name': 'Sonic Triple Trouble',   'desc': 'Fangame of the Game Gear Sonic Triple Trouble.',                    'size': '115 MB',   'git': 'stt',          'script': 'stt.sh'},
    {'name': 'Pokemon Uranium',        'desc': 'Pokemon fangame set in the Tandor region.',                         'size': '332 MB',   'git': 'pokeura',      'script': 'pokeura.sh'},
    {'name': 'MiniDoom 2',             'desc': 'DOOM transformed into an action platformer.',                 'size': '114 MB',   'git': 'minidoom2',    'script': 'minidoom2.sh'},
    {'name': 'AM2R',                   'desc': 'Another Metroid 2 Remake, unofficial remake.',                    'size': '85.6 MB',  'git': 'am2r',         'script': 'am2r.sh'},
    {'name': 'Megaman X II',           'desc': 'Mega Man X Innocent Impulse FanGame, 8-bit style.',                  'size': '354 MB',   'git': 'mmxii',        'script': 'mmxii.sh'},
    {'name': 'Super Tux Kart',         'desc': 'Open source Mario Kart-like with online mode.',                     'size': '662 MB',   'git': 'supertuxkart', 'script': 'supertuxkart.sh'},
    {'name': 'Streets of Rage R 5.2',  'desc': 'Remake of Streets of Rage 1/2/3 for Windows.',                     'size': '331 MB',   'git': 'sorr52',       'script': 'sorr52.sh'},
    {'name': 'Megaman 2.5D',           'desc': 'Mega Man fangame in 2.5D for Windows.',                        'size': '855 MB',   'git': 'megaman25',    'script': 'megaman25.sh'},
    {'name': 'Sonic Smackdown',        'desc': 'Fighting fangame in the Sonic universe.',                        'size': '1.6 GB',   'git': 'sonicsmash',   'script': 'sonicsmash.sh'},
    {'name': 'Maldita Castilla',       'desc': 'Fanmade in the style of Ghouls\'n Ghosts.',                      'size': '60.2 MB',  'git': 'maldita',      'script': 'maldita.sh'},
    {'name': 'Super Smash Crusade',    'desc': 'Super Smash Bros Crusade fangame.',                                 'size': '1.45 GB',  'git': 'supersc',      'script': 'supersc.sh'},
    {'name': 'Rayman Redemption',      'desc': 'Rayman Redemption fangame.',                                        'size': '976 MB',   'git': 'raymanr',      'script': 'raymanr.sh'},
    {'name': 'Power Bomberman',        'desc': 'Bomberman fangame.',                                             'size': '616 MB',   'git': 'powerb',       'script': 'powerb.sh'},
    {'name': 'Mushroom Kingdom Fusion','desc': 'Mario fangame crossed with many other franchises.',               'size': '962 MB',   'git': 'mushkf',       'script': 'mushkf.sh'},
    {'name': 'Dr. Robotnik\'s Racers','desc': 'Mario Kart-like fangame in the Sonic universe.',               'size': '698 MB',   'git': 'drrobo',       'script': 'drrobo.sh'},
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
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _installing = true; _installingGame = name; _log = ''; });

    // 1. Récupère l'URL de téléchargement depuis le script bash
    _appendLog('🔍 Fetching URL...');
    final scriptUrl = '$_baseUrl/$script';
    final urlRaw = await _exec(
      'curl -sL "$scriptUrl" | grep -m1 \'URL_TELECHARGEMENT=\' | head -1 | sed \'s/.*URL_TELECHARGEMENT="\\(.*\\)"/\\1/\''
    );
    final fileUrl = urlRaw.trim();
    if (fileUrl.isEmpty || !fileUrl.startsWith('http')) {
      _appendLog('❌ Unable to fetch URL from script.');
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
    _appendLog('🗑️ Removing old version...');
    await _exec('rm -f "$destFile" "$_winDir/$git" 2>/dev/null; rm -rf "$_winDir/${git}_dir" 2>/dev/null');

    // 2. Téléchargement avec progression
    _appendLog("\n⬇️ Downloading $name...");
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
      final bar = totalBytes > 0 ? '$pct%' : '$nowMb MB';
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
      _appendLog('❌ Download failed.');
      await _exec('rm -f "$destFile"');
      setState(() { _installing = false; _installingGame = null; });
      return;
    }
    _appendLog("✅ Download complete (\${(sz / 1024 / 1024).toStringAsFixed(0)} MB).");

    // 3. Extraction si zip
    if (ext == 'zip') {
      _appendLog('\n📦 Extracting...');
      await _exec('unzip -o "$destFile" -d "$_winDir/" 2>&1 && rm -f "$destFile"');
      if (!mounted) return;
      _appendLog('✅ Extraction complete.');
    }

    // 4. Téléchargement du fichier .keys si présent
    if (keyUrl.isNotEmpty && keyUrl.startsWith('http')) {
      _appendLog('\n🔑 Downloading .keys file...');
      final keyFileName = keyUrl.split('/').last;
      await _exec('curl -sL "$keyUrl" -o "$_winDir/$keyFileName"');
      _appendLog('✅ .keys file downloaded.');
    }

    // 5. Téléchargement images + vidéo gamelist
    _appendLog('\n🖼️ Downloading images...');
    final imgDir = '$_winDir/images';
    final vidDir = '$_winDir/videos';
    await _exec('mkdir -p "$imgDir" "$vidDir"');
    await _exec('curl -sL -o "$imgDir/$gitName-s.png" "$_baseImgUrl/$gitName-s.png" 2>/dev/null');
    await _exec('curl -sL -o "$imgDir/$gitName-w.png" "$_baseImgUrl/$gitName-w.png" 2>/dev/null');
    await _exec('curl -sL -o "$imgDir/$gitName-b.png" "$_baseImgUrl/$gitName-b.png" 2>/dev/null');
    await _exec('curl -sL -o "$vidDir/$gitName-v.mp4" "$_baseImgUrl/$gitName-v.mp4" 2>/dev/null');
    if (!mounted) return;

    // 6. Mise à jour gamelist
    _appendLog('📋 Updating gamelist...');
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
    _appendLog('🔄 Reloading game list...');
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
            Flexible(child: Text('Installation complete!')),
          ]),
          content: Text('$name installed successfully.',
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
                  onTap: () => Navigator.maybePop(context),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white54),
                ),
                const SizedBox(width: 12),
                Text('Windows Games',
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

// ─── YouTube TV Install ────────────────────────────────────────────────────────

class _YoutubeTvInstallScreen extends StatefulWidget {
  const _YoutubeTvInstallScreen();
  @override
  State<_YoutubeTvInstallScreen> createState() => _YoutubeTvInstallScreenState();
}

class _YoutubeTvInstallScreenState extends State<_YoutubeTvInstallScreen> {
  bool _running = false;
  String _log = '';

  static const _appUrl =
      'https://github.com/foclabroc/toolbox/raw/refs/heads/main/youtubetv/extra/YouTubeonTV-linux-x64.zip';
  static const _depUrl =
      'https://github.com/foclabroc/toolbox/raw/refs/heads/main/gparted/extra/dep.zip';
  static const _keysUrl =
      'https://raw.githubusercontent.com/foclabroc/toolbox/refs/heads/main/youtubetv/extra/YoutubeTV.sh.keys';
  static const _imgBase =
      'https://raw.githubusercontent.com/foclabroc/toolbox/refs/heads/main/youtubetv/extra';
  static const _appDir = '/userdata/system/pro/youtubetv';
  static const _portsDir = '/userdata/roms/ports';

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  void _appendLog(String msg) => setState(() => _log += '$msg\n');

  Future<void> _launch() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.play_circle_rounded, color: Colors.redAccent, size: 22),
          SizedBox(width: 10),
          Flexible(child: Text('Install YouTube TV?', overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Installs YouTube TV in the Batocera Ports menu.',
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
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 14),
              SizedBox(width: 6),
              Expanded(child: Text(
                'Batocera x86_64 only.',
                style: TextStyle(color: Colors.redAccent, fontSize: 11),
              )),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _running = true; _log = ''; });

    // 1. Suppression ancienne installation
    _appendLog('🗑️ Removing old installation...');
    await _exec('rm -rf $_appDir /userdata/system/pro/youtube-tv 2>/dev/null');
    await _exec('mkdir -p "$_appDir/temp"');

    // 2. Téléchargement de l\'app avec progression
    _appendLog('\n⬇️ Downloading YouTube TV...');
    final tmpZip = '$_appDir/temp/youtube-tv.zip';
    await _exec('rm -f /tmp/_ytv_done');
    await _exec('wget -q --tries=3 --timeout=120 -O "$tmpZip" "$_appUrl" && touch /tmp/_ytv_done || touch /tmp/_ytv_done &');

    final totalRaw = await _exec(
        'curl -sIL "$_appUrl" | grep -i content-length | tail -1 | awk \'{print \$2}\' | tr -d \$\'\\r\'');
    final totalBytes = int.tryParse(totalRaw.trim()) ?? 0;
    final totalMb = totalBytes > 0 ? (totalBytes / 1024 / 1024).toStringAsFixed(0) : '?';

    while (true) {
      if (!mounted) break;
      await Future.delayed(const Duration(seconds: 1));
      final szRaw = await _exec('stat -c%s "$tmpZip" 2>/dev/null || echo 0');
      final sz = int.tryParse(szRaw.trim()) ?? 0;
      final nowMb = (sz / 1024 / 1024).toStringAsFixed(1);
      final pct = totalBytes > 0 ? (sz * 100 ~/ totalBytes) : 0;
      final bar = totalBytes > 0 ? '$pct%' : '$nowMb MB';
      setState(() {
        final lines = _log.split('\n');
        if (lines.length >= 2 && lines[lines.length - 2].startsWith('  ↓')) {
          lines[lines.length - 2] = '  ↓ $nowMb / $totalMb Mo  [$bar]';
          _log = lines.join('\n');
        } else {
          _log += '  ↓ $nowMb / $totalMb Mo  [$bar]\n';
        }
      });
      final done = await _exec('[ -f /tmp/_ytv_done ] && echo yes || echo no');
      if (done.trim() == 'yes') break;
    }
    await _exec('rm -f /tmp/_ytv_done');
    if (!mounted) return;

    final szCheck = int.tryParse((await _exec('stat -c%s "$tmpZip" 2>/dev/null || echo 0')).trim()) ?? 0;
    if (szCheck < 100000) {
      _appendLog('❌ Download failed.');
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Download complete (${(szCheck / 1024 / 1024).toStringAsFixed(0)} MB).");

    // 3. Extraction
    _appendLog('\n📦 Extracting...');
    await _exec('unzip -o "$tmpZip" -d "$_appDir/temp/extracted" 2>/dev/null');
    await _exec('mv "$_appDir/temp/extracted/"*/* "$_appDir/" 2>/dev/null || true');
    await _exec('chmod a+x "$_appDir/YouTubeonTV" 2>/dev/null || true');
    _appendLog('✅ Extraction complete.');

    // 4. Création du Launcher
    _appendLog('\n🔧 Creating Launcher...');
    await _exec(
      'printf "%s\\n" "#!/bin/bash" > "$_appDir/Launcher" && '
      'printf "%s\\n" "unclutter-remote -s" >> "$_appDir/Launcher" && '
      'printf "%s\\n" "sed -i \\"s,!appArgs.disableOldBuildWarning,1 == 0,g\\" /userdata/system/pro/youtubetv/resources/app/lib/main.js 2>/dev/null" >> "$_appDir/Launcher" && '
      'printf "%s\\n" "mkdir /userdata/system/pro/youtubetv/home 2>/dev/null; mkdir /userdata/system/pro/youtubetv/config 2>/dev/null" >> "$_appDir/Launcher" && '
      'printf "%s\\n" \'LD_LIBRARY_PATH="/userdata/system/pro/.dep:\${LD_LIBRARY_PATH}" HOME=/userdata/system/pro/youtubetv/home XDG_CONFIG_HOME=/userdata/system/pro/youtubetv/config QT_SCALE_FACTOR="1" GDK_SCALE="1" XDG_DATA_HOME=/userdata/system/pro/youtubetv/home DISPLAY=:0.0 /userdata/system/pro/youtubetv/YouTubeonTV --no-sandbox --test-type "\${@}"\' >> "$_appDir/Launcher" && '
      'chmod a+x "$_appDir/Launcher"'
    );

    // 5. Fichiers .dep
    _appendLog('⬇️ Downloading dependencies...');
    await _exec('mkdir -p /userdata/system/pro/.dep');
    await _exec('wget -q -O /userdata/system/pro/.dep/dep.zip "$_depUrl" && unzip -o -qq /userdata/system/pro/.dep/dep.zip -d /userdata/system/pro/.dep/ 2>/dev/null && rm -f /userdata/system/pro/.dep/dep.zip');

    // 6. Script Ports
    _appendLog('\n📝 Creating Ports script...');
    await _exec('mkdir -p "$_portsDir"');
    await _exec('rm -f "$_portsDir/YouTubeTV.sh" "$_portsDir/YoutubeTV.sh" "$_portsDir/YoutubeTV.sh.keys" "$_portsDir/YouTubeTV.sh.keys"');
    await _exec(
      'printf "%s\\n" "#!/bin/bash" > "$_portsDir/YoutubeTV.sh" && '
      'printf "%s\\n" "unclutter-remote -s" >> "$_portsDir/YoutubeTV.sh" && '
      'printf "%s\\n" "killall -9 YouTubeonTV && unclutter-remote -s" >> "$_portsDir/YoutubeTV.sh" && '
      'printf "%s\\n" "/userdata/system/pro/youtubetv/Launcher" >> "$_portsDir/YoutubeTV.sh" && '
      'chmod +x "$_portsDir/YoutubeTV.sh"'
    );

    // 7. Fichier keys
    await _exec('curl -sL -o "$_portsDir/YoutubeTV.sh.keys" "$_keysUrl"');

    // 8. Images
    _appendLog('\n🖼️ Downloading images...');
    await _exec('mkdir -p "$_portsDir/images"');
    await _exec('curl -sL -o "$_portsDir/images/YoutubeTV-screenshot.png" "$_imgBase/YoutubeTV-screenshot.png"');
    await _exec('curl -sL -o "$_portsDir/images/YoutubeTV-wheel.png" "$_imgBase/YoutubeTV-wheel.png"');
    await _exec('curl -sL -o "$_portsDir/images/YoutubeTV-cartridge.png" "$_imgBase/YoutubeTV-cartridge.png"');

    // 9. Gamelist
    _appendLog('\n📋 Updating gamelist...');
    final gamelistFile = '$_portsDir/gamelist.xml';
    final xmlBin = '/userdata/system/pro/extra/xmlstarlet';
    final xmlLink = '/usr/bin/xmlstarlet';
    await _exec('[ -f "$gamelistFile" ] || echo \'<?xml version="1.0" encoding="UTF-8"?><gameList></gameList>\' > "$gamelistFile"');
    await _exec('[ -f "$xmlBin" ] || (mkdir -p /userdata/system/pro/extra && curl -sL "https://github.com/foclabroc/toolbox/raw/refs/heads/main/app/xmlstarlet" -o "$xmlBin" && chmod +x "$xmlBin" && ln -sf "$xmlBin" "$xmlLink")');
    await _exec('[ -L "$xmlLink" ] || ln -sf "$xmlBin" "$xmlLink"');
    await _exec('xmlstarlet ed -L -d "/gameList/game[path=\'./YoutubeTV.sh\']" "$gamelistFile" 2>/dev/null; '
      'xmlstarlet ed -L '
      '-s "/gameList" -t elem -n "game" -v "" '
      '-s "/gameList/game[last()]" -t elem -n "path" -v "./YoutubeTV.sh" '
      '-s "/gameList/game[last()]" -t elem -n "name" -v "Youtube TV" '
      '-s "/gameList/game[last()]" -t elem -n "desc" -v "YouTube TV pour Batocera Linux." '
      '-s "/gameList/game[last()]" -t elem -n "developer" -v "Youtube" '
      '-s "/gameList/game[last()]" -t elem -n "publisher" -v "Youtube" '
      '-s "/gameList/game[last()]" -t elem -n "genre" -v "Divertissement" '
      '-s "/gameList/game[last()]" -t elem -n "rating" -v "1.00" '
      '-s "/gameList/game[last()]" -t elem -n "region" -v "eu" '
      '-s "/gameList/game[last()]" -t elem -n "lang" -v "fr" '
      '-s "/gameList/game[last()]" -t elem -n "image" -v "./images/YoutubeTV-screenshot.png" '
      '-s "/gameList/game[last()]" -t elem -n "wheel" -v "./images/YoutubeTV-wheel.png" '
      '-s "/gameList/game[last()]" -t elem -n "thumbnail" -v "./images/YoutubeTV-cartridge.png" '
      '"$gamelistFile" 2>/dev/null || true');

    // 10. Nettoyage + rechargement
    _appendLog('\n🧹 Cleaning up...');
    await _exec('rm -rf "$_appDir/temp"');
    _appendLog('🔄 Reloading game list...');
    await _exec('curl -s http://127.0.0.1:1234/reloadgames');

    _appendLog('\n✅ YouTube TV installed successfully!');
    setState(() => _running = false);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('YouTube TV installed!')),
          ]),
          content: const Text(
            'YouTube TV is available in the Ports menu.',
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
                  onTap: () => Navigator.maybePop(context),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white54),
                ),
                const SizedBox(width: 12),
                Text('YouTube TV',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 22)),
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
                      Icon(Icons.play_circle_rounded, color: Colors.redAccent, size: 20),
                      SizedBox(width: 8),
                      Text('YouTube TV for Batocera',
                          style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
                    const SizedBox(height: 10),
                    const Text(
                      'Installs YouTube TV in the Ports menu. Access millions of videos from your Batocera.',
                      style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in ['Ports', 'x86_64', 'YouTube'])
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.25)),
                          ),
                          child: Text(e, style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 14),
                        SizedBox(width: 6),
                        Text('Batocera x86_64 only',
                            style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _running ? null : _launch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          disabledBackgroundColor: Colors.white12,
                        ),
                        icon: _running
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.download_rounded),
                        label: Text(_running ? 'Installing...' : 'Install YouTube TV'),
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
                    valueColor: AlwaysStoppedAnimation(Colors.redAccent),
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
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.white70, height: 1.5)),
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

// ─── Foclabroc Toolbox Ports Install ─────────────────────────────────────────

class _FoclabrocToolboxInstallScreen extends StatefulWidget {
  const _FoclabrocToolboxInstallScreen();
  @override
  State<_FoclabrocToolboxInstallScreen> createState() => _FoclabrocToolboxInstallScreenState();
}

class _FoclabrocToolboxInstallScreenState extends State<_FoclabrocToolboxInstallScreen> {
  bool _running = false;
  String _log = '';

  static const _portsDir = '/userdata/roms/ports';
  static const _imgBase = 'https://raw.githubusercontent.com/foclabroc/toolbox/refs/heads/main/app';

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  void _appendLog(String msg) => setState(() => _log += '$msg\n');

  Future<void> _launch() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.build_rounded, color: Colors.amberAccent, size: 22),
          SizedBox(width: 10),
          Flexible(child: Text('Install in Ports?', overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Installs Foclabroc Toolbox in the Batocera Ports menu.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amberAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.amberAccent.withOpacity(0.2)),
            ),
            child: const Row(children: [
              Icon(Icons.info_rounded, color: Colors.amberAccent, size: 14),
              SizedBox(width: 6),
              Expanded(child: Text(
                'EmulationStation will restart at the end.',
                style: TextStyle(color: Colors.amberAccent, fontSize: 11),
              )),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amberAccent, foregroundColor: Colors.black),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() { _running = true; _log = ''; });

    // 1. Vérification architecture
    _appendLog('🔍 Checking architecture...');
    final arch = await _exec('uname -m');
    if (arch.trim() != 'x86_64') {
      _appendLog('❌ Unsupported architecture: $arch (x86_64 required).');
      setState(() => _running = false);
      return;
    }
    _appendLog('✅ x86_64 architecture detected.');

    // 2. Création dossier pro si absent
    await _exec('mkdir -p /userdata/system/pro');

    // 3. Téléchargement du script et des keys
    _appendLog('\n⬇️ Downloading foclabroc-tools script...');
    await _exec('curl -sL "https://raw.githubusercontent.com/foclabroc/toolbox/refs/heads/main/app/foclabroc-tools.sh" -o "$_portsDir/foclabroc-tools.sh"');
    await _exec('curl -sL "https://raw.githubusercontent.com/foclabroc/toolbox/refs/heads/main/app/foclabroc-tools.sh.keys" -o "$_portsDir/foclabroc-tools.sh.keys"');
    await _exec('chmod +x "$_portsDir/foclabroc-tools.sh"');
    _appendLog('✅ Script downloaded.');

    // 4. Images
    _appendLog('\n🖼️ Downloading images...');
    await _exec('mkdir -p "$_portsDir/images"');
    await _exec('curl -sL -o "$_portsDir/images/foctool-screenshot.jpg" "$_imgBase/foctool-screenshot.jpg"');
    await _exec('curl -sL -o "$_portsDir/images/foctool-wheel.png" "$_imgBase/foctool-wheel.png"');
    await _exec('curl -sL -o "$_portsDir/images/foctool-box.png" "$_imgBase/foctool-box.png"');
    if (!mounted) return;

    // 5. Gamelist
    _appendLog('\n📋 Updating gamelist...');
    final gamelistFile = '$_portsDir/gamelist.xml';
    final xmlBin = '/userdata/system/pro/extra/xmlstarlet';
    final xmlLink = '/usr/bin/xmlstarlet';
    await _exec('[ -f "$gamelistFile" ] || echo \'<?xml version="1.0" encoding="UTF-8"?><gameList></gameList>\' > "$gamelistFile"');
    await _exec('[ -f "$xmlBin" ] || (mkdir -p /userdata/system/pro/extra && curl -sL "https://github.com/foclabroc/toolbox/raw/refs/heads/main/app/xmlstarlet" -o "$xmlBin" && chmod +x "$xmlBin" && ln -sf "$xmlBin" "$xmlLink")');
    await _exec('[ -L "$xmlLink" ] || ln -sf "$xmlBin" "$xmlLink"');
    await _exec('xmlstarlet ed -L -d "/gameList/game[path=\'./foclabroc-tools.sh\']" "$gamelistFile" 2>/dev/null; '
      'xmlstarlet ed -L '
      '-s "/gameList" -t elem -n "game" -v "" '
      '-s "/gameList/game[last()]" -t elem -n "path" -v "./foclabroc-tools.sh" '
      '-s "/gameList/game[last()]" -t elem -n "name" -v "Foclabroc Toolbox" '
      '-s "/gameList/game[last()]" -t elem -n "desc" -v "Boite a outils Foclabroc pour Batocera Linux." '
      '-s "/gameList/game[last()]" -t elem -n "developer" -v "Foclabroc" '
      '-s "/gameList/game[last()]" -t elem -n "publisher" -v "Foclabroc" '
      '-s "/gameList/game[last()]" -t elem -n "genre" -v "Toolbox" '
      '-s "/gameList/game[last()]" -t elem -n "rating" -v "1.00" '
      '-s "/gameList/game[last()]" -t elem -n "region" -v "eu" '
      '-s "/gameList/game[last()]" -t elem -n "lang" -v "fr" '
      '-s "/gameList/game[last()]" -t elem -n "image" -v "./images/foctool-screenshot.jpg" '
      '-s "/gameList/game[last()]" -t elem -n "marquee" -v "./images/foctool-wheel.png" '
      '-s "/gameList/game[last()]" -t elem -n "thumbnail" -v "./images/foctool-box.png" '
      '"$gamelistFile" 2>/dev/null || true');

    // 6. Rechargement + redémarrage ES
    _appendLog('\n🔄 Rechargement de la liste des jeux...');
    await _exec('curl -s http://127.0.0.1:1234/reloadgames');

    _appendLog('\n✅ Foclabroc Toolbox installed in Ports!');
    _appendLog('🔁 Restarting EmulationStation...');
    await _exec('killall -9 emulationstation');

    setState(() => _running = false);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Toolbox installed!')),
          ]),
          content: const Text(
            'Foclabroc Toolbox is available in the Ports menu.\nEmulationStation will restart.',
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
                  onTap: () => Navigator.maybePop(context),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white54),
                ),
                const SizedBox(width: 12),
                Text('Foclabroc Toolbox → Ports',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
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
                      Icon(Icons.build_rounded, color: Colors.amberAccent, size: 20),
                      SizedBox(width: 8),
                      Text('Foclabroc Toolbox',
                          style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
                    const SizedBox(height: 10),
                    const Text(
                      'Installs Foclabroc Toolbox directly in the Batocera Ports menu for easy access.',
                      style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in ['Ports', 'x86_64', 'Toolbox'])
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.amberAccent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.amberAccent.withOpacity(0.25)),
                          ),
                          child: Text(e, style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amberAccent.withOpacity(0.2)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 14),
                        SizedBox(width: 6),
                        Text('EmulationStation will restart at the end',
                            style: TextStyle(color: Colors.amberAccent, fontSize: 11)),
                      ]),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _running ? null : _launch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amberAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          disabledBackgroundColor: Colors.white12,
                        ),
                        icon: _running
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.download_rounded),
                        label: Text(_running ? 'Installing...' : 'Install in Ports'),
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
                    valueColor: AlwaysStoppedAnimation(Colors.amberAccent),
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
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.white70, height: 1.5)),
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

// ─── RGSX Install ─────────────────────────────────────────────────────────────

class _RgsxInstallScreen extends StatefulWidget {
  const _RgsxInstallScreen();
  @override
  State<_RgsxInstallScreen> createState() => _RgsxInstallScreenState();
}

class _RgsxInstallScreenState extends State<_RgsxInstallScreen> {
  bool _running = false;
  String _log = '';

  static const _portsDir = '/userdata/roms/ports';
  static const _rgsxDir = '/userdata/roms/ports/RGSX';
  static const _logDir = '/userdata/roms/ports/RGSX_INSTALL_LOGS';

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  void _appendLog(String msg) => setState(() => _log += '$msg\n');

  Future<void> _launch() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Row(children: [
          Icon(Icons.archive_rounded, color: Colors.cyanAccent, size: 22),
          SizedBox(width: 10),
          Flexible(child: Text('Install RGSX?', overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text(
            'Downloads and installs the RetroGameSets (RGSX) pack in the Ports menu.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.2)),
            ),
            child: const Row(children: [
              Icon(Icons.info_rounded, color: Colors.cyanAccent, size: 14),
              SizedBox(width: 6),
              Expanded(child: Text(
                'Requires python3. Large file.',
                style: TextStyle(color: Colors.cyanAccent, fontSize: 11),
              )),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() { _running = true; _log = ''; });

    // 1. Vérifie python3
    _appendLog('🔍 Checking python3...');
    final py = await _exec('command -v python3 && echo ok || echo fail');
    if (!py.contains('ok')) {
      _appendLog('❌ python3 not found on Batocera.');
      setState(() => _running = false);
      return;
    }
    _appendLog('✅ python3 available.');

    // 2. Crée les dossiers
    await _exec('mkdir -p "$_portsDir" "$_logDir"');

    // 3. Récupère l'URL du dernier release GitHub
    _appendLog('\n🔍 Fetching latest release URL...');
    final releaseUrl = await _exec(
      'curl -sL "https://api.github.com/repos/RetroGameSets/RGSX/releases/latest" '
      '| grep -o "https://[^\"]*RGSX_Full_latest\\.zip" | head -1'
    );
    final zipUrl = releaseUrl.trim().isNotEmpty
        ? releaseUrl.trim()
        : 'https://github.com/RetroGameSets/RGSX/releases/latest/download/RGSX_Full_latest.zip';
    _appendLog('✅ URL : $zipUrl');

    // 4. Téléchargement avec progression
    _appendLog('\n⬇️ Downloading RGSX...');
    _appendLog('  (large file, please wait)');
    await _exec('rm -f /tmp/_rgsx_done /tmp/_rgsx.zip');
    await _exec('curl -L --retry 3 --max-time 1800 -o /tmp/_rgsx.zip "$zipUrl" && touch /tmp/_rgsx_done || touch /tmp/_rgsx_done &');

    final totalRaw = await _exec('curl -sIL "$zipUrl" | grep -i content-length | tail -1 | awk \'{print \$2}\' | tr -d \$\'\\r\'');
    final totalBytes = int.tryParse(totalRaw.trim()) ?? 0;
    final totalMb = totalBytes > 0 ? (totalBytes / 1024 / 1024).toStringAsFixed(0) : '?';

    while (true) {
      if (!mounted) break;
      await Future.delayed(const Duration(seconds: 2));
      final szRaw = await _exec('stat -c%s /tmp/_rgsx.zip 2>/dev/null || echo 0');
      final sz = int.tryParse(szRaw.trim()) ?? 0;
      final nowMb = (sz / 1024 / 1024).toStringAsFixed(1);
      final pct = totalBytes > 0 ? (sz * 100 ~/ totalBytes) : 0;
      final bar = totalBytes > 0 ? '$pct%' : '$nowMb MB';
      setState(() {
        final lines = _log.split('\n');
        if (lines.length >= 2 && lines[lines.length - 2].startsWith('  ↓')) {
          lines[lines.length - 2] = '  ↓ $nowMb / $totalMb Mo  [$bar]';
          _log = lines.join('\n');
        } else {
          _log += '  ↓ $nowMb / $totalMb Mo  [$bar]\n';
        }
      });
      final done = await _exec('[ -f /tmp/_rgsx_done ] && echo yes || echo no');
      if (done.trim() == 'yes') break;
    }
    await _exec('rm -f /tmp/_rgsx_done');
    if (!mounted) return;

    final szCheck = int.tryParse((await _exec('stat -c%s /tmp/_rgsx.zip 2>/dev/null || echo 0')).trim()) ?? 0;
    if (szCheck < 100000) {
      _appendLog('❌ Download failed.');
      await _exec('rm -f /tmp/_rgsx.zip');
      setState(() => _running = false);
      return;
    }
    _appendLog("✅ Download complete (${(szCheck / 1024 / 1024).toStringAsFixed(0)} MB).");

    // 5. Vérifie le ZIP
    _appendLog('\n🔍 Verifying ZIP...');
    final zipOk = await _exec('unzip -t /tmp/_rgsx.zip >/dev/null 2>&1 && echo ok || echo fail');
    if (!zipOk.contains('ok')) {
      _appendLog('❌ Corrupted ZIP.');
      await _exec('rm -f /tmp/_rgsx.zip');
      setState(() => _running = false);
      return;
    }
    _appendLog('✅ ZIP valid.');

    // 6. Supprime l'ancienne installation
    _appendLog('\n🗑️ Removing old installation...');
    await _exec('rm -rf "$_rgsxDir"');

    // 7. Extraction
    _appendLog('\n📦 Extracting...');
    await _exec('unzip -q -o /tmp/_rgsx.zip -d /userdata/roms/ 2>&1');
    await _exec('rm -f /tmp/_rgsx.zip');
    // Find the extracted RGSX folder (name may vary)
    final extractedDir = (await _exec('ls "$_portsDir/" | grep -i rgsx | head -1')).trim();
    _appendLog('  📁 Folder: $extractedDir');
    if (extractedDir.isEmpty) {
      _appendLog('❌ RGSX directory not found after extraction.');
      setState(() => _running = false);
      return;
    }
    final rgsxPath = '$_portsDir/$extractedDir';
    _appendLog('✅ Extraction complete.');

    // 8. Permissions
    _appendLog('\n🔧 Permissions...');
    await _exec('find "$rgsxPath" -name "*.sh" -exec chmod +x {} \\;');
    await _exec('chmod +x "$rgsxPath/update_gamelist.py" 2>/dev/null || true');
    await _exec('chmod -R u+rwX "$rgsxPath" 2>/dev/null || true');

    // 9. Update gamelist
    _appendLog('\n📋 Updating gamelist...');
    final pyResult = await _exec('python3 "$rgsxPath/update_gamelist.py" 2>&1');
    if (pyResult.isNotEmpty) _appendLog('  $pyResult');
    _appendLog('✅ Gamelist updated.');

    // 10. Nettoyage
    await _exec('rm -f "$_portsDir/RGSX.zip" 2>/dev/null || true');

    // 11. Rechargement
    _appendLog('\n🔄 Rechargement de la liste des jeux...');
    await _exec('curl -s http://127.0.0.1:1234/reloadgames');

    _appendLog('\n✅ RGSX installed successfully!');

    setState(() => _running = false);

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('RGSX installed!')),
          ]),
          content: const Text(
            'RGSX is available in the Ports menu.\nUpdate your game list if needed.',
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
                  onTap: () => Navigator.maybePop(context),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white54),
                ),
                const SizedBox(width: 12),
                Text('RGSX',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 22)),
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
                      Icon(Icons.archive_rounded, color: Colors.cyanAccent, size: 20),
                      SizedBox(width: 8),
                      Text('RetroGameSets RGSX',
                          style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
                    const SizedBox(height: 10),
                    const Text(
                      'Installs the RetroGameSets RGSX pack in the Batocera Ports menu.',
                      style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final e in ['Ports', 'python3', 'RGSX'])
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.cyanAccent.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.cyanAccent.withOpacity(0.25)),
                          ),
                          child: Text(e, style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                    ]),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _running ? null : _launch,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          disabledBackgroundColor: Colors.white12,
                        ),
                        icon: _running
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.download_rounded),
                        label: Text(_running ? 'Installing...' : 'Install RGSX'),
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
                    valueColor: AlwaysStoppedAnimation(Colors.cyanAccent),
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
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10, color: Colors.white70, height: 1.5)),
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
