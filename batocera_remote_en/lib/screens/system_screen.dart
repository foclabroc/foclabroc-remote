import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/app_state.dart';

class SystemScreen extends StatelessWidget {
  const SystemScreen({super.key});

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
              child: Text('System', style: Theme.of(context).textTheme.headlineMedium),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

              _SectionHeader(label: 'Volume', icon: Icons.volume_up_rounded),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Icon(
                        state.volume == 0
                            ? Icons.volume_off_rounded
                            : state.volume < 50
                                ? Icons.volume_down_rounded
                                : Icons.volume_up_rounded,
                        color: accent,
                      ),
                      Expanded(
                        child: Slider(
                          value: state.volume.toDouble(),
                          min: 0, max: 100, divisions: 20,
                          activeColor: accent,
                          inactiveColor: Colors.white.withOpacity(0.1),
                          onChanged: (v) => state.setVolume(v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text('${state.volume}%',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                            textAlign: TextAlign.right),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              _SectionHeader(label: 'Controls', icon: Icons.settings_remote_rounded),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _ActionCard(
                      icon: Icons.refresh_rounded,
                      label: 'Refresh',
                      subtitle: 'ES games',
                      color: Colors.blueAccent,
                      onTap: () => _confirmAction(context,
                        title: 'Refresh game list?',
                        body: 'EmulationStation will restart.',
                        onConfirm: () async => await state.ssh.execute('batocera-es-swissknife --restart'),
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionCard(
                      icon: Icons.restart_alt_rounded,
                      label: 'Reboot',
                      subtitle: 'Restart',
                      color: Colors.amberAccent,
                      onTap: () => _confirmAction(context,
                        title: 'Restart?',
                        body: 'Batocera will restart.',
                        dangerous: true,
                        onConfirm: () async {
                          await state.ssh.reboot();
                          if (context.mounted) await state.disconnect();
                        },
                      ),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _ActionCard(
                      icon: Icons.power_off_rounded,
                      label: 'Shutdown',
                      subtitle: 'Shutdown',
                      color: Colors.redAccent,
                      onTap: () => _confirmAction(context,
                        title: 'Shutdown?',
                        body: "Batocera will shut down.",
                        dangerous: true,
                        onConfirm: () async {
                          await state.ssh.execute('batocera-es-swissknife --shutdown');
                          if (context.mounted) await state.disconnect();
                        },
                      ),
                    )),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              _SectionHeader(label: 'Logs', icon: Icons.article_rounded),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _LogButton(
                    label: 'stderr',
                    icon: Icons.error_outline_rounded,
                    color: Colors.orangeAccent,
                    filename: 'es_launch_stderr.log',
                    ssh: state.ssh,
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: _LogButton(
                    label: 'stdout',
                    icon: Icons.output_rounded,
                    color: Colors.greenAccent,
                    filename: 'es_launch_stdout.log',
                    ssh: state.ssh,
                  )),
                ],
              ),

              const SizedBox(height: 24),

              _SectionHeader(label: 'Gestion', icon: Icons.tune_rounded),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Quitter proprement
                    Expanded(
                      child: Card(
                        child: InkWell(
                          onTap: () => _confirmAction(context,
                            title: 'Quit the game?',
                            body: 'The game will be stopped cleanly.',
                            dangerous: false,
                            onConfirm: () async => await state.ssh.execute('hotkeygen --send exit'),
                          ),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: const Icon(Icons.exit_to_app_rounded, color: Colors.blueAccent, size: 20),
                                ),
                                const SizedBox(height: 10),
                                const Text('Quit Game', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                const Text('Clean stop', style: TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Tuer forcer
                    Expanded(
                      child: Card(
                        child: InkWell(
                          onTap: () => _confirmAction(context,
                            title: 'Force kill?',
                            body: "The emulator will be force killed.",
                            dangerous: true,
                            onConfirm: () async => await state.ssh.execute('curl http://127.0.0.1:1234/emukill'),
                          ),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: Colors.redAccent.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: const Icon(Icons.cancel_rounded, color: Colors.redAccent, size: 20),
                                ),
                                const SizedBox(height: 10),
                                const Text('Force kill', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                const Text('Force kill', style: TextStyle(color: Colors.white38, fontSize: 11)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _PowerModeSelector(ssh: state.ssh),

              const SizedBox(height: 16),

              _SectionHeader(label: 'Application', icon: Icons.phone_android_rounded),
              const SizedBox(height: 12),
              Card(
                child: InkWell(
                  onTap: () => _confirmAction(context,
                    title: 'Clear cache?',
                    body: 'Cached images and videos will be deleted. They will be re-downloaded on next use.',
                    dangerous: false,
                    onConfirm: () async {
                      try {
                        final dir = await getTemporaryDirectory();
                        final cacheFolder = Directory('${dir.path}/batocera_img_cache');
                        if (await cacheFolder.exists()) {
                          await cacheFolder.delete(recursive: true);
                        }
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Cache cleared!', style: TextStyle(color: Colors.white)),
                          backgroundColor: Color(0xFF1C2230),
                          behavior: SnackBarBehavior.floating,
                        ));
                      } catch (e) {
                        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Erreur : $e', style: const TextStyle(color: Colors.white)),
                          backgroundColor: Colors.redAccent,
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    },
                  ),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.cleaning_services_rounded, color: Colors.orangeAccent, size: 20),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Clear cache', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                          Text('Cached images and videos', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        ],
                      )),
                    ]),
                  ),
                ),
              ),

              const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmAction(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() onConfirm,
    bool dangerous = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
            style: dangerous ? ElevatedButton.styleFrom(backgroundColor: Colors.redAccent) : null,
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true) await onConfirm();
  }
}

// ─── Power Mode Selector ─────────────────────────────────────────────────────

class _PowerModeSelector extends StatefulWidget {
  final dynamic ssh;
  const _PowerModeSelector({required this.ssh});

  @override
  State<_PowerModeSelector> createState() => _PowerModeSelectorState();
}

class _PowerModeSelectorState extends State<_PowerModeSelector> {
  String _current = '';
  String _selectedMode = 'balanced';
  bool _loading = false;

  static const _modes = [
    ('highperformance', 'Performance'),
    ('balanced', 'Balanced'),
    ('powersaver', 'Economy'),
  ];

  String _modeLabel(String mode) {
    for (final m in _modes) {
      if (m.$1 == mode) return m.$2;
    }
    return mode;
  }

  @override
  void initState() {
    super.initState();
    _loadGovernor();
  }

  Future<void> _loadGovernor() async {
    try {
      final g = await widget.ssh.readFile('/sys/devices/system/cpu/cpufreq/policy0/scaling_governor');
      if (mounted) setState(() => _current = g.trim());
    } catch (_) {}
  }

  Future<void> _setMode(String mode) async {
    setState(() { _loading = true; _selectedMode = mode; });
    try {
      await widget.ssh.execute('batocera-power-mode $mode');
      await Future.delayed(const Duration(milliseconds: 800));
      await _loadGovernor();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.amberAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.bolt_rounded, color: Colors.amberAccent, size: 20),
            ),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Power',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              if (_current.isNotEmpty)
                Text(_current, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accent.withOpacity(0.25)),
              ),
              child: DropdownButton<String>(
                value: _modes.any((m) => m.$1 == _selectedMode) ? _selectedMode : null,
                underline: const SizedBox(),
                dropdownColor: const Color(0xFF1C2230),
                hint: Text('Mode', style: TextStyle(color: Colors.white38, fontSize: 12)),
                icon: _loading
                    ? SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: accent))
                    : Icon(Icons.keyboard_arrow_down_rounded, color: accent, size: 16),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                onChanged: _loading ? null : (v) { if (v != null) _setMode(v); },
                items: _modes.map((m) => DropdownMenuItem(
                  value: m.$1,
                  child: Text(m.$2, style: TextStyle(
                    color: m.$1 == _selectedMode ? accent : Colors.white70,
                    fontWeight: m.$1 == _selectedMode ? FontWeight.w700 : FontWeight.w400,
                    fontSize: 12,
                  )),
                )).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Log Button ───────────────────────────────────────────────────────────────

class _LogButton extends StatefulWidget {
  final String label;
  final String filename;
  final IconData icon;
  final Color color;
  final dynamic ssh;

  const _LogButton({
    required this.label, required this.filename,
    required this.icon, required this.color, required this.ssh,
  });

  @override
  State<_LogButton> createState() => _LogButtonState();
}

class _LogButtonState extends State<_LogButton> {
  bool _loading = false;

  Future<void> _showLog(BuildContext ctx) async {
    setState(() => _loading = true);
    String logContent;
    try {
      logContent = await widget.ssh.readLog(widget.filename);
    } catch (e) {
      logContent = 'Erreur : $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    if (!mounted) return;

    final capturedContent = logContent;
    final capturedFilename = widget.filename;

    showModalBottomSheet(
      context: ctx,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C2230),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.75, maxChildSize: 0.95, minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 12),
              child: Row(
                children: [
                  Icon(widget.icon, color: widget.color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(capturedFilename,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600))),
                  IconButton(
                    icon: const Icon(Icons.share_rounded, color: Colors.white54, size: 20),
                    onPressed: () => Share.share(capturedContent, subject: capturedFilename),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white38, size: 20),
                    onPressed: () => Navigator.of(sheetCtx, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(sheetCtx).padding.bottom),
              child: SelectableText(capturedContent,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70, height: 1.6)),
            )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: _loading ? null : () => _showLog(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_loading)
                SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: widget.color))
              else
                Icon(widget.icon, color: widget.color, size: 16),
              const SizedBox(width: 8),
              Text(widget.label, style: TextStyle(
                  color: widget.color, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionHeader({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.white.withOpacity(0.4)),
        const SizedBox(width: 8),
        Text(label.toUpperCase(), style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2,
        )),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon, required this.label,
    required this.subtitle, required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 10),
              Text(label, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
