import 'package:flutter/material.dart';

/// Dialog d'édition des métadonnées (version simple AlertDialog).
class MetadataEditorDialog extends StatefulWidget {
  final Map<String, String> initialValues;
  final String gameName;

  const MetadataEditorDialog({
    super.key,
    required this.initialValues,
    required this.gameName,
  });

  @override
  State<MetadataEditorDialog> createState() => _MetadataEditorDialogState();
}

/// Pays sélectionnable dans les puces (libellé visible + emoji + code stocké).
class _Country {
  final String label;
  final String emoji;
  final String code;
  const _Country(this.label, this.emoji, this.code);
}

/// Langues : USA et UK partagent le code "en", PT et BR partagent "pt".
/// Cocher l'un coche automatiquement l'autre (logique basée sur le code).
const _langCountries = <_Country>[
  _Country('France', '🇫🇷', 'fr'),
  _Country('USA', '🇺🇸', 'en'),
  _Country('UK', '🇬🇧', 'en'),
  _Country('Germany', '🇩🇪', 'de'),
  _Country('Spain', '🇪🇸', 'es'),
  _Country('Italy', '🇮🇹', 'it'),
  _Country('Portugal', '🇵🇹', 'pt'),
  _Country('Brazil', '🇧🇷', 'pt'),
  _Country('Japan', '🇯🇵', 'ja'),
  _Country('China', '🇨🇳', 'zh'),
  _Country('Korea', '🇰🇷', 'ko'),
  _Country('Russia', '🇷🇺', 'ru'),
];

/// Régions : sélection unique, codes uniques (pas de doublon).
/// Codes alignés sur ScreenScraper (utilisé par Batocera) : `uk` et non `gb`,
/// `sp` et non `es`, `wor` et `eu` pour les régions génériques.
const _regionCountries = <_Country>[
  _Country('World', '🌍', 'wor'),
  _Country('Europe', '🇪🇺', 'eu'),
  _Country('France', '🇫🇷', 'fr'),
  _Country('USA', '🇺🇸', 'us'),
  _Country('UK', '🇬🇧', 'uk'),
  _Country('Germany', '🇩🇪', 'de'),
  _Country('Spain', '🇪🇸', 'sp'),
  _Country('Italy', '🇮🇹', 'it'),
  _Country('Portugal', '🇵🇹', 'pt'),
  _Country('Brazil', '🇧🇷', 'br'),
  _Country('Japan', '🇯🇵', 'jp'),
  _Country('Russia', '🇷🇺', 'ru'),
  _Country('China', '🇨🇳', 'cn'),
  _Country('Korea', '🇰🇷', 'kr'),
];

/// Liste des genres standards proposés dans le picker du champ "Genre".
/// Sélection orientée rétrogaming (20 genres). L'utilisateur peut toujours
/// taper du texte libre en plus ; les libellés non standards sont conservés.
const _genreOptions = <String>[
  'Action',
  'Arcade',
  'Aventure',
  'Beat them all',
  'Combat',
  'Course',
  'Flipper',
  'Hack & Slash',
  'Horreur',
  'Plateforme',
  'Point and click',
  'Puzzle',
  'RPG',
  'Run and Gun',
  'Rythme',
  "Shoot'em up",
  'Simulation',
  'Sport',
  'Stratégie',
  'Tir',
];

class _MetadataEditorDialogState extends State<MetadataEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _genre;
  late final TextEditingController _developer;
  late final TextEditingController _publisher;
  late final TextEditingController _players;

  // Langue : champ texte (CSV de codes ex. "en, fr, de"). La saisie manuelle
  // est libre ; un picker à puces permet de cocher les langues standards.
  late final TextEditingController _lang;
  // Région : champ texte (un code unique ex. "us"). Saisie manuelle libre,
  // picker single-select via puces.
  late final TextEditingController _region;

  double _rating = 0.0;
  DateTime? _releaseDate;
  bool _favorite = false;

  /// Parse un CSV de codes en Set normalisé (lowercase, trim, sans vide).
  static Set<String> _parseCsvCodes(String? raw) {
    if (raw == null || raw.isEmpty) return <String>{};
    return raw
        .toLowerCase()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  /// Reconstruit un CSV trié à partir d'un Set de codes (canonique pour diff).
  static String _joinSortedCodes(Set<String> codes) {
    final list = codes.toList()..sort();
    return list.join(',');
  }

  @override
  void initState() {
    super.initState();
    final iv = widget.initialValues;
    _name = TextEditingController(text: iv['name'] ?? '');
    _desc = TextEditingController(text: iv['desc'] ?? '');
    _genre = TextEditingController(text: iv['genre'] ?? '');
    _developer = TextEditingController(text: iv['developer'] ?? '');
    _publisher = TextEditingController(text: iv['publisher'] ?? '');
    _players = TextEditingController(text: iv['players'] ?? '');

    // Lang & region : on garde la saisie brute (le picker normalisera au save).
    _lang = TextEditingController(text: iv['lang'] ?? '');
    _region = TextEditingController(text: iv['region'] ?? '');

    final r = double.tryParse(iv['rating'] ?? '');
    if (r != null) _rating = r.clamp(0.0, 1.0);
    final rd = iv['releasedate'] ?? '';
    if (rd.length >= 8) {
      try {
        _releaseDate = DateTime(
          int.parse(rd.substring(0, 4)),
          int.parse(rd.substring(4, 6)),
          int.parse(rd.substring(6, 8)),
        );
      } catch (_) {}
    }
    _favorite = (iv['favorite'] ?? '').toLowerCase() == 'true';
  }

  @override
  void dispose() {
    _name.dispose(); _desc.dispose(); _genre.dispose();
    _developer.dispose(); _publisher.dispose(); _players.dispose();
    _lang.dispose(); _region.dispose();
    super.dispose();
  }

  Map<String, String> _diff() {
    final iv = widget.initialValues;
    final out = <String, String>{};

    void check(String tag, String newVal) {
      final old = iv[tag] ?? '';
      if (newVal.trim() != old.trim()) {
        out[tag] = newVal.trim();
      }
    }

    check('name', _name.text);
    check('desc', _desc.text);
    check('genre', _genre.text);
    check('developer', _developer.text);
    check('publisher', _publisher.text);
    check('players', _players.text);

    // Lang : compare les Sets normalisés (ordre indifférent, doublons retirés).
    final initLang = _joinSortedCodes(_parseCsvCodes(iv['lang']));
    final newLang = _joinSortedCodes(_parseCsvCodes(_lang.text));
    if (newLang != initLang) out['lang'] = newLang;

    // Region : compare le premier code de chaque côté (le picker normalise
    // à un seul code, mais l'utilisateur peut taper plusieurs valeurs).
    String firstCode(String? raw) {
      final s = _parseCsvCodes(raw);
      return s.isEmpty ? '' : s.first;
    }
    final initRegion = firstCode(iv['region']);
    final newRegion = firstCode(_region.text);
    if (newRegion != initRegion) out['region'] = newRegion;

    final newRating = _rating > 0 ? _rating.toStringAsFixed(2) : '';
    if (newRating != (iv['rating'] ?? '')) out['rating'] = newRating;

    final newDate = _releaseDate != null
        ? '${_releaseDate!.year.toString().padLeft(4, '0')}'
            '${_releaseDate!.month.toString().padLeft(2, '0')}'
            '${_releaseDate!.day.toString().padLeft(2, '0')}T000000'
        : '';
    if (newDate != (iv['releasedate'] ?? '')) out['releasedate'] = newDate;

    final newFavorite = _favorite ? 'true' : 'false';
    final oldFavorite = (iv['favorite'] ?? 'false').toLowerCase();
    if (newFavorite != oldFavorite) out['favorite'] = newFavorite;

    return out;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _releaseDate ?? DateTime(2000),
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
    );
    if (picked != null && mounted) setState(() => _releaseDate = picked);
  }

  /// Ouvre un dialog de sélection multi-genres.
  /// Pré-coche les genres présents dans le champ qui matchent la liste standard.
  /// Conserve à la fin les libellés non standards (saisie libre) en les
  /// remettant après les genres standards cochés, séparés par " / ".
  Future<void> _openGenrePicker() async {
    // Parse le contenu actuel par / ou , (insensible à la casse côté match).
    final parts = _genre.text
        .split(RegExp(r'[/,]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    // Pour les comparaisons case-insensitive avec la liste standard.
    final standardLower = _genreOptions.map((e) => e.toLowerCase()).toSet();

    // Set des genres standards pré-cochés (libellé canonique de _genreOptions).
    final selected = <String>{};
    // Liste des libellés non standards à conserver tels quels.
    final extras = <String>[];
    for (final p in parts) {
      final pl = p.toLowerCase();
      if (standardLower.contains(pl)) {
        // Récupère le libellé canonique (avec sa casse d'origine)
        final canonical = _genreOptions.firstWhere(
          (o) => o.toLowerCase() == pl,
        );
        selected.add(canonical);
      } else {
        extras.add(p);
      }
    }

    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C2230),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              title: Row(children: const [
                Icon(Icons.checklist_rounded,
                    color: Color(0xFFE02020), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Choisir des genres',
                      style: TextStyle(fontSize: 14, color: Colors.white)),
                ),
              ]),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (extras.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          child: Text(
                            'Genres personnalisés conservés : ${extras.join(", ")}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                        ),
                      for (final option in _genreOptions)
                        CheckboxListTile(
                          value: selected.contains(option),
                          onChanged: (v) {
                            setStateDialog(() {
                              if (v == true) {
                                selected.add(option);
                              } else {
                                selected.remove(option);
                              }
                            });
                          },
                          title: Text(option,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: const Color(0xFFE02020),
                          checkColor: Colors.white,
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(false),
                  child: const Text('Annuler'),
                ),
                ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(true),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('OK'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE02020)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true || !mounted) return;
    // Reconstruit : standards cochés + extras, triés alphabétiquement,
    // joints par ", " (séparateur préféré).
    final out = <String>[
      ...selected,
      ...extras,
    ];
    out.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    setState(() {
      _genre.text = out.join(', ');
    });
  }

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType? keyboardType, bool multiline = false, Widget? suffixIcon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: ctrl,
        maxLines: multiline ? null : 1,
        minLines: multiline ? 1 : 1,
        keyboardType: multiline
            ? TextInputType.multiline
            : (keyboardType ?? TextInputType.text),
        textInputAction: multiline ? TextInputAction.newline : TextInputAction.next,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          suffixIcon: suffixIcon,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE02020)),
          ),
        ),
      ),
    );
  }

  /// Ouvre un dialog multi-sélection des langues.
  /// Cocher USA décoche UK car ils partagent le code "en" (mutex sur code).
  /// Les codes inconnus du champ sont conservés en bas du dialog.
  Future<void> _openLangPicker() async {
    // Parse le contenu actuel : codes connus → labels pré-cochés ; sinon → extras.
    final initCodes = _parseCsvCodes(_lang.text);
    final selectedLabels = <String>{};
    final extras = <String>{};
    for (final code in initCodes) {
      final matching = _langCountries.where((c) => c.code == code).toList();
      if (matching.isNotEmpty) {
        selectedLabels.add(matching.first.label);
      } else {
        extras.add(code);
      }
    }

    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C2230),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              title: Row(children: const [
                Icon(Icons.checklist_rounded,
                    color: Color(0xFFE02020), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Choisir des langues',
                      style: TextStyle(fontSize: 14, color: Colors.white)),
                ),
              ]),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (extras.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          child: Text(
                            'Codes personnalisés conservés : ${extras.join(", ")}',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                        ),
                      for (final country in _langCountries)
                        CheckboxListTile(
                          value: selectedLabels.contains(country.label),
                          onChanged: (v) {
                            setStateDialog(() {
                              if (v == true) {
                                // Mutex : décoche les autres pays au même code
                                selectedLabels.removeWhere((label) {
                                  final other = _langCountries.firstWhere(
                                      (c2) => c2.label == label);
                                  return other.code == country.code;
                                });
                                selectedLabels.add(country.label);
                              } else {
                                selectedLabels.remove(country.label);
                              }
                            });
                          },
                          title: Text('${country.emoji}  ${country.label}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          subtitle: Text(country.code,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: const Color(0xFFE02020),
                          checkColor: Colors.white,
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(false),
                  child: const Text('Annuler'),
                ),
                ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(true),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('OK'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE02020)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true || !mounted) return;
    // Reconstruit : codes des labels cochés + extras, triés alphabétiquement.
    final out = <String>{
      ...selectedLabels.map(
          (l) => _langCountries.firstWhere((c) => c.label == l).code),
      ...extras,
    };
    final list = out.toList()..sort();
    setState(() {
      _lang.text = list.join(', ');
    });
  }

  /// Ouvre un dialog single-select de la région.
  /// Codes inconnus du champ : préservés au save tant que rien n'est sélectionné.
  Future<void> _openRegionPicker() async {
    final initCodes = _parseCsvCodes(_region.text);
    final initFirst = initCodes.isEmpty ? '' : initCodes.first;
    final knownCodes = _regionCountries.map((c) => c.code).toSet();
    String selectedCode = knownCodes.contains(initFirst) ? initFirst : '';
    final extraCode = (initFirst.isNotEmpty && !knownCodes.contains(initFirst))
        ? initFirst
        : '';

    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1C2230),
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
              titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
              actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              title: Row(children: const [
                Icon(Icons.public_rounded,
                    color: Color(0xFFE02020), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Choisir une région',
                      style: TextStyle(fontSize: 14, color: Colors.white)),
                ),
              ]),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (extraCode.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                          child: Text(
                            'Code personnalisé conservé : $extraCode'
                            ' (sera remplacé si vous sélectionnez ci-dessous)',
                            style: const TextStyle(
                                color: Colors.white38, fontSize: 11),
                          ),
                        ),
                      RadioListTile<String>(
                        value: '',
                        groupValue: selectedCode,
                        onChanged: (v) =>
                            setStateDialog(() => selectedCode = v ?? ''),
                        title: const Text('Aucune',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 13)),
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: const Color(0xFFE02020),
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 4),
                      ),
                      for (final country in _regionCountries)
                        RadioListTile<String>(
                          value: country.code,
                          groupValue: selectedCode,
                          onChanged: (v) =>
                              setStateDialog(() => selectedCode = v ?? ''),
                          title: Text('${country.emoji}  ${country.label}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13)),
                          subtitle: Text(country.code,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 11)),
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: const Color(0xFFE02020),
                          dense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(false),
                  child: const Text('Annuler'),
                ),
                ElevatedButton.icon(
                  onPressed: () =>
                      Navigator.of(ctx, rootNavigator: true).pop(true),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('OK'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE02020)),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != true || !mounted) return;
    setState(() {
      _region.text = selectedCode;
    });
  }

  /// Cadre identique aux TextField (label flottant + bordure arrondie),
  /// pour entourer du contenu custom (puces, étoiles, switch, date picker…).
  Widget _framedSection({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          isDense: true,
          contentPadding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFE02020)),
          ),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1C2230),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      actionsPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      title: Row(children: [
        const Icon(Icons.edit_note_rounded, color: Color(0xFFE02020), size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Métadonnées : ${widget.gameName}',
            style: const TextStyle(fontSize: 14, color: Colors.white),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ]),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field('Nom', _name),
              _field('Description', _desc, multiline: true),
              _field('Genre', _genre,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_drop_down_rounded,
                      color: Colors.white54),
                  tooltip: 'Genres standards',
                  onPressed: _openGenrePicker,
                  visualDensity: VisualDensity.compact,
                  splashRadius: 20,
                ),
              ),
              _field('Développeur', _developer),
              _field('Éditeur', _publisher),
              _field('Joueurs', _players, keyboardType: TextInputType.number),
              _field('Langue(s)', _lang,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_drop_down_rounded,
                      color: Colors.white54),
                  tooltip: 'Choisir des langues',
                  onPressed: _openLangPicker,
                  visualDensity: VisualDensity.compact,
                  splashRadius: 20,
                ),
              ),
              _field('Région', _region,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_drop_down_rounded,
                      color: Colors.white54),
                  tooltip: 'Choisir une région',
                  onPressed: _openRegionPicker,
                  visualDensity: VisualDensity.compact,
                  splashRadius: 20,
                ),
              ),
              _framedSection(
                label: 'Note',
                child: Row(children: [
                  for (int i = 1; i <= 5; i++)
                    IconButton(
                      iconSize: 22,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => setState(() {
                        final v = i * 0.2;
                        _rating = (_rating - v).abs() < 0.01 ? (i - 1) * 0.2 : v;
                      }),
                      icon: Icon(
                        _rating >= i * 0.2 - 0.01
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: _rating >= i * 0.2 - 0.01
                            ? Colors.amberAccent
                            : Colors.white24,
                      ),
                    ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(_rating > 0 ? _rating.toStringAsFixed(2) : '—',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ),
              _framedSection(
                label: 'Date de sortie',
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today_rounded, size: 14),
                      label: Text(
                        _releaseDate != null
                            ? '${_releaseDate!.day.toString().padLeft(2, '0')}/${_releaseDate!.month.toString().padLeft(2, '0')}/${_releaseDate!.year}'
                            : 'Choisir une date…',
                        style: const TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                      ),
                    ),
                  ),
                  if (_releaseDate != null)
                    IconButton(
                      iconSize: 16,
                      icon: const Icon(Icons.close_rounded, color: Colors.white38),
                      onPressed: () => setState(() => _releaseDate = null),
                    ),
                ]),
              ),
              _framedSection(
                label: 'Favori',
                child: Row(children: [
                  Icon(
                    _favorite ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: _favorite ? Colors.amberAccent : Colors.white38,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _favorite ? 'Oui' : 'Non',
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  ),
                  Switch(
                    value: _favorite,
                    activeColor: const Color(0xFFE02020),
                    onChanged: (v) => setState(() => _favorite = v),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(null),
          child: const Text('Annuler'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            final d = _diff();
            Navigator.of(context, rootNavigator: true).pop(d);
          },
          icon: const Icon(Icons.save_rounded, size: 16),
          label: const Text('Sauvegarder'),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE02020)),
        ),
      ],
    );
  }
}
