#!/usr/bin/env python3
"""String Catalog maintenance for MacPulse.

English is the development language: source literals are the catalog keys.
Every key must also have a Turkish translation.

  python3 Scripts/localization.py sync          # build with string extraction, merge new keys into the catalog
  python3 Scripts/localization.py check         # gate: every key translated, format specifiers match, catalog compiles
  python3 Scripts/localization.py compile DIR   # write <lang>.lproj/Localizable.strings(dict) into DIR

`sync` keeps existing translations; keys that are no longer in the source are marked stale.
`compile` needs only Python, so packaging also works with the Command Line Tools. When
Xcode's xcstringstool is available, `check` verifies that both compilers produce the same tables.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'Sources/MacPulse/Resources/Localizable.xcstrings'
LANGUAGES = ['tr']
SPEC = re.compile(r'%(?:(\d+)\$)?(?:#@(\w+)@|(lld|llu|ld|lu|lf|d|u|f|@))')


def run(args, **kw):
    return subprocess.run(args, check=True, **kw)


def extract(out_dir):
    run(['swift', 'build', '--build-system', 'native', '-Xswiftc', '-emit-localized-strings',
         '-Xswiftc', '-emit-localized-strings-path', '-Xswiftc', str(out_dir)], cwd=ROOT,
        stdout=subprocess.DEVNULL)
    return sorted(Path(out_dir).glob('*.stringsdata'))


def save(catalog):
    text = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True, separators=(',', ' : '))
    CATALOG.write_text(text + '\n', encoding='utf-8')


def sync():
    with tempfile.TemporaryDirectory() as tmp:
        files = extract(tmp)
        run(['xcrun', 'xcstringstool', 'sync', str(CATALOG), '--stringsdata', *map(str, files)])
    save(json.loads(CATALOG.read_text(encoding='utf-8')))
    return check(compiled=False)


def plural_rule(variants, convert=lambda s: s):
    plural = variants.get('plural')
    if not plural or set(variants) != {'plural'}:
        raise SystemExit('Only plural variations are supported')
    rule = {'NSStringFormatSpecTypeKey': 'NSStringPluralRuleType'}
    for category, variant in plural.items():
        rule[category] = convert(variant['stringUnit']['value'])
    return rule


def compile_tables(catalog):
    """Same tables xcstringstool emits: translations as .strings, plurals as .stringsdict."""
    source = catalog['sourceLanguage']
    tables = {}
    for key, entry in catalog['strings'].items():
        if entry.get('extractionState') == 'stale' or entry.get('shouldTranslate') is False:
            continue
        for lang, loc in entry.get('localizations', {}).items():
            strings, plurals = tables.setdefault(lang, ({}, {}))
            if 'variations' in loc:
                types = list(arg_types(key).values())
                if len(types) != 1:
                    raise SystemExit(f'Plural variations need exactly one argument: {key!r}')
                rule = plural_rule(loc['variations'])
                rule['NSStringFormatValueTypeKey'] = types[0]
                plurals[key] = {'NSStringLocalizedFormatKey': '%#@value@', 'value': rule}
            elif 'substitutions' in loc:
                item = {'NSStringLocalizedFormatKey': loc['stringUnit']['value']}
                for name, sub in loc['substitutions'].items():
                    spec = '%{}${}'.format(sub['argNum'], sub['formatSpecifier'])
                    item[name] = plural_rule(sub['variations'], lambda s: s.replace('%arg', spec))
                    item[name]['NSStringFormatValueTypeKey'] = sub['formatSpecifier']
                plurals[key] = item
            elif 'stringUnit' in loc:
                unit = loc['stringUnit']
                if lang == source and (unit.get('state') != 'translated' or unit['value'] == key):
                    continue
                strings[key] = unit['value']
    return tables


def compile_catalog(out_dir):
    out_dir = Path(out_dir)
    for lang, (strings, plurals) in compile_tables(json.loads(CATALOG.read_text(encoding='utf-8'))).items():
        folder = out_dir / f'{lang}.lproj'
        folder.mkdir(parents=True, exist_ok=True)
        if strings:
            (folder / 'Localizable.strings').write_bytes(plistlib.dumps(strings, sort_keys=True))
        if plurals:
            (folder / 'Localizable.stringsdict').write_bytes(plistlib.dumps(plurals, sort_keys=True))
    return 0


def tables_in(folder):
    return {p.relative_to(folder).as_posix(): plistlib.loads(p.read_bytes())
            for p in sorted(Path(folder).glob('*.lproj/Localizable.strings*'))}


def arg_types(value, substitutions=None):
    """Format argument types by position. `%#@name@` resolves through its substitution."""
    types, seq = {}, 0
    for m in SPEC.finditer(value.replace('%%', '')):
        pos = int(m.group(1)) if m.group(1) else None
        if m.group(2):
            sub = (substitutions or {}).get(m.group(2), {})
            pos = sub.get('argNum', pos)
            kind = sub.get('formatSpecifier', '?')
        else:
            kind = m.group(3)
        if pos is None:
            seq += 1; pos = seq
        types[pos] = {'d': 'lld', 'ld': 'lld', 'u': 'lld', 'lu': 'lld', 'llu': 'lld', 'f': 'lf'}.get(kind, kind)
    return types


def has_args(key):
    return bool(arg_types(key))


def unit_values(loc):
    """All (value, substitutions) pairs of a localization, including plural variations."""
    if 'stringUnit' in loc:
        yield loc['stringUnit'], loc.get('substitutions')
    for variants in loc.get('variations', {}).values():
        for variant in variants.values():
            yield from unit_values(variant)


def check(compiled=True):
    catalog = json.loads(CATALOG.read_text(encoding='utf-8'))
    if catalog.get('sourceLanguage') != 'en':
        raise SystemExit('Catalog source language must be en')
    problems = []
    for key, entry in sorted(catalog['strings'].items()):
        if entry.get('extractionState') == 'stale' or entry.get('shouldTranslate') is False:
            continue
        expected = arg_types(key) if has_args(key) else {}
        letters = re.search(r'[^\W\d_]', SPEC.sub('', key))
        locs = entry.get('localizations', {})
        for lang in ['en'] + LANGUAGES:
            if lang not in locs:
                if lang != 'en' and letters:
                    problems.append(f'missing {lang}: {key!r}')
                continue
            for unit, subs in unit_values(locs[lang]):
                # `sync` writes positional English forms of multi-argument keys as `new`; they equal the key.
                if unit.get('state') not in ('translated', None) and not (lang == 'en' and unit.get('state') == 'new'):
                    problems.append(f'{lang} not translated: {key!r}')
                if expected and arg_types(unit.get('value', ''), subs) != expected:
                    problems.append(f'{lang} format mismatch: {key!r} -> {unit.get("value")!r}')
    if compiled:
        with tempfile.TemporaryDirectory() as tmp:
            ours = Path(tmp) / 'python'
            compile_catalog(ours)
            # English values equal their keys, so only English plurals (.stringsdict) are emitted.
            if not (ours / 'en.lproj/Localizable.stringsdict').exists():
                problems.append('compile produced no en.lproj/Localizable.stringsdict')
            for lang in LANGUAGES:
                if not (ours / f'{lang}.lproj/Localizable.strings').exists():
                    problems.append(f'compile produced no {lang}.lproj/Localizable.strings')
            if xcstringstool():
                apple = Path(tmp) / 'xcstringstool'
                run(['xcrun', 'xcstringstool', 'compile', str(CATALOG), '--output-directory', str(apple)], stdout=subprocess.DEVNULL)
                if tables_in(ours) != tables_in(apple):
                    problems.append('Python compile differs from xcstringstool output')
            else:
                print('xcstringstool not found; skipped the cross-check with Xcode', file=sys.stderr)
    for p in problems:
        print(p, file=sys.stderr)
    print(f'{len(catalog["strings"])} keys, {len(problems)} problems')
    return 1 if problems else 0


def xcstringstool():
    return shutil.which('xcrun') is not None and subprocess.run(
        ['xcrun', '--find', 'xcstringstool'], capture_output=True).returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('action', choices=['sync', 'check', 'compile'])
    parser.add_argument('output', nargs='?', help='output directory for compile')
    args = parser.parse_args()
    if args.action == 'compile':
        if not args.output:
            parser.error('compile needs an output directory')
        sys.exit(compile_catalog(args.output))
    sys.exit(sync() if args.action == 'sync' else check())


if __name__ == '__main__':
    main()
