# Foclabroc Remote 🎮

**Télécommande Android pour Batocera Linux**
- POUR BATOCERA V43+. Certaines fonctionnalités comme la capture vidéo peuvent ne pas fonctionner avec les versions précédentes

[![Voir la démo](https://img.youtube.com/vi/OkYvSxjOg3c/maxresdefault.jpg)](https://youtu.be/4veWFNOn-VU)

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
- **Vérification instantanée** de la connexion au retour au premier plan
- Indicateur "Reconnexion..." visible sur tous les onglets
- Historique des 3 dernières adresses IP (effaçable)
- Informations système détaillées (modèle, CPU, RAM, résolution, OS...)
- **Détection automatique des scraps en attente** à la connexion avec proposition de finalisation

### 🕹️ Pad virtuel
- Émule un **vrai contrôleur Xbox** via `uinput` Python côté Batocera (vendor/product Xbox 360, reconnu nativement par ES et les émulateurs)
- Périphérique nommé `Foclabroc-VPad` — persistant tant que la session SSH est active
- **D-pad** (haut/bas/gauche/droite via `EV_ABS HAT0X/HAT0Y`)
- **8 boutons** : A, B, X, Y, L1, R1, Start, Select
- **Hotkey** (BTN_MODE) pour les combos d'émulateurs
- **Clavier AZERTY virtuel** (`FoclabrocVkb`) sur la même page :
  - 3 rangées de touches (AZERTY), Espace, Entrée, Backspace, Tab, Échap
  - Modificateurs toggle : Shift, Ctrl, Alt
  - Touches spéciales : flèches, F1, Pipe (`AltGr + <`)
- Les deux périphériques (pad + clavier) démarrent/stoppent indépendamment
- Script Python embarqué en clair (pas de fichier externe requis), déployé au démarrage de l'onglet via SFTP puis exécuté via SSH

### 🎮 Jeu en cours
- Affichage du jeu en cours : wheel/marquee (fallback automatique), jaquette, screenshot
- Chronomètre de session en temps réel
- Infos : système, émulateur, core, développeur, genre
- Stats CPU/RAM en temps réel (température, usage, mémoire)
- Lien RetroAchievements
- Bouton stop (hotkeygen)
- Visionneuse PDF pour les manuels
- Auto-refresh toutes les 5 secondes
- **🆕 Scrap auto en jeu** :
  - **Vidéo auto 30s** — capture 30 secondes de gameplay et l'enregistre dans le dossier `media/videos` du système
  - **Screenshot auto** — capture un screenshot et l'enregistre comme `image` dans le dossier média du système
  - Détection auto de la convention de nommage du système (`media/videos` vs `videos`)
  - Si une vidéo/image existe déjà → propose de la remplacer en gardant le même chemin
  - **Flush playtime** avant chaque écriture gamelist (reload ES → écriture → reload ES)
  - Sauvegarde différée des balises XML (cf. système Pending ci-dessous)

### 🆕 Système Pending Scrap (intelligent)
EmulationStation réécrit le `gamelist.xml` à la sortie de chaque jeu (pour mettre à jour playtime/lastplayed). Le système Pending contourne ce comportement :
- Le média (vidéo/screenshot) est sauvegardé immédiatement sur Batocera
- Les balises XML à insérer dans le gamelist sont stockées dans `/userdata/system/configs/foclabroc-remote/pending/`
- À la sortie du jeu (auto-détectée), les balises sont automatiquement injectées dans le gamelist + double `reloadgames` pour forcer ES à les charger en mémoire sans les écraser
- **Persistance au reboot** : les pending survivent aux redémarrages de l'app et de Batocera
- **Dialog au démarrage** : si des scraps sont en attente, l'app propose de les finaliser à la connexion avec liste détaillée (nom du jeu, système, type de média)
- Détection des relaunches via flag `isLaunchingGame` pour éviter d'interrompre un nouveau lancement

### 📚 Bibliothèque de jeux
- Grille de tous tes systèmes avec logos
- **Nombre de jeux** affiché sur chaque carte système (badge bleu clair)
- **Total de jeux** affiché en haut de la grille
- **Recherche globale** dans tous les jeux de tous les systèmes (avec cache)
- Liste des jeux par système avec indicateurs : ⭐ favori, 🏆 achievements, 📖 manuel, 🗺️ map
- **Snackbar "Fermeture du jeu en cours…"** quand un jeu tourne déjà avant de lancer un autre
- **Fiche détaillée** par jeu :
  - Wheel / marquee, jaquette et screenshot côte à côte (cliquables pour agrandir)
  - Infos : genre, développeur, éditeur, année, description
  - Bouton **Lancer** (quitte le jeu en cours automatiquement avec notification)
  - **🆕 Éditer métadonnées** — 12 champs éditables (genre, langue, région, note, date, favori...)
  - **🆕 Éditer médias** — upload/suppression Logo, Jaquette, Image avec preview + undo
  - Bouton **🔄 Refresh** (invalide le cache local + reload)
  - Visionneuse **Manuel** (PDF ou image)
  - Visionneuse **Map** (PDF ou image, zoomable)
  - Lecteur **Vidéo** intégré
  - Lien **RetroAchievements**

### 📸 Capture
- Screenshot instantané
- Capture vidéo avec chronomètre
- Mode **Auto 30 secondes** avec UI optimiste (le compteur disparaît dès la fin pour ne pas bloquer l'UI pendant le post-traitement)
- Réglages qualité et audio
- Stop fiable de la capture (kill ffmpeg + nettoyage des fichiers temporaires)

### 💻 Terminal SSH
- Terminal intégré avec historique des commandes
- Texte sélectionnable et copiable
- Streaming line-by-line de la sortie

### 📁 Gestionnaire de fichiers
- Navigation dans `/userdata/` avec fil d'Ariane
- **Bouton retour Android** pour remonter dans l'arborescence
- Visionneuse intégrée : images (zoomable), PDF, vidéos
- **🆕 Lecteur audio in-app** pour `.mp3`, `.wav`, `.ogg`, `.flac`, `.m4a`, `.opus`, `.aac` (plein écran avec seek, ±10s, play/pause)
- Éditeur de texte intégré pour `.cfg`, `.conf`, `.ini`, `.sh`, `.log`, `.xml`, `.json`, `.yaml`, `.yml`, `.md`, `.txt`
- **🆕 Picker de fichiers in-app** (sans intent système, évite la duplication MIUI) avec :
  - 12 raccourcis (Stockage interne, Pictures, DCIM, Downloads, Documents, Movies, Music, Podcasts, Ringtones, Notifications, Alarms, Android/media)
  - **Détection automatique des cartes SD**
  - Permissions Android runtime (photos/vidéos/audio API 33+, storage < 33)
  - Miniatures images dans la grille
  - Multi-sélection via long-press
- Upload depuis le téléphone avec barre de progression
- **Retry automatique** sur upload échoué (reconnexion silencieuse)
- Sélection multiple : copier, couper, coller, renommer, supprimer

### ⚙️ Système
- Contrôle du volume en temps réel
- **Gestion émulateur** : quitter proprement (hotkeygen) ou forcer l'arrêt
- Mode d'alimentation (Performance / Équilibré / Économie)
- Redémarrage EmulationStation, reboot, arrêt
- Logs `stderr` et `stdout` partageables
- **Vider le cache** images et vidéos de l'application
- **🆕 Vérification automatique des mises à jour** au démarrage (lien vers la page release GitHub)

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
- **YouTube TV** — installe YouTube TV dans le menu Ports (Batocera x86_64 uniquement)
- **Foclabroc Toolbox → Ports** — installe la Toolbox dans le menu Ports pour y accéder depuis Batocera (x86_64)
- **RGSX** — télécharge et installe RetroGameSets game downloader dans 'Ports'

### 🕹️ Quiz Rétro
- Un screenshot s'affiche → trouve le jeu parmi 4 propositions
- 10 questions, 20 secondes par question
- Score = 10 pts + bonus temps
- Séries de bonnes réponses = bonus 🔥
- Meilleur score sauvegardé

### 🧱 Casse-briques Rétro
- Logos de consoles rétro comme briques (35 systèmes)
- Briques adaptées dynamiquement à la largeur de l'écran
- Niveaux infinis — densité et vitesse augmentent
- Briques résistantes (2 coups) à partir du niveau 2
- **5 power-ups** à collecter :
  - 🟢 **Batocera** → agrandit la raquette (+30px)
  - 🔴 **Recalbox** → réduit la raquette ET **−500 pts** si attrapé !
  - 🐢 **Balle lente** → ralentit la balle 5 secondes
  - ⚪ **Multiball** → 2 balles supplémentaires (max 4 balles)
  - 🔫 **Light Gun** → tire des balles depuis la raquette pendant 3 secondes
- Score pop animé (+pts) au-dessus de chaque brique détruite
- Particules d'explosion colorées à la destruction
- Pulse de la raquette à chaque power-up collecté
- Barre de progression sous la raquette (balle lente / pistolet)
- Système de combo 🔥 avec bonus croissants
- Bouton **Pause** dédié
- Écran de fin avec 6 stats détaillées (score, niveau, vies, briques, power-ups, combo max)
- **Partage du score** : capture d'écran des résultats partageable
- Meilleur score avec nom du joueur et niveau atteint
- Mode portrait forcé

---

## 📋 Prérequis

- Android 8.0+
- Batocera Linux V43+ sur le même réseau WiFi
- SSH activé sur Batocera (activé par défaut)
- Python 3.9+ sur Batocera (présent par défaut, requis pour les manipulations XML du gamelist)

**Identifiants SSH par défaut Batocera :**
```
IP     : adresse locale de ta machine (ex: 192.168.1.xxx)
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
| **flutter_svg** | Logos de systèmes en SVG |
| **crypto** | Cache images (MD5) |
| **path_provider** | Système de fichiers local |
| **permission_handler** | Permissions Android runtime |
| **open_filex** | Ouverture fichiers natifs |
| **share_plus** | Partage de logs et scores |
| **url_launcher** | Liens externes (RetroAchievements) |
| **wakelock_plus** | Écran allumé en permanence |
| **shared_preferences** | Sauvegarde préférences |

---

## 🏗️ Architecture

```
lib/
├── main.dart                    # Splash + bootstrap
├── models/
│   └── app_state.dart           # ChangeNotifier global (SSH, connexion, launching)
├── services/
│   ├── ssh_service.dart         # Wrapper dartssh2 (execute, SFTP, tunnels)
│   ├── metadata_service.dart    # 🆕 Lecture/écriture gamelist.xml (Python via base64)
│   ├── media_service.dart       # 🆕 Détection dossiers médias + paths
│   ├── pending_scrap_service.dart  # Sauvegarde/finalisation des scraps différés
│   └── update_check_service.dart   # 🆕 Vérification nouvelle version GitHub
├── widgets/
│   ├── back_handler.dart        # Interception bouton retour Android
│   ├── status_bar.dart          # Barre d'état en bas
│   ├── status_badge.dart        # Badge indicateur
│   ├── in_app_file_picker.dart  # 🆕 Picker fichiers in-app (permissions runtime + SD)
│   ├── media_editor_dialog.dart # 🆕 Édition médias (3 cadres : logo/jaquette/image)
│   ├── metadata_editor_dialog.dart # 🆕 Édition métadonnées (12 champs)
│   ├── pending_scraps_dialog.dart  # Dialog de proposition de finalisation
│   └── update_dialog.dart       # 🆕 Dialog mise à jour
└── screens/
    ├── connect_screen.dart       # Saisie IP + historique + connexion auto
    ├── virtual_pad_screen.dart   # Pad Xbox uinput + clavier AZERTY virtuels via SSH
    ├── running_game_screen.dart  # Jeu en cours + scrap auto + finalize pending
    ├── games_screen.dart         # Bibliothèque (grille systèmes + liste jeux)
    ├── game_detail_screen.dart   # Fiche jeu détaillée + visionneuses
    ├── capture_screen.dart       # Capture manuelle screenshot/vidéo
    ├── ssh_terminal_screen.dart  # Terminal SSH interactif avec historique
    ├── file_manager_screen.dart  # Navigation /userdata + éditeur intégré
    ├── system_screen.dart        # Volume, alimentation, reboot, logs
    ├── wine_tools_screen.dart    # Conversion/compression .wine + runners
    ├── foclabroc_tools_screen.dart # Packs (NES3D, Kodi, Music, fangames…)
    ├── quiz_screen.dart          # Quiz rétro 10 questions
    ├── breakout_screen.dart      # Casse-briques avec power-ups
    ├── links_screen.dart         # Liens utiles (forum, wiki, releases…)
    └── home_screen.dart          # Drawer 12 onglets + listener pending scraps
```

**Endpoints API EmulationStation utilisés** (`http://127.0.0.1:1234/`) :
- `runningGame` — infos du jeu en cours
- `launch` — lance un jeu (POST avec path en body)
- `emukill` — quitte le jeu en cours (équivalent hotkeygen)
- `reloadgames` — relit les gamelist.xml depuis le disque
- `systems` — liste des systèmes

---

## 👨‍💻 Auteur

**foclabroc** — Contributeur Batocera
🔗 [GitHub](https://github.com/foclabroc)

---

## 📄 Licence

MIT License — libre d'utilisation, de modification et de distribution.

---

*Fait avec le ❤️ pour la communauté Batocera*
