import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../widgets/back_handler.dart';
import 'connect_screen.dart';
import 'system_screen.dart';
import 'capture_screen.dart';
import 'ssh_terminal_screen.dart';
import 'file_manager_screen.dart';
import 'running_game_screen.dart';
import 'games_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  static const _tabs = [
    _TabInfo(icon: Icons.wifi_rounded, label: 'Connexion'),
    _TabInfo(icon: Icons.sports_esports_rounded, label: 'Jeu'),
    _TabInfo(icon: Icons.library_books_rounded, label: 'Biblio'),
    _TabInfo(icon: Icons.camera_alt_rounded, label: 'Capture'),
    _TabInfo(icon: Icons.terminal_rounded, label: 'SSH'),
    _TabInfo(icon: Icons.folder_rounded, label: 'Fichiers'),
    _TabInfo(icon: Icons.settings_rounded, label: 'Système'),
  ];

  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    7, (_) => GlobalKey<NavigatorState>(),
  );

  Widget _buildScreen(int index) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => switch (index) {
          0 => const ConnectScreen(),
          1 => const RunningGameScreen(),
          2 => const GamesScreen(),
          3 => const CaptureScreen(),
          4 => const SshTerminalScreen(),
          5 => const FileManagerScreen(),
          _ => const SystemScreen(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final connected = state.isConnected;
    final accent = Theme.of(context).colorScheme.primary;

    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (TabBackHandler.handle(_index)) return;
        final currentNav = _navigatorKeys[_index].currentState;
        if (currentNav != null && currentNav.canPop()) {
          currentNav.pop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Stack(
                    children: List.generate(7, (i) => Offstage(
                      offstage: _index != i,
                      child: _buildScreen(i),
                    )),
                  ),
                ),
              ],
            ),
            // Overlay reconnexion
            if (state.isReconnecting)
              Positioned(
                bottom: 80,
                left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C2230),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white12),
                      boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: accent)),
                      const SizedBox(width: 10),
                      const Text('Reconnexion...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161A22),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_tabs.length, (i) {
                  final selected = _index == i;
                  final tab = _tabs[i];
                  final disabled = i > 0 && !connected;
                  return GestureDetector(
                    onTap: disabled ? null : () => setState(() => _index = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? accent.withOpacity(0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(tab.icon,
                          color: selected ? accent : disabled
                              ? Colors.white.withOpacity(0.2)
                              : Colors.white.withOpacity(0.5),
                          size: 22),
                        const SizedBox(height: 3),
                        Text(tab.label, style: TextStyle(
                          fontSize: 9,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                          color: selected ? accent : disabled
                              ? Colors.white.withOpacity(0.2)
                              : Colors.white.withOpacity(0.5),
                        )),
                      ]),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabInfo {
  final IconData icon;
  final String label;
  const _TabInfo({required this.icon, required this.label});
}
