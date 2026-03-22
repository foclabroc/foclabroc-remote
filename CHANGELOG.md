# Changelog

Toutes les modifications notables de ce projet sont documentées ici.

Format basé sur [Keep a Changelog](https://keepachangelog.com/fr/1.0.0/),
versioning selon [Semantic Versioning](https://semver.org/lang/fr/).

---

## [1.2.0] - 2026-03-22

### Ajouté
- **Historique des connexions nommées** — possibilité de nommer chaque IP sauvegardée pour une identification facile
- **Écran détail du jeu** (`GameDetailScreen`) — vue complète avec wheel/marquee, jaquette, screenshot zoomables, métadonnées (genre, développeur, éditeur, année), lancement du jeu, visionneuse PDF/image pour manuels et cartes, lecteur vidéo intégré, lien RetroAchievements
- **Widget StatusBar** — barre de statut persistante indiquant l'état de connexion sur tous les onglets
- **Widget BackHandler** — gestion améliorée du bouton retour Android

### Amélioré
- **Bibliothèque de jeux** — grille de systèmes avec logos, recherche globale avec cache MD5, indicateurs par jeu (favori ⭐, achievements 🏆, manuel 📖, carte 🗺️)
- **Gestionnaire de fichiers** — fonctionnalités étendues, UI/UX améliorée
- **Écran système** — refonte majeure avec nouvelles commandes
- **Écran de capture** — refonte UI
- **Service SSH** — fiabilité améliorée, nouvelles fonctionnalités
- **Icônes de lancement** — optimisation pour toutes les densités Android (hdpi, mdpi, xhdpi, xxhdpi, xxxhdpi)

---

## [1.1.0] - 2026-03-19

### Ajouté
- **Écran jeu en cours** (`RunningGameScreen`) — affichage temps réel avec minuteur de session (refresh toutes les 5s), artwork, infos système/émulateur/core, bouton stop (hotkeygen), visionneuse PDF manuel, lien RetroAchievements
- **Support plateforme Windows** — configuration CMake et plugin registration

### Amélioré
- Documentation README enrichie

---

## [1.0.0] - 2026-03-18

### Ajouté
- Connexion SSH/SFTP à Batocera Linux via WiFi
- Auto-connexion et reconnexion silencieuse
- Historique des 5 derniers hôtes
- Navigation par onglets (7 écrans)
- Bibliothèque de jeux avec navigation par système
- Écran de capture (screenshots, enregistrement vidéo, mode auto 30s)
- Terminal SSH interactif avec historique de commandes
- Gestionnaire de fichiers `/userdata/` (browse, upload, éditeur texte, visionneuses)
- Contrôles système : volume, modes énergie, redémarrage, arrêt, logs
- Thème sombre Material 3 avec accent rouge Batocera (#E02020)
