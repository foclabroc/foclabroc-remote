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
  List<String> _recentHosts = [];

  ConnectionStatus get status => _status;
  String get errorMessage => _errorMessage;
  bool get isConnected => _status == ConnectionStatus.connected;
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAndReconnect();
    }
  }

  Future<void> _checkAndReconnect() async {
    if (_status != ConnectionStatus.connected) return;
    // Vérifie si la connexion est toujours active
    try {
      await _ssh.execute('echo ok');
    } catch (_) {
      // Connexion perdue, on reconnecte
      _status = ConnectionStatus.connecting;
      notifyListeners();
      final ok = await _ssh.connect(
        host: _host,
        port: _port,
        username: _username,
        password: _password,
      );
      if (ok) {
        _status = ConnectionStatus.connected;
        await refreshSystemInfo();
        await refreshVolume();
      } else {
        _status = ConnectionStatus.error;
        _errorMessage = 'Connexion perdue — reconnexion impossible';
      }
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
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', _host);
    await prefs.setInt('port', _port);
    await prefs.setString('username', _username);
    await prefs.setString('password', _password);
    _recentHosts = [_host, ..._recentHosts.where((h) => h != _host)].take(3).toList();
    await prefs.setStringList('recent_hosts', _recentHosts);
  }

  Future<void> connect({
    required String host,
    required int port,
    required String username,
    required String password,
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
      await _savePrefs();
      await refreshSystemInfo();
      await refreshVolume();
    } else {
      _status = ConnectionStatus.error;
      _errorMessage = 'Impossible de se connecter à $host:$port';
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
