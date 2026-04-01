# Foclabroc Remote 🎮

**Télécommande Android pour Batocera Linux**
- POUR BATOCERA V43+. Certaines fonctionnalités comme la capture vidéo peuvent ne pas fonctionner avec les versions précédentes

[![Voir la démo](https://img.youtube.com/vi/OkYvSxjOg3c/maxresdefault.jpg)](https://youtu.be/OkYvSxjOg3c)

> *Cliquez sur l'image pour voir la vidéo de présentation*

---

## 📥 Télécharger

[![Download APK](https://img.shields.io/badge/Download-APK-red?style=for-the-badge&logo=android)](https://github.com/foclabroc/foclabroc-remote/releases)

Version Française disponible  
English version available

---

## ✨ Fonctionnalités

### 🔗 Connexion SSH
- Connexion WiFi via SSH à ta machine Batocera (possibilité de nommer les IP)
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
- **Nombre de jeux** affiché sur chaque carte système (badge bleu clair)
- **Total de jeux** affiché en haut de la grille
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

### 🍷 Wine Tools
- **.PC Converter** — convertit un dossier `.pc` en `.wine` avec compression optionnelle
- **Decompressor** — décompresse `.wtgz` / `.wsquashfs` → `.wine`
- **Compressor** — compresse `.wine` → `.wtgz` ou `.wsquashfs`
- **Téléchargement Runner** — télécharge et installe des runners Wine depuis GitHub :
  - Wine GE-Custom, Wine Vanilla, Wine TKG-Staging, GE-Proton, GE-Custom V40
  - **Runner Manager** — liste et supprime les runners installés
- **Wine Bottle Manager** — liste et supprime les bouteilles Wine
- **Winetricks** — installe des dépendances Windows (VC++, DirectX...) dans une bouteille

### 🔧 Foclabroc Tools
- **NES3D** — installe le pack NES 3D (détection automatique de la version Batocera V40/41/42/43+)
- **Pack Kodi** — installe la configuration Kodi de Foclabroc (Vstream, IPTV...) avec remplacement complet du dossier `.kodi`
- **Pack Music** — ajoute 39 musiques OST dans `/userdata/music` pour la lecture aléatoire dans EmulationStation
- **Jeux Windows** — installe 21 fangames & remakes gratuits directement depuis GitHub :
  - Celeste 64, Celeste pico8, Crash Bandicoot bit, Donkey Kong Advanced, TMNT Rescue Palooza
  - Spelunky, Sonic Triple Trouble, Pokemon Uranium, MiniDoom 2, AM2R, Megaman X II
  - Super Tux Kart, Streets of Rage R 5.2, Megaman 2.5D, Sonic Smackdown, Maldita Castilla
  - Super Smash Crusade, Rayman Redemption, Power Bomberman, Mushroom Kingdom Fusion, Dr. Robotnik's Racers
  - Téléchargement avec progression, mise à jour automatique du gamelist (images, vidéo, métadonnées)
- **YouTube TV** — installe YouTube TV dans le menu Ports (Batocera x86_64 uniquement)
- **Foclabroc Toolbox → Ports** — installe la Toolbox dans le menu Ports pour y accéder depuis Batocera (x86_64)
- **RGSX** — télécharge et installe le pack RetroGameSets dans `/userdata/roms` (requiert python3)

---

## 📋 Prérequis

- Android 8.0+
- Batocera Linux sur le même réseau WiFi
- SSH activé sur Batocera (activé par défaut)

**Identifiants SSH par défaut Batocera :**
```
IP     : adresse locale de ta machine (ex: 192.168.1.134)
Port   : 22
User   : root
Pass   : linux
```

---

## 🚀 Installation

1. Télécharge l'APK via le bouton ci-dessus
2. Sur ton téléphone Android : **Paramètres → Sécurité → Sources inconnues** → Autoriser
3. Installe l'APK
4. Lance l'app — connexion automatique si déjà utilisée

---

## 🛠️ Compiler depuis les sources

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

## 📦 Stack technique

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

## 👨‍💻 Auteur

**foclabroc** — Contributeur Batocera  
🔗 [GitHub](https://github.com/foclabroc)

---

## 📄 Licence

MIT License — libre d'utilisation, de modification et de distribution.

---

*Fait avec le ❤️ pour la communauté Batocera*
