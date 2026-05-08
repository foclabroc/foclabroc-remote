# Changelog — Foclabroc Remote 🎮

Historique complet des versions depuis la création du projet.

---

## v3.3.1+34 — Mai 2026

### 🐛 Correctifs
- **Picker in-app : fichiers invisibles** — ajout des permissions Android runtime (`permission_handler ^11.3.0`). Demande `photos`/`videos`/`audio` sur API 33+ ou `storage` sur < 33. Écran dédié si permission refusée/permanente avec bouton "Ouvrir paramètres"
- **Picker in-app : permission toujours refusée** — fix du bug où `Permission.storage` retournait `permanentlyDenied` sur Android 13+ même si les permissions media étaient accordées (logique séparée API 33+ vs < 33)
- **Logo absent sur certains jeux (ex: Doom 3)** — ajout du parsing `marquee` depuis l'API ES + fallback automatique `wheel` → `marquee` dans `_reloadImages()`
- **Scrap screenshot : balise `<screenshot>` orpheline** — le scrap auto n'écrit plus que la balise `<image>` (fichier nommé `-image.png`). La confirmation ne se déclenche que si `<image>` existe, un `<screenshot>` orphelin n'est plus bloquant
- **Edit media/métadonnées : tags partiellement écrits** — `tagsJson` passé en base64 dans le script Python au lieu d'un argument shell (élimine les problèmes de quoting avec apostrophes, parenthèses, caractères spéciaux dans les noms de jeu)
- **Edit media/métadonnées : playtime écrasé** — séquence `reloadEs` (flush playtime mémoire → disque) → 1s pause → `writeMetadata` → `reloadEs` dans `_editMedia()` ET `_editMetadata()`
- **Téléchargement mise à jour en double/triple** — le bouton ouvre maintenant la page release GitHub au lieu du téléchargement direct APK
- **Lecteur audio dans Fichiers** — ajout de `_isAudio()` dans `_isOpenable()` + option "Lire l'audio" / "Play audio" dans le menu fichier
- **Fichiers .log : "Binary file — preview not available"** — skip du check `file | grep text` pour les extensions texte connues (BusyBox mal-identifie certains .log)
- **Picker in-app / vue texte / éditeur : contenu caché derrière navbar Android** — padding bottom dynamique via `MediaQuery.of(context).padding.bottom`
- **Strings FR résiduelles dans version EN** — correction de 6+ strings ("Erreur", "Remplacer", "Logo indisponible", "Image indisponible", "Erreur PDF", etc.)

### ✨ Améliorations
- **Picker in-app étendu** — 12 raccourcis (Stockage interne, Pictures, DCIM, Downloads, Documents, Movies, Music, Podcasts, Ringtones, Notifications, Alarms, Android/media) + détection dynamique des cartes SD + filtrage par existence
- **Suppression du dialog Source (Basique/Externe)** — ouverture directe du picker in-app dans Edit media et Fichiers
- **Tous les fichiers texte éditables** — `.log` ajouté à `_editableExts`
- **Menu fichier simplifié** — suppression de "Open on phone" / "Ouvrir sur le téléphone" (redondant avec Download), ajout "View content" pour tous les fichiers texte
- **AndroidManifest** — ajout `READ_MEDIA_AUDIO`

### 🗑️ Retraits
- Import et usage de `file_picker` supprimés (remplacé par le picker in-app)

---

## v3.3.0+33 — Mai 2026

### ✨ Nouvelles fonctionnalités
- **Édition des médias** — bouton "Éditer médias" dans game_detail_screen. Dialog avec 3 cadres (Logo / Jaquette / Image), preview existante, upload 📤, suppression 🗑️ avec confirmation, undo ↶. Logique majorité système pour wheel/marquee. Convention Batocera native pour les systèmes vierges
- **Lecteur audio in-app dans Fichiers** — détection auto .mp3/.wav/.ogg/.flac/.m4a/.opus/.aac, lecteur plein écran avec pochette, slider seek, ±10s, play/pause. Réutilise `VideoPlayerController`
- **Retry SSH automatique sur upload** — méthode `ensureConnected()` dans app_state.dart, 2 tentatives par fichier avec reconnexion silencieuse
- **Dialog "Source du fichier"** — choix entre picker Basique (in-app) et Externe (FilePicker système) pour contourner la duplication MIUI
- **Bouton refresh dans game_detail** — 🔄 dans l'AppBar, invalide le cache local MD5 + reload images
- **Service MediaService** — `findExistingMedia`, `detectMediaDir`, `detectLogoTag`, `ensureRemoteDir`, `deleteRemoteFile`

### 📦 Dépendances
- Ajout `permission_handler: ^11.3.0` (préparé mais pas encore utilisé)

---

## v3.2.0 — Avril/Mai 2026

### ✨ Nouvelles fonctionnalités
- **Édition des métadonnées** — bouton "Éditer métadonnées" dans game_detail_screen, 12 champs éditables (genre, langue multi-select, région radio, note, date, favori, développeur, éditeur, joueurs, description, nom)
- **Picker Genre** — 20 genres rétro alphabétiques + saisie manuelle, sortie séparée par virgules
- **Picker Langue** — CheckboxListTile multi-select avec mutex sur codes partagés (USA/UK = en, PT/BR = pt)
- **Picker Région** — RadioListTile single-select, 14 régions ScreenScraper
- **Service MetadataService** — lecture/écriture gamelist.xml via script Python embarqué

### 🐛 Correctifs
- `<favorite>false</favorite>` → suppression de la balise (Batocera/ES traite l'absence comme non-favori)
- Groupage pending + métadonnées : reload ES (flush) + delay 1s + applyPendingNoReload + writeMetadata + reload final

---

## v3.1.0+31 — Avril 2026

### ✨ Nouvelles fonctionnalités
- **Vérification automatique des mises à jour** — nouveau service `update_check_service.dart`, vérifie via API GitHub `releases/tags/release` au démarrage. Dialog modal si nouvelle version, silencieux si à jour
- **Pattern APK** : `foclabroc.remote.V<X.Y>.<FR|EN>.apk`

### 🧹 Nettoyage
- Code mort supprimé dans running_game_screen.dart : `_updateGamelistVideo`, `_reloadEsGamelist`, `_updateGamelistImages` (−99 lignes/variante)
- 32 strings UI traduites FR→EN dans running_game_screen.dart
- "Mo" → "MB" dans la version EN

---

## v2.9.0 — Avril 2026

### ✨ Nouvelles fonctionnalités
- **Scrap auto en jeu** :
  - **Vidéo auto 30s** — capture 30 secondes de gameplay, sauvegarde dans `media/videos` du système
  - **Screenshot auto** — capture et sauvegarde dans `media/screenshots`
  - Détection auto de la convention de nommage (`media/videos` vs `videos`)
  - Si vidéo/image existe déjà → proposition de remplacement
- **Système Pending Scrap** — sauvegarde différée des balises XML :
  - Médias sauvegardés immédiatement, balises stockées dans `/userdata/system/configs/foclabroc-remote/pending/`
  - Auto-finalisation à la sortie du jeu (double `reloadgames`)
  - Persistance au reboot
  - Dialog au démarrage si pending en attente
- **Stats CPU/RAM en temps réel** dans Jeu en cours (température, usage, mémoire)
- **Infos développeur et genre** dans Jeu en cours

---

## v2.7.0+27 — Mars/Avril 2026

### ✨ Nouvelles fonctionnalités
- **Wine Tools** (onglet complet) :
  - .PC Converter (.pc → .wine avec compression optionnelle)
  - Decompressor (.wtgz/.wsquashfs → .wine)
  - Compressor (.wine → .wtgz/.wsquashfs)
  - Téléchargement Runner (Wine GE-Custom, Vanilla, TKG-Staging, GE-Proton, GE-Custom V40)
  - Runner Manager (liste + suppression)
  - Wine Bottle Manager (liste + suppression)
  - Winetricks (VC++, DirectX...)
- **Foclabroc Tools** (onglet complet) :
  - NES3D (auto-détection V40/41/42/43+)
  - Pack Kodi (Vstream, IPTV)
  - Pack Music (39 OST)
  - 21 Jeux Windows (fangames & remakes gratuits depuis GitHub)
  - YouTube TV (x86_64)
  - Foclabroc Toolbox → Ports (x86_64)
  - RGSX
  - Eden Nightly
- **Quiz Rétro** — 10 questions, 20s/question, score avec bonus temps et séries 🔥
- **Casse-briques Rétro** — logos consoles comme briques, 5 power-ups, niveaux infinis, partage du score
- **Liens utiles** (onglet)
- **Ajout `flutter_svg ^2.0.0`** — logos systèmes en SVG (conversion rsvg-convert si >15KB)
- **12 onglets** via drawer latéral (était 7 avant)

### 🐛 Correctifs
- Ajout `video_player`, `crypto`, `wakelock_plus` au pubspec (manquants)
- Optimisation SSH : algorithmes rapides (x25519, aes128ctr), cache SFTP, TCP NoDelay

---

## v1.8.0 — Mars 2026

### 🏗️ Version initiale publiée
- **Connexion SSH** — WiFi via dartssh2, auto-connect, reconnexion silencieuse, historique 3 IP
- **Jeu en cours** — wheel, jaquette, screenshot, chronomètre, bouton stop, lien RetroAchievements, visionneuse PDF manuels
- **Bibliothèque** — grille systèmes avec logos, nombre de jeux, recherche globale, fiche détaillée (lancer, manuel, map, vidéo, RA)
- **Capture** — screenshot instantané, capture vidéo avec chronomètre, réglages qualité/audio
- **Terminal SSH** — historique commandes, texte sélectionnable
- **Gestionnaire de fichiers** — navigation /userdata/, visionneuse images/PDF/vidéos, éditeur texte, upload avec barre de progression, sélection multiple
- **Système** — volume, gestion émulateur, alimentation, reboot/arrêt, logs partageables, vider le cache
- **7 onglets** : Connexion, Jeu, Biblio, Capture, SSH, Fichiers, Système
