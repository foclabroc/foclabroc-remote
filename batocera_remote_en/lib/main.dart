import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'models/app_state.dart';
import 'screens/home_screen.dart';

final GlobalKey<NavigatorState> _rootNavKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Forcer le mode portrait uniquement
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Empêche la mise en veille tant que l'app est ouverte
  await WakelockPlus.enable();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
      child: const BatoceraRemoteApp(),
    ),
  );
}

class BatoceraRemoteApp extends StatelessWidget {
  const BatoceraRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _rootNavKey,
      title: 'Foclabroc Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFFE02020),
          surface: const Color(0xFF1C2230),
          onSurface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFF0D0F14),
        cardTheme: CardThemeData(
          color: const Color(0xFF1C2230),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161A22),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
          titleMedium: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          bodyLarge: TextStyle(color: Colors.white70, fontSize: 14),
          bodyMedium: TextStyle(color: Colors.white38, fontSize: 13),
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: const Color(0xFFE02020),
          thumbColor: const Color(0xFFE02020),
          overlayColor: const Color(0xFFE02020).withOpacity(0.2),
          inactiveTrackColor: Colors.white12,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFE02020),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;
  late Animation<double> _glowOpacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.6, curve: Curves.elasticOut)));
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.0, 0.4, curve: Curves.easeIn)));
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.5, 0.9, curve: Curves.easeIn)));
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.5, 0.9, curve: Curves.easeOut)));
    _glowOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: const Interval(0.6, 1.0, curve: Curves.easeIn)));

    _ctrl.forward();

    // Navigate after animation + short pause
    Future.delayed(const Duration(milliseconds: 2600), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            transitionDuration: const Duration(milliseconds: 500),
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      body: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Stack(
          fit: StackFit.expand,
          children: [
            // Fond avec particules
            CustomPaint(painter: _BackgroundPainter(_ctrl.value)),

            // Contenu centré
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logo avec glow
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow effect
                      Opacity(
                        opacity: _glowOpacity.value,
                        child: Container(
                          width: 220, height: 220,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE02020).withOpacity(0.3),
                                blurRadius: 80,
                                spreadRadius: 20,
                              ),
                              BoxShadow(
                                color: const Color(0xFF0040FF).withOpacity(0.2),
                                blurRadius: 60,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Logo sans fond blanc
                      Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: ColorFiltered(
                            colorFilter: const ColorFilter.matrix(<double>[
                              1, 0, 0, 0, 0,
                              0, 1, 0, 0, 0,
                              0, 0, 1, 0, 0,
                              -1, -1, -1, 3, 0, // white → transparent
                            ]),
                            child: Image.asset('assets/icon.png', width: 210, height: 210),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Texte
                  FadeTransition(
                    opacity: _textOpacity,
                    child: SlideTransition(
                      position: _textSlide,
                      child: Column(children: [
                        const Text('FOCLABROC',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFFE02020), Color(0xFFFF6060)],
                          ).createShader(bounds),
                          child: const Text('BATOCERA REMOTE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ],
              ),
            ),

            // Barre de chargement en bas
            Positioned(
              bottom: 60,
              left: 60, right: 60,
              child: FadeTransition(
                opacity: _textOpacity,
                child: Column(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _ctrl.value,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFE02020)),
                      minHeight: 3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('by foclabroc',
                    style: TextStyle(color: Colors.white24, fontSize: 11, letterSpacing: 2)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundPainter extends CustomPainter {
  final double progress;
  _BackgroundPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Gradient background circles
    paint.color = const Color(0xFFE02020).withOpacity(0.22 * progress);
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.15), 220, paint);

    paint.color = const Color(0xFF0040FF).withOpacity(0.18 * progress);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.85), 280, paint);

    paint.color = const Color(0xFFE02020).withOpacity(0.14 * progress);
    canvas.drawCircle(Offset(size.width * 0.88, size.height * 0.12), 160, paint);

    paint.color = const Color(0xFF0040FF).withOpacity(0.10 * progress);
    canvas.drawCircle(Offset(size.width * 0.1, size.height * 0.8), 180, paint);
  }

  @override
  bool shouldRepaint(_BackgroundPainter old) => old.progress != progress;
}
