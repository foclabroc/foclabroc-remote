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
