import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/app_state.dart';
import '../widgets/status_badge.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final _nameCtrl = TextEditingController();
  final _ipCtrl = TextEditingController();
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController(text: 'root');
  final _passCtrl = TextEditingController(text: 'linux');
  bool _obscurePass = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = context.read<AppState>();
      _ipCtrl.text = state.host;
      _portCtrl.text = state.port.toString();
      _userCtrl.text = state.username;
      _passCtrl.text = state.password;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _showEntryOptions(BuildContext context, AppState state, String entry) {
    final ip = state.recentHostIp(entry);
    final name = state.recentHostName(entry);
    final nameCtrl = TextEditingController(text: name);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2230),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ip, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: nameCtrl,
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Nom (ex: Salon, Bureau...)',
              hintStyle: const TextStyle(color: Colors.white38),
              filled: true,
              fillColor: Colors.white.withOpacity(0.06),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () {
                  state.removeRecentHost(entry);
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                label: const Text('Supprimer', style: TextStyle(color: Colors.redAccent)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  state.renameRecentHost(entry, nameCtrl.text);
                  Navigator.pop(ctx);
                },
                child: const Text('Sauvegarder'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _connect(AppState state) async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) return;
    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    await state.connect(
      host: ip,
      name: _nameCtrl.text.trim(),
      port: port,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final accent = Theme.of(context).colorScheme.primary;
    final isConnected = state.isConnected;
    final isConnecting = state.status == ConnectionStatus.connecting;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Header logo + titre
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset('assets/icon.png', width: 60, height: 60),
                  ),
                  const SizedBox(width: 16),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Batocera Remote',
                          style: Theme.of(context).textTheme.headlineMedium),
                      Text('by foclabroc',
                          style: Theme.of(context).textTheme.bodyMedium),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Badge statut
              StatusBadge(status: state.status),

              if (state.errorMessage.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(state.errorMessage,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),

              const SizedBox(height: 24),

              // Récents
              if (state.recentHosts.isNotEmpty) ...[
                Row(
                  children: [
                    Text('Récents',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => state.clearRecentHosts(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Text('Vider',
                            style: TextStyle(color: Colors.white38, fontSize: 11)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: state.recentHosts.map((entry) {
                    final ip = state.recentHostIp(entry);
                    final name = state.recentHostName(entry);
                    return GestureDetector(
                      onTap: () {
                        _ipCtrl.text = ip;
                        _connect(state);
                      },
                      onLongPress: () => _showEntryOptions(context, state, entry),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: accent.withOpacity(0.4)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.history_rounded, color: accent, size: 14),
                            const SizedBox(width: 6),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (name.isNotEmpty)
                                  Text(name,
                                      style: TextStyle(
                                          color: accent,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700)),
                                Text(ip,
                                    style: TextStyle(
                                        color: name.isNotEmpty ? accent.withOpacity(0.7) : accent,
                                        fontSize: name.isNotEmpty ? 11 : 13,
                                        fontWeight: name.isNotEmpty ? FontWeight.w400 : FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // Formulaire SSH — masqué si connecté
              if (!isConnected) Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C2230),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Paramètres SSH',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 20),

                    // IP + Port
                    _FieldBox(
                      controller: _nameCtrl,
                      label: 'Nom (optionnel)',
                      icon: Icons.label_outline_rounded,
                      onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _FieldBox(
                            controller: _ipCtrl,
                            label: 'Adresse IP',
                            icon: Icons.computer_rounded,
                            keyboardType: TextInputType.number,
                            onSubmitted: (_) => _connect(state),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 80,
                          child: _FieldBox(
                            controller: _portCtrl,
                            label: 'Port',
                            keyboardType: TextInputType.number,
                            onSubmitted: (_) => _connect(state),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Utilisateur
                    _FieldBox(
                      controller: _userCtrl,
                      label: 'Utilisateur',
                      icon: Icons.person_rounded,
                      onSubmitted: (_) => _connect(state),
                    ),

                    const SizedBox(height: 12),

                    // Mot de passe
                    _FieldBox(
                      controller: _passCtrl,
                      label: 'Mot de passe',
                      icon: Icons.lock_rounded,
                      obscureText: _obscurePass,
                      onSubmitted: (_) => _connect(state),
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePass ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                          color: Colors.white38, size: 20,
                        ),
                        onPressed: () => setState(() => _obscurePass = !_obscurePass),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Bouton connexion
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: isConnecting
                            ? null
                            : isConnected
                                ? () => state.disconnect()
                                : () => _connect(state),
                        icon: isConnecting
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(isConnected
                                ? Icons.link_off_rounded
                                : Icons.link_rounded),
                        label: Text(isConnecting
                            ? 'Connexion...'
                            : isConnected
                                ? 'Déconnecter'
                                : 'Se connecter'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isConnected ? Colors.white12 : Colors.green.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Bouton déconnecter (visible uniquement si connecté)
              if (isConnected)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => state.disconnect(),
                      icon: const Icon(Icons.link_off_rounded),
                      label: const Text('Déconnecter'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),

              // Infos système
              if (isConnected && state.systemInfo.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C2230),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.info_outline_rounded, color: Colors.white38, size: 14),
                        const SizedBox(width: 6),
                        Text('Informations système',
                            style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1)),
                      ]),
                      const SizedBox(height: 10),
                      Text(state.systemInfo,
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Colors.white70,
                              height: 1.6)),
                    ],
                  ),
                ),

              const SizedBox(height: 16),

              // Hint
              Center(
                child: Text(
                  'Batocera : SSH activé par défaut · User root / linux',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FieldBox extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final void Function(String)? onSubmitted;
  final Widget? suffix;

  const _FieldBox({
    required this.controller,
    required this.label,
    this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.onSubmitted,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        onSubmitted: onSubmitted,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white38, fontSize: 13),
          prefixIcon: icon != null
              ? Icon(icon, color: Colors.white38, size: 18)
              : null,
          suffixIcon: suffix,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
