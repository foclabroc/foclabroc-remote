#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_fr_en.py — Contrôle de symétrie FR / EN pour Foclabroc Remote.

À lancer depuis la racine du projet (là où se trouvent lib/ et batocera_remote_en/) :

    python check_fr_en.py

Vérifie, sans rien modifier :
  1. Fichiers .dart présents d'un seul côté (lib/ vs batocera_remote_en/lib/)
  2. Différences de LOGIQUE entre chaque fichier FR et son jumeau EN
     (textes entre guillemets et commentaires ignorés)
  3. Textes restés en français dans la version EN
  4. Cohérence des versions (pubspec.yaml FR/EN + kAppVersion)

Code de sortie : 0 = tout est OK, 1 = au moins un problème détecté.
"""

import difflib
import os
import re
import sys

FR_ROOT = '.'
EN_ROOT = 'batocera_remote_en'
MAX_DIFF_LINES = 12  # lignes de différence affichées par fichier

# Fichiers dont la logique diffère VOLONTAIREMENT entre FR et EN
# (affichés comme « ignorés » au lieu d'être comptés comme problèmes).
IGNORE_LOGIC = {
    'screens/virtual_pad_screen.dart': 'clavier AZERTY (FR) / QWERTY (EN), différence voulue',
}

# Mots français fréquents dans les textes d'interface (détection dans la version EN)
FRENCH_WORDS = re.compile(
    r"\b(le|les|des|une|pour|avec|sans|dans|sur|est|sont|fichiers?|dossiers?|"
    r"erreur|annuler|choisir|impossible|connexion|connecté|chargement|jeux?|"
    r"envoi|envoyer|téléchargement|télécharger|supprimer|enregistrer|"
    r"réessayer|paramètres|introuvable|aucun|aucune|terminés?|en cours|"
    r"oui|non|fermer|ouvrir|lancer|quitter|sauvegard\w*|mise à jour)\b",
    re.IGNORECASE,
)
FRENCH_ACCENTS = re.compile(r"[àâçéèêëîïôûùüÿœÀÂÇÉÈÊËÎÏÔÛÙÜŸŒ]")

# ─────────────────────────────────────────────────────────────────────────────
#  Découpage d'un fichier Dart : code / chaînes / commentaires
# ─────────────────────────────────────────────────────────────────────────────

def tokenize(src):
    """Retourne (code_lines, strings) :
    - code_lines : liste de (n° de ligne, code normalisé) — chaînes remplacées
      par S, commentaires retirés, espaces supprimés
    - strings    : liste de (n° de ligne, contenu) des chaînes simple ligne
      (les chaînes multi-lignes ''' / \"\"\", ex. scripts Python embarqués,
      sont ignorées)
    """
    out_lines = {}
    strings = []
    i, n, line = 0, len(src), 1
    buf = []

    def emit(text):
        buf.append(text)

    while i < n:
        c = src[i]
        # Commentaire ligne
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        # Commentaire bloc
        if src.startswith('/*', i):
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            line += src.count('\n', i, j)
            for _ in range(src.count('\n', i, j)):
                buf.append('\n')
            i = j
            continue
        # Chaînes (avec préfixe r éventuel)
        raw = False
        k = i
        if c in 'rR' and i + 1 < n and src[i + 1] in '\'"' and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] == '_')):
            raw = True
            k = i + 1
        if src[k] in '\'"':
            q = src[k]
            triple = src.startswith(q * 3, k)
            start_line = line
            if triple:
                end = src.find(q * 3, k + 3)
                end = n if end < 0 else end + 3
                nl = src.count('\n', k, end)
                emit('S' + '\n' * nl)
                line += nl
                i = end
                continue
            j, content = _scan_string(src, k + 1, q, raw)
            strings.append((start_line, content))
            emit('S')
            i = j
            continue
        if c == '\n':
            line += 1
        emit(c)
        i += 1

    code = ''.join(buf)
    result = []
    for idx, l in enumerate(code.split('\n'), start=1):
        norm = re.sub(r'\s+', '', l)
        if norm:
            result.append((idx, norm))
    return result, strings


def _scan_string(src, j, q, raw):
    """Parcourt une chaîne simple ligne à partir de j (après le guillemet
    ouvrant). Gère les échappements et les interpolations ${…}, qui peuvent
    elles-mêmes contenir des chaînes. Retourne (position après la chaîne,
    contenu)."""
    n = len(src)
    content = []
    while j < n and src[j] != q and src[j] != '\n':
        if not raw and src[j] == '\\' and j + 1 < n:
            content.append(src[j:j + 2])
            j += 2
            continue
        if not raw and src.startswith('${', j):
            depth, k = 1, j + 2
            while k < n and depth and src[k] != '\n':
                ch = src[k]
                if ch in '\'"':
                    k, _ = _scan_string(src, k + 1, ch, False)
                    continue
                if ch == '{':
                    depth += 1
                elif ch == '}':
                    depth -= 1
                k += 1
            content.append(src[j:k])
            j = k
            continue
        content.append(src[j])
        j += 1
    if j < n and src[j] == q:
        j += 1
    return j, ''.join(content)


def read(path):
    with open(path, encoding='utf-8', errors='replace') as f:
        return f.read()


def dart_files(root):
    base = os.path.join(root, 'lib')
    files = set()
    for d, _, names in os.walk(base):
        for name in names:
            if name.endswith('.dart'):
                files.add(os.path.relpath(os.path.join(d, name), base).replace('\\', '/'))
    return files


# ─────────────────────────────────────────────────────────────────────────────
#  Contrôles
# ─────────────────────────────────────────────────────────────────────────────

def looks_french(s):
    t = s.strip()
    if len(t) < 3:
        return False
    # Chemins, URLs, regex, clés techniques : ignorés
    if t.startswith(('/', 'http', 'package:', '../', './')) or re.fullmatch(r'[\w./\-:${}%+*#@]+', t):
        return False
    return bool(FRENCH_ACCENTS.search(t) or FRENCH_WORDS.search(t))


def main():
    if not os.path.isdir(os.path.join(FR_ROOT, 'lib')) or not os.path.isdir(os.path.join(EN_ROOT, 'lib')):
        print("Lance ce script depuis la racine du projet (lib/ et batocera_remote_en/lib/ introuvables).")
        return 2

    problems = 0
    fr_files, en_files = dart_files(FR_ROOT), dart_files(EN_ROOT)

    # 1) Fichiers présents d'un seul côté
    print('== 1. Fichiers présents des deux côtés')
    only_fr, only_en = sorted(fr_files - en_files), sorted(en_files - fr_files)
    for f in only_fr:
        print(f'   [X] uniquement en FR : lib/{f}')
    for f in only_en:
        print(f'   [X] uniquement en EN : {EN_ROOT}/lib/{f}')
    problems += len(only_fr) + len(only_en)
    if not only_fr and not only_en:
        print(f'   [OK] {len(fr_files)} fichiers, tous présents en FR et en EN')

    # 2) Différences de logique
    print('\n== 2. Logique identique FR / EN (textes et commentaires ignorés)')
    logic_issues = 0
    french_hits = []
    for f in sorted(fr_files & en_files):
        fr_src = read(os.path.join(FR_ROOT, 'lib', f))
        en_src = read(os.path.join(EN_ROOT, 'lib', f))
        fr_code, _ = tokenize(fr_src)
        en_code, en_strings = tokenize(en_src)

        a = [c for _, c in fr_code]
        b = [c for _, c in en_code]
        if a != b and f in IGNORE_LOGIC:
            print(f'   [--] {f} : ignoré ({IGNORE_LOGIC[f]})')
        elif a != b:
            logic_issues += 1
            print(f'   [X] {f}')
            shown = 0
            fr_lines, en_lines = fr_src.split('\n'), en_src.split('\n')
            sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
            for tag, i1, i2, j1, j2 in sm.get_opcodes():
                if tag == 'equal':
                    continue
                for k in range(i1, i2):
                    if shown >= MAX_DIFF_LINES:
                        break
                    ln = fr_code[k][0]
                    print(f'       FR l.{ln:<5} {fr_lines[ln - 1].strip()[:110]}')
                    shown += 1
                for k in range(j1, j2):
                    if shown >= MAX_DIFF_LINES:
                        break
                    ln = en_code[k][0]
                    print(f'       EN l.{ln:<5} {en_lines[ln - 1].strip()[:110]}')
                    shown += 1
                if shown >= MAX_DIFF_LINES:
                    print('       … (autres différences non affichées)')
                    break

        # 3) Textes français dans l'EN
        for ln, s in en_strings:
            if looks_french(s):
                french_hits.append((f, ln, s))

    problems += logic_issues
    if logic_issues == 0:
        print('   [OK] aucune différence de logique')
    else:
        print(f'   -> {logic_issues} fichier(s) à vérifier '
              '(une différence de pure mise en forme, ex. accolades, est sans danger)')

    print('\n== 3. Textes en français dans la version EN')
    if french_hits:
        for f, ln, s in french_hits:
            print(f'   [X] {EN_ROOT}/lib/{f} l.{ln} : "{s[:90]}"')
        problems += len(french_hits)
    else:
        print('   [OK] aucun texte français détecté')

    # 4) Versions
    print('\n== 4. Versions')
    def pubspec_version(root):
        try:
            m = re.search(r'^version:\s*(\S+)', read(os.path.join(root, 'pubspec.yaml')), re.M)
            return m.group(1) if m else None
        except OSError:
            return None

    def app_version(root):
        try:
            m = re.search(r"kAppVersion\s*=\s*'([^']+)'", read(os.path.join(root, 'lib', 'screens', 'home_screen.dart')))
            return m.group(1) if m else None
        except OSError:
            return None

    pv_fr, pv_en = pubspec_version(FR_ROOT), pubspec_version(EN_ROOT)
    av_fr, av_en = app_version(FR_ROOT), app_version(EN_ROOT)
    print(f'   pubspec  FR : {pv_fr}   EN : {pv_en}')
    print(f'   kAppVersion FR : {av_fr}   EN : {av_en}')
    ver_ok = True
    if pv_fr != pv_en:
        print('   [X] versions pubspec différentes entre FR et EN'); ver_ok = False
    num = lambda v: (v or '').split('-')[0]
    if num(av_fr) != num(av_en):
        print('   [X] kAppVersion différent entre FR et EN'); ver_ok = False
    if pv_fr and av_fr:
        short = '.'.join(pv_fr.split('+')[0].split('.')[:2])
        if num(av_fr) != short:
            print(f'   [X] kAppVersion ({num(av_fr)}) ne correspond pas au pubspec ({short}) '
                  '-> le vérificateur de mises à jour se trompera'); ver_ok = False
    if av_fr and not av_fr.upper().endswith('FR'):
        print("   [X] kAppVersion FR ne se termine pas par '-FR'"); ver_ok = False
    if av_en and not av_en.upper().endswith('EN'):
        print("   [X] kAppVersion EN ne se termine pas par '-EN'"); ver_ok = False
    if ver_ok:
        print('   [OK] versions cohérentes')
    else:
        problems += 1

    print('\n' + ('=' * 60))
    if problems:
        print(f'RÉSULTAT : {problems} point(s) à vérifier')
        return 1
    print('RÉSULTAT : tout est OK, FR et EN sont synchronisés')
    return 0


if __name__ == '__main__':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
    sys.exit(main())
