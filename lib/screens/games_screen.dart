import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';

class GamesScreen extends StatefulWidget {
  const GamesScreen({super.key});

  @override
  State<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends State<GamesScreen> {
  String _filter = '';
  String? _selectedSystem;

  static const Map<String, IconData> _systemIcons = {
    'nes': Icons.gamepad_rounded,
    'snes': Icons.gamepad_rounded,
    'megadrive': Icons.sports_esports_rounded,
    'gba': Icons.phone_android_rounded,
    'psx': Icons.album_rounded,
    'n64': Icons.sports_esports_rounded,
    'gb': Icons.phone_android_rounded,
    'gbc': Icons.phone_android_rounded,
    'mame': Icons.videogame_asset_rounded,
    'arcade': Icons.videogame_asset_rounded,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      if (state.isConnected && state.roms.isEmpty) {
        state.loadRoms();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final accent = Theme.of(context).colorScheme.primary;

    final systems = state.roms.map((r) => r['system']!).toSet().toList()..sort();
    final filtered = state.roms.where((r) {
      final matchFilter =
          _filter.isEmpty || r['name']!.toLowerCase().contains(_filter.toLowerCase());
      final matchSystem = _selectedSystem == null || r['system'] == _selectedSystem;
      return matchFilter && matchSystem;
    }).toList();

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Jeux', style: Theme.of(context).textTheme.headlineMedium),
                  IconButton(
                    icon: Icon(Icons.refresh_rounded, color: accent),
                    onPressed: state.loadingRoms ? null : () => state.loadRoms(),
                    tooltip: 'Rafraîchir',
                  ),
                ],
              ),
            ),

            // Search
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Rechercher un jeu...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _filter.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => setState(() => _filter = ''),
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _filter = v),
              ),
            ),

            // System filter chips
            if (systems.isNotEmpty)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
                  children: [
                    _SystemChip(
                      label: 'Tous',
                      selected: _selectedSystem == null,
                      onTap: () => setState(() => _selectedSystem = null),
                    ),
                    ...systems.map((s) => Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _SystemChip(
                            label: s.toUpperCase(),
                            selected: _selectedSystem == s,
                            onTap: () => setState(() => _selectedSystem = s),
                          ),
                        )),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // Content
            Expanded(
              child: state.loadingRoms
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: accent),
                          const SizedBox(height: 14),
                          Text('Chargement des ROMs...',
                              style: Theme.of(context).textTheme.bodyMedium),
                        ],
                      ),
                    )
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_rounded,
                                  size: 56,
                                  color: Colors.white.withOpacity(0.15)),
                              const SizedBox(height: 12),
                              Text('Aucun jeu trouvé',
                                  style: Theme.of(context).textTheme.bodyMedium),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final rom = filtered[i];
                            return _RomTile(rom: rom);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SystemChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SystemChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withOpacity(0.15) : const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : Colors.white.withOpacity(0.1),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? accent : Colors.white.withOpacity(0.6),
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _RomTile extends StatelessWidget {
  final Map<String, String> rom;
  const _RomTile({required this.rom});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final state = context.read<AppState>();

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: ListTile(
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.sports_esports_rounded, color: accent, size: 20),
        ),
        title: Text(rom['name'] ?? '',
            style: Theme.of(context).textTheme.titleMedium),
        subtitle: Text(
          (rom['system'] ?? '').toUpperCase(),
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontSize: 11, letterSpacing: 0.5),
        ),
        trailing: IconButton(
          icon: Icon(Icons.play_circle_rounded, color: accent, size: 30),
          onPressed: () => _launch(context, state, rom['path']!),
          tooltip: 'Lancer',
        ),
      ),
    );
  }

  Future<void> _launch(
      BuildContext context, AppState state, String path) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C2230),
        title: const Text('Lancer le jeu ?'),
        content: Text(rom['name'] ?? path),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Lancer')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await state.ssh.launchGame(path);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Lancement : ${rom['name']}'),
              backgroundColor: const Color(0xFF1C2230),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erreur : $e'),
              backgroundColor: Colors.redAccent.withOpacity(0.8),
            ),
          );
        }
      }
    }
  }
}
