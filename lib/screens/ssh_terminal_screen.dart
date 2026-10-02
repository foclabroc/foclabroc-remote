import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_state.dart';

class SshTerminalScreen extends StatefulWidget {
  const SshTerminalScreen({super.key});

  @override
  State<SshTerminalScreen> createState() => _SshTerminalScreenState();
}

class _SshTerminalScreenState extends State<SshTerminalScreen> {
  final TextEditingController _cmdCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final List<_TermLine> _lines = [];
  bool _running = false;

  // Historique des commandes
  final List<String> _history = [];
  // Historique sauvegardé sur le téléphone (SharedPreferences) : conservé
  // après fermeture de l'appli. 50 commandes max, sans doublon.
  static const _historyKey = 'ssh_terminal_history';
  static const _historyMax = 50;
  static const _clearHistoryValue = '\u0000clear';

  static const _prompt = '~ # ';

  // Commandes rapides (menu « Commandes ») : un choix l'exécute directement.
  // `warn` non nul = commande sensible : confirmation demandée avant exécution.
  static const _quickCmds = <({IconData icon, String label, String cmd, String? warn})>[
    (icon: Icons.storage_rounded, label: 'Espace disque', cmd: 'df -h /userdata', warn: null),
    (icon: Icons.thermostat_rounded, label: 'Température', cmd: r'for t in /sys/class/thermal/thermal_zone*/temp; do echo "$(cat ${t%/temp}/type): $(( $(cat $t) / 1000 ))°C"; done', warn: null),
    (icon: Icons.lan_rounded, label: 'Adresse IP', cmd: 'ip -4 addr show | grep inet', warn: null),
    (icon: Icons.computer_rounded, label: 'Infos système', cmd: 'batocera-info', warn: null),
    (icon: Icons.info_outline_rounded, label: 'Version Batocera', cmd: 'batocera-version', warn: null),
    (icon: Icons.lock_open_rounded, label: '/boot en écriture', cmd: 'mount -o remount,rw /boot', warn: 'Remonte la partition /boot en écriture. Une mauvaise modification de ses fichiers peut empêcher Batocera de démarrer.'),
    (icon: Icons.save_rounded, label: 'Sauvegarder overlay', cmd: 'batocera-save-overlay', warn: 'Enregistre dans l\'overlay les modifications faites au système (hors /userdata). Elles seront conservées après redémarrage, erreurs comprises.'),
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_historyKey) ?? const <String>[];
      if (!mounted) return;
      setState(() {
        final typedMeanwhile = List<String>.of(_history);
        _history
          ..clear()
          ..addAll(saved);
        for (final c in typedMeanwhile) {
          _history.remove(c);
          _history.add(c);
        }
        _trimHistory();
      });
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_historyKey, List<String>.of(_history));
    } catch (_) {}
  }

  void _trimHistory() {
    if (_history.length > _historyMax) {
      _history.removeRange(0, _history.length - _historyMax);
    }
  }

  void _addToHistory(String cmd) {
    _history.remove(cmd);
    _history.add(cmd);
    _trimHistory();
    _saveHistory();
  }

  void _clearHistory() {
    setState(() => _history.clear());
    _saveHistory();
  }

  @override
  void dispose() {
    _cmdCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _runCommand(AppState state) async {
    final cmd = _cmdCtrl.text.trim();
    if (cmd.isEmpty) return;

    // Ajoute à l'historique (une commande déjà présente remonte en tête)
    _addToHistory(cmd);

    setState(() {
      _lines.add(_TermLine(text: '$_prompt$cmd', type: _LineType.input));
      _running = true;
    });
    _cmdCtrl.clear();
    _scrollToBottom();

    try {
      final client = state.ssh.client;
      if (client == null) throw Exception('Non connecté');
      // Échappe les apostrophes : sans ça, une commande contenant ' cassait
      // l'enveloppe bash -c '…' (awk, echo 'texte'…).
      final escaped = cmd.replaceAll("'", "'\\''");
      final session = await client.execute('bash -c \'$escaped\' </dev/null 2>&1');

      // Index de la ligne de sortie en cours (streaming)
      int outputLineIndex = -1;
      String pending = '';

      await for (final chunk in session.stdout) {
        if (!mounted) break;
        pending += utf8.decode(chunk, allowMalformed: true);
        final parts = pending.split('\n');
        pending = parts.removeLast(); // dernière partie incomplète
        for (final part in parts) {
          final line = part.trimRight();
          if (line.isEmpty) continue;
          if (outputLineIndex == -1) {
            setState(() {
              _lines.add(_TermLine(text: line, type: _LineType.output));
              outputLineIndex = _lines.length - 1;
            });
          } else {
            setState(() {
              _lines.add(_TermLine(text: line, type: _LineType.output));
            });
          }
          _scrollToBottom();
        }
      }
      // Flush le reste
      if (pending.trimRight().isNotEmpty && mounted) {
        setState(() => _lines.add(_TermLine(text: pending.trimRight(), type: _LineType.output)));
        _scrollToBottom();
      }
      session.stderr.drain();
      await session.done;
    } catch (e) {
      if (mounted) setState(() => _lines.add(_TermLine(text: 'Erreur : $e', type: _LineType.error)));
    }
    if (mounted) {
      setState(() => _running = false);
      _scrollToBottom();
      _focusNode.requestFocus();
    }
  }

  void _clearTerminal() {
    setState(() => _lines.clear());
  }

  Future<void> _runQuick(AppState state, String cmd) async {
    if (_running) return;
    final warn = _quickCmds.firstWhere((q) => q.cmd == cmd).warn;
    if (warn != null) {
      final ok = await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1C2230),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 22),
            SizedBox(width: 8),
            Text('Commande sensible', style: TextStyle(fontSize: 15)),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(warn, style: const TextStyle(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0C10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(cmd,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(false),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx, rootNavigator: true).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
              child: const Text('Exécuter'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted || _running) return;
    }
    _cmdCtrl.text = cmd;
    _runCommand(state);
  }

  // Historique (menu « Historique ») : un choix remet la commande dans le
  // champ pour la modifier / relancer. 20 dernières, la plus récente en haut.
  void _recallHistory(String cmd) {
    setState(() {
        _cmdCtrl.text = cmd;
      _cmdCtrl.selection = TextSelection.collapsed(offset: cmd.length);
    });
    _focusNode.requestFocus();
  }

  void _copyLastOutput() {
    final outputs = _lines.where((l) => l.type == _LineType.output);
    if (outputs.isEmpty) return;
    Clipboard.setData(ClipboardData(text: outputs.last.text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copié dans le presse-papiers',
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1C2230),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final accent = Theme.of(context).colorScheme.primary;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 4, 24, 8),
              child: Row(
                children: [
                  Text('Terminal', style: Theme.of(context).textTheme.headlineMedium),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.copy_rounded, color: Colors.white38, size: 20),
                    onPressed: _copyLastOutput,
                    tooltip: 'Copier dernier output',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_sweep_rounded, color: Colors.white38, size: 20),
                    onPressed: _clearTerminal,
                    tooltip: 'Effacer',
                  ),
                ],
              ),
            ),

            // Terminal output
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0C10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: _lines.isEmpty
                    ? Center(
                        child: Text(
                          'Tape une commande...',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.2),
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        itemCount: _lines.length,
                        itemBuilder: (_, i) {
                          final line = _lines[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: SelectableText(
                              line.text,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.5,
                                color: switch (line.type) {
                                  _LineType.input => accent,
                                  _LineType.error => Colors.redAccent,
                                  _LineType.output => Colors.white70,
                                },
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),

            // Barre d'outils : Commandes à gauche, Historique à droite
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  PopupMenuButton<String>(
                    enabled: !_running,
                    color: const Color(0xFF1C2230),
                    position: PopupMenuPosition.over,
                    onSelected: (cmd) => _runQuick(state, cmd),
                    itemBuilder: (_) => [
                      for (final q in _quickCmds)
                        PopupMenuItem<String>(
                          value: q.cmd,
                          height: 42,
                          child: Row(children: [
                            Icon(q.icon, size: 18, color: q.warn != null ? Colors.orangeAccent : accent),
                            const SizedBox(width: 10),
                            Text(q.label, style: const TextStyle(fontSize: 13)),
                          ]),
                        ),
                    ],
                    child: _MenuBtn(
                      icon: Icons.terminal_rounded,
                      label: 'Commandes',
                      enabled: !_running,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (_running)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5, color: accent),
                    ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    enabled: !_running && _history.isNotEmpty,
                    color: const Color(0xFF1C2230),
                    position: PopupMenuPosition.over,
                    constraints: const BoxConstraints(minWidth: 180, maxWidth: 300),
                    onSelected: (v) => v == _clearHistoryValue ? _clearHistory() : _recallHistory(v),
                    itemBuilder: (_) => [
                      for (final c in _history.reversed.take(20))
                        PopupMenuItem<String>(
                          value: c,
                          height: 40,
                          child: Text(c,
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      const PopupMenuDivider(),
                      PopupMenuItem<String>(
                        value: _clearHistoryValue,
                        height: 40,
                        child: Row(children: [
                          const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                          const SizedBox(width: 8),
                          Text('Effacer l\'historique',
                            style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                        ]),
                      ),
                    ],
                    child: _MenuBtn(
                      icon: Icons.history_rounded,
                      label: 'Historique',
                      enabled: !_running && _history.isNotEmpty,
                    ),
                  ),
                ],
              ),
            ),

            // Input
            AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + bottomInset),
              child: Row(
                children: [
                  Text(
                    _prompt,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _cmdCtrl,
                      focusNode: _focusNode,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: Colors.white,
                      ),
                      decoration: InputDecoration(
                        hintText: 'commande...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.2),
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        filled: true,
                        fillColor: const Color(0xFF0A0C10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(
                              color: Colors.white.withOpacity(0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              BorderSide(color: accent, width: 1.5),
                        ),
                      ),
                      onSubmitted: _running
                          ? null
                          : (_) => _runCommand(state),
                      enabled: !_running,
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _running ? null : () => _runCommand(state),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _running
                            ? Colors.white.withOpacity(0.05)
                            : accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.send_rounded,
                        color: _running ? Colors.white24 : Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;

  const _MenuBtn({required this.icon, required this.label, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
          const Icon(Icons.arrow_drop_down_rounded, size: 18, color: Colors.white38),
        ]),
      ),
    );
  }
}

enum _LineType { input, output, error }

class _TermLine {
  final String text;
  final _LineType type;
  const _TermLine({required this.text, required this.type});
}
