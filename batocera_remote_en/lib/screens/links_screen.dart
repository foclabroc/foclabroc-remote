import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'home_screen.dart';

class LinksScreen extends StatelessWidget {
  const LinksScreen({super.key});

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 12, 24, 0),
              child: Text('Useful links',
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  _tile(context,
                    icon: Icons.system_update_rounded, color: accent,
                    title: 'Foclabroc Remote Update',
                    subtitle: 'Current version: $kAppVersion',
                    url: 'https://github.com/foclabroc/foclabroc-remote/releases'),
                  const SizedBox(height: 10),
                  _tile(context,
                    icon: Icons.menu_book_rounded, color: Colors.cyanAccent,
                    title: 'Wiki Batocera',
                    subtitle: 'Official Batocera documentation',
                    url: 'https://wiki.batocera.org/'),
                  const SizedBox(height: 10),
                  _tile(context,
                    icon: Icons.group_rounded, color: const Color(0xFF1877F2),
                    title: 'Batocera Fans FR',
                    subtitle: 'French community Facebook group',
                    url: 'https://www.facebook.com/groups/BatoceraFansFr/'),
                  const SizedBox(height: 10),
                  _tile(context,
                    icon: Icons.chat_rounded, color: const Color(0xFF5865F2),
                    title: 'Discord Batocera Fans FR',
                    subtitle: 'French community Discord server',
                    url: 'https://discord.gg/vY4rGeSP'),
                  const SizedBox(height: 10),
                  _tile(context,
                    icon: Icons.forum_rounded, color: const Color(0xFF5865F2),
                    title: 'Discord Batocera Officiel',
                    subtitle: 'Official Batocera Discord server',
                    url: 'https://discord.gg/MZX8pMa6'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, {
    required IconData icon, required Color color,
    required String title, required String subtitle, required String url,
  }) {
    return Material(
      color: const Color(0xFF1C2230),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _open(url),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            )),
            Icon(Icons.open_in_new_rounded, color: color.withOpacity(0.6), size: 18),
          ]),
        ),
      ),
    );
  }
}
