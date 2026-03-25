# Foclabroc Remote 🎮

**Android Remote Control for Batocera Linux — v1.1.0**

[![Voir la démo](https://img.youtube.com/vi/OkYvSxjOg3c/maxresdefault.jpg)](https://youtu.be/OkYvSxjOg3c)

> *Click on the image to watch the demo video*

---

## 📥 Download

[![Download APK](https://img.shields.io/badge/Download-APK-red?style=for-the-badge&logo=android)](https://github.com/foclabroc/foclabroc-remote/releases/download/release/foclabroc.remote.apk)

---

## ✨ Features

### 🔗 Connexion SSH
- Connexion WiFi via SSH à ta machine Batocera
- **Connexion automatique** à la dernière IP utilisée au démarrage
- Reconnexion silencieuse automatique si la connexion est perdue
- Indicateur "Reconnexion..." visible sur tous les onglets
- Historique des 3 dernières adresses IP (effaçable)
- Informations système détaillées (modèle, CPU, RAM, résolution, OS...)

### 🎮 Jeu en cours
- Affichage du jeu en cours : wheel, jaquette, screenshot
- Chronomètre de session en temps réel
- Infos : système, émulateur, core
- Lien RetroAchievements
- Bouton stop (hotkeygen)
- Visionneuse PDF pour les manuels
- Auto-refresh toutes les 5 secondes

### 📚 Bibliothèque de jeux
- Grille de tous tes systèmes avec logos
- **Recherche globale** dans tous les jeux de tous les systèmes (avec cache)
- Liste des jeux par système avec indicateurs : ⭐ favori, 🏆 achievements, 📖 manuel, 🗺️ map
- **Fiche détaillée** par jeu :
  - Wheel / marquee, jaquette et screenshot côte à côte (cliquables pour agrandir)
  - Infos : genre, développeur, éditeur, année, description
  - Bouton **Lancer** (quitte le jeu en cours automatiquement)
  - Visionneuse **Manuel** (PDF ou image)
  - Visionneuse **Map** (PDF ou image, zoomable)
  - Lecteur **Vidéo** intégré
  - Lien **RetroAchievements**

### 📸 Capture
- Screenshot instantané
- Capture vidéo avec chronomètre
- Mode **Auto 30 secondes**
- Réglages qualité et audio

### 💻 Terminal SSH
- Terminal intégré avec historique des commandes
- Texte sélectionnable et copiable

### 📁 Gestionnaire de fichiers
- Navigation dans `/userdata/` avec fil d'Ariane
- **Bouton retour Android** pour remonter dans l'arborescence
- Visionneuse intégrée : images (zoomable), PDF, vidéos
- Éditeur de texte intégré pour `.cfg`, `.conf`, `.ini`, `.sh`...
- Upload depuis le téléphone avec barre de progression
- Sélection multiple : copier, couper, coller, renommer, supprimer

### ⚙️ Système
- Contrôle du volume en temps réel
- **Gestion émulateur** : quitter proprement (hotkeygen) ou forcer l'arrêt
- Mode d'alimentation (Performance / Équilibré / Économie)
- Redémarrage EmulationStation, reboot, arrêt
- Logs `stderr` et `stdout` partageables
- **Vider le cache** images et vidéos de l'application

---

## 📋 Requirements

- Android 8.0+
- Batocera Linux sur le même réseau WiFi
- SSH activé sur Batocera (activé par défaut)

**Default Batocera SSH credentials :**
```
IP     : adresse locale de ta machine (ex: 192.168.1.134)
Port   : 22
User   : root
Pass   : linux
```

---

## 🚀 Installation

1. Download the APK using the button above
2. On your Android phone: **Settings → Security → Unknown sources** → Allow
3. Install the APK
4. Launch the app — auto-connects if previously used

---

## 🛠️ Build from source

```bash
# Prérequis : Flutter SDK >= 3.0
git clone https://github.com/foclabroc/foclabroc-remote.git
cd foclabroc-remote
flutter pub get
dart run flutter_launcher_icons
flutter run
```

```bash
# Compiler un APK release
flutter build apk --release
```

---

## 📦 Tech stack

| Package | Usage |
|---|---|
| **Flutter** | Framework UI |
| **dartssh2** | SSH / SFTP natif Dart |
| **Provider** | Gestion d'état |
| **video_player** | Lecteur vidéo |
| **flutter_pdfview** | Visionneuse PDF |
| **crypto** | Cache images (MD5) |
| **path_provider** | Système de fichiers local |
| **file_picker** | Sélection fichiers Android |
| **open_filex** | Ouverture fichiers natifs |
| **share_plus** | Partage de logs |
| **url_launcher** | Liens externes (RetroAchievements) |
| **wakelock_plus** | Écran allumé en permanence |
| **shared_preferences** | Sauvegarde préférences |

---

## 👨‍💻 Author

**foclabroc** — Batocera contributor  
🔗 [GitHub](https://github.com/foclabroc)

---

## 📄 License

MIT License — free to use, modify and distribute.

---

*Made with ❤️ for the Batocera community*
