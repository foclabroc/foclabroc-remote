import 'package:flutter/material.dart';
import '../services/pending_scrap_service.dart';

/// Dialog qui liste les scraps pending et propose de les installer.
/// Retourne `true` si l'utilisateur a cliqué "Installer maintenant", `false`
/// pour "Plus tard", `null` si annulé (dismiss).
class PendingScrapsDialog extends StatelessWidget {
  final List<PendingScrap> pending;
  final bool gameRunning;

  const PendingScrapsDialog({
    super.key,
    required this.pending,
    required this.gameRunning,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C2230),
      title: Row(children: [
        const Icon(Icons.cloud_upload_rounded, color: Color(0xFFE02020), size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            pending.length == 1 ? 'Scrap en attente' : '${pending.length} scraps en attente',
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Les scraps suivants n\'ont pas encore été enregistrés dans le gamelist :',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: pending.length,
                separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 8),
                itemBuilder: (_, i) {
                  final p = pending[i];
                  final labels = p.tagLabels.join(' + ');
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      const Icon(Icons.videogame_asset_rounded, color: Colors.white38, size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.gameName.isEmpty ? p.romBase : p.gameName,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                overflow: TextOverflow.ellipsis),
                            Text('${p.systemName} — $labels',
                                style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                    ]),
                  );
                },
              ),
            ),
            if (gameRunning) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orangeAccent.withOpacity(0.4)),
                ),
                child: const Row(children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Un jeu est en cours. Cliquer sur Installer le fermera.',
                      style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Plus tard'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE02020)),
          child: const Text('Installer'),
        ),
      ],
    );
  }
}
