import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';

class SshService {
  SSHClient? _client;
  bool _connected = false;
  Timer? _keepAlive;
  String _host = '';

  bool get isConnected => _connected;
  SSHClient? get client => _client;
  String get host => _host;

  Future<bool> connect({
    required String host,
    required int port,
    required String username,
    required String password,
  }) async {
    try {
      _host = host;
      final socket = await SSHSocket.connect(host, port,
          timeout: const Duration(seconds: 5)); // réduit de 10s à 5s
      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () => password,
        // Algorithmes rapides en priorité
        algorithms: SSHAlgorithms(
          kex: [SSHKexType.x25519],
          cipher: [SSHCipherType.aes128ctr, SSHCipherType.aes256ctr],
          mac: [SSHMacType.hmacSha1, SSHMacType.hmacSha256],
        ),
      );
      await _client!.authenticated;
      _connected = true;
      _startKeepAlive();
      return true;
    } catch (e) {
      _connected = false;
      return false;
    }
  }

  Future<void> disconnect() async {
    await stopTunnel();
    _keepAlive?.cancel();
    _keepAlive = null;
    _client?.close();
    _client = null;
    _connected = false;
  }

  void _startKeepAlive() {
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_client == null || !_connected) {
        _keepAlive?.cancel();
        return;
      }
      try {
        final session = await _client!.execute('echo ok');
        await session.done;
      } catch (_) {
        // Connexion perdue
        _connected = false;
        _keepAlive?.cancel();
      }
    });
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
      throw Exception('Not connected');
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
      throw Exception('Command error: $e');
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
    // Sauvegarder dans batocera.conf pour persistance
    try {
      final session = await _client!.execute(
        'batocera-settings-set audio.volume $percent 2>/dev/null; '
        'sed -i s/^audio\\.volume=.*/audio.volume=$percent/ /userdata/system/batocera.conf 2>/dev/null',
      );
      await session.done;
    } catch (_) {}
  }

  Future<int> getVolume() async {
    try {
      // Utiliser client direct pour éviter les problèmes d'échappement avec bash -l -c
      final session = await _client!.execute(
        'grep audio.volume= /userdata/system/batocera.conf 2>/dev/null | grep -v boost | grep -v pcengine | cut -d= -f2 | head -1',
      );
      final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
      await session.done;
      final out = utf8.decode(bytes).trim();
      final v = int.tryParse(out);
      if (v != null && v >= 0 && v <= 100) return v;
      return 50;
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
    // setsid détache ffmpeg du process group du shell SSH.
    // Sans ça, la fermeture du canal SSH propage SIGHUP à ffmpeg
    // et corrompt le trailer MKV au stop (fichier 0 ko).
    await execute('setsid batocera-record start </dev/null >/dev/null 2>&1 &');
  }

  Future<void> stopRecord() async {
    await execute('batocera-record stop');
    // Remux MKV → MKV pour régénérer l'index (cues) et permettre le seek.
    // -c copy = pas de réencodage, ~1s. On écrit dans un fichier temporaire
    // puis on remplace l'original pour garder le même nom de fichier.
    await execute(
      'sleep 1; '
      'mkv=\$(ls -t /userdata/recordings/*.mkv 2>/dev/null | head -1); '
      '[ -n "\$mkv" ] && [ -s "\$mkv" ] && '
      'ffmpeg -y -i "\$mkv" -c copy -map 0 "\${mkv%.mkv}.tmp.mkv" '
      '</dev/null >/dev/null 2>&1 && '
      'mv -f "\${mkv%.mkv}.tmp.mkv" "\$mkv"',
    );
  }

  // ─── Logs & fichiers (sans bash -l pour éviter le banner) ───────────────────

  Future<String> readLog(String filename) async {
    if (_client == null || !_connected) throw Exception('Not connected');
    final session = await _client!.execute(
      'cat /userdata/system/logs/$filename',
    );
    final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
    await session.done;
    final output = utf8.decode(bytes).trim();
    return output.isEmpty ? '(fichier vide)' : output;
  }

  Future<String> readFile(String remotePath) async {
    if (_client == null || !_connected) throw Exception('Not connected');
    final session = await _client!.execute('cat "$remotePath"');
    final bytes = await session.stdout.fold<List<int>>([], (a, b) => a..addAll(b));
    await session.done;
    return utf8.decode(bytes);
  }

  // ─── Téléchargement SFTP ────────────────────────────────────────────────────

  Future<Uint8List> downloadFile(String remotePath) async {
    if (_client == null || !_connected) {
      throw Exception('Not connected');
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

  // Stream direct vers disque (pour les gros fichiers)
  Future<void> downloadFileToDisk(String remotePath, String localPath,
      {void Function(int bytes)? onProgress}) async {
    if (_client == null || !_connected) throw Exception('Not connected');
    final sftp = await _client!.sftp();
    final remoteFile = await sftp.open(remotePath);
    final localFile = File(localPath).openWrite();
    int total = 0;
    await for (final chunk in remoteFile.read()) {
      localFile.add(chunk);
      total += chunk.length;
      onProgress?.call(total);
      // Cède le contrôle à l'event loop tous les 512KB
      if (total % (512 * 1024) < chunk.length) {
        await Future.delayed(Duration.zero);
      }
    }
    await localFile.flush();
    await localFile.close();
    await remoteFile.close();
  }

  // ─── Tunnel SSH local → Batocera:1234 ───────────────────────────────────────

  ServerSocket? _tunnelServer;
  int _tunnelPort = 0;

  int get tunnelPort => _tunnelPort;
  bool get hasTunnel => _tunnelServer != null;

  Future<int> startTunnel() async {
    if (_tunnelServer != null) return _tunnelPort;
    if (_client == null || !_connected) throw Exception('Not connected');

    _tunnelServer = await ServerSocket.bind('127.0.0.1', 0);
    _tunnelPort = _tunnelServer!.port;

    _tunnelServer!.listen((socket) async {
      try {
        final forward = await _client!.forwardLocal('127.0.0.1', 1234);
        socket.cast<List<int>>().pipe(forward.sink).catchError((_) {});
        forward.stream.cast<List<int>>().pipe(socket).catchError((_) {});
      } catch (_) {
        socket.destroy();
      }
    });

    return _tunnelPort;
  }

  Future<void> stopTunnel() async {
    await _tunnelServer?.close();
    _tunnelServer = null;
    _tunnelPort = 0;
  }

  // ─── Upload SFTP ─────────────────────────────────────────────────────────────

  // Upload depuis un chemin local — stream par chunks sans tout charger en RAM
  Future<void> uploadFileFromPath(
    String localPath,
    String remotePath, {
    void Function(int sent, int total)? onProgress,
  }) async {
    if (_client == null || !_connected) {
      throw Exception('Not connected');
    }
    final ioFile = File(localPath);
    final total = await ioFile.length();
    final sftp = await _client!.sftp();
    final remoteFile = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.create | SftpFileOpenMode.write | SftpFileOpenMode.truncate,
    );

    const chunkSize = 256 * 1024; // 256KB par chunk
    int sent = 0;
    final controller = StreamController<Uint8List>();
    final writeFuture = remoteFile.write(controller.stream);

    final reader = ioFile.openRead();
    await for (final chunk in reader) {
      // Découpe les chunks trop grands
      int offset = 0;
      while (offset < chunk.length) {
        final end = (offset + chunkSize).clamp(0, chunk.length);
        controller.add(Uint8List.fromList(chunk.sublist(offset, end)));
        sent += end - offset;
        offset = end;
        onProgress?.call(sent, total);
        await Future.delayed(Duration.zero);
      }
    }

    await controller.close();
    await writeFuture;
    await remoteFile.close();
  }
}
