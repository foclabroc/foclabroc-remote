# Foclabroc Remote 🎮

**Télécommande Android pour Batocera Linux**

[![Voir la démo](https://img.youtube.com/vi/iw04C1K-Yio/0.jpg)](https://youtube.com/shorts/iw04C1K-Yio?feature=share)

> *Cliquez sur l'image pour voir la vidéo de présentation*

---

## 📥 Télécharger

[![Download APK](https://img.shields.io/badge/Download-APK-red?style=for-the-badge&logo=android)](https://github.com/foclabroc/foclabroc-remote/releases/download/release/foclabroc.remote.apk)

---

## ✨ Fonctionnalités

### 🔗 Connexion SSH
- Connexion WiFi via SSH à ta machine Batocera
- Historique des 3 dernières adresses IP
- Reconnexion automatique à la réouverture de l'app
- Informations système (hostname, IP, uptime, version)

### 📸 Capture
- Screenshot instantané (`batocera-screenshot`)
- Capture vidéo avec chronomètre en temps réel
- Mode **Auto 30 secondes** — start et stop automatique
- Confirmation avec nom du fichier créé

### 💻 Terminal SSH
- Terminal intégré avec police monospace
- Historique des commandes (flèches ▲▼)
- Texte sélectionnable et copiable
- Prompt `~ #` interactif

### 📁 Gestionnaire de fichiers
- Navigation dans `/userdata/` avec fil d'Ariane
- Aperçu et ouverture des images, vidéos, fichiers texte
- **Éditeur de texte intégré** pour `.cfg`, `.conf`, `.ini`, `.sh`...
- Sauvegarde directe sur Batocera via SFTP
- Upload de fichiers depuis le téléphone
- Sélection multiple (appui long) : copier, couper, coller, renommer, supprimer

### ⚙️ Système
- Contrôle du volume en temps réel
- Actualiser la liste des jeux (redémarre EmulationStation)
- Reboot et arrêt complet
- Visualisation des logs `es_launch_stderr` et `es_launch_stdout`

---

## 📋 Prérequis

- Android 8.0+
- Batocera Linux sur le même réseau WiFi
- SSH activé sur Batocera (activé par défaut)

**Identifiants SSH par défaut Batocera :**
```
IP     : adresse locale de ta machine (ex: 192.168.1.50)
Port   : 22
User   : root
Pass   : linux
```

---

## 🚀 Installation

1. Télécharge l'APK via le bouton ci-dessus
2. Sur ton téléphone Android : **Paramètres → Sécurité → Sources inconnues** → Autoriser
3. Installe l'APK
4. Lance l'app et entre l'IP de ta machine Batocera

---

## 🛠️ Compiler depuis les sources

```bash
# Prérequis : Flutter SDK >= 3.0
git clone https://github.com/foclabroc/foclabroc-remote.git
cd foclabroc-remote
flutter pub get
flutter run
```

```bash
# Compiler un APK release
flutter build apk --release
```

---

## 📦 Stack technique

- **Flutter** — Framework UI multiplateforme
- **dartssh2** — Connexion SSH / SFTP native Dart
- **Provider** — Gestion d'état
- **open_filex** — Ouverture de fichiers natifs Android
- **file_picker** — Sélection de fichiers depuis le téléphone
- **path_provider** — Accès au système de fichiers local
- **shared_preferences** — Sauvegarde des préférences

---

## 👨‍💻 Auteur

**foclabroc** — Contributeur Batocera  
🔗 [GitHub](https://github.com/foclabroc)

---

## 📄 Licence

MIT License — libre d'utilisation, de modification et de distribution.

---

*Fait avec ❤️ pour la communauté Batocera*
