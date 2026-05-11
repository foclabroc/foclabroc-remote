import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/app_state.dart';

// ─────────────────────────────────────────────
//  PYTHON SCRIPTS
// ─────────────────────────────────────────────

// Vrai périphérique Xbox (BTN_TL/TR, EV_ABS dpad, BTN_MODE hotkey)
const _padScript = r'''
import sys, time
try:
    from evdev import UInput, AbsInfo, ecodes as e
except ImportError:
    print("ERR:evdev not found")
    sys.exit(1)

capabilities = {
    e.EV_KEY: [
        e.BTN_A, e.BTN_B, e.BTN_X, e.BTN_Y,
        e.BTN_TL, e.BTN_TR,
        e.BTN_SELECT, e.BTN_START,
        e.BTN_MODE,
        e.BTN_THUMBL, e.BTN_THUMBR,
    ],
    e.EV_ABS: {
        e.ABS_HAT0X: AbsInfo(value=0, min=-1, max=1, fuzz=0, flat=0, resolution=0),
        e.ABS_HAT0Y: AbsInfo(value=0, min=-1, max=1, fuzz=0, flat=0, resolution=0),
    },
}

ui = UInput(capabilities, name="Foclabroc-VPad", vendor=0x045e, product=0x028e, version=0x0114, bustype=e.BUS_USB)
time.sleep(0.2)
print("READY")
sys.stdout.flush()

buttons = {
    "a": e.BTN_A, "b": e.BTN_B, "x": e.BTN_X, "y": e.BTN_Y,
    "l1": e.BTN_TL, "r1": e.BTN_TR,
    "start": e.BTN_START, "select": e.BTN_SELECT,
    "hotkey": e.BTN_MODE,
}

dpad = {
    "left":  (e.ABS_HAT0X, -1),
    "right": (e.ABS_HAT0X,  1),
    "up":    (e.ABS_HAT0Y, -1),
    "down":  (e.ABS_HAT0Y,  1),
}

while True:
    try:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip().lower()
    except Exception:
        break
    if line == "quit":
        break
    parts = line.split()
    if len(parts) != 2:
        continue
    action, key = parts
    value = 1 if action == "press" else 0
    if key in dpad:
        axis, direction = dpad[key]
        ui.write(e.EV_ABS, axis, direction if value else 0)
    elif key in buttons:
        ui.write(e.EV_KEY, buttons[key], value)
    ui.syn()

ui.close()
''';

// Clavier virtuel Linux standard
const _kbScript = r'''
import sys, time
try:
    from evdev import UInput, ecodes as e
except ImportError:
    print("ERR:evdev not found")
    sys.exit(1)

KEY_MAP = {
    "q": e.KEY_Q, "w": e.KEY_W, "e": e.KEY_E, "r": e.KEY_R,
    "t": e.KEY_T, "y": e.KEY_Y, "u": e.KEY_U, "i": e.KEY_I,
    "o": e.KEY_O, "p": e.KEY_P,
    "a": e.KEY_A, "s": e.KEY_S, "d": e.KEY_D, "f": e.KEY_F,
    "g": e.KEY_G, "h": e.KEY_H, "j": e.KEY_J, "k": e.KEY_K,
    "l": e.KEY_L,
    "z": e.KEY_Z, "x": e.KEY_X, "c": e.KEY_C, "v": e.KEY_V,
    "b": e.KEY_B, "n": e.KEY_N, "m": e.KEY_M,
    "space": e.KEY_SPACE,
    "enter": e.KEY_ENTER,
    "backspace": e.KEY_BACKSPACE,
    "tab": e.KEY_TAB,
    "esc": e.KEY_ESC,
    "shift": e.KEY_LEFTSHIFT,
    "ctrl": e.KEY_LEFTCTRL,
    "alt": e.KEY_LEFTALT,
    "up": e.KEY_UP, "down": e.KEY_DOWN,
    "left": e.KEY_LEFT, "right": e.KEY_RIGHT,
    "f1": e.KEY_F1,
    "pipe": e.KEY_BACKSLASH,
    "semicolon": e.KEY_SEMICOLON,
    "dot": e.KEY_DOT,
    "minus": e.KEY_MINUS,
    # underscore géré par handler spécial ci-dessous
    "lparen": e.KEY_9,
    "rparen": e.KEY_0,
    "colon": e.KEY_SEMICOLON,
}

ui = UInput({e.EV_KEY: list(KEY_MAP.values())}, name="FoclabrocVkb")
time.sleep(0.3)
print("READY")
sys.stdout.flush()

while True:
    try:
        line = sys.stdin.readline()
        if not line:
            break
        line = line.strip().lower()
    except Exception:
        break
    if line == "quit":
        break
    parts = line.split()
    if len(parts) != 2:
        continue
    action, key = parts

    # LPAREN ( = SHIFT+9
    if key == "lparen" and action == "press":
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 1)
        ui.write(e.EV_KEY, e.KEY_9, 1)
        ui.syn()
        ui.write(e.EV_KEY, e.KEY_9, 0)
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 0)
        ui.syn()
        continue

    # RPAREN ) = SHIFT+0
    if key == "rparen" and action == "press":
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 1)
        ui.write(e.EV_KEY, e.KEY_0, 1)
        ui.syn()
        ui.write(e.EV_KEY, e.KEY_0, 0)
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 0)
        ui.syn()
        continue

    # PIPE | = SHIFT+BACKSLASH
    if key == "pipe" and action == "press":
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 1)
        ui.write(e.EV_KEY, e.KEY_BACKSLASH, 1)
        ui.syn()
        ui.write(e.EV_KEY, e.KEY_BACKSLASH, 0)
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 0)
        ui.syn()
        continue

    # COLON : = SHIFT+SEMICOLON
    if key == "colon" and action == "press":
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 1)
        ui.write(e.EV_KEY, e.KEY_SEMICOLON, 1)
        ui.syn()
        ui.write(e.EV_KEY, e.KEY_SEMICOLON, 0)
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 0)
        ui.syn()
        continue

    # UNDERSCORE _ = SHIFT+MINUS
    if key == "underscore" and action == "press":
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 1)
        ui.write(e.EV_KEY, e.KEY_MINUS, 1)
        ui.syn()
        ui.write(e.EV_KEY, e.KEY_MINUS, 0)
        ui.write(e.EV_KEY, e.KEY_LEFTSHIFT, 0)
        ui.syn()
        continue

    if key not in KEY_MAP:
        continue
    code = KEY_MAP[key]
    if action == "press":
        ui.write(e.EV_KEY, code, 1)
    elif action == "release":
        ui.write(e.EV_KEY, code, 0)
    ui.syn()

ui.close()
''';

// ─────────────────────────────────────────────
//  DEVICE SESSION
// ─────────────────────────────────────────────

class _DeviceSession {
  SSHSession? _session;
  bool ready = false;
  bool starting = false;
  String? error;

  final String scriptName;
  final String scriptContent;
  final void Function(VoidCallback) setState;

  _DeviceSession({
    required this.scriptName,
    required this.scriptContent,
    required this.setState,
  });

  Future<void> start(BuildContext context) async {
    if (starting || ready) return;
    setState(() {
      starting = true;
      error = null;
    });

    try {
      final state = context.read<AppState>();
      if (!state.isConnected) throw Exception('Not connected');

      final b64 = base64.encode(utf8.encode(scriptContent));
      await state.ssh.execute('echo "$b64" | base64 -d > /tmp/$scriptName');

      final client = state.ssh.client;
      if (client == null) throw Exception('SSH client unavailable');

      final session = await client.execute(
        'python3 -u /tmp/$scriptName',
      );
      _session = session;

      final completer = Completer<void>();
      late StreamSubscription sub;
      sub = session.stdout.cast<List<int>>().transform(utf8.decoder).listen((data) {
        if (data.contains('READY') && !completer.isCompleted) completer.complete();
        if (data.contains('ERR:') && !completer.isCompleted) completer.completeError(data.trim());
      });

      await completer.future.timeout(const Duration(seconds: 5));
      await sub.cancel();

      setState(() {
        ready = true;
        starting = false;
      });
    } catch (e) {
      setState(() {
        starting = false;
        ready = false;
        error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void stop(BuildContext context) {
    try {
      send('quit');
      _session?.close();
    } catch (_) {}
    _session = null;
    setState(() => ready = false);
  }

  void send(String cmd) {
    if (!ready) return;
    try {
      _session?.stdin.add(utf8.encode('$cmd\n'));
    } catch (_) {}
  }
}

// ─────────────────────────────────────────────
//  MAIN SCREEN
// ─────────────────────────────────────────────

class VirtualPadScreen extends StatefulWidget {
  const VirtualPadScreen({super.key});

  @override
  State<VirtualPadScreen> createState() => _VirtualPadScreenState();
}

class _VirtualPadScreenState extends State<VirtualPadScreen> {
  late final _DeviceSession _pad;
  late final _DeviceSession _kb;

  @override
  void initState() {
    super.initState();
    _pad = _DeviceSession(
      scriptName: 'foclabrocvpad.py',
      scriptContent: _padScript,
      setState: (fn) { if (mounted) setState(fn); },
    );
    _kb = _DeviceSession(
      scriptName: 'foclabrocvkb.py',
      scriptContent: _kbScript,
      setState: (fn) { if (mounted) setState(fn); },
    );
  }

  @override
  void dispose() {
    _pad.stop(context);
    _kb.stop(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(flex: 5, child: _KeyboardSection(session: _kb)),
            Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 16), color: Colors.white10),
            Expanded(flex: 6, child: _PadSection(session: _pad)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  KEYBOARD SECTION
// ─────────────────────────────────────────────

class _KeyboardSection extends StatefulWidget {
  final _DeviceSession session;
  const _KeyboardSection({required this.session});

  @override
  State<_KeyboardSection> createState() => _KeyboardSectionState();
}

class _KeyboardSectionState extends State<_KeyboardSection> {
  bool _shift = false;
  bool _ctrl = false;
  bool _alt = false;

  static const _row1 = ['q','w','e','r','t','y','u','i','o','p'];
  static const _row2 = ['a','s','d','f','g','h','j','k','l'];
  static const _row3 = ['z','x','c','v','b','n','m'];

  void _tap(String key) {
    HapticFeedback.lightImpact();
    widget.session.send('press $key');
    Future.delayed(const Duration(milliseconds: 80), () {
      widget.session.send('release $key');
      if (key != 'shift' && key != 'ctrl' && key != 'alt') {
        if (_shift) { widget.session.send('release shift'); setState(() => _shift = false); }
      }
    });
  }

  void _toggleMod(String key, bool current, void Function(bool) update) {
    HapticFeedback.mediumImpact();
    if (current) {
      widget.session.send('release $key');
      update(false);
    } else {
      widget.session.send('press $key');
      update(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;

    return Column(
      children: [
        _DeviceStatusBar(
          label: 'FoclabrocVkb',
          ready: session.ready,
          starting: session.starting,
          error: session.error,
          onConnect: () => session.start(context),
          onDisconnect: () => session.stop(context),
          accentColor: const Color(0xFF8BE9FD),
        ),
        if (session.starting)
          const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF8BE9FD), strokeWidth: 2)))
        else if (session.error != null)
          Expanded(child: _ErrorView(error: session.error!, accentColor: const Color(0xFF8BE9FD)))
        else
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Ligne 1 : ESC | F1 | pipe | ↑ | ↓ | ← | → | TAB
                  Row(children: [
                    _KbKey.flex(label: 'ESC', flex: 11, color: const Color(0xFFE02020), onTap: () => _tap('esc')),
                    _KbKey.flex(label: 'F1',  flex: 10, color: const Color(0xFF8BE9FD), onTap: () => _tap('f1')),
                    _KbKey.flex(label: '|',   flex: 9,  onTap: () => _tap('pipe')),
                    _KbKey.flex(label: '(',   flex: 10, onTap: () => _tap('lparen')),
                    _KbKey.flex(label: ')',   flex: 10, onTap: () => _tap('rparen')),
                    _KbKey.flex(label: '←',   flex: 10, onTap: () => _tap('left')),
                    _KbKey.flex(label: '→',   flex: 10, onTap: () => _tap('right')),
                    _KbKey.flex(label: 'TAB', flex: 12, onTap: () => _tap('tab')),
                  ]),
                  // Ligne 2 : QWERTYUIOP
                  Row(children: _row1.map((k) => _KbKey.flex(label: k.toUpperCase(), onTap: () => _tap(k))).toList()),
                  // Ligne 3 : ASDFGHJKL + ;
                  Row(children: [
                    ..._row2.map((k) => _KbKey.flex(label: k.toUpperCase(), onTap: () => _tap(k))),
                    _KbKey.flex(label: ':', onTap: () => _tap('colon'), flex: 10),
                    _KbKey.flex(label: ';', onTap: () => _tap('semicolon'), flex: 10),
                  ]),
                  // Ligne 4 : ZXCVBNM + . - _ + ⌫
                  Row(children: [
                    ..._row3.map((k) => _KbKey.flex(label: k.toUpperCase(), onTap: () => _tap(k))),
                    _KbKey.flex(label: '.', onTap: () => _tap('dot'), flex: 9),
                    _KbKey.flex(label: '-', onTap: () => _tap('minus'), flex: 9),
                    _KbKey.flex(label: '_', onTap: () => _tap('underscore'), flex: 9),
                    _KbKey.flex(label: '⌫', onTap: () => _tap('backspace'), flex: 13),
                  ]),
                  // Ligne 5 : CTRL | ALT | ⇧ | SPACE | ↵
                  Row(children: [
                    _KbKey.flex(label: 'CTRL', flex: 14, active: _ctrl, color: _ctrl ? const Color(0xFF50FA7B) : null,
                      onTap: () => _toggleMod('ctrl', _ctrl, (v) => setState(() => _ctrl = v))),
                    _KbKey.flex(label: 'ALT', flex: 13, active: _alt, color: _alt ? const Color(0xFF50FA7B) : null,
                      onTap: () => _toggleMod('alt', _alt, (v) => setState(() => _alt = v))),
                    _KbKey.flex(label: '⇧', flex: 12, active: _shift, color: _shift ? const Color(0xFF50FA7B) : null,
                      onTap: () => _toggleMod('shift', _shift, (v) => setState(() => _shift = v))),
                    _KbKey.flex(label: 'SPACE', flex: 42, onTap: () => _tap('space')),
                    _KbKey.flex(label: 'ENTER', flex: 22, color: const Color(0xFF50FA7B), onTap: () => _tap('enter')),
                  ]),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  KEYBOARD KEY WIDGET
// ─────────────────────────────────────────────

class _KbKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool active;
  final double? fixedWidth;
  final int flex;

  const _KbKey._({
    required this.label,
    required this.onTap,
    this.color,
    this.active = false,
    this.fixedWidth,
    this.flex = 10,
  });

  factory _KbKey.flex({
    required String label,
    required VoidCallback onTap,
    Color? color,
    bool active = false,
    int flex = 10,
  }) => _KbKey._(label: label, onTap: onTap, color: color, active: active, flex: flex);

  factory _KbKey.fixed({
    required String label,
    required VoidCallback onTap,
    required double width,
    Color? color,
  }) => _KbKey._(label: label, onTap: onTap, color: color, fixedWidth: width);

  @override
  State<_KbKey> createState() => _KbKeyState();
}

class _KbKeyState extends State<_KbKey> {
  bool _pressed = false;

  Widget _buildInner() {
    final accent = widget.color ?? Colors.white38;
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true); widget.onTap(); },
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        height: 34,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: _pressed || widget.active ? accent.withValues(alpha: 0.22) : const Color(0xFF1C2230),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: _pressed || widget.active ? accent : Colors.white10,
            width: _pressed || widget.active ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            widget.label,
            style: TextStyle(
              color: _pressed || widget.active ? accent : Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.fixedWidth != null) return SizedBox(width: widget.fixedWidth, child: _buildInner());
    return Expanded(flex: widget.flex, child: _buildInner());
  }
}

// ─────────────────────────────────────────────
//  PAD SECTION
// ─────────────────────────────────────────────

class _PadSection extends StatelessWidget {
  final _DeviceSession session;
  const _PadSection({required this.session});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _DeviceStatusBar(
          label: 'FoclabrocVpad',
          ready: session.ready,
          starting: session.starting,
          error: session.error,
          onConnect: () => session.start(context),
          onDisconnect: () => session.stop(context),
          accentColor: const Color(0xFF50FA7B),
        ),
        if (session.starting)
          const Expanded(child: Center(child: CircularProgressIndicator(color: Color(0xFF50FA7B), strokeWidth: 2)))
        else if (session.error != null)
          Expanded(child: _ErrorView(error: session.error!, accentColor: const Color(0xFF50FA7B)))
        else
          Expanded(
            child: Column(
              children: [
                    // L1 / R1
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _ShoulderButton(label: 'L1', onDown: () => session.send('press l1'), onUp: () => session.send('release l1')),
                          _ShoulderButton(label: 'R1', onDown: () => session.send('press r1'), onUp: () => session.send('release r1')),
                        ],
                      ),
                    ),
                    // DPAD + ABXY
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                          // D-PAD: btn=58, gap=40 => zone=161x161
                          SizedBox(
                            width: 161,
                            height: 161,
                            child: Stack(
                              children: [
                                Positioned(left: 50, top: 2,
                                  child: _DpadButton(icon: Icons.keyboard_arrow_up_rounded, onDown: () => session.send('press up'), onUp: () => session.send('release up'))),
                                Positioned(left: 50, top: 98,
                                  child: _DpadButton(icon: Icons.keyboard_arrow_down_rounded, onDown: () => session.send('press down'), onUp: () => session.send('release down'))),
                                Positioned(left: 2, top: 50,
                                  child: _DpadButton(icon: Icons.keyboard_arrow_left_rounded, onDown: () => session.send('press left'), onUp: () => session.send('release left'))),
                                Positioned(left: 98, top: 50,
                                  child: _DpadButton(icon: Icons.keyboard_arrow_right_rounded, onDown: () => session.send('press right'), onUp: () => session.send('release right'))),
                              ],
                            ),
                          ),
                          // ABXY: btn=58, gap=40 => zone=154x154
                          SizedBox(
                            width: 154,
                            height: 154,
                            child: Stack(
                              children: [
                                Positioned(left: 45, top: 6,
                                  child: _ActionButtonFilled(label: 'Y', color: Colors.green, onDown: () => session.send('press y'), onUp: () => session.send('release y'))),
                                Positioned(left: 45, top: 96,
                                  child: _ActionButtonFilled(label: 'A', color: Colors.red, onDown: () => session.send('press a'), onUp: () => session.send('release a'))),
                                Positioned(left: 0, top: 51,
                                  child: _ActionButtonFilled(label: 'X', color: Colors.blue, onDown: () => session.send('press x'), onUp: () => session.send('release x'))),
                                Positioned(left: 90, top: 51,
                                  child: _ActionButtonFilled(label: 'B', color: Colors.orange, onDown: () => session.send('press b'), onUp: () => session.send('release b'))),
                              ],
                            ),
                          ),
                          ],
                        ),
                      ),
                    ),
                    // SELECT / HOTKEY / START
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _PillButton(label: 'SELECT', onDown: () => session.send('press select'), onUp: () => session.send('release select')),
                          const SizedBox(width: 20),
                          _HotkeyButton(onDown: () => session.send('press hotkey'), onUp: () => session.send('release hotkey')),
                          const SizedBox(width: 20),
                          _PillButton(label: 'START', onDown: () => session.send('press start'), onUp: () => session.send('release start')),
                        ],
                      ),
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  SHARED WIDGETS
// ─────────────────────────────────────────────

class _DeviceStatusBar extends StatelessWidget {
  final String label;
  final bool ready;
  final bool starting;
  final String? error;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final Color accentColor;

  const _DeviceStatusBar({
    required this.label,
    required this.ready,
    required this.starting,
    required this.error,
    required this.onConnect,
    required this.onDisconnect,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const SizedBox(width: 44),
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              color: ready ? accentColor : (error != null ? Colors.redAccent : Colors.white24),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            ready ? '$label connected' : '$label disconnected',
            style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (!starting)
            GestureDetector(
              onTap: ready ? onDisconnect : onConnect,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: ready
                      ? const Color(0xFFE02020).withValues(alpha: 0.15)
                      : accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: ready ? const Color(0xFFE02020) : accentColor,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      ready ? Icons.link_off_rounded : Icons.link_rounded,
                      color: ready ? const Color(0xFFE02020) : accentColor,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      ready ? 'DISCONNECT' : 'CONNECT',
                      style: TextStyle(
                        color: ready ? const Color(0xFFE02020) : accentColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: accentColor, strokeWidth: 2)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final Color accentColor;
  const _ErrorView({required this.error, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final isEvdev = error.contains('evdev');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: accentColor, size: 32),
            const SizedBox(height: 8),
            Text(
              isEvdev ? 'evdev not found — run: pip install evdev' : error,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  GAMEPAD BUTTON WIDGETS
// ─────────────────────────────────────────────

// Bouton D-pad (carré, icône flèche)
class _DpadButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onDown;
  final VoidCallback onUp;
  const _DpadButton({required this.icon, required this.onDown, required this.onUp});

  @override
  State<_DpadButton> createState() => _DpadButtonState();
}

class _DpadButtonState extends State<_DpadButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true); HapticFeedback.lightImpact(); widget.onDown(); },
      onTapUp: (_) { setState(() => _pressed = false); widget.onUp(); },
      onTapCancel: () { setState(() => _pressed = false); widget.onUp(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: 60, height: 60,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _pressed ? Colors.grey.shade700 : Colors.grey.shade900,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: _pressed ? 4 : 10,
              offset: Offset(0, _pressed ? 2 : 5),
            ),
          ],
        ),
        child: Icon(widget.icon, color: Colors.white, size: 30),
      ),
    );
  }
}

// Bouton action (cercle plein coloré, style original)
class _ActionButtonFilled extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onDown;
  final VoidCallback onUp;
  const _ActionButtonFilled({required this.label, required this.color, required this.onDown, required this.onUp});

  @override
  State<_ActionButtonFilled> createState() => _ActionButtonFilledState();
}

class _ActionButtonFilledState extends State<_ActionButtonFilled> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) { setState(() => _pressed = true); HapticFeedback.mediumImpact(); widget.onDown(); },
      onTapUp: (_) { setState(() => _pressed = false); widget.onUp(); },
      onTapCancel: () { setState(() => _pressed = false); widget.onUp(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _pressed ? 0.9 : 0.45),
              blurRadius: _pressed ? 24 : 12,
              spreadRadius: _pressed ? 4 : 1,
            ),
          ],
        ),
        child: Center(
          child: Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

// Bouton hotkey central (cercle avec icône home)
class _HotkeyButton extends StatefulWidget {
  final VoidCallback onDown;
  final VoidCallback onUp;
  const _HotkeyButton({required this.onDown, required this.onUp});

  @override
  State<_HotkeyButton> createState() => _HotkeyButtonState();
}

class _HotkeyButtonState extends State<_HotkeyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) { setState(() => _pressed = true); HapticFeedback.mediumImpact(); widget.onDown(); },
      onTapUp: (_) { setState(() => _pressed = false); widget.onUp(); },
      onTapCancel: () { setState(() => _pressed = false); widget.onUp(); },
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: _pressed
                ? [Colors.grey.shade600, Colors.grey.shade800]
                : [Colors.grey.shade700, Colors.grey.shade900],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: _pressed ? 0.15 : 0.06),
              blurRadius: 12,
            ),
          ],
          border: Border.all(color: Colors.white24, width: 2),
        ),
        child: const Icon(Icons.home_rounded, color: Colors.white, size: 26),
      ),
    );
  }
}

// Bouton épaule (L1 / R1)
class _ShoulderButton extends StatefulWidget {
  final String label;
  final VoidCallback onDown;
  final VoidCallback onUp;
  const _ShoulderButton({required this.label, required this.onDown, required this.onUp});

  @override
  State<_ShoulderButton> createState() => _ShoulderButtonState();
}

class _ShoulderButtonState extends State<_ShoulderButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true); HapticFeedback.lightImpact(); widget.onDown(); },
      onTapUp: (_) { setState(() => _pressed = false); widget.onUp(); },
      onTapCancel: () { setState(() => _pressed = false); widget.onUp(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: 76, height: 38,
        decoration: BoxDecoration(
          color: _pressed ? Colors.grey.shade700 : Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: _pressed ? 4 : 10,
              offset: Offset(0, _pressed ? 2 : 5),
            ),
          ],
        ),
        child: Center(
          child: Text(
            widget.label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

// Bouton pill (SELECT / START)
class _PillButton extends StatefulWidget {
  final String label;
  final VoidCallback onDown;
  final VoidCallback onUp;
  const _PillButton({required this.label, required this.onDown, required this.onUp});

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) { setState(() => _pressed = true); HapticFeedback.lightImpact(); widget.onDown(); },
      onTapUp: (_) { setState(() => _pressed = false); widget.onUp(); },
      onTapCancel: () { setState(() => _pressed = false); widget.onUp(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        width: 86, height: 34,
        decoration: BoxDecoration(
          color: _pressed ? Colors.grey.shade700 : Colors.grey.shade900,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: _pressed ? 4 : 10,
              offset: Offset(0, _pressed ? 2 : 5),
            ),
          ],
        ),
        child: Center(
          child: Text(
            widget.label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.2),
          ),
        ),
      ),
    );
  }
}
