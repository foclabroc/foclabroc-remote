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

class _MetadataEditorDialogState extends State<MetadataEditorDialog> {
  late final TextEditingController _name;
  late final TextEditingController _desc;
  late final TextEditingController _genre;
  late final TextEditingController _developer;
  late final TextEditingController _publisher;
  late final TextEditingController _players;
  late final TextEditingController _lang;
  late final TextEditingController _region;

  double _rating = 0.0;
  DateTime? _releaseDate;
  bool _favorite = false;

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
    _developer.dispose(); _publisher.dispose();
    _players.dispose(); _lang.dispose(); _region.dispose();
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
    check('lang', _lang.text);
    check('region', _region.text);

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

  Widget _field(String label, TextEditingController ctrl,
      {TextInputType? keyboardType, bool multiline = false}) {
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
              _field('Genre', _genre),
              _field('Développeur', _developer),
              _field('Éditeur', _publisher),
              _field('Joueurs', _players, keyboardType: TextInputType.number),
              _field('Langue(s)', _lang),
              _field('Région', _region),
              const SizedBox(height: 8),
              const Text('Note', style: TextStyle(color: Colors.white70, fontSize: 12)),
              Row(children: [
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
            const SizedBox(height: 6),
            const Text('Date de sortie', style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 4),
            Row(children: [
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
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.star_rounded, color: Colors.amberAccent, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Favori',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
              Switch(
                value: _favorite,
                activeColor: const Color(0xFFE02020),
                onChanged: (v) => setState(() => _favorite = v),
              ),
            ]),
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
