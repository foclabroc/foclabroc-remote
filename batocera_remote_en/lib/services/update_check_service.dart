import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Information sur une mise à jour disponible.
class UpdateInfo {
  /// Version distante extraite de l'asset (ex : "3.2").
  final String latestVersion;

  /// Version locale extraite de [kAppVersion] (ex : "3.1").
  final String currentVersion;

  /// URL directe de téléchargement de l'APK pour la variante (FR ou EN).
  final String apkUrl;

  /// URL de la page release GitHub (fallback navigateur).
  final String releasePageUrl;

  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.apkUrl,
    required this.releasePageUrl,
  });
}

/// Service de vérification des mises à jour via l'API GitHub Releases.
///
/// Format des assets attendu : `foclabroc.remote.V<version>.<variant>.apk`
/// (ex : `foclabroc.remote.V3.1.FR.apk` ou `foclabroc.remote.V3.10.EN.apk`).
class UpdateCheckService {
  static const _githubApiUrl =
      'https://api.github.com/repos/foclabroc/foclabroc-remote/releases/tags/release';
  static const _releasePageUrl =
      'https://github.com/foclabroc/foclabroc-remote/releases/tag/release';

  /// Vérifie si une nouvelle version est disponible pour la variante donnée.
  ///
  /// [currentVersion] : valeur de `kAppVersion` (ex : "3.1-FR" ou "3.1-EN").
  /// [variant] : "FR" ou "EN".
  ///
  /// Retourne `null` si tout est à jour, si aucun asset ne matche, ou si
  /// une erreur survient (timeout, pas d'internet, etc.). Silent fail.
  static Future<UpdateInfo?> check({
    required String currentVersion,
    required String variant,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.getUrl(Uri.parse(_githubApiUrl));
      req.headers.add('Accept', 'application/vnd.github+json');
      req.headers.add('User-Agent', 'foclabroc-remote-update-check');
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;
      final body = await resp.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final assets = (data['assets'] as List?) ?? const [];

      // Cherche l'APK matchant la variante. La regex accepte des versions
      // à 2, 3 ou 4 segments (3.1, 3.1.0, 3.1.0.1).
      final pattern = RegExp(
        r'V(\d+(?:\.\d+){1,3})\.' + variant + r'\.apk$',
        caseSensitive: false,
      );
      String? latestVersion;
      String? apkUrl;
      for (final asset in assets) {
        final m = asset as Map<String, dynamic>;
        final name = m['name'] as String? ?? '';
        final url = m['browser_download_url'] as String? ?? '';
        final match = pattern.firstMatch(name);
        if (match == null) continue;
        final v = match.group(1)!;
        if (latestVersion == null || _compareVersions(v, latestVersion) > 0) {
          latestVersion = v;
          apkUrl = url;
        }
      }
      if (latestVersion == null || apkUrl == null) return null;

      // Extrait la partie numérique de currentVersion ("3.1-FR" → "3.1").
      final currentNumeric = currentVersion.split(RegExp(r'[-+ _]')).first;
      if (_compareVersions(latestVersion, currentNumeric) <= 0) return null;

      return UpdateInfo(
        latestVersion: latestVersion,
        currentVersion: currentNumeric,
        apkUrl: apkUrl,
        releasePageUrl: _releasePageUrl,
      );
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// URL de la page release (utile pour un bouton manuel "Voir les releases").
  static String get releasePageUrl => _releasePageUrl;

  /// Compare deux versions au format "3.1" ou "3.1.2" segment par segment.
  /// Retourne > 0 si a > b, < 0 si a < b, 0 si égales.
  /// "3.10" est considéré supérieur à "3.2" (chaque segment est un int).
  static int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final bParts = b.split('.').map((p) => int.tryParse(p) ?? 0).toList();
    final maxLen = aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < maxLen; i++) {
      final ai = i < aParts.length ? aParts[i] : 0;
      final bi = i < bParts.length ? bParts[i] : 0;
      if (ai != bi) return ai - bi;
    }
    return 0;
  }
}
