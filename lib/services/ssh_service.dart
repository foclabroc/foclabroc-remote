import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';

class SshService {
  SSHClient? _client;
  bool _connected = false;

  bool get isConnected => _connected;
  SSHClient? get client => _client;

  Future<bool> connect({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    try {
      final socket = await SSHSocket.connect(host, port,
          timeout: const Duration(seconds: 10));
      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
      );
      await _client!.authenticated;
      _connected = true;
      return true;
    } catch (e) {
      _connected = false;
      return false;
    }
  }

  Future<void> disconnect() async {
    _client?.close();
    _client = null;
    _connected = false;
  }

  bool _isBannerLine(String line) {
    if (line.isEmpty) return false;
    final t = line.trimLeft();
    return t.startsWith('_') ||
        t.startsWith('(') ||
        t.startsWith(')') ||
        line.startsWith('--') ||
        line.contains('R E A D Y') ||
        line.contains('READY   TO   RETRO') ||
        line.contains('batocera-check-updates') ||
        line.contains('butterfly') ||
        line.contains('type \'batocera') ||
        line.contains('add \'butterfly') ||
        line.contains('/dev/tty');
  }

  Future<String> execute(String command) async {
    if (_client == null || !_connected) {
      throw Exception('Non connecté');
    }
    try {
      // </dev/null évite le /dev/tty, 2>/dev/null supprime stderr
      final session = await _client!.execute(
        'bash -l -c \'$command\' </dev/null 2>/dev/null',
      );
      final stdoutBytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      session.stderr.drain();
      await session.done;
      final output = utf8.decode(stdoutBytes)
          .split('\n')
          .where((line) => !_isBannerLine(line))
          .join('\n');
      return output.trim();
    } catch (e) {
      throw Exception('Erreur commande: $e');
    }
  }

  // ─── Gestion des jeux ───────────────────────────────────────────────────────

  Future<List<Map<String, String>>> listRoms() async {
    final raw = await execute(
      "find /userdata/roms -maxdepth 2 -type f "
      r"\( -name '*.zip' -o -name '*.7z' -o -name '*.rom' -o -name '*.iso' "
      r"-o -name '*.chd' -o -name '*.nes' -o -name '*.snes' -o -name '*.bin' "
      r"-o -name '*.img' -o -name '*.cue' -o -name '*.gba' -o -name '*.n64' "
      r"-o -name '*.nds' -o -name '*.gb' -o -name '*.gbc' -o -name '*.md' "
      r"-o -name '*.smd' -o -name '*.gg' -o -name '*.pce' \) "
      "2>/dev/null | head -200",
    );
    if (raw.isEmpty) return [];
    return raw.split('\n').where((l) => l.isNotEmpty).map((path) {
      final parts = path.split('/');
      final system = parts.length >= 4 ? parts[3] : 'unknown';
      final name = parts.last.replaceAll(RegExp(r'\.[^.]+$'), '');
      return {'name': name, 'system': system, 'path': path};
    }).toList();
  }

  Future<void> launchGame(String romPath) async {
    await execute('batocera-es-swissknife --emulator auto --rom "$romPath" &');
  }

  Future<void> quitEmulationStation() async {
    await execute('batocera-es-swissknife --es-quit 2>/dev/null || pkill emulationstation');
  }

  // ─── Gestion système ────────────────────────────────────────────────────────

  Future<void> reboot() async {
    await execute('reboot');
    _connected = false;
  }

  Future<void> shutdown() async {
    await execute('poweroff');
    _connected = false;
  }

  Future<void> setVolume(int percent) async {
    await execute(
      'amixer sset Master ${percent}% 2>/dev/null || '
      'pactl set-sink-volume @DEFAULT_SINK@ ${percent}%',
    );
  }

  Future<int> getVolume() async {
    try {
      final out = await execute(
        "amixer sget Master 2>/dev/null | grep -o '[0-9]*%' | head -1 | tr -d '%'",
      );
      return int.tryParse(out) ?? 50;
    } catch (_) {
      return 50;
    }
  }

  Future<String> getSystemInfo() async {
    return await execute(
      'echo "Hostname: \$(hostname)" && '
      'echo "IP: \$(hostname -I | awk \'{print \$1}\')" && '
      'echo "Uptime: \$(uptime -p)" && '
      'echo "Batocera: \$(cat /usr/share/batocera/batocera.version 2>/dev/null || echo N/A)"',
    );
  }

  Future<String> getCurrentGame() async {
    return await execute(
      'cat /var/run/batocera-info 2>/dev/null || echo ""',
    );
  }

  // ─── Capture ────────────────────────────────────────────────────────────────

  Future<void> screenshot() async {
    await execute('batocera-screenshot');
  }

  Future<void> startRecord() async {
    await execute('batocera-record start &');
  }

  Future<void> stopRecord() async {
    await execute('batocera-record stop');
  }

  // ─── Logs & fichiers (sans bash -l pour éviter le banner) ───────────────────

  Future<String> readLog(String filename) async {
    if (_client == null || !_connected) throw Exception('Non connecté');
    final session = await _client!.execute(
      'cat /userdata/system/logs/$filename',
    );
    final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
    await session.done;
    final output = utf8.decode(bytes).trim();
    return output.isEmpty ? '(fichier vide)' : output;
  }

  Future<String> readFile(String remotePath) async {
    if (_client == null || !_connected) throw Exception('Non connecté');
    final session = await _client!.execute('cat "$remotePath"');
    final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
    await session.done;
    return utf8.decode(bytes);
  }

  // ─── Téléchargement SFTP ────────────────────────────────────────────────────

  Future<Uint8List> downloadFile(String remotePath) async {
    if (_client == null || !_connected) {
      throw Exception('Non connecté');
    }
    final sftp = await _client!.sftp();
    final file = await sftp.open(remotePath);
    final chunks = <Uint8List>[];
    await for (final chunk in file.read()) {
      chunks.add(chunk);
    }
    await file.close();
    final total = chunks.fold<int>(0, (s, c) => s + c.length);
    final result = Uint8List(total);
    int offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  // ─── Upload SFTP ─────────────────────────────────────────────────────────────

  Future<void> uploadFile(String remotePath, Uint8List bytes) async {
    if (_client == null || !_connected) {
      throw Exception('Non connecté');
    }
    final sftp = await _client!.sftp();
    final file = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );
    await file.write(Stream.value(bytes));
    await file.close();
  }
}
