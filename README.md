# Batocera Remote 🎮

Télécommande Android pour Batocera Linux — par **foclabroc**

## Fonctionnalités

- 🔗 Connexion SSH au PC Batocera via WiFi
- 🎮 Liste et lancement des ROMs
- 🔊 Contrôle du volume
- ⚙️ Reboot / Shutdown / Quitter EmulationStation

## Prérequis

- **Flutter SDK** ≥ 3.0 — https://flutter.dev/docs/get-started/install
- **Android Studio** ou **VS Code** avec le plugin Flutter
- Un appareil Android ou émulateur

## Installation

```bash
# 1. Cloner / dézipper le projet
cd batocera_remote

# 2. Installer les dépendances
flutter pub get

# 3. Lancer sur un appareil connecté
flutter run

# 4. Compiler un APK release
flutter build apk --release
# L'APK se trouve dans : build/app/outputs/flutter-apk/app-release.apk
```

## Configuration Batocera

Sur Batocera, le SSH est activé par défaut :
- **IP** : adresse locale de ta machine (ex: 192.168.1.50)
- **Port** : 22
- **User** : `root`
- **Mot de passe** : `linux`

Tu peux trouver l'IP dans Batocera → Paramètres réseau.

## Structure du projet

```
lib/
├── main.dart              # Point d'entrée + thème
├── models/
│   └── app_state.dart     # État global (Provider)
├── services/
│   └── ssh_service.dart   # Connexion SSH + commandes
├── screens/
│   ├── home_screen.dart   # Navigation principale
│   ├── connect_screen.dart # Écran connexion
│   ├── games_screen.dart  # Liste des ROMs
│   └── system_screen.dart # Contrôles système
└── widgets/
    └── status_badge.dart  # Badge de statut
```

## Roadmap

- [ ] Authentification par clé SSH
- [ ] Scraping des jaquettes
- [ ] Contrôleur virtuel (D-Pad tactile)
- [ ] Notifications (jeu en cours)
- [ ] Support iOS
