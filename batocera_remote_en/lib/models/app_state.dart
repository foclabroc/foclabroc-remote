import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ssh_service.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

class AppState extends ChangeNotifier with WidgetsBindingObserver {
  final SshService _ssh = SshService();

  ConnectionStatus _status = ConnectionStatus.disconnected;
  String _errorMessage = '';
  String _host = '';
  int _port = 22;
  String _username = 'root';
  String _password = 'linux';
  int _volume = 50;
  String _systemInfo = '';
  List<Map<String, String>> _roms = [];
  bool _loadingRoms = false;
  List<String> _recentHosts = []; // format: 'name::ip' or just 'ip'
  Timer? _watchdog; // surveille la connexion en continu

  ConnectionStatus get status => _status;
  String get errorMessage => _errorMessage;
  bool get isConnected => _status == ConnectionStatus.connected;
  bool get isReconnecting => _status == ConnectionStatus.connecting && _host.isNotEmpty;
  String get host => _host;
  int get port => _port;
  String get username => _username;
  String get password => _password;
  int get volume => _volume;
  String get systemInfo => _systemInfo;
  List<Map<String, String>> get roms => _roms;
  bool get loadingRoms => _loadingRoms;
  List<String> get recentHosts => _recentHosts;
  SshService get ssh => _ssh;

  AppState() {
    _loadPrefs();
    WidgetsBinding.instance.addObserver(this);
    _startWatchdog();
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Watchdog : vérifie la connexion toutes les 5s ────────────────────────
  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_host.isEmpty) return;
      if (_status == ConnectionStatus.connecting) return; // déjà en cours
      if (_status == ConnectionStatus.disconnected) return; // déconnexion volontaire

      // Si le ssh_service a perdu la connexion sans qu'app_state le sache
      if (_status == ConnectionStatus.connected && !_ssh.isConnected) {
        await _silentReconnect();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // On resume: always check even if we think we're connected
      if (_host.isNotEmpty && _status != ConnectionStatus.connecting) {
        _checkAndReconnect();
      }
    } else if (state == AppLifecycleState.paused) {
      if (_status == ConnectionStatus.connected) {
        _ssh.execute('echo bg').catchError((_) {});
      }
    }
  }

  // Quick ping to check if connection is alive
  Future<void> _checkAndReconnect() async {
    if (_status == ConnectionStatus.connecting) return;
    bool alive = false;
    try {
      await _ssh.execute('echo ok').timeout(const Duration(seconds: 3));
      alive = true;
    } catch (_) {}
    if (!alive) {
      await _silentReconnect();
    }
  }

  Future<void> _silentReconnect() async {
    if (_host.isEmpty) return;
    if (_status == ConnectionStatus.connecting) return;

    // Passe en "connecting" pour afficher la bannière
    _status = ConnectionStatus.connecting;
    notifyListeners();

    // Déconnecte proprement l'ancienne session
    try { await _ssh.disconnect(); } catch (_) {}

    // Tente de reconnecter
    try {
      final ok = await _ssh.connect(
        host: _host,
        port: _port,
        username: _username,
        password: _password,
      );
      if (ok) {
        _status = ConnectionStatus.connected;
        notifyListeners();
        await refreshSystemInfo();
        await refreshVolume();
      } else {
        _status = ConnectionStatus.disconnected;
        notifyListeners();
      }
    } catch (_) {
      _status = ConnectionStatus.disconnected;
      notifyListeners();
    }
  }



  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _host = prefs.getString('host') ?? '';
    _port = prefs.getInt('port') ?? 22;
    _username = prefs.getString('username') ?? 'root';
    _password = prefs.getString('password') ?? 'linux';
    _recentHosts = prefs.getStringList('recent_hosts') ?? [];
    notifyListeners();

    // Connexion automatique si on a une adresse sauvegardée
    if (_host.isNotEmpty) {
      _autoConnect();
    }
  }

  Future<void> _autoConnect() async {
    if (_status == ConnectionStatus.connecting || _status == ConnectionStatus.connected) return;
    _status = ConnectionStatus.connecting;
    notifyListeners();
    try {
      final ok = await _ssh.connect(
        host: _host,
        port: _port,
        username: _username,
        password: _password,
      );
      _status = ok ? ConnectionStatus.connected : ConnectionStatus.disconnected;
      if (ok) {
        await refreshSystemInfo();
        await refreshVolume();
      }
    } catch (_) {
      _status = ConnectionStatus.disconnected;
    }
    notifyListeners();
  }

  Future<void> _savePrefs({String name = ''}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', _host);
    await prefs.setInt('port', _port);
    await prefs.setString('username', _username);
    await prefs.setString('password', _password);
    final existing = _recentHosts.firstWhere(
      (e) => _extractIp(e) == _host, orElse: () => '');
    final entryName = name.trim().isNotEmpty ? name.trim()
        : existing.isNotEmpty ? _extractName(existing) : '';
    final newEntry = entryName.isNotEmpty ? '$entryName::$_host' : _host;
    _recentHosts = [newEntry, ..._recentHosts.where((e) => _extractIp(e) != _host)].take(5).toList();
    await prefs.setStringList('recent_hosts', _recentHosts);
  }

  String _extractIp(String entry) => entry.contains('::') ? entry.split('::')[1] : entry;
  String _extractName(String entry) => entry.contains('::') ? entry.split('::')[0] : '';

  String recentHostIp(String entry) => _extractIp(entry);
  String recentHostName(String entry) => _extractName(entry);

  Future<void> renameRecentHost(String entry, String newName) async {
    final ip = _extractIp(entry);
    final newEntry = newName.trim().isEmpty ? ip : '${newName.trim()}::$ip';
    _recentHosts = _recentHosts.map((e) => _extractIp(e) == ip ? newEntry : e).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_hosts', _recentHosts);
    notifyListeners();
  }

  Future<void> removeRecentHost(String entry) async {
    _recentHosts = _recentHosts.where((e) => e != entry).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('recent_hosts', _recentHosts);
    notifyListeners();
  }

  Future<void> clearRecentHosts() async {
    _recentHosts = [];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('recent_hosts');
    notifyListeners();
  }

  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required String password,
    String name = '',
  }) async {
    _host = host;
    _port = port;
    _username = username;
    _password = password;
    _status = ConnectionStatus.connecting;
    _errorMessage = '';
    notifyListeners();

    final ok = await _ssh.connect(
      host: host,
      port: port,
      username: username,
      password: password,
    );

    if (ok) {
      _status = ConnectionStatus.connected;
      await _savePrefs(name: name);
      await refreshSystemInfo();
      await refreshVolume();
    } else {
      _status = ConnectionStatus.error;
      _errorMessage = 'Unable to connect to $host:$port';
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _ssh.disconnect();
    _status = ConnectionStatus.disconnected;
    _roms = [];
    _systemInfo = '';
    notifyListeners();
  }

  Future<void> refreshSystemInfo() async {
    try {
      _systemInfo = await _ssh.getSystemInfo();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshVolume() async {
    try {
      _volume = await _ssh.getVolume();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setVolume(int v) async {
    _volume = v;
    notifyListeners();
    try {
      await _ssh.setVolume(v);
    } catch (_) {}
  }

  Future<void> loadRoms() async {
    _loadingRoms = true;
    notifyListeners();
    try {
      _roms = await _ssh.listRoms();
    } catch (_) {
      _roms = [];
    }
    _loadingRoms = false;
    notifyListeners();
  }
}
