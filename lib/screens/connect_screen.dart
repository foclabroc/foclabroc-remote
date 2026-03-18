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
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _userCtrl;
  late TextEditingController _passCtrl;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final s = context.read<AppState>();
    _hostCtrl = TextEditingController(text: s.host);
    _portCtrl = TextEditingController(text: s.port.toString());
    _userCtrl = TextEditingController(text: s.username);
    _passCtrl = TextEditingController(text: s.password);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit(AppState state) async {
    if (!_formKey.currentState!.validate()) return;
    await state.connect(
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 22,
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final accent = Theme.of(context).colorScheme.primary;
    final connected = state.isConnected;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Header avec logo PNG
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accent.withOpacity(0.2)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.asset('assets/icon.png', fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 14),
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
              const SizedBox(height: 32),

              StatusBadge(status: state.status),
              const SizedBox(height: 24),

              if (connected) ...[
                _InfoCard(info: state.systemInfo),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async => await state.disconnect(),
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Se déconnecter'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ] else ...[

                // Historique IP récentes
                if (state.recentHosts.isNotEmpty) ...[
                  Text('Récents', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: state.recentHosts.map((ip) => ActionChip(
                      avatar: Icon(Icons.history_rounded, size: 14, color: accent),
                      label: Text(ip),
                      backgroundColor: const Color(0xFF1C2230),
                      side: BorderSide(color: accent.withOpacity(0.3)),
                      labelStyle: TextStyle(color: accent, fontSize: 13),
                      onPressed: () => setState(() => _hostCtrl.text = ip),
                    )).toList(),
                  ),
                  const SizedBox(height: 20),
                ],

                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Paramètres SSH',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 20),

                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: TextFormField(
                                  controller: _hostCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Adresse IP',
                                    hintText: '192.168.1.x',
                                    prefixIcon: Icon(Icons.computer_rounded),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (v) =>
                                      v == null || v.isEmpty ? 'Requis' : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 1,
                                child: TextFormField(
                                  controller: _portCtrl,
                                  decoration: const InputDecoration(
                                    labelText: 'Port',
                                    hintText: '22',
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _userCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Utilisateur',
                              hintText: 'root',
                              prefixIcon: Icon(Icons.person_rounded),
                            ),
                          ),
                          const SizedBox(height: 14),

                          TextFormField(
                            controller: _passCtrl,
                            obscureText: _obscure,
                            decoration: InputDecoration(
                              labelText: 'Mot de passe',
                              hintText: 'linux',
                              prefixIcon: const Icon(Icons.lock_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(_obscure
                                    ? Icons.visibility_rounded
                                    : Icons.visibility_off_rounded),
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: state.status == ConnectionStatus.connecting
                                  ? null
                                  : () => _submit(state),
                              icon: state.status == ConnectionStatus.connecting
                                  ? const SizedBox(
                                      width: 18, height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.link_rounded),
                              label: Text(state.status == ConnectionStatus.connecting
                                  ? 'Connexion...'
                                  : 'Se connecter'),
                            ),
                          ),

                          if (state.errorMessage.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.redAccent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: Colors.redAccent.withOpacity(0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_rounded,
                                      color: Colors.redAccent, size: 18),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      state.errorMessage,
                                      style: const TextStyle(
                                          color: Colors.redAccent, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: Colors.white.withOpacity(0.4)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Batocera: SSH activé par défaut. User: root / Pass: linux',
                          style: TextStyle(
                              fontSize: 12, color: Colors.white.withOpacity(0.4)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String info;
  const _InfoCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final lines = info.split('\n').where((l) => l.isNotEmpty).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_rounded,
                    color: Theme.of(context).colorScheme.primary, size: 18),
                const SizedBox(width: 8),
                Text('Informations système',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ...lines.map((line) {
              final parts = line.split(': ');
              if (parts.length >= 2) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Text('${parts[0]}: ',
                          style: Theme.of(context).textTheme.bodyMedium),
                      Expanded(
                        child: Text(
                          parts.sublist(1).join(': '),
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Text(line, style: Theme.of(context).textTheme.bodyMedium);
            }),
          ],
        ),
      ),
    );
  }
}
