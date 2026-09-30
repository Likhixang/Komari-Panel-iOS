#!/usr/bin/env python3
"""Validate all five localization catalogs and Chinese UI source-key coverage.

No dependencies. Run from any directory. --ipa additionally verifies the exact
compiled catalogs shipped in an unsigned IPA (binary or XML .strings plists).
"""
import argparse
from collections import Counter
import itertools
import json
from pathlib import Path
import plistlib
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = ('zh-Hans', 'zh-Hant', 'en', 'ja', 'ko')
PAIR = re.compile(r'"((?:\\.|[^"\\])*)"\s*=\s*"((?:\\.|[^"\\])*)"\s*;')
FORMAT = re.compile(r'%(?:(\d+)\$)?[-+ #0]*(?:\d+)?(?:\.\d+)?(lld|llu|ld|lu|d|u|f|g|@)')
CHINESE = re.compile(r'[\u4e00-\u9fff]')


def decode(text):
    return json.loads('"' + text + '"')


def catalog(path):
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'/\*.*?\*/|^\s*//[^\n]*', '', text, flags=re.S | re.M)
    pairs = [(decode(k), decode(v)) for k, v in PAIR.findall(text)]
    residue = PAIR.sub('', text).strip()
    assert not residue, f'{path}: malformed .strings: {residue[:120]}'
    counts = Counter(k for k, _ in pairs)
    assert all(v == 1 for v in counts.values()), f'{path}: duplicate keys'
    assert all(v.strip() for _, v in pairs), f'{path}: empty translation'
    return dict(pairs)


def placeholders(text):
    # Ignore literal percent signs; normalize only format argument order.
    text = text.replace('%%', '')
    result = {}
    next_index = 1
    for match in FORMAT.finditer(text):
        index = int(match[1]) if match[1] else next_index
        result.setdefault(index, []).append(match[2])
        next_index += 1
    return {k: sorted(v) for k, v in result.items()}


def swift_strings(text):
    """Lex normal Swift strings, including nested literals in interpolation.

    Returns each literal as literal chunks alternating with expressions; does
    not mistake comments, API subscripts, or escaped quotes for UI strings.
    """
    literals = []

    def quoted(i):
        start = i
        i += 1
        chunks = ['']
        while i < len(text):
            if text.startswith('\\(', i):
                i, expression = interpolated(i + 2)
                chunks.extend([expression, ''])
            elif text[i] == '\\' and i + 1 < len(text):
                chunks[-1] += text[i:i + 2]
                i += 2
            elif text[i] == '"':
                literals.append((start, chunks))
                return i + 1
            else:
                chunks[-1] += text[i]
                i += 1
        raise AssertionError('Unterminated Swift string')

    def interpolated(i):
        start, depth = i, 1
        while i < len(text):
            if text[i] == '"':
                i = quoted(i)
                continue
            if text[i] == '(':
                depth += 1
            elif text[i] == ')':
                depth -= 1
                if depth == 0:
                    return i + 1, text[start:i]
            i += 1
        raise AssertionError('Unterminated Swift interpolation')

    i = 0
    while i < len(text):
        if text.startswith('//', i):
            end = text.find('\n', i)
            i = len(text) if end == -1 else end + 1
        elif text.startswith('/*', i):
            depth = 1
            i += 2
            while depth and i < len(text):
                if text.startswith('/*', i):
                    depth += 1
                    i += 2
                elif text.startswith('*/', i):
                    depth -= 1
                    i += 2
                else:
                    i += 1
        elif text[i] == '"':
            i = quoted(i)
        else:
            i += 1
    return literals


def source_keys(catalog_keys):
    covered = set()
    errors = []
    for path in (ROOT / 'KomariPanel').glob('*.swift'):
        text = path.read_text()
        for offset, chunks in swift_strings(text):
            if not any(CHINESE.search(chunk) for chunk in chunks[::2]):
                continue
            parts = [decode(chunk) for chunk in chunks[::2]]
            # SwiftUI and Foundation differ in Int format width. Catalog format
            # parity and runtime tests validate exact signatures separately.
            candidates = set()
            for formats in itertools.product(('%@', '%lld', '%ld', '%d'), repeat=len(parts) - 1):
                key = parts[0]
                for fmt, part in zip(formats, parts[1:]):
                    key += fmt + part
                candidates.add(key)
            found = candidates.intersection(catalog_keys)
            if found:
                covered.update(found)
            else:
                line = text.count('\n', 0, offset) + 1
                errors.append(f'{path.name}:{line}: {parts}')
    assert not errors, 'Missing source keys:\n' + '\n'.join(errors)
    return covered


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa', type=Path)
    args = parser.parse_args()
    tables = {language: catalog(ROOT / 'KomariPanel' / (language + '.lproj') / 'Localizable.strings') for language in LANGUAGES}
    reference = tables['zh-Hans']
    for language, table in tables.items():
        assert set(table) == set(reference), f'{language}: missing={set(reference)-set(table)}, extra={set(table)-set(reference)}'
        for key, value in table.items():
            assert placeholders(key) == placeholders(value), f'{language}: placeholder mismatch: {key!r} -> {value!r}'
            if language in ('en', 'ko'):
                assert not CHINESE.search(value), f'{language}: untranslated Chinese: {key!r}'
        info = catalog_info(language)
        assert set(info) == {'CFBundleDisplayName', 'NSLocalNetworkUsageDescription'}, language
        assert info['CFBundleDisplayName'] == 'Monitor Panel'
        print(f'{language}: {len(table)} nonempty unique keys, format signatures valid, InfoPlist valid')
    covered = source_keys(set(reference))
    print(f'Swift source: {len(covered)} Chinese UI resource keys covered (not a runtime rendering check)')
    if args.ipa:
        with zipfile.ZipFile(args.ipa) as archive:
            assert archive.testzip() is None, 'Corrupt IPA'
            for language in LANGUAGES:
                prefix = f'Payload/KomariPanel.app/{language}.lproj/'
                for filename, expected in [('Localizable.strings', tables[language]), ('InfoPlist.strings', catalog_info(language))]:
                    actual = plistlib.loads(archive.read(prefix + filename))
                    assert actual == expected, f'IPA {language}/{filename} differs from source'
            print('IPA: all five compiled Localizable/InfoPlist catalogs match source exactly')


def catalog_info(language):
    path = ROOT / 'KomariPanel' / (language + '.lproj') / 'InfoPlist.strings'
    text = path.read_text()
    # InfoPlist historically uses legal unquoted identifier keys.
    return {key: decode(value) for key, value in re.findall(r'"?(\w+)"?\s*=\s*"((?:\\.|[^"\\])*)"\s*;', text)}


if __name__ == '__main__':
    main()
