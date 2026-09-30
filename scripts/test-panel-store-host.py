#!/usr/bin/env python3
"""Build/run real PanelStore + transport XCTest sources on the host, never an iOS simulator.

macOS CI: python3 scripts/test-panel-store-host.py --build-dir "$RUNNER_TEMP/panel-store-host"
Linux:   python3 scripts/test-panel-store-host.py --build-dir "$TMPDIR/panel-store-host"
Requires Python 3 and Swift 5.9+. --prepare-only allows a separate Swift container.
Only platform adapters are replaced: Linux observation and unused host Keychain.
The store, request generation checks, transports and regression tests are copied verbatim.
"""
import argparse
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--build-dir", required=True, type=Path)
parser.add_argument("--prepare-only", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = args.build_dir.resolve()
sources = out / "Sources" / "KomariPanel"
tests = out / "Tests" / "KomariPanelTests"
sources.mkdir(parents=True, exist_ok=True)
tests.mkdir(parents=True, exist_ok=True)
(out / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "PanelStoreHostRegression",
    platforms: [.macOS(.v13)],
    products: [.library(name: "KomariPanel", targets: ["KomariPanel"])],
    targets: [
        .target(name: "KomariPanel"),
        .testTarget(name: "KomariPanelTests", dependencies: ["KomariPanel"])
    ],
    swiftLanguageVersions: [.v5]
)
''')
networking = "\n#if canImport(FoundationNetworking)\nimport FoundationNetworking\n#endif\n"
core = (root / "KomariPanel/Core.swift").read_text()
marker = "/// Keys are local-only"
assert core.count(marker) == 1, "Keychain boundary changed; review the host adapter"
core = core.split(marker)[0].replace("import Security", networking)
(sources / "Core.swift").write_text(core)
(sources / "Backends.swift").write_text(
    (root / "KomariPanel/Backends.swift").read_text().replace("import Foundation", "import Foundation" + networking, 1)
)
(sources / "PanelStore.swift").write_text(
    (root / "KomariPanel/PanelStore.swift").read_text().replace("import Combine", "#if canImport(Combine)\nimport Combine\n#endif")
)
app = (root / "KomariPanel/App.swift").read_text()
date_function = re.search(r"^func recordDate\([^\n]+", app, re.MULTILINE)
assert date_function, "recordDate moved; update the source extraction"
(sources / "HostAdapters.swift").write_text('''import Foundation
#if !canImport(Combine)
// Linux has no Combine. Only the observation wrapper is replaced, not store logic.
protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
#endif
// Tests inject connections and must never access a developer/CI Keychain.
enum Keychain {
    static func load(account: String) throws -> String {
        fatalError("Host tests must inject a connection, not access Keychain")
    }
}
''' + date_function.group(0) + "\n")
for name in ("PanelStoreTests.swift", "TransportCancellationTests.swift"):
    (tests / name).write_text((root / "KomariPanelTests" / name).read_text().replace("import XCTest", "import XCTest" + networking, 1))
print(f"Prepared actual store/transport sources and XCTest cases at {out}", flush=True)
if not args.prepare_only:
    subprocess.run(["swift", "test", "--package-path", str(out)], check=True)
