import 'package:flutter/material.dart';
import 'quiz_screen.dart';
import 'breakout_screen.dart';
import 'jump_screen.dart';

/// "Mini games" tab: groups the Retro Quiz, Breakout and Retro Jump.
/// Each game opens in the tab's Navigator → the Android back button
/// returns to this list.
class MiniGamesScreen extends StatelessWidget {
  const MiniGamesScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(64, 8, 24, 16),
              child: Text('Mini games', style: Theme.of(context).textTheme.headlineMedium),
            ),
            _GameCard(
              icon: Icons.quiz_rounded,
              color: Colors.amberAccent,
              title: 'Retro Quiz',
              subtitle: '10 questions · 20 s per question',
              onTap: () => _open(context, const QuizScreen()),
            ),
            _GameCard(
              icon: Icons.sports_tennis_rounded,
              color: Colors.lightBlueAccent,
              title: 'Breakout',
              subtitle: 'Retro brick breaker · playable offline',
              onTap: () => _open(context, const BreakoutScreen()),
            ),
            _GameCard(
              icon: Icons.keyboard_double_arrow_up_rounded,
              color: Colors.greenAccent,
              title: 'Retro Jump',
              subtitle: 'Jump from cartridge to cartridge · offline',
              onTap: () => _open(context, const JumpScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _GameCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: const Color(0xFF1C2230),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(subtitle,
                      style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
            ]),
          ),
        ),
      ),
    );
  }
}
