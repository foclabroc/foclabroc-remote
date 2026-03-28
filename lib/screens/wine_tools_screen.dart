import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';

// ─── Menu Wine Tools ──────────────────────────────────────────────────────────

class WineToolsScreen extends StatelessWidget {
  const WineToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 8, 24, 0),
              child: Text('Wine Tools', style: Theme.of(context).textTheme.headlineMedium),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: !state.isConnected
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.wifi_off_rounded, size: 48, color: Colors.white.withOpacity(0.1)),
                      const SizedBox(height: 12),
                      Text('Non connecté', style: Theme.of(context).textTheme.bodyMedium),
                    ]))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [
                        _ToolCard(
                          icon: Icons.transform_rounded,
                          title: '.PC Converter',
                          subtitle: 'Convertit un dossier .pc en .wine\navec compression optionnelle',
                          color: accent,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const _PcConverterScreen(),
                          )),
                        ),

                        const SizedBox(height: 12),
                        _ToolCard(
                          icon: Icons.unarchive_rounded,
                          title: 'Decompressor',
                          subtitle: 'Décompresse un fichier .wtgz ou .wsquashfs\nen dossier .wine',
                          color: Colors.purpleAccent,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const _DecompressorScreen(),
                          )),
                        ),
                        const SizedBox(height: 12),
                        _ToolCard(
                          icon: Icons.archive_rounded,
                          title: 'Compressor',
                          subtitle: 'Compresse un dossier .wine\nen .wtgz ou .wsquashfs',
                          color: Colors.orangeAccent,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const _CompressorScreen(),
                          )),
                        ),
                        const SizedBox(height: 12),
                        _ToolCard(
                          icon: Icons.download_rounded,
                          title: 'Téléchargement Runner',
                          subtitle: 'Télécharge et installe des runners Wine\n(GE-Custom, Proton...)',
                          color: Colors.tealAccent,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const _DownloadRunnerScreen(),
                          )),
                        ),
                        const SizedBox(height: 12),
                        _ToolCard(
                          icon: Icons.delete_sweep_rounded,
                          title: 'Wine Bottle Manager',
                          subtitle: 'Liste et supprime les bouteilles Wine\nde /system/wine-bottles/windows',
                          color: Colors.redAccent,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const _WineBottleManagerScreen(),
                          )),
                        ),
                        const SizedBox(height: 12),
                        _ToolCard(
                          icon: Icons.extension_rounded,
                          title: 'Winetricks',
                          subtitle: 'Installe des dépendances Windows\n(VC++, DirectX, etc.) dans une bouteille',
                          color: Colors.purpleAccent,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const _WinetricksScreen(),
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

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color color;
  final VoidCallback onTap;
  const _ToolCard({required this.icon, required this.title, required this.subtitle,
    required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
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
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: Colors.white24),
        ]),
      ),
    ),
  );
}

// ─── .pc Converter ────────────────────────────────────────────────────────────

class _PcConverterScreen extends StatefulWidget {
  const _PcConverterScreen();
  @override
  State<_PcConverterScreen> createState() => _PcConverterScreenState();
}

class _PcConverterScreenState extends State<_PcConverterScreen> {
  List<String> _pcFolders = [];
  List<String> _wineFolders = [];
  String? _selectedPc;
  String? _selectedWine;
  bool _loading = false;
  bool _converting = false;
  String _log = '';
  String _step = '';
  double _progress = 0;
  Timer? _progressTimer;
  final ScrollController _logScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFolders());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }
  // Lance une commande longue en background et poll la taille + log toutes les secondes
  Future<String> _execStream(String cmd, ScrollController? scrollCtrl) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute('stdbuf -oL $cmd');
      final buffer = StringBuffer();
      String pending = '';
      await for (final chunk in session.stdout) {
        final text = String.fromCharCodes(chunk);
        buffer.write(text);
        pending += text;
        final lines = pending.split('\n');
        pending = lines.removeLast();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && mounted) {
            setState(() => _log += "  $trimmed\n");
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (scrollCtrl != null && scrollCtrl.hasClients) {
                scrollCtrl.animateTo(scrollCtrl.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeOut);
              }
            });
          }
        }
      }
      if (pending.trim().isNotEmpty && mounted) {
        setState(() => _log += "  ${pending.trim()}\n");
      }
      await session.done;
      return buffer.toString().trim();
    } catch (e) { return ''; }
  }


  void _startProgress(String outputPath) {
    _progress = 0;
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (mounted && _converting) setState(() => _progress = (_progress + 0.02).clamp(0.0, 0.95));
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
    setState(() => _progress = 1.0);
  }

  Future<void> _showSuccessDialog(String title, String path) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
          const SizedBox(width: 10),
          Flexible(child: Text(title)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Chemin :', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 6),
          Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              path,
              style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace', height: 1.5),
            ),
          ),
        ]),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _loadFolders() async {
    setState(() => _loading = true);
    final pc = await _exec(
        r"find /userdata/roms/windows -maxdepth 1 -type d -name '*.pc' 2>/dev/null | sort");
    final wine = await _exec(
        r"find /userdata/system/wine-bottles -type d -name '*.wine' 2>/dev/null | sort");
    setState(() {
      _pcFolders = pc.isEmpty ? [] : pc.split('\n').where((l) => l.isNotEmpty).toList();
      _wineFolders = wine.isEmpty ? [] : wine.split('\n').where((l) => l.isNotEmpty).toList();
      _loading = false;
    });
  }

  void _appendLog(String msg) => setState(() => _log += '$msg\n');

  Future<void> _convert() async {
    if (_selectedPc == null || _selectedWine == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Confirmation'),
        content: Text(
          'Copier les données depuis :\n\n$_selectedWine\n\nvers :\n\n$_selectedPc\n\npuis supprimer la bouteille Wine et renommer le dossier .pc en .wine.',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuer')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() { _converting = true; _log = ''; });

    _appendLog('⏳ Copie des données Wine...');
    _appendLog('\$ cp -a "$_selectedWine"/. "$_selectedPc"/');
    setState(() => _step = 'Copie en cours...');
    await _exec('cp -a "$_selectedWine"/. "$_selectedPc"/');
    _appendLog('✅ Copie terminée.');

    _appendLog('🗑️ Suppression de la bouteille Wine...');
    _appendLog('\$ rm -rf "$_selectedWine"');
    setState(() => _step = 'Suppression...');
    await _exec('rm -rf "$_selectedWine"');
    _appendLog('✅ Bouteille Wine supprimée.');

    final baseName = _selectedPc!.split('/').last;
    final newName = baseName.replaceAll(RegExp(r'\.pc$'), '.wine');
    final parentDir = _selectedPc!.substring(0, _selectedPc!.lastIndexOf('/'));
    final newPath = '$parentDir/$newName';

    _appendLog('✏️ Renommage en $newName...');
    _appendLog('\$ mv "$_selectedPc" "$newPath"');
    setState(() => _step = 'Renommage...');
    await _exec('mv "$_selectedPc" "$newPath"');
    _appendLog('✅ Conversion terminée !\n📁 $newPath');
    setState(() { _step = 'Terminé !'; _selectedPc = null; _selectedWine = null; });
    if (!mounted) return;

    await _showSuccessDialog('Conversion réussie !', newPath);
    if (!mounted) return;

    final compress = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Compression (optionnel)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Souhaitez-vous compresser le dossier .wine ?',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          _CompressionOption(
            title: '.wtgz (TGZ)', subtitle: 'Petits jeux avec nombreuses écritures',
            icon: Icons.archive_rounded, color: Colors.blueAccent,
            onTap: () => Navigator.pop(ctx, 'wtgz'),
          ),
          const SizedBox(height: 8),
          _CompressionOption(
            title: '.wsquashfs (SquashFS)', subtitle: "Gros jeux avec peu d'écritures",
            icon: Icons.compress_rounded, color: Colors.purpleAccent,
            onTap: () => Navigator.pop(ctx, 'wsquashfs'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Non merci')),
        ],
      ),
    );

    if (compress != null && mounted) {
      await _compressFolder(newPath, compress);
    } else {
      setState(() => _converting = false);
      await _loadFolders();
    }
  }

  Future<void> _compressFolder(String path, String type) async {
    final cmd = type == 'wtgz'
        ? 'batocera-wine windows wine2winetgz "$path" 2>&1'
        : 'batocera-wine windows wine2squashfs "$path" 2>&1';
    final parentDir = path.substring(0, path.lastIndexOf('/'));
    final baseName = path.split('/').last.replaceAll('.wine', '');
    final finalOut = '$parentDir/$baseName.$type';
    _appendLog('\n⏳ Compression en $type... (peut prendre plusieurs minutes)');
    _appendLog('\$ $cmd');
    setState(() { _step = 'Compression $type...'; _progress = 0; });
    await _execStream(cmd, _logScrollCtrl);
    // Cherche le fichier créé quel que soit le nom exact
    final foundRaw = await _exec(
        'find "$parentDir" -maxdepth 1 \\( -name "*$baseName*.$type" -o -name "*$baseName*.${type.toUpperCase()}" \\) 2>/dev/null | head -1');
    final found = foundRaw.trim();
    if (found.isNotEmpty && found != finalOut) {
      await _exec('mv "$found" "$finalOut"');
    }
    _appendLog('✅ Compression terminée !\n📦 $finalOut');
    setState(() => _step = 'Compression terminée !');
    if (!mounted) return;

    await _showSuccessDialog('Compression réussie !', finalOut);
    if (!mounted) return;

    final del = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Supprimer le dossier .wine ?'),
        content: Text('Supprimer :\n$path',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (del == true) {
      await _exec('rm -rf "$path"');
      _appendLog('🗑️ Dossier .wine supprimé.');
    }
    setState(() => _converting = false);
    await _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
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
                Text('.PC Converter',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
                const Spacer(),
                if (_loading)
                  SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: accent))
                else
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                    onPressed: _loadFolders,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_rounded, color: Colors.blueAccent, size: 16),
                      SizedBox(width: 8),
                      Expanded(child: Text(
                        'Lance le jeu .pc au moins une fois avant de continuer pour que Batocera génère la bouteille .wine.',
                        style: TextStyle(color: Colors.white60, fontSize: 11),
                      )),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel(label: 'DOSSIER .PC', icon: Icons.folder_rounded, accent: accent),
                  const SizedBox(height: 8),
                  _pcFolders.isEmpty
                      ? _EmptyHint('Aucun dossier .pc trouvé dans /userdata/roms/windows')
                      : _DropdownCard(
                          hint: 'Sélectionner un dossier .pc',
                          value: _selectedPc, items: _pcFolders,
                          onChanged: (v) => setState(() => _selectedPc = v), accent: accent),
                  const SizedBox(height: 16),
                  _SectionLabel(label: 'BOUTEILLE .WINE', icon: Icons.wine_bar_rounded, accent: accent),
                  const SizedBox(height: 8),
                  _wineFolders.isEmpty
                      ? _EmptyHint('Aucune bouteille .wine trouvée dans /userdata/system/wine-bottles')
                      : _DropdownCard(
                          hint: 'Sélectionner une bouteille .wine',
                          value: _selectedWine, items: _wineFolders,
                          onChanged: (v) => setState(() => _selectedWine = v), accent: accent),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_selectedPc != null && _selectedWine != null && !_converting)
                          ? _convert : null,
                      icon: _converting
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.transform_rounded),
                      label: Text(_converting
                          ? (_step.isNotEmpty ? _step : 'Conversion...') : 'Convertir'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: accent, foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white12,
                      ),
                    ),
                  ),
                  if (_converting) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: AlwaysStoppedAnimation(accent),
                        minHeight: 6,
                      ),
                    ),
                  ],
                  if (_log.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0C10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: SelectableText(_log,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                              color: Colors.white70, height: 1.5)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Widgets helpers ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label; final IconData icon; final Color accent;
  const _SectionLabel({required this.label, required this.icon, required this.accent});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 14, color: accent),
    const SizedBox(width: 6),
    Text(label, style: TextStyle(color: accent, fontSize: 11,
        fontWeight: FontWeight.w700, letterSpacing: 0.8)),
  ]);
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withOpacity(0.06)),
    ),
    child: Text(text, style: const TextStyle(color: Colors.white38, fontSize: 12)),
  );
}

class _DropdownCard extends StatelessWidget {
  final String hint; final String? value;
  final List<String> items; final ValueChanged<String?> onChanged; final Color accent;
  const _DropdownCard({required this.hint, required this.value,
    required this.items, required this.onChanged, required this.accent});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: DropdownButton<String>(
        value: value,
        hint: Text(hint, style: const TextStyle(color: Colors.white38, fontSize: 12)),
        isExpanded: true, underline: const SizedBox(),
        dropdownColor: const Color(0xFF1C2230),
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: accent, size: 20),
        style: const TextStyle(color: Colors.white, fontSize: 12),
        items: items.map((p) {
          final parts = p.split('/');
          final label = parts.length >= 2
              ? '${parts[parts.length - 2]}/${parts.last}'
              : parts.last;
          return DropdownMenuItem(
            value: p,
            child: SizedBox(
              width: double.infinity,
              child: Text(label, overflow: TextOverflow.ellipsis, softWrap: false),
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    ),
  );
}

class _CompressionOption extends StatelessWidget {
  final String title, subtitle; final IconData icon;
  final Color color; final VoidCallback onTap;
  const _CompressionOption({required this.title, required this.subtitle,
    required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11), overflow: TextOverflow.ellipsis),
        ])),
      ]),
    ),
  );
}

// ─── Decompressor ─────────────────────────────────────────────────────────────

class _DecompressorScreen extends StatefulWidget {
  const _DecompressorScreen();
  @override
  State<_DecompressorScreen> createState() => _DecompressorScreenState();
}

class _DecompressorScreenState extends State<_DecompressorScreen> {
  List<String> _files = [];
  String? _selected;
  bool _loading = false;
  bool _processing = false;
  String _log = '';
  String _step = '';
  double _progress = 0;
  Timer? _progressTimer;
  final ScrollController _logScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFiles());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }
  // Lance une commande longue en background et poll la taille + log toutes les secondes
  Future<String> _execStream(String cmd, ScrollController? scrollCtrl) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute('stdbuf -oL $cmd');
      final buffer = StringBuffer();
      String pending = '';
      await for (final chunk in session.stdout) {
        final text = String.fromCharCodes(chunk);
        buffer.write(text);
        pending += text;
        final lines = pending.split('\n');
        pending = lines.removeLast();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && mounted) {
            setState(() => _log += "  $trimmed\n");
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (scrollCtrl != null && scrollCtrl.hasClients) {
                scrollCtrl.animateTo(scrollCtrl.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeOut);
              }
            });
          }
        }
      }
      if (pending.trim().isNotEmpty && mounted) {
        setState(() => _log += "  ${pending.trim()}\n");
      }
      await session.done;
      return buffer.toString().trim();
    } catch (e) { return ''; }
  }


  void _startProgress(String outputDir) {
    _progress = 0;
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (mounted && _processing) setState(() => _progress = (_progress + 0.02).clamp(0.0, 0.95));
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
    setState(() => _progress = 1.0);
  }

  Future<void> _showSuccessDialog(String title, String path) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
          const SizedBox(width: 10),
          Flexible(child: Text(title)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Chemin :', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 6),
          Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              path,
              style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace', height: 1.5),
            ),
          ),
        ]),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _loadFiles() async {
    setState(() => _loading = true);
    final raw = await _exec(
      r"find /userdata/roms/windows -maxdepth 1 -type f \( -iname '*.wtgz' -o -iname '*.wsquashfs' \) 2>/dev/null | sort");
    setState(() {
      _files = raw.isEmpty ? [] : raw.split('\n').where((l) => l.isNotEmpty).toList();
      _loading = false;
    });
  }

  void _appendLog(String msg) => setState(() => _log += '$msg\n');

  Future<void> _decompress() async {
    if (_selected == null) return;

    final ext = _selected!.split('.').last.toLowerCase();
    if (ext != 'wtgz' && ext != 'wsquashfs') {
      _appendLog('❌ Extension non supportée : $ext');
      return;
    }

    setState(() { _processing = true; _log = ''; });

    final fileName = _selected!.split('/').last;
    final baseName = fileName
        .replaceAll(RegExp(r'\.(wtgz|WTGZ|wsquashfs|WSQUASHFS)$', caseSensitive: false), '');
    final finalDir = '/userdata/roms/windows/$baseName.wine';

    _appendLog('🗑️ Suppression du dossier existant...');
    setState(() => _step = 'Préparation...');
    await _exec('rm -rf "$finalDir" && mkdir -p "$finalDir"');

    if (ext == 'wtgz') {
      _appendLog('⏳ Décompression TGZ...');
      _appendLog('\$ tar -xzf "$_selected" -C "$finalDir"');
      setState(() { _step = 'Décompression TGZ...'; _progress = 0; });
      _startProgress(finalDir);
      final result = await _exec('tar -xzf "$_selected" -C "$finalDir" 2>&1');
      _stopProgress();
      if (result.toLowerCase().contains('error') || result.toLowerCase().contains('erreur')) {
        _appendLog('❌ Erreur : $result');
        setState(() { _processing = false; _step = ''; });
        return;
      }
    } else {
      _appendLog('⏳ Décompression SquashFS...');
      _appendLog('\$ unsquashfs -d "$finalDir" "$_selected"');
      setState(() { _step = 'Décompression SquashFS...'; _progress = 0; });
      _startProgress(finalDir);
      final result = await _exec('unsquashfs -d "$finalDir" "$_selected" 2>&1');
      _stopProgress();
      if (result.toLowerCase().contains('error') || result.toLowerCase().contains('erreur')) {
        _appendLog('❌ Erreur : $result');
        setState(() { _processing = false; _step = ''; });
        return;
      }
    }

    _appendLog('✅ Décompression terminée !\n📁 $finalDir');
    setState(() => _step = 'Terminé !');
    if (!mounted) return;

    await _showSuccessDialog('Décompression réussie !', finalDir);
    if (!mounted) return;

    // Proposer suppression du fichier source
    final del = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Supprimer le fichier compressé ?'),
        content: Text('Supprimer :\n$_selected',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (del == true) {
      await _exec('rm -f "$_selected"');
      _appendLog('🗑️ Fichier source supprimé.');
    }

    setState(() { _processing = false; _selected = null; });
    await _loadFiles();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Colors.purpleAccent;
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
                Text('Decompressor',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
                const Spacer(),
                if (_loading)
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purpleAccent))
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                    onPressed: _loadFiles,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _SectionLabel(label: 'FICHIER COMPRESSÉ', icon: Icons.archive_rounded, accent: accent),
                  const SizedBox(height: 8),
                  _files.isEmpty
                      ? _EmptyHint('Aucun fichier .wtgz ou .wsquashfs trouvé dans /userdata/roms/windows')
                      : _DropdownCard(
                          hint: 'Sélectionner un fichier',
                          value: _selected, items: _files,
                          onChanged: (v) => setState(() => _selected = v),
                          accent: accent),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_selected != null && !_processing) ? _decompress : null,
                      icon: _processing
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.unarchive_rounded),
                      label: Text(_processing
                          ? (_step.isNotEmpty ? _step : 'Décompression...') : 'Décompresser'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: accent, foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white12,
                      ),
                    ),
                  ),
                  if (_processing) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: const AlwaysStoppedAnimation(Colors.purpleAccent),
                        minHeight: 6,
                      ),
                    ),
                  ],
                  if (_log.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0C10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: SelectableText(_log,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                              color: Colors.white70, height: 1.5)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Compressor ───────────────────────────────────────────────────────────────

class _CompressorScreen extends StatefulWidget {
  const _CompressorScreen();
  @override
  State<_CompressorScreen> createState() => _CompressorScreenState();
}

class _CompressorScreenState extends State<_CompressorScreen> {
  List<String> _wineFolders = [];
  String? _selected;
  bool _loading = false;
  bool _processing = false;
  String _log = '';
  String _step = '';
  double _progress = 0;
  Timer? _progressTimer;
  final ScrollController _logScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFolders());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }
  // Lance une commande longue en background et poll la taille + log toutes les secondes
  Future<String> _execStream(String cmd, ScrollController? scrollCtrl) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute('stdbuf -oL $cmd');
      final buffer = StringBuffer();
      String pending = '';
      await for (final chunk in session.stdout) {
        final text = String.fromCharCodes(chunk);
        buffer.write(text);
        pending += text;
        final lines = pending.split('\n');
        pending = lines.removeLast();
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isNotEmpty && mounted) {
            setState(() => _log += "  $trimmed\n");
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (scrollCtrl != null && scrollCtrl.hasClients) {
                scrollCtrl.animateTo(scrollCtrl.position.maxScrollExtent,
                    duration: const Duration(milliseconds: 100),
                    curve: Curves.easeOut);
              }
            });
          }
        }
      }
      if (pending.trim().isNotEmpty && mounted) {
        setState(() => _log += "  ${pending.trim()}\n");
      }
      await session.done;
      return buffer.toString().trim();
    } catch (e) { return ''; }
  }


  Future<void> _showSuccessDialog(String title, String path) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Row(children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
          const SizedBox(width: 10),
          Flexible(child: Text(title)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Chemin :', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 6),
          Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(6),
            ),
            child: SelectableText(
              path,
              style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace', height: 1.5),
            ),
          ),
        ]),
        actions: [
          ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  void _startProgress(String outputPath) {
    _progress = 0;
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final sizeRaw = await _exec('stat -c%s "$outputPath" 2>/dev/null || echo 0');
      final size = int.tryParse(sizeRaw.trim()) ?? 0;
      // Estimation : ~50% compression ratio, augmente progressivement
      if (mounted && _processing) {
        setState(() {
          _progress = (_progress + 0.02).clamp(0.0, 0.95);
        });
      }
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    _progressTimer = null;
    setState(() => _progress = 1.0);
  }

  Future<void> _loadFolders() async {
    setState(() => _loading = true);
    final raw = await _exec(
        r"find /userdata/roms/windows -maxdepth 1 -type d -name '*.wine' 2>/dev/null | sort");
    setState(() {
      _wineFolders = raw.isEmpty ? [] : raw.split('\n').where((l) => l.isNotEmpty).toList();
      _loading = false;
    });
  }

  void _appendLog(String msg) => setState(() => _log += '$msg\n');

  Future<void> _compress() async {
    if (_selected == null) return;

    // Choix du type de compression
    final type = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Type de compression'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Choisissez la méthode de compression :',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          _CompressionOption(
            title: '.wtgz (TGZ)',
            subtitle: 'Petits jeux avec nombreuses écritures',
            icon: Icons.archive_rounded, color: Colors.blueAccent,
            onTap: () => Navigator.pop(ctx, 'wtgz'),
          ),
          const SizedBox(height: 8),
          _CompressionOption(
            title: '.wsquashfs (SquashFS)',
            subtitle: "Gros jeux avec peu d'écritures",
            icon: Icons.compress_rounded, color: Colors.purpleAccent,
            onTap: () => Navigator.pop(ctx, 'wsquashfs'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Annuler')),
        ],
      ),
    );
    if (type == null) return;

    setState(() { _processing = true; _log = ''; });

    final parentDir = _selected!.substring(0, _selected!.lastIndexOf('/'));
    final baseName = _selected!.split('/').last.replaceAll('.wine', '');
    final finalOut = '$parentDir/$baseName.$type';

    final cmd = type == 'wtgz'
        ? 'batocera-wine windows wine2winetgz "$_selected" 2>&1'
        : 'batocera-wine windows wine2squashfs "$_selected" 2>&1';

    _appendLog('⏳ Compression en .$type... (peut prendre plusieurs minutes)');
    _appendLog('\$ $cmd');
    setState(() { _step = 'Compression .$type...'; _progress = 0; });
    await _execStream(cmd, _logScrollCtrl);

    // Cherche le fichier créé (le nom exact peut varier selon la version de batocera-wine)
    final foundRaw = await _exec(
        'find "$parentDir" -maxdepth 1 -name "*$baseName*.$type" -o -name "*$baseName*.${type.toUpperCase()}" 2>/dev/null | head -1');
    final found = foundRaw.trim();

    if (found.isNotEmpty) {
      // Renomme en nom propre si nécessaire
      if (found != finalOut) {
        await _exec('mv "$found" "$finalOut"');
      }
      _appendLog('✅ Compression terminée !\n📦 $finalOut');
      setState(() => _step = 'Terminé !');
      if (mounted) await _showSuccessDialog('Compression réussie !', finalOut);
    } else {
      // Dernière chance : vérifie le fichier avec le nom .wine.ext
      final oldOut = '$_selected.$type';
      final existsOld = await _exec('[ -f "$oldOut" ] && echo "yes" || echo "no"');
      if (existsOld.trim() == 'yes') {
        await _exec('mv "$oldOut" "$finalOut"');
        _appendLog('✅ Compression terminée !\n📦 $finalOut');
        setState(() => _step = 'Terminé !');
      } else {
        _appendLog('❌ Erreur : fichier de sortie introuvable.\nEspace disque insuffisant ?');
        setState(() { _processing = false; _step = ''; });
        return;
      }
    }

    if (!mounted) return;

    // Suppression du .wine source
    final del = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Supprimer le dossier .wine ?'),
        content: Text('Supprimer :\n$_selected',
            style: const TextStyle(fontSize: 12, color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Non')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (del == true) {
      await _exec('rm -rf "$_selected"');
      _appendLog('🗑️ Dossier .wine supprimé.');
    }

    setState(() { _processing = false; _selected = null; });
    await _loadFolders();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Colors.orangeAccent;
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
                Text('Compressor',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
                const Spacer(),
                if (_loading)
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent))
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                    onPressed: _loadFolders,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _SectionLabel(label: 'DOSSIER .WINE', icon: Icons.wine_bar_rounded, accent: accent),
                  const SizedBox(height: 8),
                  _wineFolders.isEmpty
                      ? _EmptyHint('Aucun dossier .wine trouvé dans /userdata/roms/windows')
                      : _DropdownCard(
                          hint: 'Sélectionner un dossier .wine',
                          value: _selected, items: _wineFolders,
                          onChanged: (v) => setState(() => _selected = v),
                          accent: accent),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_selected != null && !_processing) ? _compress : null,
                      icon: _processing
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.archive_rounded),
                      label: Text(_processing
                          ? (_step.isNotEmpty ? _step : 'Compression...') : 'Compresser'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: accent, foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white12,
                      ),
                    ),
                  ),
                  if (_processing) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white.withOpacity(0.08),
                        valueColor: AlwaysStoppedAnimation(Colors.orangeAccent.withOpacity(0.8)),
                        minHeight: 6,
                      ),
                    ),
                  ],
                  if (_log.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A0C10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withOpacity(0.06)),
                      ),
                      child: SelectableText(_log,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                              color: Colors.white70, height: 1.5)),
                    ),
                    const SizedBox(height: 24),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Téléchargement Runner ────────────────────────────────────────────────────

class _DownloadRunnerScreen extends StatelessWidget {
  const _DownloadRunnerScreen();

  @override
  Widget build(BuildContext context) {
    const accent = Colors.tealAccent;
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
                Text('Téléchargement Runner',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _ToolCard(
                    icon: Icons.wine_bar_rounded,
                    title: 'Wine GE-Custom',
                    subtitle: 'Télécharge et installe une version\nWine GE-Custom depuis GitHub',
                    color: Colors.tealAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _WineGeScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _ToolCard(
                    icon: Icons.wine_bar_outlined,
                    title: 'Wine Vanilla',
                    subtitle: 'Télécharge et installe une version\nWine Vanilla depuis GitHub',
                    color: Colors.lightBlueAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _WineVanillaScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _ToolCard(
                    icon: Icons.science_rounded,
                    title: 'Wine TKG-Staging',
                    subtitle: 'Télécharge et installe une version\nWine TKG-Staging depuis GitHub',
                    color: Colors.deepPurpleAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _WineTkgScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _ToolCard(
                    icon: Icons.bolt_rounded,
                    title: 'GE-Proton',
                    subtitle: 'Télécharge et installe une version\nGE-Proton depuis GitHub',
                    color: Colors.orangeAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _GeProtonScreen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _ToolCard(
                    icon: Icons.system_update_alt_rounded,
                    title: 'GE-Custom V40',
                    subtitle: 'Installe la version fixe ge-custom V40\n(2 parties depuis GitHub)',
                    color: Colors.greenAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _GeCustomV40Screen(),
                    )),
                  ),
                  const SizedBox(height: 12),
                  _ToolCard(
                    icon: Icons.delete_sweep_rounded,
                    title: 'Runner Manager',
                    subtitle: 'Liste et supprime les runners\ninstallés dans /wine/custom',
                    color: Colors.redAccent,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const _RunnerManagerScreen(),
                    )),
                  ),
                  // D'autres runners peuvent être ajoutés ici
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Wine GE-Custom ───────────────────────────────────────────────────────────

class _WineGeScreen extends StatefulWidget {
  const _WineGeScreen();
  @override
  State<_WineGeScreen> createState() => _WineGeScreenState();
}

class _WineGeScreenState extends State<_WineGeScreen> {
  List<Map<String, String>> _releases = [];
  bool _loadingReleases = true;
  bool _processing = false;
  String _log = '';
  String _step = '';
  String? _error;
  final ScrollController _logScrollCtrl = ScrollController();

  static const _installDir = '/userdata/system/wine/custom/';
  static const _apiUrl =
      'https://api.github.com/repos/GloriousEggroll/wine-ge-custom/releases?per_page=100';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchReleases());
  }

  @override
  void dispose() {
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  void _appendLog(String msg) {
    setState(() => _log += '$msg\n');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(_logScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _fetchReleases() async {
    setState(() { _loadingReleases = true; _error = null; });
    // Tout se passe côté Batocera : curl + jq en une seule commande
    final parsed = await _exec(
        'curl -s "$_apiUrl" | jq -r \'.[] | .tag_name + "||" + (first(.assets[]? | select(.name | endswith("x86_64.tar.xz"))) | .browser_download_url)\' 2>/dev/null | grep "||http" | head -60');
    if (!mounted) return;
    if (parsed.isEmpty) {
      setState(() {
        _error = 'Impossible de récupérer les versions.\n(connexion internet disponible sur Batocera ? jq installé ?)';
        _loadingReleases = false;
      });
      return;
    }
    final releases = <Map<String, String>>[];
    for (final line in parsed.split('\n')) {
      final parts = line.split('||');
      if (parts.length == 2 && parts[1].trim().startsWith('http')) {
        releases.add({'tag': parts[0].trim(), 'url': parts[1].trim()});
      }
    }
    if (releases.isEmpty) {
      setState(() {
        _error = 'Aucune version trouvée. Vérifiez que jq est installé sur Batocera.';
        _loadingReleases = false;
      });
      return;
    }
    setState(() { _releases = releases; _loadingReleases = false; });
  }

  Future<void> _install(Map<String, String> release) async {
    final tag = release['tag']!;
    final url = release['url']!;
    final version = 'Custom-$tag';
    final wineDir = '$_installDir$version';
    final archive = '$wineDir/$version.tar.xz';

    // Confirmation
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Confirmer le téléchargement'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Version : $version', style: const TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('⚠️ Les versions supérieures à 8.15 semblent ne pas fonctionner sous Batocera.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.tealAccent, foregroundColor: Colors.black),
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() { _processing = true; _log = ''; });

    // Création du dossier
    _appendLog('📁 Création du dossier...');
    setState(() => _step = 'Préparation...');
    await _exec('mkdir -p "$wineDir"');

    // Téléchargement synchrone (bloque jusqu'à la fin)
    _appendLog('⬇️ Téléchargement de $version...');
    _appendLog('\$ wget -O "$archive" "$url"');
    setState(() => _step = 'Téléchargement en cours...');

    // Lance wget en synchrone — la session SSH reste ouverte jusqu'à la fin
    await _exec('wget --tries=3 --no-check-certificate --timeout=120 -q -O "$archive" "$url" 2>&1');

    if (!mounted) return;

    // Vérifie que l'archive existe
    final exists = await _exec('[ -f "$archive" ] && stat -c%s "$archive" || echo 0');
    final size = int.tryParse(exists.trim()) ?? 0;
    if (size < 1000000) {
      _appendLog('❌ Erreur : téléchargement échoué ou archive trop petite (${size}o).');
      await _exec('rm -f "$archive"');
      setState(() { _processing = false; _step = ''; });
      return;
    }
    _appendLog('✅ Téléchargement terminé (${(size / 1024 / 1024).toStringAsFixed(0)} Mo).');

    // Extraction synchrone
    _appendLog('\n📦 Extraction en cours (patience, peut prendre plusieurs minutes)...');
    setState(() => _step = 'Extraction...');

    await _exec('tar --strip-components=1 -xJf "$archive" -C "$wineDir" 2>&1 && rm -f "$archive"');

    if (!mounted) return;

    // Vérifie que l'extraction a produit des fichiers
    final fileCount = await _exec('ls "$wineDir" 2>/dev/null | wc -l');
    final count = int.tryParse(fileCount.trim()) ?? 0;
    if (count == 0) {
      _appendLog('❌ Erreur : extraction échouée (dossier vide).');
      setState(() { _processing = false; _step = ''; });
      return;
    }

    _appendLog('✅ Extraction terminée ! ($count éléments)');
    _appendLog('📂 Installé dans : $wineDir');
    setState(() { _step = 'Terminé !'; _processing = false; });

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: Row(children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            const SizedBox(width: 10),
            const Flexible(child: Text('Installation réussie !')),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Chemin :', style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 6),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
              child: SelectableText(wineDir,
                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace', height: 1.5)),
            ),
          ]),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      // Efface le log après fermeture du dialog
      if (mounted) setState(() => _log = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    const accent = Colors.tealAccent;
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
                Text('Wine GE-Custom',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
                const Spacer(),
                if (_loadingReleases)
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent))
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                    onPressed: _fetchReleases,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            // Avertissement
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orangeAccent.withOpacity(0.2)),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 15),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Les versions > 8.15 semblent ne pas fonctionner sous Batocera.',
                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                  )),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchReleases,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ]),
                    ))
                  : _loadingReleases
                      ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(color: Colors.tealAccent),
                          SizedBox(height: 12),
                          Text('Récupération des versions...', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ]))
                      : Column(children: [
                          // Liste des versions
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              itemCount: _releases.length,
                              itemBuilder: (_, i) {
                                final r = _releases[i];
                                final tag = r['tag']!;
                                final isOld = _isCompatible(tag);
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: _processing ? null : () => _install(r),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      child: Row(children: [
                                        Icon(Icons.wine_bar_rounded,
                                            size: 18,
                                            color: isOld ? Colors.tealAccent : Colors.white24),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text('Custom-$tag',
                                            style: TextStyle(
                                              color: isOld ? Colors.white : Colors.white38,
                                              fontSize: 13,
                                              fontWeight: isOld ? FontWeight.w600 : FontWeight.normal,
                                            ))),
                                        if (!isOld)
                                          const Text('> 8.15',
                                              style: TextStyle(color: Colors.orange, fontSize: 10)),
                                        const SizedBox(width: 8),
                                        const Icon(Icons.download_rounded, size: 16, color: Colors.white24),
                                      ]),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          // Barre de progression + log
                          if (_processing) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    backgroundColor: Colors.white.withOpacity(0.08),
                                    valueColor: const AlwaysStoppedAnimation(Colors.tealAccent),
                                    minHeight: 4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(_step, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                              ]),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_log.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A0C10),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                                ),
                                child: SelectableText(_log,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                                        color: Colors.white70, height: 1.5)),
                              ),
                            ),
                        ]),
            ),
          ],
        ),
      ),
    );
  }

  bool _isCompatible(String tag) {
    // Considère compatible si version <= 8.15
    final m = RegExp(r'(\d+)\.(\d+)').firstMatch(tag);
    if (m == null) return true;
    final major = int.tryParse(m.group(1) ?? '') ?? 0;
    final minor = int.tryParse(m.group(2) ?? '') ?? 0;
    return major < 8 || (major == 8 && minor <= 15);
  }
}

// ─── Wine Vanilla ─────────────────────────────────────────────────────────────

class _WineVanillaScreen extends StatefulWidget {
  const _WineVanillaScreen();
  @override
  State<_WineVanillaScreen> createState() => _WineVanillaScreenState();
}

class _WineVanillaScreenState extends State<_WineVanillaScreen> {
  List<Map<String, String>> _releases = [];
  bool _loadingReleases = true;
  bool _processing = false;
  String _log = '';
  String _step = '';
  String? _error;
  final ScrollController _logScrollCtrl = ScrollController();

  static const _installDir = '/userdata/system/wine/custom/';
  static const _apiUrl =
      'https://api.github.com/repos/Kron4ek/Wine-Builds/releases?per_page=300';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchReleases());
  }

  @override
  void dispose() {
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  void _appendLog(String msg) {
    setState(() => _log += '$msg\n');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(_logScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _fetchReleases() async {
    setState(() { _loadingReleases = true; _error = null; });
    final parsed = await _exec(
        'curl -s "$_apiUrl" | jq -r \'.[] | .tag_name + "||" + (first(.assets[]? | select(.name | endswith("amd64.tar.xz"))) | .browser_download_url)\' 2>/dev/null | grep "||http" | head -60');
    if (!mounted) return;
    if (parsed.isEmpty) {
      setState(() {
        _error = 'Impossible de récupérer les versions.\n(connexion internet disponible sur Batocera ? jq installé ?)';
        _loadingReleases = false;
      });
      return;
    }
    final releases = <Map<String, String>>[];
    for (final line in parsed.split('\n')) {
      final parts = line.split('||');
      if (parts.length == 2 && parts[1].trim().startsWith('http')) {
        releases.add({'tag': parts[0].trim(), 'url': parts[1].trim()});
      }
    }
    if (releases.isEmpty) {
      setState(() {
        _error = 'Aucune version trouvée. Vérifiez que jq est installé sur Batocera.';
        _loadingReleases = false;
      });
      return;
    }
    setState(() { _releases = releases; _loadingReleases = false; });
  }

  Future<void> _install(Map<String, String> release) async {
    final tag = release['tag']!;
    final url = release['url']!;
    final version = 'Vanilla-$tag';
    final wineDir = '$_installDir$version';
    final archive = '$wineDir/$version.tar.xz';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Confirmer le téléchargement'),
        content: Text('Version : $version',
            style: const TextStyle(color: Colors.lightBlueAccent, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent, foregroundColor: Colors.black),
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() { _processing = true; _log = ''; });

    _appendLog('📁 Création du dossier...');
    setState(() => _step = 'Préparation...');
    await _exec('mkdir -p "$wineDir"');

    _appendLog('⬇️ Téléchargement de $version...');
    _appendLog('\$ wget -O "$archive" "$url"');
    setState(() => _step = 'Téléchargement en cours...');
    await _exec('wget --tries=3 --no-check-certificate --timeout=120 -q -O "$archive" "$url" 2>&1');
    if (!mounted) return;

    final exists = await _exec('[ -f "$archive" ] && stat -c%s "$archive" || echo 0');
    final size = int.tryParse(exists.trim()) ?? 0;
    if (size < 1000000) {
      _appendLog('❌ Erreur : téléchargement échoué ou archive trop petite (${size}o).');
      await _exec('rm -f "$archive"');
      setState(() { _processing = false; _step = ''; });
      return;
    }
    _appendLog('✅ Téléchargement terminé (${(size / 1024 / 1024).toStringAsFixed(0)} Mo).');

    _appendLog('\n📦 Extraction en cours (patience, peut prendre plusieurs minutes)...');
    setState(() => _step = 'Extraction...');
    await _exec('tar --strip-components=1 -xJf "$archive" -C "$wineDir" 2>&1 && rm -f "$archive"');
    if (!mounted) return;

    final fileCount = await _exec('ls "$wineDir" 2>/dev/null | wc -l');
    final count = int.tryParse(fileCount.trim()) ?? 0;
    if (count == 0) {
      _appendLog('❌ Erreur : extraction échouée (dossier vide).');
      setState(() { _processing = false; _step = ''; });
      return;
    }

    _appendLog('✅ Extraction terminée ! ($count éléments)');
    _appendLog('📂 Installé dans : $wineDir');
    setState(() { _step = 'Terminé !'; _processing = false; });

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Installation réussie !')),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Chemin :', style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 6),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
              child: SelectableText(wineDir,
                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace', height: 1.5)),
            ),
          ]),
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
    const accent = Colors.lightBlueAccent;
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
                Text('Wine Vanilla',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
                const Spacer(),
                if (_loadingReleases)
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.lightBlueAccent))
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                    onPressed: _fetchReleases,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchReleases,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ]),
                    ))
                  : _loadingReleases
                      ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(color: Colors.lightBlueAccent),
                          SizedBox(height: 12),
                          Text('Récupération des versions...', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ]))
                      : Column(children: [
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              itemCount: _releases.length,
                              itemBuilder: (_, i) {
                                final r = _releases[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: _processing ? null : () => _install(r),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      child: Row(children: [
                                        const Icon(Icons.wine_bar_outlined, size: 18, color: Colors.lightBlueAccent),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text('Vanilla-${r['tag']}',
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                                        const Icon(Icons.download_rounded, size: 16, color: Colors.white24),
                                      ]),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_processing) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: const LinearProgressIndicator(
                                    backgroundColor: Color(0x14FFFFFF),
                                    valueColor: AlwaysStoppedAnimation(Colors.lightBlueAccent),
                                    minHeight: 4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(_step, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                              ]),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_log.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A0C10),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                                ),
                                child: SelectableText(_log,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                                        color: Colors.white70, height: 1.5)),
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

// ─── Wine TKG-Staging ─────────────────────────────────────────────────────────

class _WineTkgScreen extends StatefulWidget {
  const _WineTkgScreen();
  @override
  State<_WineTkgScreen> createState() => _WineTkgScreenState();
}

class _WineTkgScreenState extends State<_WineTkgScreen> {
  List<Map<String, String>> _releases = [];
  bool _loadingReleases = true;
  bool _processing = false;
  String _log = '';
  String _step = '';
  String? _error;
  final ScrollController _logScrollCtrl = ScrollController();

  static const _installDir = '/userdata/system/wine/custom/';
  static const _apiUrl =
      'https://api.github.com/repos/Kron4ek/Wine-Builds/releases?per_page=300';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchReleases());
  }

  @override
  void dispose() {
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  void _appendLog(String msg) {
    setState(() => _log += '$msg\n');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(_logScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _fetchReleases() async {
    setState(() { _loadingReleases = true; _error = null; });
    // Filtre : exclut proton, prend l'asset staging-tkg amd64.tar.xz
    final parsed = await _exec(
        'curl -s "$_apiUrl" | jq -r \'.[] | select(.name | ascii_downcase | contains("proton") | not) | .tag_name + "||" + (first(.assets[]? | select(.name | (contains("staging-tkg") and endswith("amd64.tar.xz")))) | .browser_download_url)\' 2>/dev/null | grep "||http" | head -60');
    if (!mounted) return;
    if (parsed.isEmpty) {
      setState(() {
        _error = 'Impossible de récupérer les versions.\n(connexion internet disponible sur Batocera ? jq installé ?)';
        _loadingReleases = false;
      });
      return;
    }
    final releases = <Map<String, String>>[];
    for (final line in parsed.split('\n')) {
      final parts = line.split('||');
      if (parts.length == 2 && parts[1].trim().startsWith('http')) {
        releases.add({'tag': parts[0].trim(), 'url': parts[1].trim()});
      }
    }
    if (releases.isEmpty) {
      setState(() {
        _error = 'Aucune version trouvée. Vérifiez que jq est installé sur Batocera.';
        _loadingReleases = false;
      });
      return;
    }
    setState(() { _releases = releases; _loadingReleases = false; });
  }

  Future<void> _install(Map<String, String> release) async {
    final tag = release['tag']!;
    final url = release['url']!;
    final version = 'Tkg-$tag';
    final wineDir = '$_installDir$version';
    final archive = '$wineDir/$version.tar.xz';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Confirmer le téléchargement'),
        content: Text('Version : $version',
            style: const TextStyle(color: Colors.deepPurpleAccent, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurpleAccent, foregroundColor: Colors.white),
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() { _processing = true; _log = ''; });

    _appendLog('📁 Création du dossier...');
    setState(() => _step = 'Préparation...');
    await _exec('mkdir -p "$wineDir"');

    _appendLog('⬇️ Téléchargement de $version...');
    _appendLog('\$ wget -O "$archive" "$url"');
    setState(() => _step = 'Téléchargement en cours...');
    await _exec('wget --tries=3 --no-check-certificate --timeout=120 -q -O "$archive" "$url" 2>&1');
    if (!mounted) return;

    final exists = await _exec('[ -f "$archive" ] && stat -c%s "$archive" || echo 0');
    final size = int.tryParse(exists.trim()) ?? 0;
    if (size < 1000000) {
      _appendLog('❌ Erreur : téléchargement échoué ou archive trop petite (${size}o).');
      await _exec('rm -f "$archive"');
      setState(() { _processing = false; _step = ''; });
      return;
    }
    _appendLog('✅ Téléchargement terminé (${(size / 1024 / 1024).toStringAsFixed(0)} Mo).');

    _appendLog('\n📦 Extraction en cours (patience, peut prendre plusieurs minutes)...');
    setState(() => _step = 'Extraction...');
    await _exec('tar --strip-components=1 -xJf "$archive" -C "$wineDir" 2>&1 && rm -f "$archive"');
    if (!mounted) return;

    final fileCount = await _exec('ls "$wineDir" 2>/dev/null | wc -l');
    final count = int.tryParse(fileCount.trim()) ?? 0;
    if (count == 0) {
      _appendLog('❌ Erreur : extraction échouée (dossier vide).');
      setState(() { _processing = false; _step = ''; });
      return;
    }

    _appendLog('✅ Extraction terminée ! ($count éléments)');
    _appendLog('📂 Installé dans : $wineDir');
    setState(() { _step = 'Terminé !'; _processing = false; });

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Installation réussie !')),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Chemin :', style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 6),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
              child: SelectableText(wineDir,
                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace', height: 1.5)),
            ),
          ]),
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
                Text('Wine TKG-Staging',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
                const Spacer(),
                if (_loadingReleases)
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurpleAccent))
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                    onPressed: _fetchReleases,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchReleases,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ]),
                    ))
                  : _loadingReleases
                      ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(color: Colors.deepPurpleAccent),
                          SizedBox(height: 12),
                          Text('Récupération des versions...', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ]))
                      : Column(children: [
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              itemCount: _releases.length,
                              itemBuilder: (_, i) {
                                final r = _releases[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: _processing ? null : () => _install(r),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      child: Row(children: [
                                        const Icon(Icons.wine_bar_rounded, size: 18, color: Colors.deepPurpleAccent),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text('Tkg-${r['tag']}',
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                                        const Icon(Icons.download_rounded, size: 16, color: Colors.white24),
                                      ]),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_processing) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: const LinearProgressIndicator(
                                    backgroundColor: Color(0x14FFFFFF),
                                    valueColor: AlwaysStoppedAnimation(Colors.deepPurpleAccent),
                                    minHeight: 4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(_step, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                              ]),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_log.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A0C10),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                                ),
                                child: SelectableText(_log,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                                        color: Colors.white70, height: 1.5)),
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

// ─── GE-Proton ────────────────────────────────────────────────────────────────

class _GeProtonScreen extends StatefulWidget {
  const _GeProtonScreen();
  @override
  State<_GeProtonScreen> createState() => _GeProtonScreenState();
}

class _GeProtonScreenState extends State<_GeProtonScreen> {
  List<Map<String, String>> _releases = [];
  bool _loadingReleases = true;
  bool _processing = false;
  String _log = '';
  String _step = '';
  String? _error;
  final ScrollController _logScrollCtrl = ScrollController();

  static const _installDir = '/userdata/system/wine/custom/';
  static const _apiUrl =
      'https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases?per_page=100';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchReleases());
  }

  @override
  void dispose() {
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  void _appendLog(String msg) {
    setState(() => _log += '$msg\n');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(_logScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _fetchReleases() async {
    setState(() { _loadingReleases = true; _error = null; });
    // Asset : .tar.gz (pas .tar.xz)
    final parsed = await _exec(
        'curl -s "$_apiUrl" | jq -r \'.[] | .tag_name + "||" + (first(.assets[]? | select(.name | endswith(".tar.gz"))) | .browser_download_url)\' 2>/dev/null | grep "||http" | head -60');
    if (!mounted) return;
    if (parsed.isEmpty) {
      setState(() {
        _error = 'Impossible de récupérer les versions.\n(connexion internet disponible sur Batocera ? jq installé ?)';
        _loadingReleases = false;
      });
      return;
    }
    final releases = <Map<String, String>>[];
    for (final line in parsed.split('\n')) {
      final parts = line.split('||');
      if (parts.length == 2 && parts[1].trim().startsWith('http')) {
        releases.add({'tag': parts[0].trim(), 'url': parts[1].trim()});
      }
    }
    if (releases.isEmpty) {
      setState(() {
        _error = 'Aucune version trouvée. Vérifiez que jq est installé sur Batocera.';
        _loadingReleases = false;
      });
      return;
    }
    setState(() { _releases = releases; _loadingReleases = false; });
  }

  Future<void> _install(Map<String, String> release) async {
    final tag = release['tag']!;
    final url = release['url']!;
    final version = tag; // pas de préfixe pour GE-Proton
    final wineDir = '$_installDir$version';
    final archive = '$wineDir/$version.tar.gz'; // .tar.gz

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Confirmer le téléchargement'),
        content: Text('Version : $version',
            style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent, foregroundColor: Colors.black),
            child: const Text('Télécharger'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() { _processing = true; _log = ''; });

    _appendLog('📁 Création du dossier...');
    setState(() => _step = 'Préparation...');
    await _exec('mkdir -p "$wineDir"');

    _appendLog('⬇️ Téléchargement de $version...');
    _appendLog('\$ wget -O "$archive" "$url"');
    setState(() => _step = 'Téléchargement en cours...');
    // .tar.gz (synchrone)
    await _exec('wget --tries=3 --no-check-certificate --timeout=120 -q -O "$archive" "$url" 2>&1');
    if (!mounted) return;

    final exists = await _exec('[ -f "$archive" ] && stat -c%s "$archive" || echo 0');
    final size = int.tryParse(exists.trim()) ?? 0;
    if (size < 1000000) {
      _appendLog('❌ Erreur : téléchargement échoué ou archive trop petite (${size}o).');
      await _exec('rm -f "$archive"');
      setState(() { _processing = false; _step = ''; });
      return;
    }
    _appendLog('✅ Téléchargement terminé (${(size / 1024 / 1024).toStringAsFixed(0)} Mo).');

    _appendLog('\n📦 Extraction en cours (patience, peut prendre plusieurs minutes)...');
    setState(() => _step = 'Extraction...');
    // -xzf pour .tar.gz (pas -xJf)
    await _exec('tar --strip-components=1 -xzf "$archive" -C "$wineDir" 2>&1 && rm -f "$archive"');
    if (!mounted) return;

    // Si le sous-dossier "files" existe, on déplace son contenu vers wineDir
    final hasFiles = await _exec('[ -d "$wineDir/files" ] && echo "yes" || echo "no"');
    if (hasFiles.trim() == 'yes') {
      _appendLog('📂 Déplacement du contenu files/...');
      await _exec('rsync -a --remove-source-files "$wineDir/files/" "$wineDir/" && rm -rf "$wineDir/files"');
    }

    final fileCount = await _exec('ls "$wineDir" 2>/dev/null | wc -l');
    final count = int.tryParse(fileCount.trim()) ?? 0;
    if (count == 0) {
      _appendLog('❌ Erreur : extraction échouée (dossier vide).');
      setState(() { _processing = false; _step = ''; });
      return;
    }

    _appendLog('✅ Extraction terminée ! ($count éléments)');
    _appendLog('📂 Installé dans : $wineDir');
    setState(() { _step = 'Terminé !'; _processing = false; });

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Installation réussie !')),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Chemin :', style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 6),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
              child: SelectableText(wineDir,
                  style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace', height: 1.5)),
            ),
          ]),
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
                Text('GE-Proton',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
                const Spacer(),
                if (_loadingReleases)
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent))
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                    onPressed: _fetchReleases,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _error != null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, color: Colors.redAccent, size: 36),
                        const SizedBox(height: 12),
                        Text(_error!, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _fetchReleases,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Réessayer'),
                        ),
                      ]),
                    ))
                  : _loadingReleases
                      ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          CircularProgressIndicator(color: Colors.orangeAccent),
                          SizedBox(height: 12),
                          Text('Récupération des versions...', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ]))
                      : Column(children: [
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                              itemCount: _releases.length,
                              itemBuilder: (_, i) {
                                final r = _releases[i];
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: _processing ? null : () => _install(r),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      child: Row(children: [
                                        const Icon(Icons.bolt_rounded, size: 18, color: Colors.orangeAccent),
                                        const SizedBox(width: 10),
                                        Expanded(child: Text(r['tag']!,
                                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                                        const Icon(Icons.download_rounded, size: 16, color: Colors.white24),
                                      ]),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (_processing) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: const LinearProgressIndicator(
                                    backgroundColor: Color(0x14FFFFFF),
                                    valueColor: AlwaysStoppedAnimation(Colors.orangeAccent),
                                    minHeight: 4,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(_step, style: const TextStyle(color: Colors.white38, fontSize: 10)),
                              ]),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (_log.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0A0C10),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                                ),
                                child: SelectableText(_log,
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                                        color: Colors.white70, height: 1.5)),
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

// ─── GE-Custom V40 (split) ────────────────────────────────────────────────────

class _GeCustomV40Screen extends StatefulWidget {
  const _GeCustomV40Screen();
  @override
  State<_GeCustomV40Screen> createState() => _GeCustomV40ScreenState();
}

class _GeCustomV40ScreenState extends State<_GeCustomV40Screen> {
  bool _processing = false;
  String _log = '';
  String _step = '';
  final ScrollController _logScrollCtrl = ScrollController();

  static const _url1 = 'https://github.com/foclabroc/toolbox/raw/refs/heads/main/wine-tools/ge-customv40.tar.xz.001';
  static const _url2 = 'https://github.com/foclabroc/toolbox/raw/refs/heads/main/wine-tools/ge-customv40.tar.xz.002';
  static const _downloadDir = '/tmp/ge-custom-download';
  static const _extractDir = '/userdata/system/wine/custom';

  @override
  void dispose() {
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  void _appendLog(String msg) {
    setState(() => _log += '$msg\n');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(_logScrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _install() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Confirmer l\'installation'),
        content: const Text('Télécharger et installer ge-custom V40 ?',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black),
            child: const Text('Installer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() { _processing = true; _log = ''; });

    // Préparation des dossiers
    _appendLog('📁 Préparation des dossiers...');
    setState(() => _step = 'Préparation...');
    await _exec('mkdir -p "$_downloadDir" "$_extractDir"');

    // Téléchargement partie 1
    _appendLog('⬇️ Téléchargement partie 1/2...');
    setState(() => _step = 'Téléchargement 1/2...');
    await _exec('wget --tries=3 --no-check-certificate --timeout=120 -q -O "$_downloadDir/ge-customv40.tar.xz.001" "$_url1"');
    if (!mounted) return;

    final size1 = int.tryParse(await _exec('stat -c%s "$_downloadDir/ge-customv40.tar.xz.001" 2>/dev/null || echo 0')) ?? 0;
    if (size1 < 1000000) {
      _appendLog('❌ Erreur : téléchargement partie 1 échoué.');
      await _exec('rm -rf "$_downloadDir"');
      setState(() { _processing = false; _step = ''; });
      return;
    }
    _appendLog('✅ Partie 1 OK (${(size1 / 1024 / 1024).toStringAsFixed(0)} Mo).');

    // Téléchargement partie 2
    _appendLog('⬇️ Téléchargement partie 2/2...');
    setState(() => _step = 'Téléchargement 2/2...');
    await _exec('wget --tries=3 --no-check-certificate --timeout=120 -q -O "$_downloadDir/ge-customv40.tar.xz.002" "$_url2"');
    if (!mounted) return;

    final size2 = int.tryParse(await _exec('stat -c%s "$_downloadDir/ge-customv40.tar.xz.002" 2>/dev/null || echo 0')) ?? 0;
    if (size2 < 1000000) {
      _appendLog('❌ Erreur : téléchargement partie 2 échoué.');
      await _exec('rm -rf "$_downloadDir"');
      setState(() { _processing = false; _step = ''; });
      return;
    }
    _appendLog('✅ Partie 2 OK (${(size2 / 1024 / 1024).toStringAsFixed(0)} Mo).');

    // Assemblage
    _appendLog('\n🔗 Assemblage des 2 parties...');
    setState(() => _step = 'Assemblage...');
    await _exec('cat "$_downloadDir/ge-customv40.tar.xz.001" "$_downloadDir/ge-customv40.tar.xz.002" > "$_downloadDir/ge-customv40.tar.xz"');
    if (!mounted) return;

    final sizeAssembled = int.tryParse(await _exec('stat -c%s "$_downloadDir/ge-customv40.tar.xz" 2>/dev/null || echo 0')) ?? 0;
    if (sizeAssembled < 1000000) {
      _appendLog('❌ Erreur : assemblage échoué.');
      await _exec('rm -rf "$_downloadDir"');
      setState(() { _processing = false; _step = ''; });
      return;
    }
    _appendLog('✅ Assemblage OK (${(sizeAssembled / 1024 / 1024).toStringAsFixed(0)} Mo).');

    // Décompression .xz
    _appendLog('\n📦 Décompression .xz (peut prendre plusieurs minutes)...');
    setState(() => _step = 'Décompression .xz...');
    await _exec('cd "$_downloadDir" && xz -d ge-customv40.tar.xz');
    if (!mounted) return;

    final hasTar = await _exec('[ -f "$_downloadDir/ge-customv40.tar" ] && echo yes || echo no');
    if (hasTar.trim() != 'yes') {
      _appendLog('❌ Erreur : décompression .xz échouée.');
      await _exec('rm -rf "$_downloadDir"');
      setState(() { _processing = false; _step = ''; });
      return;
    }
    _appendLog('✅ Décompression .xz OK.');

    // Suppression ancien dossier + extraction .tar
    _appendLog('\n🗑️ Suppression de l\'ancien dossier ge-custom...');
    await _exec('rm -rf "$_extractDir/ge-custom"');

    _appendLog('📦 Extraction .tar...');
    setState(() => _step = 'Extraction .tar...');
    await _exec('tar -xf "$_downloadDir/ge-customv40.tar" -C "$_extractDir"');
    if (!mounted) return;

    final ok2 = await _exec('[ -d "$_extractDir/ge-custom" ] && echo yes || echo no');
    if (ok2.trim() != 'yes') {
      _appendLog('❌ Erreur : extraction échouée.');
      await _exec('rm -rf "$_downloadDir"');
      setState(() { _processing = false; _step = ''; });
      return;
    }

    // Nettoyage
    _appendLog('🗑️ Nettoyage des fichiers temporaires...');
    await _exec('rm -rf "$_downloadDir"');

    _appendLog('✅ Installation de ge-custom V40 terminée !');
    _appendLog('📂 Installé dans : $_extractDir/ge-custom');
    setState(() { _step = 'Terminé !'; _processing = false; });

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Installation réussie !')),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Chemin :', style: TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 6),
            Container(
              width: double.maxFinite,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
              child: const SelectableText('$_extractDir/ge-custom',
                  style: TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace', height: 1.5)),
            ),
          ]),
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
                Text('GE-Custom V40',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
              ]),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.info_outline_rounded, color: Colors.greenAccent, size: 18),
                      SizedBox(width: 8),
                      Text('ge-custom V40', style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w700, fontSize: 15)),
                    ]),
                    const SizedBox(height: 10),
                    const Text('Version fixe hébergée sur GitHub.\nTéléchargement en 2 parties, assemblage et extraction automatiques.',
                        style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.5)),
                    const SizedBox(height: 8),
                    const Text('Destination : /userdata/system/wine/custom/ge-custom',
                        style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _processing ? null : _install,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.greenAccent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        icon: _processing
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Icon(Icons.download_rounded),
                        label: Text(_processing ? _step : 'Télécharger et installer'),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            if (_processing) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: const LinearProgressIndicator(
                    backgroundColor: Color(0x14FFFFFF),
                    valueColor: AlwaysStoppedAnimation(Colors.greenAccent),
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
                      controller: _logScrollCtrl,
                      child: SelectableText(_log,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                              color: Colors.white70, height: 1.5)),
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

// ─── Wine Bottle Manager ──────────────────────────────────────────────────────

class _WineBottleManagerScreen extends StatefulWidget {
  const _WineBottleManagerScreen();
  @override
  State<_WineBottleManagerScreen> createState() => _WineBottleManagerScreenState();
}

class _WineBottleManagerScreenState extends State<_WineBottleManagerScreen> {
  List<String> _bottles = [];
  bool _loading = true;
  String? _error;

  static const _targetDir = '/userdata/system/wine-bottles/windows';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBottles());
  }

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  Future<void> _loadBottles() async {
    setState(() { _loading = true; _error = null; });
    final raw = await _exec(
        'find "$_targetDir" -maxdepth 2 -type d \\( -name "*.wine" -o -name "*.wsquashfs" -o -name "*.wtgz" \\) 2>/dev/null | sort');
    if (!mounted) return;
    if (raw.isEmpty) {
      setState(() { _bottles = []; _loading = false; });
      return;
    }
    setState(() {
      _bottles = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
      _loading = false;
    });
  }

  // Affiche toujours depuis "wine-bottles/" en supprimant le préfixe /userdata/system/
  String _displayPath(String fullPath) {
    const prefix = '/userdata/system/';
    if (fullPath.startsWith(prefix)) {
      return fullPath.substring(prefix.length);
    }
    return fullPath;
  }

  Future<void> _confirmDelete(String path) async {
    final display = _displayPath(path);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Row(children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
          SizedBox(width: 8),
          Flexible(child: Text('Supprimer la bouteille ?', overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('⚠️ Cette action est irréversible.\nLes sauvegardes et paramètres du jeu seront perdus.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          const SizedBox(height: 12),
          Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
            child: Text(display,
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await _exec('rm -rf "$path"');
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('🗑️ $display supprimée.'),
      backgroundColor: const Color(0xFF1C2230),
    ));
    _loadBottles();
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
                Text('Wine Bottle Manager',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 18)),
                const Spacer(),
                if (_loading)
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                    onPressed: _loadBottles,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ]),
            ),
            // Avertissement
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.redAccent.withOpacity(0.2)),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 15),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Les bouteilles contiennent les paramètres et sauvegardes de vos jeux. La suppression est irréversible.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 11),
                  )),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(color: Colors.redAccent),
                      SizedBox(height: 12),
                      Text('Recherche des bouteilles...', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ]))
                  : _bottles.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.wine_bar_outlined, color: Colors.white24, size: 48),
                          const SizedBox(height: 12),
                          const Text('Aucune bouteille trouvée.',
                              style: TextStyle(color: Colors.white38, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(_targetDir,
                              style: const TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace')),
                        ]))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _bottles.length,
                          itemBuilder: (_, i) {
                            final path = _bottles[i];
                            final display = _displayPath(path);
                            final parts = display.split('/');
                            final name = parts.last;
                            final parent = parts.length >= 2
                                ? parts.sublist(0, parts.length - 1).join('/')
                                : '';
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                                leading: const Icon(Icons.wine_bar_rounded, color: Colors.redAccent, size: 22),
                                title: Text(name,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                subtitle: Text(parent,
                                    style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace')),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                                  onPressed: () => _confirmDelete(path),
                                  tooltip: 'Supprimer',
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Runner Manager ───────────────────────────────────────────────────────────

class _RunnerManagerScreen extends StatefulWidget {
  const _RunnerManagerScreen();
  @override
  State<_RunnerManagerScreen> createState() => _RunnerManagerScreenState();
}

class _RunnerManagerScreenState extends State<_RunnerManagerScreen> {
  List<Map<String, String>> _runners = [];
  bool _loading = true;

  static const _customDir = '/userdata/system/wine/custom';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRunners());
  }

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  Future<void> _loadRunners() async {
    setState(() => _loading = true);
    // Vérifie que le dossier existe
    final exists = await _exec('[ -d "$_customDir" ] && echo yes || echo no');
    if (!mounted) return;
    if (exists.trim() != 'yes') {
      setState(() { _runners = []; _loading = false; });
      return;
    }
    // Liste les sous-dossiers avec taille et date
    final raw = await _exec(
        'find "$_customDir" -mindepth 1 -maxdepth 1 -type d | sort | while read d; do '
        'nom=\$(basename "\$d"); '
        'taille=\$(du -sh "\$d" 2>/dev/null | cut -f1); '
        'date=\$(stat -c "%y" "\$d" 2>/dev/null | cut -d"." -f1); '
        'echo "\$nom||\$taille||\$date"; done');
    if (!mounted) return;
    final runners = <Map<String, String>>[];
    for (final line in raw.split('\n')) {
      final parts = line.split('||');
      if (parts.length == 3 && parts[0].trim().isNotEmpty) {
        runners.add({
          'name': parts[0].trim(),
          'size': parts[1].trim(),
          'date': parts[2].trim(),
        });
      }
    }
    setState(() { _runners = runners; _loading = false; });
  }

  Future<void> _confirmDelete(Map<String, String> runner) async {
    final name = runner['name']!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Row(children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 22),
          SizedBox(width: 8),
          Flexible(child: Text('Supprimer le runner ?', overflow: TextOverflow.ellipsis)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('⚠️ Cette action est irréversible.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
          const SizedBox(height: 10),
          Container(
            width: double.maxFinite,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(6)),
            child: Text(name,
                style: const TextStyle(color: Colors.white70, fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.w600)),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    // Sécurité : vérifie que le nom est valide
    if (name.isEmpty || name == '/') return;
    await _exec('rm -rf "$_customDir/$name"');
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('🗑️ Runner "$name" supprimé.'),
      backgroundColor: const Color(0xFF1C2230),
    ));
    _loadRunners();
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
                Text('Runner Manager',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
                const Spacer(),
                if (_loading)
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))
                else
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 20),
                    onPressed: _loadRunners,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(_customDir,
                  style: const TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace')),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(color: Colors.redAccent),
                      SizedBox(height: 12),
                      Text('Chargement des runners...', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ]))
                  : _runners.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.folder_off_rounded, color: Colors.white24, size: 48),
                          const SizedBox(height: 12),
                          const Text('Aucun runner trouvé.',
                              style: TextStyle(color: Colors.white38, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(_customDir,
                              style: const TextStyle(color: Colors.white24, fontSize: 10, fontFamily: 'monospace')),
                        ]))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: _runners.length,
                          itemBuilder: (_, i) {
                            final r = _runners[i];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                leading: const Icon(Icons.folder_rounded, color: Colors.tealAccent, size: 26),
                                title: Text(r['name']!,
                                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                subtitle: Text('${r['size']}  •  ${r['date']}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 22),
                                  onPressed: () => _confirmDelete(r),
                                  tooltip: 'Supprimer',
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Winetricks ───────────────────────────────────────────────────────────────

class _WinetricksScreen extends StatefulWidget {
  const _WinetricksScreen();
  @override
  State<_WinetricksScreen> createState() => _WinetricksScreenState();
}

class _WinetricksScreenState extends State<_WinetricksScreen> {
  // Étapes : bottle → mode → pick → confirm → install
  List<String> _bottles = [];
  bool _loadingBottles = true;
  String? _selectedBottle;

  // Liste tricks
  bool _loadingTricks = false;
  List<Map<String, String>> _tricks = [];
  String? _selectedTrick;
  bool _commonMode = true; // true = liste courante, false = liste complète

  // Installation
  bool _installing = false;
  String _log = '';
  final ScrollController _logScroll = ScrollController();

  static const _commonTricks = [
    {'id': 'vcrun2008',  'desc': 'Visual C++ 2008'},
    {'id': 'vcrun2010',  'desc': 'Visual C++ 2010'},
    {'id': 'vcrun2012',  'desc': 'Visual C++ 2012'},
    {'id': 'vcrun2013',  'desc': 'Visual C++ 2013'},
    {'id': 'vcrun2022',  'desc': 'Visual C++ 2015 à 2022'},
    {'id': 'openal',     'desc': 'OpenAL Runtime Creative 2023'},
    {'id': 'directplay', 'desc': 'MS DirectPlay from DirectX'},
    {'id': 'd3dx9_43',   'desc': 'DirectX9 (d3dx9_43)'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadBottles());
  }

  @override
  void dispose() {
    _logScroll.dispose();
    super.dispose();
  }

  Future<String> _exec(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return String.fromCharCodes(bytes).trim();
    } catch (_) { return ''; }
  }

  void _appendLog(String msg) {
    setState(() => _log += '$msg\n');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScroll.hasClients) {
        _logScroll.animateTo(_logScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _loadBottles() async {
    setState(() { _loadingBottles = true; _bottles = []; });
    final raw = await _exec(
      'find /userdata/system/wine-bottles -type d -name "*.wine" 2>/dev/null; '
      'find /userdata/roms/windows -maxdepth 1 -type d -name "*.wine" 2>/dev/null'
    );
    if (!mounted) return;
    final bottles = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
    setState(() { _bottles = bottles; _loadingBottles = false; });
  }

  Future<void> _loadFullTricks() async {
    setState(() { _loadingTricks = true; _tricks = []; });
    _appendLog('⏳ Récupération de la liste Winetricks officielle...');
    const url = 'https://raw.githubusercontent.com/Winetricks/winetricks/master/files/verbs/all.txt';
    final raw = await _exec('curl -Ls "$url" 2>/dev/null');
    if (!mounted) return;
    if (raw.isEmpty) {
      setState(() { _loadingTricks = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Impossible de récupérer la liste Winetricks.'),
          backgroundColor: Colors.redAccent,
        ));
      }
      return;
    }
    final tricks = <Map<String, String>>[];
    for (final line in raw.split('\n')) {
      if (line.startsWith('=====') || line.trim().isEmpty) continue;
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) continue;
      final id = parts[0];
      final desc = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      tricks.add({'id': id, 'desc': desc});
    }
    _appendLog('✅ ${tricks.length} composants disponibles.');
    setState(() { _tricks = tricks; _loadingTricks = false; });
  }

  Future<void> _install(String bottle, String trick) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Confirmer l\'installation'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Trick :', style: TextStyle(color: Colors.white38, fontSize: 11)),
          Text(trick, style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 10),
          const Text('Bouteille :', style: TextStyle(color: Colors.white38, fontSize: 11)),
          Text(bottle.split('/').last, style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, foregroundColor: Colors.white),
            child: const Text('Installer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() { _installing = true; _log = ''; });
    _appendLog('⚙️ Lancement de l\'installation sur l\'écran de Batocera...');
    _appendLog('Regardez l\'écran de Batocera pour suivre l\'installation.\n');

    // Lance xterm + écrit un flag /tmp/_wt_done quand terminé
    await _exec('rm -f /tmp/_wt_done');
    await _exec(
      'DISPLAY=:0.0 xterm -fs 12 -maximized -fg white -bg black -fa "DejaVuSansMono" -en UTF-8 '
      "-e bash -c 'unclutter-remote -s; batocera-wine windows tricks \"$bottle\" \"$trick\" unattended; unclutter-remote -h; touch /tmp/_wt_done' &"
    );
    // Attend l'apparition du flag (toutes les 3s)
    await Future.delayed(const Duration(seconds: 3));
    while (true) {
      if (!mounted) break;
      final done = await _exec('[ -f /tmp/_wt_done ] && echo yes || echo no');
      if (done.trim() == 'yes') break;
      await Future.delayed(const Duration(seconds: 3));
      _appendLog('  installation en cours...');
    }
    await _exec('rm -f /tmp/_wt_done');
    if (!mounted) return;

    _appendLog('✅ Installation terminée !');
    setState(() { _installing = false; });

    if (mounted) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF50FA7B), size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('Winetricks installé !')),
          ]),
          content: Text('[$trick] appliqué sur\n${bottle.split('/').last}',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
          actions: [
            ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      if (mounted) setState(() => _log = '');
    }
  }

  String _bottleDisplay(String path) {
    // Affiche depuis wine-bottles/ ou roms/
    final prefixes = ['/userdata/system/', '/userdata/'];
    for (final p in prefixes) {
      if (path.startsWith(p)) return path.substring(p.length);
    }
    return path;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 24, 0),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: const Icon(Icons.arrow_back_rounded, color: Colors.white54),
                ),
                const SizedBox(width: 12),
                Text('Winetricks',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
                if (_loadingBottles || _loadingTricks) ...[
                  const Spacer(),
                  const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.purpleAccent)),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loadingBottles
                  ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(color: Colors.purpleAccent),
                      SizedBox(height: 12),
                      Text('Recherche des bouteilles...', style: TextStyle(color: Colors.white38, fontSize: 12)),
                    ]))
                  : _bottles.isEmpty
                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.wine_bar_outlined, color: Colors.white24, size: 48),
                          const SizedBox(height: 12),
                          const Text('Aucune bouteille .wine trouvée.',
                              style: TextStyle(color: Colors.white38, fontSize: 13)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _loadBottles,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Réessayer'),
                          ),
                        ]))
                      : _selectedBottle == null
                          ? _buildBottleList()
                          : _buildTricksPicker(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottleList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Sélectionnez une bouteille Wine :',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: _bottles.length,
            itemBuilder: (_, i) {
              final b = _bottles[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _selectedBottle = b),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(children: [
                      const Icon(Icons.wine_bar_rounded, size: 20, color: Colors.purpleAccent),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(b.split('/').last,
                            style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        Text(_bottleDisplay(b),
                            style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace')),
                      ])),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white24),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTricksPicker() {
    final bottle = _selectedBottle!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bouteille sélectionnée
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            const Icon(Icons.wine_bar_rounded, size: 16, color: Colors.purpleAccent),
            const SizedBox(width: 6),
            Expanded(child: Text(bottle.split('/').last,
                style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.w600, fontSize: 13),
                overflow: TextOverflow.ellipsis)),
            TextButton(
              onPressed: () => setState(() { _selectedBottle = null; _tricks = []; _log = ''; }),
              child: const Text('Changer', style: TextStyle(fontSize: 11)),
            ),
          ]),
        ),
        // Toggle mode
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() { _commonMode = true; _tricks = []; }),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _commonMode ? Colors.purpleAccent.withOpacity(0.15) : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                    border: Border.all(color: _commonMode ? Colors.purpleAccent : Colors.white12),
                  ),
                  child: Center(child: Text('Courants',
                      style: TextStyle(color: _commonMode ? Colors.purpleAccent : Colors.white38, fontSize: 12, fontWeight: FontWeight.w600))),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  setState(() => _commonMode = false);
                  if (_tricks.isEmpty && !_loadingTricks) _loadFullTricks();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: !_commonMode ? Colors.purpleAccent.withOpacity(0.15) : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                    border: Border.all(color: !_commonMode ? Colors.purpleAccent : Colors.white12),
                  ),
                  child: Center(child: Text('Liste complète',
                      style: TextStyle(color: !_commonMode ? Colors.purpleAccent : Colors.white38, fontSize: 12, fontWeight: FontWeight.w600))),
                ),
              ),
            ),
          ]),
        ),
        // Liste tricks
        Expanded(
          child: _loadingTricks
              ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(color: Colors.purpleAccent),
                  SizedBox(height: 12),
                  Text('Chargement de la liste officielle...', style: TextStyle(color: Colors.white38, fontSize: 12)),
                ]))
              : Column(children: [
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      itemCount: _commonMode ? _commonTricks.length : _tricks.length,
                      itemBuilder: (_, i) {
                        final t = _commonMode ? _commonTricks[i] : _tricks[i];
                        final id = t['id']!;
                        final desc = t['desc']!;
                        final selected = _selectedTrick == id;
                        return Card(
                          margin: const EdgeInsets.only(bottom: 6),
                          color: selected ? Colors.purpleAccent.withOpacity(0.12) : null,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _installing ? null : () {
                              setState(() => _selectedTrick = id);
                              _install(bottle, id);
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Row(children: [
                                const Icon(Icons.extension_rounded, size: 16, color: Colors.purpleAccent),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(id, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                  if (desc.isNotEmpty)
                                    Text(desc, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                                ])),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (_installing) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: LinearProgressIndicator(
                        backgroundColor: Color(0x14FFFFFF),
                        valueColor: AlwaysStoppedAnimation(Colors.purpleAccent),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_log.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(maxHeight: 120),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0A0C10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white.withOpacity(0.06)),
                        ),
                        child: SingleChildScrollView(
                          controller: _logScroll,
                          child: SelectableText(_log,
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 10,
                                  color: Colors.white70, height: 1.5)),
                        ),
                      ),
                    ),
                ]),
        ),
      ],
    );
  }
}
