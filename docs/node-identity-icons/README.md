# Offline node identity artwork

All `OS-*` and `Flag-*` imagesets are bundled PNGs; no URL lookup, font/emoji rendering,
or network access is involved at runtime. `NodeIdentityIcons(node: JSON)` draws a
`globe`/`server.rack` SF Symbol only when identity is unknown. Missing metadata is not
invented. A neutral white plate behind OS artwork preserves black/dark brand logos
in Dark Mode. Flags keep their original colors.

## Pinned, redistributable source collections

| Collection | Fixed Git commit | License / use |
| --- | --- | --- |
| [Homarr Labs Dashboard Icons](https://github.com/homarr-labs/dashboard-icons) (formerly walkxcode/dashboard-icons) | `c716eb6798576923fa08e9b3e4125173148994ed` | Apache-2.0; 22 OS/vendor brand images |
| [Simple Icons](https://github.com/simple-icons/simple-icons) | `d4e6ba93e48f178898707f0145ec285f28b64b38` | CC0-1.0 collection; FreeBSD, OpenBSD, NetBSD and SUSE paths, with upstream metadata brand colors |
| [flag-icons](https://github.com/lipis/flag-icons) | `086f7e97d657358203916dbe84f61c2bccaa81eb` | MIT, Copyright (c) 2013 Panayiotis Lipiridis; 270 real flag graphics |
| [pycountry](https://github.com/pycountry/pycountry), ISO country-code data originating in Debian iso-codes | `7c51a88dfb467faf7851019cdeecc39bd11d296e` (24.6.1) | LGPL-2.1-or-later; country code reference data, not artwork or linked executable code |

Copies of the collection licenses and ISO-data copyright notice are in this folder.
The editable ISO data is retained in `countries.json`; the generated alpha-3 table
in `NodeIdentity.swift` is its reduced code-only representation. No pycountry
runtime dependency is shipped. Preserve these attribution/license files when
redistributing the assets. The JSON data and Swift tables may be edited/rebuilt.

**Brand rights remain with their respective owners.** Collection licenses permit
redistribution of their contents but do not grant trademark rights or endorsement.
These images are used only to identify the corresponding OS/vendor. Simple Icons
upstream brand/source/guideline links are preserved in `simple-icons-metadata.json`.
Oracle Linux and Amazon Linux deliberately use real Oracle and AWS marks from the
collection (not an invented distribution-specific logo). macOS uses Apple's mark.
No Qure assets, fabricated logos or randomly recolored artwork are included.

## Coverage and transformations

- 26 OS images: AlmaLinux, Alpine, Amazon, Arch, CentOS, Debian, Fedora, FreeBSD,
  Gentoo, Kali, generic Linux (Tux), macOS, Manjaro, Mint, NetBSD, NixOS, OpenBSD,
  openSUSE, Oracle, Raspberry Pi OS/Raspbian, RHEL, Rocky, SUSE, Ubuntu, Void, Windows.
- 270 flag images: all 249 ISO 3166-1 territories and 21 additional upstream regions/
  organizations. The upstream `xx` unknown image is intentionally excluded;
  unknown input returns `nil`, yielding the globe fallback.
- ISO alpha-2 and all 249 alpha-3 codes are supported, plus UK→GB, EL→GR, UAE→AE,
  XKX/KOS→XK, AC→SH-AC, TA→SH-TA, and UK subdivision aliases.
- Existing regional-indicator flag strings and England/Scotland/Wales Unicode tag
  sequences are decoded to resource names, **never drawn as emoji**. Malformed,
  mixed, multi-flag or unknown values return `nil`.
- Original PNG OS logos are proportionally resized/centered on transparent 96×96
  canvases. Simple Icons paths are unchanged, filled with their upstream `hex`
  color, and rasterized at 96×96. Flag SVGs become 96×72 PNGs. All images use
  `template-rendering-intent: original`. These are modifications for packaging,
  not claims of original artwork authorship.
- Kernel metadata can identify Linux/BSD/Darwin/Windows families, but never a Linux
  distribution from a suffix/version. Explicit distro/platform/OS metadata takes
  precedence. Unknown numeric kernel versions remain unknown.

`manifest.json` records every pinned raw URL, verified Git blob SHA-1, original
SHA-256, transformed PNG SHA-256, dimensions and size. Total PNG payload: **678,609
bytes**; dimensions are intentionally sufficient for compact @3x card icons.

## Reproduce / verify without global installations

From the repository root, create an isolated environment under your scratch path:

```sh
uv venv "$TMPDIR/node-identity-venv"
uv pip install --python "$TMPDIR/node-identity-venv/bin/python" cairosvg==2.8.2 Pillow==12.1.1
"$TMPDIR/node-identity-venv/bin/python" scripts/build-node-identity-assets.py
"$TMPDIR/node-identity-venv/bin/python" scripts/build-node-identity-assets.py --verify
```

Rebuild needs Cairo, network access and `gh` CLI. It discovers GitHub trees at the
fixed commits, rejects truncated listings, downloads raw URLs, and checks every
source against its Git blob hash **before** converting it. `--verify` is offline:
it decodes every image, verifies dimensions/hash/manifest/catalog entries and
cross-checks all Swift code tables and declared OS regex cases against bundled
resources. It is not a substitute for Swift/XCTest execution.

`KomariPanelTests/NodeIdentityTests.swift` also checks field precedence, aliases,
malformed input, no kernel-based distro guessing, `UIImage(named:)` loading of all
296 compiled assets, and SwiftUI rendering with/without metadata. Run on the iOS
simulator with the project's Xcode scheme. The Linux authoring host has no Swift,
Xcode/actool or iOS simulator; compiled asset loading and XCTest rendering cannot
be claimed verified here. XcodeGen includes these directories via the existing
`project.yml` sources declarations, so no project file changes are needed.
