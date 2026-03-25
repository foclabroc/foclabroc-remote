import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';

class StatusBar extends StatefulWidget {
  const StatusBar({super.key});

  @override
  State<StatusBar> createState() => _StatusBarState();
}

class _StatusBarState extends State<StatusBar> {
  String _ip = '';
  String _storage = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (state.isConnected) _fetch();
    });
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted && context.read<AppState>().isConnected) _fetch();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Exécute directement sans bash -l pour éviter le banner
  Future<String> _execDirect(String cmd) async {
    try {
      final state = context.read<AppState>();
      final session = await state.ssh.client!.execute(cmd);
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      return utf8.decode(bytes).trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _fetch() async {
    try {
      final state = context.read<AppState>();
      if (!state.isConnected) return;

      final ip = await _execDirect(
        "ip -4 addr show | grep -oP '(?<=inet )([0-9.]+)' | grep -v '127.0.0.1' | head -n1",
      );

      // Affiche taille utilisée, totale et pourcentage pour /userdata
      final storage = await _execDirect(
        "df -h /userdata | awk 'NR==2 {print \$3\"/\"\$2\" (\"\$5\")\"}'"
      );

      if (mounted) setState(() {
        _ip = ip;
        _storage = storage;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: (!state.isConnected || (_ip.isEmpty && _storage.isEmpty))
          ? const SizedBox.shrink()
          : SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        color: const Color(0xFF161A22),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            // IP à gauche
            if (_ip.isNotEmpty) ...[
              const Icon(Icons.wifi_rounded, size: 11, color: Colors.white24),
              const SizedBox(width: 4),
              Text(_ip, style: const TextStyle(color: Colors.white38, fontSize: 10)),
            ] else
              const SizedBox(),

            // BATOCERA au centre
            const Expanded(
              child: Text(
                'BATOCERA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white24,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),

            // Disque à droite
            if (_storage.isNotEmpty) ...[
              Text(_storage, style: const TextStyle(color: Colors.white38, fontSize: 10)),
              const SizedBox(width: 4),
              const Icon(Icons.storage_rounded, size: 11, color: Colors.white24),
            ] else
              const SizedBox(),
          ],
        ),
      ),
      ),
    );
  }
}
