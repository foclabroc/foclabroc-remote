import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
  bool _recording = false;
  int _seconds = 0;
  Timer? _timer;
  bool _loadingScreenshot = false;
  bool _loadingRecord = false;
  bool _auto30 = false;

  // Options vidéo
  String _quality = 'high';
  String _audio = 'auto';

  static const _qualities = [
    ('ultra', 'Ultra (60fps)'),
    ('high', 'High (60fps)'),
    ('mid', 'Mid (30fps)'),
    ('low', 'Low (30fps)'),
  ];

  static const _audios = [
    ('auto', 'Système (défaut)'),
    ('mic', 'Microphone'),
    ('none', 'Sans audio'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCurrentSettings();
    });
  }

  Future<void> _loadCurrentSettings() async {
    try {
      final state = context.read<AppState>();
      if (!state.isConnected) return;
      final q = await state.ssh.execute('batocera-record get-quality');
      final a = await state.ssh.execute('batocera-record get-audio');
      if (mounted) {
        setState(() {
          if (q.isNotEmpty) _quality = q.trim();
          if (a.isNotEmpty) _audio = a.trim();
        });
      }
    } catch (_) {}
  }

  Future<void> _setQuality(AppState state, String q) async {
    setState(() => _quality = q);
    try {
      await state.ssh.execute('batocera-record set-quality $q');
    } catch (_) {}
  }

  Future<void> _setAudio(AppState state, String a) async {
    setState(() => _audio = a);
    try {
      await state.ssh.execute('batocera-record set-audio $a');
    } catch (_) {}
  }

  void _startTimer() {
    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _seconds++);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  String get _timerLabel {
    final m = _seconds ~/ 60;
    final s = _seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _takeScreenshot(AppState state) async {
    setState(() => _loadingScreenshot = true);
    try {
      await state.ssh.screenshot();
      if (mounted) _showSuccess('Screenshot enregistré dans : /userdata/screenshots');
    } catch (e) {
      if (mounted) _showError('Erreur : $e');
    } finally {
      if (mounted) setState(() => _loadingScreenshot = false);
    }
  }

  Future<void> _startRecording(AppState state) async {
    setState(() => _loadingRecord = true);
    try {
      await state.ssh.startRecord();
      setState(() { _recording = true; _loadingRecord = false; });
      _startTimer();
      if (_auto30) {
        Future.delayed(const Duration(seconds: 30), () async {
          if (_recording && mounted) await _stopRecording(state);
        });
      }
    } catch (e) {
      if (mounted) _showError('Erreur : $e');
      setState(() => _loadingRecord = false);
    }
  }

  Future<void> _stopRecording(AppState state) async {
    setState(() => _loadingRecord = true);
    try {
      await state.ssh.stopRecord();
      _stopTimer();
      final duration = _timerLabel;
      setState(() { _recording = false; _seconds = 0; _loadingRecord = false; });
      if (mounted) _showSuccess('Capture enregistrée dans : /userdata/recordings - Durée : $duration');
    } catch (e) {
      if (mounted) _showError('Erreur : $e');
      setState(() => _loadingRecord = false);
    }
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      backgroundColor: const Color(0xFF1C2230),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent.withOpacity(0.85),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

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
              Text('Capture', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 28),

              // ── Screenshot ────────────────────────────────────────────────
              _SectionLabel(label: 'Screenshot', icon: Icons.camera_alt_rounded),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prend une capture d\'écran de Batocera et la sauvegarde dans /userdata/screenshots.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _loadingScreenshot ? null : () => _takeScreenshot(state),
                          icon: _loadingScreenshot
                              ? const SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Icon(Icons.camera_alt_rounded),
                          label: Text(_loadingScreenshot ? 'Capture en cours...' : 'Prendre un screenshot'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // ── Capture vidéo ─────────────────────────────────────────────
              _SectionLabel(label: 'Capture vidéo', icon: Icons.videocam_rounded),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Enregistre une vidéo de Batocera via batocera-record.',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const SizedBox(height: 20),

                      // ── Qualité + Audio côte à côte ──────────────────
                      Row(
                        children: [
                          Expanded(
                            child: _DropdownOption(
                              label: 'Qualité',
                              icon: Icons.high_quality_rounded,
                              options: _qualities.map((q) => q.$1).toList(),
                              labels: _qualities.map((q) => q.$2).toList(),
                              selected: _quality,
                              enabled: !_recording,
                              onChanged: (v) => _setQuality(state, v),
                              accent: accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _DropdownOption(
                              label: 'Audio',
                              icon: Icons.mic_rounded,
                              options: _audios.map((a) => a.$1).toList(),
                              labels: _audios.map((a) => a.$2).toList(),
                              selected: _audio,
                              enabled: !_recording,
                              onChanged: (v) => _setAudio(state, v),
                              accent: accent,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 20),

                      // ── Chrono ───────────────────────────────────────────
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _recording
                              ? Colors.redAccent.withOpacity(0.08)
                              : Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _recording
                                ? Colors.redAccent.withOpacity(0.3)
                                : Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_recording) ...[
                                  _PulsingDot(),
                                  const SizedBox(width: 10),
                                ],
                                Text(
                                  _recording ? _timerLabel : '00:00',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w800,
                                    color: _recording
                                        ? Colors.redAccent
                                        : Colors.white.withOpacity(0.2),
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                                if (_auto30 && _recording) ...[
                                  const SizedBox(width: 12),
                                  Column(
                                    children: [
                                      Text('${30 - _seconds}s',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                              color: Colors.redAccent.withOpacity(0.7))),
                                      Text('restantes',
                                          style: TextStyle(fontSize: 10,
                                              color: Colors.redAccent.withOpacity(0.5))),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _recording
                                  ? _auto30
                                      ? 'Auto-stop dans ${30 - _seconds} seconde${(30 - _seconds) > 1 ? 's' : ''}...'
                                      : 'Enregistrement en cours...'
                                  : 'Prêt',
                              style: TextStyle(
                                fontSize: 12,
                                color: _recording
                                    ? Colors.redAccent.withOpacity(0.7)
                                    : Colors.white.withOpacity(0.25),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Toggle auto 30s
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: _auto30 ? accent.withOpacity(0.08) : Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _auto30 ? accent.withOpacity(0.3) : Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(children: [
                              Icon(Icons.timer_rounded, size: 18,
                                  color: _auto30 ? accent : Colors.white38),
                              const SizedBox(width: 10),
                              Text('Auto 30 secondes',
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: _auto30 ? accent : Colors.white70)),
                            ]),
                            Switch(
                              value: _auto30,
                              onChanged: _recording ? null : (v) => setState(() => _auto30 = v),
                              activeColor: accent,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Start / Stop
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: (_recording || _loadingRecord) ? null : () => _startRecording(state),
                              icon: _loadingRecord && !_recording
                                  ? const SizedBox(width: 16, height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.fiber_manual_record_rounded),
                              label: const Text('Start'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _recording ? Colors.white12 : Colors.redAccent,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: (!_recording || _loadingRecord) ? null : () => _stopRecording(state),
                              icon: _loadingRecord && _recording
                                  ? const SizedBox(width: 16, height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                  : const Icon(Icons.stop_rounded),
                              label: const Text('Stop'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _recording ? accent : Colors.white12,
                                foregroundColor: _recording ? Colors.black : Colors.white38,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Dropdown option ─────────────────────────────────────────────────────────

class _DropdownOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<String> options;
  final List<String> labels;
  final String selected;
  final bool enabled;
  final void Function(String) onChanged;
  final Color accent;

  const _DropdownOption({
    required this.label,
    required this.icon,
    required this.options,
    required this.labels,
    required this.selected,
    required this.enabled,
    required this.onChanged,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final selectedLabel = labels[options.indexOf(selected)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 13, color: Colors.white38),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withOpacity(0.25)),
          ),
          child: DropdownButton<String>(
            value: selected,
            isExpanded: true,
            underline: const SizedBox(),
            dropdownColor: const Color(0xFF1C2230),
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: accent, size: 18),
            style: TextStyle(color: enabled ? Colors.white : Colors.white38, fontSize: 12),
            onChanged: enabled ? (v) { if (v != null) onChanged(v); } : null,
            items: List.generate(options.length, (i) => DropdownMenuItem(
              value: options[i],
              child: Text(labels[i], style: TextStyle(
                color: options[i] == selected ? accent : Colors.white70,
                fontWeight: options[i] == selected ? FontWeight.w700 : FontWeight.w400,
                fontSize: 12,
              )),
            )),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final IconData icon;
  const _SectionLabel({required this.label, required this.icon});

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

class _PulsingDot extends StatefulWidget {
  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _anim = Tween(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(width: 10, height: 10,
        decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle)),
    );
  }
}
