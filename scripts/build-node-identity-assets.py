#!/usr/bin/env python3
"""Build pinned, offline identity assets. Run in a venv with CairoSVG 2.8.2/Pillow 12.1.1.
Requires gh CLI for GitHub tree discovery. --verify is offline and only needs Pillow.
Only writes OS-*/Flag-* imagesets and docs/node-identity-icons metadata/licenses.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
from hashlib import sha1, sha256
from io import BytesIO
import json
import re
from pathlib import Path
import subprocess
import time
from urllib.request import urlopen
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'KomariPanel/Assets.xcassets'
DOCS = ROOT / 'docs/node-identity-icons'
SOURCES = {
    'dashboard': ('homarr-labs/dashboard-icons', 'c716eb6798576923fa08e9b3e4125173148994ed'),
    'flags': ('lipis/flag-icons', '086f7e97d657358203916dbe84f61c2bccaa81eb'),
    'simple': ('simple-icons/simple-icons', 'd4e6ba93e48f178898707f0145ec285f28b64b38'),
    'countries': ('pycountry/pycountry', '7c51a88dfb467faf7851019cdeecc39bd11d296e'),
}
OS = {
    'ubuntu': 'ubuntu-linux', 'debian': 'debian-linux', 'centos': 'centos',
    'rocky': 'rocky-linux', 'almalinux': 'alma-linux', 'rhel': 'redhat-linux',
    'fedora': 'fedora', 'arch': 'arch-linux', 'alpine': 'alpine-linux',
    'opensuse': 'opensuse', 'gentoo': 'gentoo-linux', 'oracle': 'oracle',
    'amazon': 'amazon-web-services', 'kali': 'kali-linux', 'nixos': 'nixos',
    'windows': 'windows-11', 'macos': 'apple', 'linux': 'linux',
    'mint': 'linux-mint', 'manjaro': 'manjaro-linux', 'raspbian': 'raspberry-pi',
    'void': 'void-linux',
}


def digest(data):
    return sha256(data).hexdigest()


def verify():
    manifest = json.loads((DOCS / 'manifest.json').read_text())
    for row in manifest['assets']:
        folder = ASSETS / (row['asset'] + '.imageset')
        contents = json.loads((folder / 'Contents.json').read_text())
        assert contents['properties']['template-rendering-intent'] == 'original'
        data = (folder / contents['images'][0]['filename']).read_bytes()
        assert digest(data) == row['png_sha256'], row['asset']
        with Image.open(BytesIO(data)) as image:
            image.load()
            assert list(image.size) == row['pixels']
            assert image.convert('RGBA').getbbox() is not None
    countries = json.loads((DOCS / 'countries.json').read_text())
    flags = {r['asset'].removeprefix('Flag-') for r in manifest['assets'] if r['kind'] == 'flag'}
    assert len(countries) == 249
    assert {x['alpha_2'] for x in countries} <= flags
    swift = (ROOT / 'KomariPanel/NodeIdentity.swift').read_text()
    codes = swift.split('static let supportedCountryCodes: Set<String> = [', 1)[1].split(']', 1)[0]
    assert set(re.findall(r'"([A-Z-]+)"', codes)) == flags
    mapping = swift.split('static let alpha3ToAlpha2: [String: String] = [', 1)[1].split(']', 1)[0]
    assert dict(re.findall(r'"([A-Z]{3})": "([A-Z]{2})"', mapping)) == {x['alpha_3']: x['alpha_2'] for x in countries}
    rules = swift.split('let rules: [(String, String)] = [', 1)[1].split('\n        ]', 1)[0]
    expected_os = {r['asset'] for r in manifest['assets'] if r['kind'] == 'os'}
    assert {'OS-' + slug for _, slug in re.findall(r'\("([^"]+)", "([a-z]+)"\)', rules)} | {'OS-linux'} == expected_os
    tests = (ROOT / 'KomariPanelTests/NodeIdentityTests.swift').read_text()
    cases = tests.split('let cases = [', 1)[1].split('\n        ]', 1)[0]
    extracted_rules = re.findall(r'\("([^"]+)", "([a-z]+)"\)', rules)
    for raw, slug in re.findall(r'"([^"]+)": "([a-z]+)"', cases):
        actual = next((name for pattern, name in extracted_rules if re.search(r'(?<![a-z])(?:' + pattern + r')(?![a-z])', raw, re.I)), None)
        if actual is None and re.search(r'(?<![a-z])linux(?![a-z])', raw, re.I):
            actual = 'linux'
        assert actual == slug, (raw, actual, slug)
    print(json.dumps({'verified_assets': len(manifest['assets']), 'iso_countries': len(countries),
                      'flags': len(flags), 'os': len(manifest['assets']) - len(flags),
                      'png_bytes': sum(r['png_bytes'] for r in manifest['assets'])}, indent=2))


def build():
    import cairosvg
    DOCS.mkdir(parents=True, exist_ok=True)
    trees = {}
    for key, (repo, commit) in SOURCES.items():
        result = json.loads(subprocess.check_output(['gh', 'api', f'repos/{repo}/git/trees/{commit}?recursive=1']))
        assert not result.get('truncated')
        trees[key] = {x['path']: x['sha'] for x in result['tree'] if x['type'] == 'blob'}

    def fetch(key, path):
        repo, commit = SOURCES[key]
        expected = trees[key][path]
        url = f'https://raw.githubusercontent.com/{repo}/{commit}/{path}'
        for attempt in range(3):
            try:
                with urlopen(url, timeout=60) as response:
                    assert response.status == 200
                    data = response.read()
                assert sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest() == expected, path
                return data, url
            except Exception:
                if attempt == 2:
                    raise
                time.sleep(1 + attempt)

    for key, path in [('dashboard', 'LICENSE'), ('flags', 'LICENSE'), ('simple', 'LICENSE.md'),
                      ('countries', 'LICENSE.txt'), ('countries', 'COPYRIGHT.txt')]:
        data, _ = fetch(key, path)
        (DOCS / f'{key}-{Path(path).name}').write_bytes(data)
    countries, _ = fetch('countries', 'src/pycountry/databases/iso3166-1.json')
    countries = json.loads(countries)['3166-1']
    (DOCS / 'countries.json').write_text(json.dumps(countries, ensure_ascii=False, indent=2) + '\n')
    simple, _ = fetch('simple', 'data/simple-icons.json')
    simple = json.loads(simple)
    if isinstance(simple, dict):
        simple = simple['icons']
    selected_simple = {i['title'].lower(): i for i in simple if i['title'].lower() in ['freebsd','openbsd','netbsd','suse']}
    (DOCS / 'simple-icons-metadata.json').write_text(json.dumps(selected_simple, indent=2) + '\n')
    tasks = [(f'OS-{key}', 'os', 'dashboard', f'png/{slug}.png', None) for key, slug in OS.items()]
    tasks += [(f'OS-{key}', 'os', 'simple', f'icons/{key}.svg', value['hex']) for key, value in selected_simple.items()]
    flag_paths = sorted(p for p in trees['flags'] if p.startswith('flags/4x3/') and p.endswith('.svg') and not p.endswith('/xx.svg'))
    tasks += [(f'Flag-{Path(p).stem.upper()}', 'flag', 'flags', p, None) for p in flag_paths]
    # Validate all source names before downloading any image.
    for _, _, key, path, _ in tasks:
        assert path in trees[key], path

    def render(task):
        name, kind, key, path, color = task
        source, url = fetch(key, path)
        data = source
        if path.endswith('.svg'):
            if color:
                data = data.replace(b'<svg ', f'<svg fill="#{color}" '.encode(), 1)
            data = cairosvg.svg2png(bytestring=data, output_width=96, output_height=72 if kind == 'flag' else 96)
        image = Image.open(BytesIO(data)).convert('RGBA')
        if kind == 'os':
            image.thumbnail((96, 96), Image.Resampling.LANCZOS)
            canvas = Image.new('RGBA', (96, 96))
            canvas.alpha_composite(image, ((96 - image.width)//2, (96 - image.height)//2))
            image = canvas
        output = BytesIO()
        image.save(output, format='PNG', optimize=True)
        png = output.getvalue()
        folder = ASSETS / (name + '.imageset')
        folder.mkdir(exist_ok=True)
        (folder / 'icon.png').write_bytes(png)
        contents = {'images': [{'filename': 'icon.png', 'idiom': 'universal'}],
                    'info': {'author': 'xcode', 'version': 1},
                    'properties': {'template-rendering-intent': 'original'}}
        (folder / 'Contents.json').write_text(json.dumps(contents, indent=2) + '\n')
        return {'asset': name, 'kind': kind, 'url': url, 'source_git_blob': trees[key][path],
                'source_sha256': digest(source), 'png_sha256': digest(png), 'png_bytes': len(png),
                'pixels': list(image.size), 'brand_hex': color}

    with ThreadPoolExecutor(max_workers=10) as pool:
        rows = list(pool.map(render, tasks))
    (DOCS / 'manifest.json').write_text(json.dumps({'sources': SOURCES, 'assets': sorted(rows, key=lambda r:r['asset'])}, indent=2) + '\n')
    verify()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    verify() if args.verify else build()
