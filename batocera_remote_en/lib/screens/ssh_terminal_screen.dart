import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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

  // Command history
  final List<String> _history = [];
  int _historyIndex = -1;

  static const _prompt = '~ # ';

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

    if (_history.isEmpty || _history.last != cmd) _history.add(cmd);
    _historyIndex = -1;

    setState(() {
      _lines.add(_TermLine(text: '$_prompt$cmd', type: _LineType.input));
      _running = true;
    });
    _cmdCtrl.clear();
    _scrollToBottom();

    try {
      final client = state.ssh.client;
      if (client == null) throw Exception('Not connected');
      final session = await client.execute('bash -c \'$cmd\' </dev/null 2>&1');

      // Index de la ligne de sortie en cours (streaming)
      int outputLineIndex = -1;
      String pending = '';

      await for (final chunk in session.stdout) {
        if (!mounted) break;
        pending += utf8.decode(chunk, allowMalformed: true);
        final parts = pending.split('\n');
        pending = parts.removeLast(); // last incomplete part
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

  void _historyUp() {
    if (_history.isEmpty) return;
    setState(() {
      if (_historyIndex == -1) {
        _historyIndex = _history.length - 1;
      } else if (_historyIndex > 0) {
        _historyIndex--;
      }
      _cmdCtrl.text = _history[_historyIndex];
      _cmdCtrl.selection = TextSelection.collapsed(offset: _cmdCtrl.text.length);
    });
  }

  void _historyDown() {
    if (_historyIndex == -1) return;
    setState(() {
      if (_historyIndex < _history.length - 1) {
        _historyIndex++;
        _cmdCtrl.text = _history[_historyIndex];
      } else {
        _historyIndex = -1;
        _cmdCtrl.clear();
      }
      _cmdCtrl.selection = TextSelection.collapsed(offset: _cmdCtrl.text.length);
    });
  }

  void _clearTerminal() {
    setState(() => _lines.clear());
  }

  void _copyLastOutput() {
    final outputs = _lines.where((l) => l.type == _LineType.output);
    if (outputs.isEmpty) return;
    Clipboard.setData(ClipboardData(text: outputs.last.text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard',
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
                    tooltip: 'Copy last output',
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_sweep_rounded, color: Colors.white38, size: 20),
                    onPressed: _clearTerminal,
                    tooltip: 'Clear',
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
                          'Type a command...',
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

            // Raccourcis historique
            if (_history.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: Row(
                  children: [
                    _HistoryBtn(
                      icon: Icons.arrow_upward_rounded,
                      onTap: _historyUp,
                      tooltip: 'Previous command',
                    ),
                    const SizedBox(width: 8),
                    _HistoryBtn(
                      icon: Icons.arrow_downward_rounded,
                      onTap: _historyDown,
                      tooltip: 'Next command',
                    ),
                    const SizedBox(width: 8),
                    if (_running)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: accent),
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
                        hintText: 'command...',
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

class _HistoryBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  const _HistoryBtn({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Icon(icon, size: 14, color: Colors.white38),
        ),
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
