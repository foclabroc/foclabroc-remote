# Changelog — Foclabroc Remote 🎮

Historique complet des versions depuis la création du projet.

---

## v3.18.0+48 — Octobre 2026

> Script Supabase **v13 à jour** requis (participation quotidienne) — relancer le script complet si ce n'est pas déjà fait.

### 🎨 Rétro Jump : style des pages
- 2 styles pour l'interface du jeu : **Futuriste** (étoiles, anneaux HUD, sol quadrillé qui défile, accent cyan) et **Disco** (boule à facettes, faisceaux colorés, piste de danse lumineuse, accent rose)
- Fond animé sur l'accueil et dans tous les panneaux (Boutique, Classements, Stats, Réglages), cartes et fenêtres aux couleurs du style
- Nouvelle section **Style des pages** dans la Boutique, **3 000 pièces** chacun (Classique reste gratuit)

### ✨ Rétro Jump : héros dorés
- Version **en or avec étincelles** de chaque héros, **15 000 pièces** (Boutique, sous la grille des héros)
- Visible par tous : classements, chat, fiche joueur, fantôme du défi, podium
- Interrupteur pour activer / désactiver la version dorée ; le pouvoir du héros ne change pas

### 🎡 Rétro Jump : roue de la fortune
- Roue **redessinée** : couronne dorée, ampoules qui clignotent, icônes des lots, pointeur et moyeu en relief
- Après **Récupérer**, la roue **reste ouverte** : le lot s'affiche et on peut retenter sa chance (payant) directement
- Nouveau bouton **Fermer**

### 🕹️ Rétro Jump : jeu
- **Plateformes verticales** qui montent et descendent
- **Son** au déclenchement du turbo (nouveau son natif `boost` dans `MainActivity.kt`)
- Le bouton principal devient **Jouer Solo**

### 🏅 Rétro Jump : classements
- **Médaille de participation chaque jour** à tous les joueurs du défi hors podium (remise à minuit), comptée dans le **Défi semaine** et cumulée dans le **Défi général**
- **Onglets, pseudo, compte à rebours et « Ton rang » fixes** en haut, seule la liste défile
- **Fiche joueur** réorganisée : section *Défi du jour* (jour, semaine 🥇🥈🥉✅, général 🏆, défis gagnés / joués, meilleur défi) et section *Solo* (record et semaine)

### 🧑 Rétro Jump : avatars
- Beaucoup plus de modèles : peau (16), visage (8), coiffure (28), couleur des cheveux (24), yeux (18), bouche (18), accessoire (22), fond (24)
- Rendu **en relief** (ombres et reflets)

### 🛠️ Rétro Jump : corrections et confort
- Le réglage **son / muet** est désormais conservé au relancement
- La pointe de la fusée de l'écran de démarrage n'est plus coupée
- Fenêtre **Nouveautés** au lancement (avec « Ne plus afficher ») à la place de l'explication des classements

### 📦 Rétro Jump autonome (v1.0.7 → v1.0.8)
- Mêmes nouveautés, plus les **notifications Android de classement** (un joueur te dépasse au Solo ou au Défi du jour) propres à l'appli autonome

---

## v3.17.0+47 — Octobre 2026

> ⚠️ Script Supabase **v13** à relancer.

### 🏆 Rétro Jump : classements
- **4 onglets** :
  - **Défi du jour** : chaque jour, **médailles** d'or, d'argent et de bronze aux 3 premiers (remises à minuit)
  - **Défi semaine** : classement aux médailles de la semaine ; chaque lundi à minuit, **coupes** d'or, d'argent et de bronze aux 3 premiers et **médaille de participation** aux autres joueurs
  - **Défi général** : toutes les récompenses depuis le début (coupes, puis médailles du jour, puis participation)
  - **Solo** : meilleur score des parties normales — la partie du jour n'y compte plus
- Coupes affichées à côté du pseudo, palmarès complet sur la fiche joueur
- **Compte à rebours** de fin du défi du jour et de la semaine dans le classement
- Accueil : **Record Solo** (synchronisé avec le serveur)
- Au lancement, **explication des nouveaux classements** (case « Ne plus afficher »)
- Partie du jour : le record affiché en jeu est ton meilleur score **du jour**

### 🎡 Rétro Jump : roue de la fortune
- Lots revus : **20 à 500 pièces**, **jackpot 1 000 pièces**, bouclier, turbo, départ 1000, rejouer offert et **objet surprise 🎁** (un héros, thème, musique ou traînée encore verrouillé, ou 1 000 pièces si tout est débloqué)
- Tour supplémentaire : **75 pièces**

### 🗄️ Serveur (Supabase) — v13
- Médailles du jour, coupes de la semaine, participation et classement général

### 📦 Rétro Jump autonome (v1.0.4)
- Mêmes nouveautés

---

## v3.16.0+46 — Octobre 2026

> ⚠️ Script Supabase **v12** à relancer.

### 🧑 Rétro Jump : avatars façon Mii
- **Créer son avatar** (Réglages → Avatar) : 8 catégories — peau (12), visage (6), coiffure (20), couleur des cheveux (16), yeux (12), bouche (12), accessoire (14), fond (16) — avec miniatures et bouton 🎲 Aléatoire
- Affiché dans le **classement**, le **chat**, la **fiche joueur** et le **podium** de l'écran de démarrage
- Le **héros utilisé pour le record** reste visible à côté du score

### 🎨 Rétro Jump : nouveaux contenus
- **4 thèmes réalistes** : Jungle, Plage, Ville la nuit, Canyon (950 à 1 100 pièces)
  - Jungle : singes qui se balancent de liane en liane, guirlandes et lianes pendantes
  - Ville la nuit : avion, montgolfières, hélicoptère avec projecteur, dirigeable à bandeau LED
- **4 héros avec pouvoir** (600 à 800 pièces) : Manette (bug écrasé = 6 pièces), Portable (logos comptés double), Fantôme (2ᵉ chance gratuite, hors partie du jour), Casque (+25 % d'XP)
- **4 musiques** : RPG Battle, 8-bit Console, Byte Blast, Game On (1 100 à 1 500 pièces)
- **16 nouveaux trophées** (68 au total) — l'avancement % tient compte des nouveaux objets

### 🌍 Rétro Jump : classement
- **Jusqu'à 500 joueurs** (« Voir plus ») et bouton **« Ma position »**
- **Heure de la dernière partie** de chaque joueur (classement et fiche)
- **Record battu** : au lancement, liste des joueurs qui t'ont dépassé depuis ta dernière visite

### ⚙️ Rétro Jump : réglages et confort
- **Intensité des vibrations** : Faible / Normal / Fort
- Nouveau record : le nom n'est plus demandé si un pseudo est déjà choisi
- Codes secrets utilisables **3 fois** chacun, résultat affiché dans une fenêtre

### 🗄️ Serveur (Supabase)
- v10 : heure de la dernière partie · v11 : « record battu » · v12 : avatars

---

## v3.15.0+45 — Octobre 2026

### 🛡️ Rétro Jump : jeu
- **Bouclier de 2 s en sortie de turbo** (bonus ou propulsion de départ) : bulle qui clignote, insensible aux bugs
- **Bouclier en réserve** — ramasser un bouclier alors qu'un autre est actif le met en réserve (1 au maximum) : bulle cyan en bas de l'écran, un appui l'active ; conservé en cas de Continue
- **Option Fantôme** (Réglages → Options) : afficher ou non le fantôme du n°1 dans la partie du jour
- **Sensibilité réglable** : **tactile** 70 à 130 % et **inclinaison** 50 à 200 % — incluses dans la sauvegarde

### 🎨 Rétro Jump : interface
- **Écran de démarrage** : ciel de nuit étoilé, titre « RÉTRO JUMP », « by foclabroc », héros qui rebondit sur une cartouche et **podium des 3 meilleurs scores**
- **Barre du bas** :
  - **Quêtes** (remplace Défis) : 3 onglets **Défis / Trophées / Collection**
  - **Messages** (remplace Collection) : le chat, avec pastille **NEW** ou **@** — le Classement revient à 3 onglets
- **Compte à rebours** sur la tuile Défis du jour jusqu'à minuit
- Titre de l'accueil remonté avec la signature **« by foclabroc »**

### 📦 Rétro Jump autonome (v1.0.2 / v1.0.3)
- Mêmes nouveautés, plus la **mise à jour intégrée** (APK téléchargé et installé depuis l'appli)

---

## v3.14.0+44 — Octobre 2026

### 🏆 Rétro Jump : progression
- **Niveau joueur (XP)** — chaque partie rapporte de l'XP : 1 XP pour 10 pts, +10 par partie, +25 par défi réussi, +30 pour la partie du jour
  - Niveaux 1 à 99 (courbe 50·L·(L−1)), **rang tous les 10 niveaux** : Débutant → Bronze → Argent → Or → Platine → Diamant → Maître → Légende
  - **Pièces offertes à chaque niveau** (20 × le niveau atteint)
  - Barre de niveau sur l'accueil (touche = page « Gagner de l'XP » + liste des rangs), encadré « +XP / Niveau X atteint ! » dans les résultats
  - Joueurs existants : XP de départ calculée d'après les stats à vie (points ÷ 10 + 10 par partie), sans pièces rétroactives
  - XP incluse dans la sauvegarde
- **52 trophées permanents** (bronze / argent / or) — parties, record, points cumulés, bugs, sauts, turbos, combo, pièces, sacs, logos, temps de jeu, niveau, albums, collection complète (héros, thèmes, musiques, traînées), séries de défis, **jours d'affilée**, parties du jour, **podium / 1ʳᵉ place du défi du jour**, premier message dans le chat, chutes
  - Récompense : **25 / 75 / 200 pièces** selon la médaille
  - Bouton **🏆 Trophées** dans l'en-tête de l'accueil (nombre débloqué), page avec progression de chaque trophée (débloqués en premier)
  - Trophées gagnés listés dans les résultats ; ceux gagnés hors partie (achat, chat) annoncés par une notification
  - Joueurs existants : trophées déjà mérités débloqués d'office, sans pièces
  - Nouvelles stats suivies : parties du jour, série de jours joués, podium / victoire du défi du jour, messages envoyés

### 🌍 Rétro Jump : en ligne
- **Chat** (4ᵉ onglet du Classement) — 200 derniers messages gardés, rafraîchi toutes les 8 s tant que l'onglet est ouvert, pastille « nouveau message » sur la tuile Classement
  - Filtre FR/EN côté serveur : gros mots (même déguisés : c0nn4rd, majuscules, lettres doublées), liens et numéros de téléphone masqués ; 120 caractères, 1 message / 10 s
  - **Appui long = signaler** : message masqué pour soi tout de suite, pour tous au 3ᵉ signalement ; bannissement d'un appareil depuis Supabase (requêtes de modération en fin de fichier SQL)
  - Liste des mots filtrés dans la table `jump_chat_words`, modifiable sans mettre l'appli à jour
- **Mentions @pseudo** — suggestions de pseudos en tapant `@`, mentions colorées (la sienne en doré), message qui te cite encadré, notification « 💬 X t'a mentionné dans le chat » au lancement
- **Fiche joueur** — touche un joueur (classement, page de la partie du jour, chat) : héros, niveau et rang, pièces, avancement, record et rangs (général, semaine, jour), défis joués / gagnés / meilleur défi, toutes les stats de jeu, collection et trophées, date d'inscription ; bouton « Mentionner » depuis le chat
- **Avancement %** de chaque joueur dans le classement (📦) : **40 % boutique + 30 % albums + 30 % trophées**
- **Pastille de niveau** devant chaque pseudo (classement, chat, fiche)

### 🎨 Rétro Jump : interface
- **Accueil fixe**, sans défilement : la scène du héros s'adapte à la place disponible
- Bouton **Jouer** fixé au-dessus de la barre du bas (plus jamais masqué)
- En-tête : **Pièces · Trophées · Stats · Son**, avec leur nom sous chaque bouton
- **Règles du jeu** complétées (météo, partie du jour, fantôme, classements, niveau, trophées, avancement, chat, sauvegarde)
- Correctif : une feuille ouverte depuis une autre (ex. Défis → Trophées) perdait son contexte à la fermeture de la première

### 🗄️ Serveur (Supabase) — `supabase_retro_jump.sql` (v9) à relancer
- v5 : colonne `progress` + fonction `set_jump_profile` (pièces + avancement)
- v6 : tables `jump_chat`, `jump_chat_reports`, `jump_chat_bans`, `jump_chat_words` + fonctions `send_jump_chat` / `report_jump_chat` / `jump_chat_filter`
- v7 : colonne `stats` + fonctions `set_jump_stats` / `jump_player_card` (fiche joueur), index sur `pid`
- v8 : colonne `level` (joueurs, scores, chat)
- v9 : clés `trophies` / `trophies_n` dans les stats publiques

### 📦 Rétro Jump autonome (v1.0.1)
- Mêmes nouveautés ; version affichée dans les Réglages + bouton « Vérifier les mises à jour » ; nouvelle icône (thème Nuit, titre « RÉTRO JUMP »)

---

## v3.13.0+43 — Octobre 2026

### 🌦️ Rétro Jump : gameplay
- **Météo dynamique** — un événement vers 1 100, 2 100, 3 100… pts, pendant 18 s, annoncé par une bannière et affiché sous le score :
  - 💨 **Vent** : pousse le héros à gauche ou à droite par rafales
  - 🌧️ **Pluie** : sol glissant (accélération et freinage réduits)
  - ⛈️ **Orage** : ciel sombre, éclairs avec flash, 3 pièces qui tombent du ciel à chaque éclair (partie normale)
  - 🌫️ **Brouillard** : visibilité réduite autour du héros
  - En partie du jour, même suite de météos pour tous (générateur à graine dédié, parcours inchangé)
- **Fantôme du n°1** (partie du jour) — le meilleur joueur du jour grimpe en même temps que toi (héros translucide + pseudo). Trajet enregistré tous les 0,1 s et envoyé seulement en cas de nouveau meilleur score du jour ; le serveur ne garde que le trajet du meilleur score

### 🎨 Rétro Jump : personnalisation
- **5 nouveaux thèmes** :
  - 🌙 **Nuit** : étoiles qui scintillent, lune, étoile filante, teinte bleutée
  - 🔄 **Négatif** : couleurs inversées
  - 💚 **Matrix** : vert phosphore + pluie de code
  - 🌄 **Réaliste** : décor entièrement redessiné — ciel qui change avec l'altitude (jour → coucher de soleil → espace étoilé), soleil et rayons, montagnes enneigées, nuages en parallaxe, prairie ; planches de bois, poutres d'acier, bois pourri, ressorts chromés, ombres portées, pièces en or
  - ❄️ **Tour gelée** : tour de château en pierres taillées, neige posée sur les pierres, meurtrières éclairées, corniches avec congères et stalactites, dalles enneigées, blocs de glace, neige qui tombe sur 3 plans
- **Thème « Rouge » retiré** — numérotation des thèmes migrée automatiquement (thèmes débloqués et sélection conservés), **350 pièces remboursées** aux joueurs qui l'avaient acheté
- **Traînées de saut** (nouvelle section de la Boutique) : Arc-en-ciel, Étincelles, Pixels, Flammes, Bulles (150 à 350 pièces)
- **4 nouvelles musiques** à débloquer : 8-bit Retro (600), Mountain (700), Video Game (800), Pixel Fight (1 000) — 7 morceaux au total, section Musique sur 2 lignes
- **Boutique** : nom des objets toujours affiché, même verrouillés (grisé, avec le prix en dessous)

### 🌍 Classement en ligne
- **Classement de la semaine** — 3 onglets **Défi journalier / Semaine / Général** ; remise à zéro chaque lundi (« fin dans X j ») ; alimenté côté serveur par chaque partie normale (anciennes versions comprises)
- **Pièces des joueurs** affichées sous chaque pseudo dans le classement
- **Sauvegarde = identité en ligne** — le fichier de sauvegarde emporte aussi l'identifiant en ligne : en le chargeant (autre téléphone, réinstallation, ou application Rétro Jump autonome), on retrouve son pseudo et ses scores
- Accueil : tuiles réduites à leur titre, **« Défis du jour »** et **« Classement »**

### 🗄️ Serveur (Supabase) — `supabase_retro_jump.sql` à relancer
- Mode `week` (contrainte + rang hebdomadaire), colonne `coins` + fonction `set_jump_coins`, table `jump_ghosts` + fonctions `submit_jump_ghost` / `jump_top_ghost`

### 📦 Fichiers
- Nouveaux assets : `assets/game/game_music_4.ogg` à `game_music_7.ogg`
- `MainActivity.kt` : liste des musiques étendue (index 3 à 6)
- Application **Rétro Jump autonome** (projet séparé `retro_jump`, APK bilingue FR/EN selon la langue du téléphone, même classement)

---

## v3.12.0+42 — Octobre 2026

### 🌍 Rétro Jump : classement en ligne
- **Classement en ligne** via Supabase (nouveau `lib/services/leaderboard_service.dart`, API REST sans dépendance supplémentaire) : onglets **Aujourd'hui** / **Tous temps**, top 50 avec médailles et héros, rang du joueur mis en évidence
- **Sans compte** : identifiant secret généré par téléphone, pseudo automatique (`Joueur-XXXX`) modifiable ; le nom saisi au record devient le pseudo
- **Pseudos uniques** (majuscules / espaces ignorés) : pseudo déjà pris refusé, suffixe automatique (`Mario2`) pour un nouveau joueur ; table `jump_players`
- **Sécurité côté serveur** (`supabase_retro_jump.sql`) : écriture uniquement via fonctions signées (SHA-256 salé), contrôle de cohérence score / durée de partie, identifiant du téléphone jamais exposé (colonnes publiques limitées), accès réservé au rôle `anon`
- **Hors ligne** : scores mis en file d'attente et renvoyés automatiquement ; rang affiché sur l'écran de résultats (et sur l'image partagée)
- **Lignes des autres joueurs dans le parcours** — top 20 (classement du jour en Partie du jour, tous temps en partie normale) : ligne épaisse lumineuse or / argent / bronze / bleu avec rang, pseudo et score ; bannière « TU DÉPASSES … ! » au passage

### 📅 Rétro Jump : Partie du jour
- **Même parcours pour tous** chaque jour (générateur à graine `SeededRandom` mulberry32, identique sur tous les téléphones), nouveau parcours à minuit, **rejouable à volonté** (seul le meilleur score compte)
- **Sans bonus de départ, sans continue, sans pièces** : ni pièces, ni sacs, ni pièces sur les bugs ; aimant et ×2 remplacés par super saut / ralenti
- **Page dédiée** : règles, meilleur score et rang du jour, choix **Héros / Décor / Musique** (menus limités aux éléments débloqués), bouton « Jouer la partie du jour », scores du jour
- Meilleur score et rang du jour mémorisés localement

### ✨ Rétro Jump : accueil
- **Tuiles « Partie du jour » et « Classement »** sous le record (même gabarit, rang mondial et du jour affichés), point rouge si la partie du jour n'a pas encore été jouée
- Bouton **✏️ Personnaliser** sur la scène du héros (ouvre la boutique)
- **La roue s'ouvre automatiquement** à l'ouverture du jeu si le tour gratuit du jour n'a pas été joué
- Accueil compacté (héros plus petit, bouton Jouer réduit) : tout tient sans défiler

### 📦 Fichiers
- Nouveau : `lib/services/leaderboard_service.dart`, `supabase_retro_jump.sql` (à exécuter dans Supabase → SQL Editor)

---

## v3.11.0+41 — Octobre 2026

### 🎮 Nouveau mini-jeu : Rétro Jump
Jeu de saut vertical façon « doodle jump » rétro, ajouté comme 3e carte de l'onglet **Mini jeux** (nouveau `jump_screen.dart`).

- **Gameplay** — déplacement tactile (gauche/droite de l'écran) ou **inclinaison du téléphone** (option, via `sensors_plus`, zone morte + lissage), passage d'un bord à l'autre. Cartouches normales, mobiles, fissurées (se cassent), ressorts, turbo invincible, bouclier, bugs à écraser
- **Décors** — mur de tour en briques qui change tous les 400 pts (Château, Donjon, Temple, Glace, Volcan, Cyber, Espace, en boucle) : parallaxe, corniches entre paliers, torches, lave, néons, planète… Ligne du record affichée dans le parcours
- **Objets à ramasser** — pièces, **sac de 15 pièces** (~tous les 250 pts), **logos de consoles** à collectionner, **bonus en partie** (~tous les 350 pts) : 🧲 aimant, ×2 pièces, ⏫ super saut (5 rebonds), ⏳ ralenti
- **Combo** — chaque cartouche plus haute que la précédente fait monter le combo : pièces ×2 dès 5 sauts, ×3 dès 10… jusqu'à ×5. Affichage en jeu + meilleur combo dans les résultats
- **Continuer** après une chute ou un bug pour 20 pièces (1 fois par partie), avec cartouche de secours et invulnérabilité
- **12 héros à débloquer** (Robot, Joystick, Borne, Jeton, Cartouche, Disquette, CD, Cassette, Télé, Souris, Chat, Fusée), animés, chacun avec un **petit pouvoir** (vitesse, continue moins cher, sacs plus riches, aimant permanent, bouclier au départ, saut plus haut, turbo plus long…)
- **8 thèmes visuels** — Classique, Néon, Pocket, Sépia, CRT (scanlines), Synthwave, Rouge, **Disco** (boule à facettes, faisceaux, reflets, cartouches qui changent de couleur)
- **3 musiques** (Disco Funk offerte, Shop, Good Morning) + muet ; musique dès l'ouverture du jeu, en pause hors de l'onglet et en arrière-plan
- **Bonus de départ achetables** (cumulables) : départ propulsé à 500 / 1 000 pts, bouclier, turbo
- **Roue de la fortune** — 1 tour gratuit par jour puis 25 pièces le tour ; gains : pièces, bonus de départ offerts, « rejouer » gratuit
- **Défis par séries** — 8 défis qui se renouvellent avec des objectifs et récompenses plus élevés, bonus de série
- **Collection par albums** — 16 logos par album (3 prises chacun, puis plus dans les albums suivants), 2 séries de logos en alternance, **cadeau de 500 pièces** par album complété
- **Statistiques à vie** — parties, points cumulés, moyenne, sauts, meilleur combo, pièces, sacs, bugs, turbos, logos, continues, chutes, temps de jeu
- **Codes secrets** (5 appuis sur le titre) — codes stockés uniquement sous forme d'empreinte SHA-256 salée, introuvables dans le source
- **Sauvegarde / chargement / reset** de la progression — fichier JSON signé (anti-modification), dossier et fichier choisis via le picker in-app, partage Android en secours
- **Accueil « console »** — héros animé sur une scène aux couleurs du thème, bonus et bouton Jouer, barre du bas (Boutique, Défis, Collection, Roue, Réglages) ouvrant des panneaux ; fiches de déblocage toujours consultables (bouton grisé si pas assez de pièces)
- Vibrations (option), écran de résultats compact, partage du score en image, saisie du nom au record

### 🔊 Sons et musique (mini-jeux)
- **Effets chiptune générés** côté Android (`MainActivity.kt`, objet `ChipSynth`) et joués via `SoundPool` (faible latence, plusieurs à la fois) : saut, ressort, pièce, bug écrasé, turbo, bouclier, coup encaissé, cartouche cassée, logo, palier, continue
- **Musique de fond** en boucle via `MediaPlayer` à partir de fichiers `.ogg` (`assets/game/game_music*.ogg`), pause automatique quand l'app passe en arrière-plan
- `QuizAudio` : nouvelles méthodes `sfx()`, `musicStart/Stop/Pause/Resume()`, réglage musique mémorisé ; couper le son coupe aussi la musique

### 🧱 Breakout
- Règles du jeu repliables, accueil compacté, écran de résultats compacté
- Musique de fond (Disco Funk) et bouton musique dans l'en-tête
- Bouton « Sauvegarder » du record qui passait sur deux lignes : corrigé

### ✨ Améliorations
- **Bannière « Connexion perdue »** placée sous le contenu (ne masque plus les boutons), masquée dans l'onglet Mini jeux et pendant la saisie au clavier, fermable avec une croix
- Musique des mini-jeux mise en pause quand on change d'onglet, reprise au retour
- **Script `check_fr_en.py`** — contrôle de symétrie FR/EN (fichiers présents des deux côtés, logique identique, textes français restés dans l'EN, cohérence des versions)

### 🐛 Correctifs
- **Strings FR résiduelles dans la version EN** — 13 textes traduits (connexion, capture, Foclabroc Tools, lancement de jeu, jeu inconnu, fichier vide…)
- Jeux : dessin qui débordait sous la barre d'état et sous la barre de navigation Android (`ClipRect` + marge système garantie) ; titre et score masqués par le bouton menu
- `game_detail_screen` EN aligné sur la structure FR (le contrôle FR/EN est désormais à 100 %)

### 📦 Dépendances / fichiers
- `sensors_plus` (inclinaison du téléphone)
- Nouveaux assets : `assets/game/game_music.ogg`, `game_music_2.ogg`, `game_music_3.ogg`

---

## v3.10.0+40 — Septembre 2026

### ✨ Nouvelles fonctionnalités
- **Transferts parallèles** — envoi ET téléchargement (dossiers comme fichiers simples) en **6 transferts simultanés**, chaque worker réutilisant son propre canal SFTP pour tous ses fichiers. Gain net sur les dossiers contenant beaucoup de petits fichiers. Si Batocera refuse un canal (limite `MaxSessions`), le transfert continue avec moins de workers
  - Dialog de progression simplifié : compteur « Terminés x/y », nom du fichier en cours et **barre globale unique** (progression en octets pour l'envoi)
  - Annulation : attente de l'arrêt de tous les workers avant le rollback, suppression groupée des fichiers partiels et déjà transférés
  - Tous les `mkdir -p` distants créés en amont, par lots de 50 en une seule commande
- **Envoi de fichiers simples = même moteur que l'envoi de dossier** — nouvelle méthode commune `_runUpload()` : même dialog, parallélisme, bouton Annuler avec rollback et raison du 1er échec. Remplace l'ancienne barre inline dans l'en-tête. En mode fichiers simples, aucun dossier n'est créé ni supprimé à l'annulation
- **Terminal SSH : menus Commandes / Historique**
  - Menu déroulant **Commandes** (gauche) : Espace disque, Température, Adresse IP, Infos système (`batocera-info`), Version Batocera, `/boot` en écriture (`mount -o remount,rw /boot`), Sauvegarder overlay (`batocera-save-overlay`)
  - **Confirmation** avant les commandes sensibles (remount `/boot`, save-overlay) avec avertissement + commande affichée ; icône orange dans le menu. Champ `warn` dans `_quickCmds`
  - Menu déroulant **Historique** (droite) : 20 dernières commandes, sans doublon, un choix remet la commande dans le champ. Entrée « Effacer l'historique »
  - **Historique persistant** via `SharedPreferences` (clé `ssh_terminal_history`, 50 commandes max) — conservé après fermeture de l'appli
- **Liste des jeux : icônes manuel/map uniquement si le fichier existe** — un script Python unique côté Batocera lit le(s) `gamelist.xml`, résout les chemins `<manual>`/`<map>` (`./`, `~/`) et ne garde que les fichiers présents (taille > 0). Gère les **collections** (mario, pokemon…) en lisant le gamelist du vrai système de chaque jeu (déduit de `/userdata/roms/<système>/`). Règle stricte : pas de fichier vérifié → pas d'icône
- **Onglet « Mini jeux »** — Quiz Rétro et Breakout regroupés dans un nouvel onglet placé en dernier dans le menu (nouveau `mini_games_screen.dart`). Deux cartes ouvrant chaque jeu dans le Navigator de l'onglet : le bouton retour Android (ou re-sélectionner « Mini jeux » dans le menu) ramène à la liste. Le menu passe de 13 à 12 entrées (Liens utiles en index 10, Mini jeux en 11)
- **Erreur explicite en fin d'envoi** — la notification indique la raison du 1er échec (ex. « lecture refusée par Android (activer « Accès à tous les fichiers ») »)

### 📱 Android
- **Permission `MANAGE_EXTERNAL_STORAGE`** (« Accès à tous les fichiers ») ajoutée au manifest et demandée une fois par lancement par le picker in-app. Sans elle, Android 11+ ne laisse lire que les médias : ROMs, sauvegardes, `.romfs`… échouaient en `Permission denied` à l'envoi

### 🐛 Correctifs
- **Éditeur de texte : fichiers corrompus à l'enregistrement** — le contenu passait par un heredoc shell dans `bash -l -c '…'` : les `$VAR` étaient remplacées, les `$(…)` **exécutés**, les `\\` réduits, et les chemins avec espaces cassés. Écriture désormais directe via SFTP (`writeFileBytes()`), octets à l'identique, droits du fichier préservés
- **Éditeur de texte : fichier vidé** — une lecture en échec (fichier non-UTF8…) ouvrait un éditeur vide qui effaçait le fichier à l'enregistrement. Lecture tolérante (`allowMalformed`) et éditeur non ouvert si la lecture échoue
- **Saturation mémoire sur les gros envois** — le fichier entier finissait en RAM (disque plus rapide que le réseau), risque de plantage sur les ISO, multiplié par le parallélisme. Contre-pression ajoutée : la lecture attend que le writer SFTP reprenne
- **Annulation d'envoi : suppression possible d'un dossier existant** — si la vérification d'existence du dossier distant échouait, il était considéré comme nouveau et supprimé (`rm -rf`) à l'annulation. Il est maintenant considéré existant sauf réponse explicite contraire
- **Boutons Manuel/Map/Vidéo grisés à tort (fiche jeu)** — la vérification de v3.8 passait des chemins entre apostrophes dans l'enveloppe `bash -l -c '…'` et échouait dès qu'un nom contenait un espace ou des parenthèses. Exécution directe via le client SSH
- **Gestionnaire de fichiers : noms avec apostrophe** (`Link's Awakening`…) — lister, renommer, déplacer, copier, supprimer et télécharger échouaient silencieusement. Nouvelle fonction `_shq()` d'échappement adaptée à l'enveloppe `bash -l -c`
- **Bouton retour du gestionnaire de fichiers enregistré sur le mauvais onglet** — `TabBackHandler.register(5, …)` pointait sur le Terminal SSH (index 5) au lieu de Fichiers (index 6), reste du décalage des index lors de l'ajout du Pad virtuel. Dans le Terminal, le retour remontait le dossier du gestionnaire en arrière-plan ; dans Fichiers, le retour ne désélectionnait pas. Corrigé en index 6
- **Nombre d'onglets codé en dur** (`List.generate(13, …)` pour les Navigators et la pile d'onglets `Offstage`) — remplacé par `_tabs.length`
- **Terminal : commandes contenant une apostrophe** (`awk '{…}'`, `echo 'texte'`) cassées par l'enveloppe `bash -c '…'` — échappement ajouté
- **Canal SFTP jamais fermé** — `uploadFileFromPath()` et `downloadFileToDisk()` laissaient un canal ouvert par fichier transféré. Fermeture systématique, fichiers local/distant fermés même en cas d'annulation ou d'erreur
- **Exception non gérée dans les logs** à l'envoi d'un fichier illisible (`openRead()`) — lecture via `RandomAccessFile`, erreur propre et plus de fichier vide créé côté Batocera
- **Téléchargement : taille lue via le canal SFTP du worker** au lieu d'une commande `stat` par fichier (évite de dépasser la limite de canaux SSH)
- **`app_state` : `catchError` sans valeur de retour** au passage en arrière-plan (avertissement `flutter analyze`)
- **Strings FR résiduelles dans le picker EN** — ~15 textes traduits (« Choisir ce dossier », « Stockage interne », messages de permission…). Titre « Choisir un dossier » en mode sélection de dossier (FR et EN)

---

## v3.9.0+39 — Septembre 2026

### ✨ Nouvelles fonctionnalités
- **Envoi de dossier complet** vers Batocera depuis le gestionnaire de fichiers — même logique que le téléchargement de dossier (v3.8), pour le sens inverse : listing récursif local (`FileSystemEntity.typeSync`, pas `entity is File` — évite le même piège symlink que pour le picker), confirmation avec récap (nb fichiers + taille totale estimée), double barre de progression (fichier + globale), `mkdir -p` créé à la volée côté distant, bouton **Annuler** avec **rollback complet côté Batocera** (suppression SSH des fichiers déjà envoyés + fichier partiel + dossiers distants créés)
- **Mode sélection de dossier dans le picker in-app** — nouveau paramètre `pickFolderMode` sur `InAppFilePicker` : navigation classique jusqu'au dossier voulu, fichiers visibles pour se repérer mais non sélectionnables, bouton "Choisir ce dossier" dans l'AppBar dès qu'on est entré dans un dossier. Nouvelle classe `InAppFolderPickerResult`

### 🧹 Nettoyage
- `_DownloadCancelledException` renommée en `_TransferCancelledException` (désormais partagée entre téléchargement et envoi de dossier)

---

## v3.8.0+38 — Septembre 2026

### 🐛 Correctifs
- **Boutons Manuel/Map/Vidéo allumés à tort** — l'API ES expose toujours une route pour ces médias même si le fichier n'existe pas côté Batocera, donc le bouton s'allumait puis échouait au clic ("Impossible de charger le fichier"). Branchement de `_checkMediaAvailability()` (déjà écrite côté FR mais jamais appelée) sur `hasManual`/`hasMap`/`hasVideo` ; portage complet de la méthode côté EN où elle était totalement absente

### ✨ Nouvelles fonctionnalités
- **Téléchargement de dossier complet** dans le gestionnaire de fichiers — sélection multiple fichiers + dossiers, listing récursif via `find -exec stat -c "%s %n"` (compatible BusyBox, `find -printf` non supporté), confirmation avec récap (nb fichiers + taille totale estimée), double barre de progression (fichier en cours + globale, largeur de dialog fixe pour éviter tout clignotement), bouton **Annuler** avec confirmation et **rollback complet** (fichier partiel + fichiers déjà téléchargés + dossiers vides créés supprimés, avec filet de sécurité sur les dossiers top-level fraîchement créés)
  - Sortie de la commande SSH encadrée par deux marqueurs uniques pour l'isoler de toute pollution (bannière système Batocera mélangée au stdout sur certaines configs)
  - Sélection automatiquement vidée en fin de transfert

---

## v3.7.0+37 — Septembre 2026

### ✨ Améliorations
- **Recherche en ligne des médias** — bouton loupe 🔍 par cadre dans Éditer médias. Ouvre Google Images dans le navigateur système avec une requête ciblée (nom du jeu + type : `logo` / `box art` / `screenshot`). L'utilisateur télécharge puis importe via le bouton upload

### 🐛 Correctifs
- **Édition médias/métadonnées depuis une collection** — les jeux ouverts depuis une collection (2 joueurs, favoris, collections thématiques…) affichaient "No image" et ne trouvaient pas leurs balises, faute de `gamelist.xml` propre à la collection. Nouvelle méthode `_resolveSystemName()` qui résout le vrai système : extraction depuis le `path` `/userdata/roms/<system>/...`, fallback sur `systemName` (API ES), puis `_systemName` (app). Utilisée dans `_editMedia()` et `_editMetadata()`

---

## v3.6.0+36 — Septembre 2026

### ✨ Améliorations
- **Boutons médias/RA toujours affichés** — Manuel, Map, Vidéo et RetroAchievements restent visibles dans la fiche jeu même quand la ressource est absente. Ils apparaissent grisés et affichent un message ("… non disponible") au tap au lieu de disparaître
- **Temps de jeu dans la fiche détail** — nouveau chip ⏱️ affichant le temps de jeu (`gametime`) formaté de façon lisible (`< 1 min`, `X min`, `Xh Ymin`). Masqué si le temps est nul

---

## v3.5.0+35 — Mai 2026

### ✨ Améliorations
- **Ajouts pad/clavier virtuel** — clavier et manette virtuel connectable dans onglet "pad virtuel"

---

## v3.3.0+34 — Mai 2026

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
