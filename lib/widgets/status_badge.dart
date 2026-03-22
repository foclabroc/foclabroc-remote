import 'package:flutter/material.dart';
import '../models/app_state.dart';

class StatusBadge extends StatelessWidget {
  final ConnectionStatus status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (status) {
      ConnectionStatus.connected => (
          Colors.green,
          Icons.link_rounded,
          'Connecté'
        ),
      ConnectionStatus.connecting => (
          Colors.amberAccent,
          Icons.sync_rounded,
          'Connexion...'
        ),
      ConnectionStatus.error => (
          Colors.redAccent,
          Icons.link_off_rounded,
          'Erreur'
        ),
      ConnectionStatus.disconnected => (
          Colors.white38,
          Icons.link_off_rounded,
          'Déconnecté'
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          status == ConnectionStatus.connecting
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 1.5, color: color),
                )
              : Icon(icon, color: color, size: 14),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
