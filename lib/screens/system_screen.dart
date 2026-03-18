import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';

class SystemScreen extends StatelessWidget {
  const SystemScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text('Système', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 24),

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
                          min: 0,
                          max: 100,
                          divisions: 20,
                          activeColor: accent,
                          inactiveColor: Colors.white.withOpacity(0.1),
                          onChanged: (v) => state.setVolume(v.round()),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text(
                          '${state.volume}%',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              _SectionHeader(label: 'Contrôles', icon: Icons.settings_remote_rounded),
              const SizedBox(height: 12),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.refresh_rounded,
                        label: 'Actualiser',
                        subtitle: 'Jeux ES',
                        color: Colors.blueAccent,
                        onTap: () => _confirmAction(
                          context,
                          title: 'Actualiser la liste des jeux ?',
                          body: 'EmulationStation va redémarrer.',
                          onConfirm: () async {
                            await state.ssh.execute('batocera-es-swissknife --restart');
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.restart_alt_rounded,
                        label: 'Reboot',
                        subtitle: 'Redémarrer',
                        color: Colors.amberAccent,
                        onTap: () => _confirmAction(
                          context,
                          title: 'Redémarrer ?',
                          body: 'Batocera va redémarrer.',
                          onConfirm: () async {
                            await state.ssh.reboot();
                            if (context.mounted) await state.disconnect();
                          },
                          dangerous: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionCard(
                        icon: Icons.power_off_rounded,
                        label: 'Éteindre',
                        subtitle: 'Arrêt',
                        color: Colors.redAccent,
                        onTap: () => _confirmAction(
                          context,
                          title: 'Éteindre ?',
                          body: 'Batocera va s\'arrêter.',
                          onConfirm: () async {
                            await state.ssh.execute('batocera-es-swissknife --shutdown');
                            if (context.mounted) await state.disconnect();
                          },
                          dangerous: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              _SectionHeader(label: 'Logs', icon: Icons.article_rounded),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _LogButton(
                      label: 'stderr',
                      icon: Icons.error_outline_rounded,
                      color: Colors.orangeAccent,
                      filename: 'es_launch_stderr.log',
                      ssh: state.ssh,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _LogButton(
                      label: 'stdout',
                      icon: Icons.output_rounded,
                      color: Colors.greenAccent,
                      filename: 'es_launch_stdout.log',
                      ssh: state.ssh,
                    ),
                  ),
                ],
              ),
            ],
          ),
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
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogCtx, rootNavigator: true).pop(true),
            style: dangerous
                ? ElevatedButton.styleFrom(backgroundColor: Colors.redAccent)
                : null,
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await onConfirm();
    }
  }
}

class _LogButton extends StatefulWidget {
  final String label;
  final String filename;
  final IconData icon;
  final Color color;
  final dynamic ssh;

  const _LogButton({
    required this.label,
    required this.filename,
    required this.icon,
    required this.color,
    required this.ssh,
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

    showModalBottomSheet(
      context: ctx,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C2230),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Icon(widget.icon, color: widget.color, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.filename,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 20),
                    onPressed: () =>
                        Navigator.of(sheetCtx, rootNavigator: true).pop(),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                padding: const EdgeInsets.all(16),
                child: Text(
                  capturedContent,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.white70,
                    height: 1.6,
                  ),
                ),
              ),
            ),
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
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: widget.color),
                )
              else
                Icon(widget.icon, color: widget.color, size: 16),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.color,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
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
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
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
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(height: 10),
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontSize: 13)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
