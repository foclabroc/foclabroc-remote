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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _tabs = [
    _TabInfo(icon: Icons.wifi_rounded, label: 'Connect'),
    _TabInfo(icon: Icons.sports_esports_rounded, label: 'Running game'),
    _TabInfo(icon: Icons.library_books_rounded, label: 'Library'),
    _TabInfo(icon: Icons.camera_alt_rounded, label: 'Capture'),
    _TabInfo(icon: Icons.terminal_rounded, label: 'SSH Terminal'),
    _TabInfo(icon: Icons.folder_rounded, label: 'Files'),
    _TabInfo(icon: Icons.settings_rounded, label: 'System'),
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

  void _goTo(int i) {
    Navigator.of(context).pop(); // ferme le drawer
    setState(() => _index = i);
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
        key: _scaffoldKey,
        drawer: _buildDrawer(state, connected, accent),
        body: Stack(
          children: [
            // Écrans
            Stack(
              children: List.generate(7, (i) => Offstage(
                offstage: _index != i,
                child: _buildScreen(i),
              )),
            ),

            // Bouton menu haut gauche
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 12,
              child: GestureDetector(
                onTap: () => _scaffoldKey.currentState?.openDrawer(),
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2230).withOpacity(0.95),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                  ),
                  child: const Icon(Icons.menu_rounded, color: Colors.white54, size: 20),
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(AppState state, bool connected, Color accent) {
    return Drawer(
      backgroundColor: const Color(0xFF161A22),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header drawer
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.sports_esports_rounded, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Foclabroc Remote',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(
                    connected ? (state.ssh.host.isNotEmpty ? state.ssh.host : 'Connected') : 'Not connected',
                    style: TextStyle(
                      color: connected ? const Color(0xFF50FA7B) : Colors.white38,
                      fontSize: 11,
                    ),
                  ),
                ]),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(color: Colors.white.withOpacity(0.08), height: 20),
            ),

            // Items
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                itemCount: _tabs.length,
                itemBuilder: (_, i) {
                  final tab = _tabs[i];
                  final selected = _index == i;
                  final disabled = i > 0 && !connected;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: disabled ? null : () => _goTo(i),
                        borderRadius: BorderRadius.circular(12),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: selected ? accent.withOpacity(0.13) : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: selected
                                ? Border.all(color: accent.withOpacity(0.25))
                                : null,
                          ),
                          child: Row(children: [
                            Icon(tab.icon,
                              size: 20,
                              color: selected ? accent
                                  : disabled ? Colors.white.withOpacity(0.2)
                                  : Colors.white.withOpacity(0.55),
                            ),
                            const SizedBox(width: 14),
                            Text(tab.label, style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? accent
                                  : disabled ? Colors.white.withOpacity(0.2)
                                  : Colors.white.withOpacity(0.75),
                            )),
                            if (selected) ...[
                              const Spacer(),
                              Container(width: 4, height: 4,
                                decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                            ],
                          ]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Version
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Text('v1.5', style: TextStyle(color: Colors.white.withOpacity(0.2), fontSize: 11)),
            ),
          ],
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

