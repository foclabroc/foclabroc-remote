import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'wine_tools_screen.dart';
import 'foclabroc_tools_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _index = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _tabs = [
    _TabInfo(icon: Icons.wifi_rounded,           label: 'Connection'),
    _TabInfo(icon: Icons.sports_esports_rounded, label: 'Current Game'),
    _TabInfo(icon: Icons.library_books_rounded,  label: 'Library'),
    _TabInfo(icon: Icons.camera_alt_rounded,     label: 'Capture'),
    _TabInfo(icon: Icons.terminal_rounded,       label: 'Terminal SSH'),
    _TabInfo(icon: Icons.folder_rounded,         label: 'Files'),
    _TabInfo(icon: Icons.settings_rounded,       label: 'System'),
    _TabInfo(icon: Icons.wine_bar_rounded,       label: 'Wine Tools'),
    _TabInfo(icon: Icons.build_circle_rounded,   label: 'Foclabroc Tools'),
  ];

  final List<GlobalKey<NavigatorState>> _navigatorKeys =
      List.generate(9, (_) => GlobalKey<NavigatorState>());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    // Intercepte le bouton retour Android AVANT Flutter
    final drawerState = _scaffoldKey.currentState;
    if (drawerState != null && drawerState.isDrawerOpen) {
      drawerState.closeDrawer();
      return true;
    }
    if (TabBackHandler.handle(_index)) return true;
    final nav = _navigatorKeys[_index].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return true;
    }
    drawerState?.openDrawer();
    return true; // empêche de quitter l'app
  }

  Widget _buildScreen(int index) => Navigator(
    key: _navigatorKeys[index],
    onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => switch (index) {
      0 => const ConnectScreen(),
      1 => const RunningGameScreen(),
      2 => const GamesScreen(),
      3 => const CaptureScreen(),
      4 => const SshTerminalScreen(),
      5 => const FileManagerScreen(),
      6 => const SystemScreen(),
      7 => const WineToolsScreen(),
      _ => const FoclabroctoolsScreen(),
    }),
  );

  void _goTo(int i) {
    Navigator.of(context).pop();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final connected = state.isConnected;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      key: _scaffoldKey,
      drawer: _buildDrawer(state, connected, accent),
      body: Stack(children: [
        Stack(children: List.generate(9, (i) => Offstage(
          offstage: _index != i,
          child: _buildScreen(i),
        ))),
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
      ]),
    );
  }

  Widget _buildDrawer(AppState state, bool connected, Color accent) {
    return Drawer(
      backgroundColor: const Color(0xFF161A22),
      child: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset('assets/icon.png', width: 36, height: 36),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Foclabroc Remote',
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
          const Divider(color: Colors.white10, height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _tabs.length,
              itemBuilder: (_, i) {
                final tab = _tabs[i];
                final selected = _index == i;
                return InkWell(
                  onTap: () => _goTo(i),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected ? accent.withOpacity(0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: selected ? Border.all(color: accent.withOpacity(0.25)) : null,
                    ),
                    child: Row(children: [
                      Icon(tab.icon, size: 20, color: selected ? accent : Colors.white38),
                      const SizedBox(width: 14),
                      Text(tab.label, style: TextStyle(
                        color: selected ? accent : Colors.white54,
                        fontSize: 14,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                      )),
                    ]),
                  ),
                );
              },
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('v1.7',
                style: TextStyle(color: Colors.white.withOpacity(0.15), fontSize: 11)),
          ),
        ]),
      ),
    );
  }
}

class _TabInfo {
  final IconData icon;
  final String label;
  const _TabInfo({required this.icon, required this.label});
}
