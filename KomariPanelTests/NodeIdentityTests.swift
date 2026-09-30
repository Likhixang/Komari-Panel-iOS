import XCTest
import UIKit
import SwiftUI
@testable import KomariPanel

final class NodeIdentityTests: XCTestCase {
    private func node(_ os: String) -> JSON { .object(["os": .string(os)]) }

    func testExplicitOperatingSystems() {
        let cases = [
            "Ubuntu 24.04 LTS": "ubuntu", "Debian GNU/Linux 12": "debian",
            "CentOS Stream 9": "centos", "Rocky Linux 9.4": "rocky",
            "AlmaLinux 9": "almalinux", "Alma Linux": "almalinux",
            "Red Hat Enterprise Linux 9": "rhel", "rhel": "rhel",
            "Fedora Linux 40": "fedora", "Arch Linux": "arch", "archlinux": "arch",
            "Alpine Linux 3.20": "alpine", "openSUSE Tumbleweed": "opensuse",
            "opensuse-leap": "opensuse", "SUSE Linux Enterprise Server 15": "suse",
            "SLES": "suse", "Gentoo Linux": "gentoo", "Oracle Linux Server 9": "oracle",
            "Amazon Linux 2023": "amazon", "amzn": "amazon", "Kali GNU/Linux": "kali",
            "NixOS 24.05": "nixos", "FreeBSD 14": "freebsd", "OpenBSD 7.5": "openbsd",
            "NetBSD 10": "netbsd", "Microsoft Windows Server 2022": "windows",
            "windows": "windows", "macOS Sonoma": "macos", "Mac OS X": "macos",
            "Darwin": "macos", "GNU/Linux": "linux", "Linux Mint 22": "mint",
            "Manjaro Linux": "manjaro", "Raspberry Pi OS": "raspbian", "Void Linux": "void"
        ]
        for (raw, slug) in cases {
            XCTAssertEqual(NodeIdentity.osAssetName(for: node(raw)), "OS-" + slug, raw)
        }
    }

    func testFieldPrecedenceAndKernelIsNotDistroEvidence() {
        XCTAssertEqual(NodeIdentity.osAssetName(for: .object(["os": .string("Linux"), "platform": .string("debian")])), "OS-debian")
        XCTAssertEqual(NodeIdentity.osAssetName(for: .object(["os": .string("Linux"), "distro": .string("Ubuntu")])), "OS-ubuntu")
        XCTAssertEqual(NodeIdentity.osAssetName(for: .object(["os": .string("Linux"), "distro": .string("AlmaLinux"), "platform": .string("rhel")])), "OS-almalinux")
        XCTAssertEqual(NodeIdentity.osAssetName(for: .object(["os": .string("Linux"), "kernel_version": .string("6.8.0-ubuntu")])), "OS-linux")
        XCTAssertEqual(NodeIdentity.osAssetName(for: .object(["kernel_version": .string("Linux 6.1.0-debian")])), "OS-linux")
        XCTAssertEqual(NodeIdentity.osAssetName(for: .object(["kernel_version": .string("Darwin 23.1.0")])), "OS-macos")
        for kernel in ["6.1.0-18-amd64", "5.14.0.el9.x86_64", "6.8.0-ubuntu"] {
            XCTAssertNil(NodeIdentity.osAssetName(for: .object(["kernel_version": .string(kernel)])))
        }
        for raw in ["", "Unknown", "research-os", "superwindowsclone", "debianish"] {
            XCTAssertNil(NodeIdentity.osAssetName(for: node(raw)), raw)
        }
        XCTAssertNil(NodeIdentity.osAssetName(for: .null))
    }

    func testCountryAliasesAndUnicodeInputs() {
        let cases = [" us \n": "US", "UK": "GB", "uk": "GB", "EL": "GR", "USA": "US",
                     "GBR": "GB", "CHN": "CN", "DEU": "DE", "HKG": "HK", "MAC": "MO",
                     "XKX": "XK", "UAE": "AE", "EU": "EU", "UN": "UN", "AC": "SH-AC",
                     "gb-sct": "GB-SCT", "🇺🇸": "US", "🇨🇳": "CN", "🇬🇧": "GB"]
        for (raw, code) in cases {
            XCTAssertEqual(NodeIdentity.countryCode(for: raw), code, raw)
            XCTAssertEqual(NodeIdentity.flagAssetName(for: raw), "Flag-" + code, raw)
        }
        let england = "\u{1F3F4}\u{E0067}\u{E0062}\u{E0065}\u{E006E}\u{E0067}\u{E007F}"
        XCTAssertEqual(NodeIdentity.countryCode(for: england), "GB-ENG")
        for raw in ["", "ZZ", "XX", "ZZZ", "unknown", "US-East", "🇺", "🇺🇸🇨🇳", "🏳️", "🇺🇸 US", "US/GB"] {
            XCTAssertNil(NodeIdentity.countryCode(for: raw), raw)
            XCTAssertNil(NodeIdentity.flagAssetName(for: raw), raw)
        }
        XCTAssertEqual(NodeIdentity.countryCode(for: .object(["region": .string("??"), "country_code": .string("JPN")])), "JP")
    }

    func testCompleteISOAlpha3MappingAndAssetsLoadFromAppBundle() {
        XCTAssertEqual(NodeIdentity.alpha3ToAlpha2.count, 249)
        XCTAssertEqual(Set(NodeIdentity.alpha3ToAlpha2.values).count, 249)
        XCTAssertEqual(NodeIdentity.supportedCountryCodes.count, 270)
        for (alpha3, alpha2) in NodeIdentity.alpha3ToAlpha2 {
            XCTAssertEqual(NodeIdentity.countryCode(for: alpha3.lowercased()), alpha2)
            XCTAssertEqual(NodeIdentity.countryCode(for: alpha2), alpha2)
        }
        for code in NodeIdentity.supportedCountryCodes {
            let asset = "Flag-" + code
            XCTAssertEqual(NodeIdentity.flagAssetName(for: code), asset)
            XCTAssertNotNil(UIImage(named: asset), "Missing compiled image: " + asset)
        }
        for slug in ["almalinux", "alpine", "amazon", "arch", "centos", "debian", "fedora", "freebsd", "gentoo", "kali", "linux", "macos", "manjaro", "mint", "netbsd", "nixos", "openbsd", "opensuse", "oracle", "raspbian", "rhel", "rocky", "suse", "ubuntu", "void", "windows"] {
            XCTAssertNotNil(UIImage(named: "OS-" + slug), "Missing OS image: " + slug)
        }
    }

    @MainActor func testIdentityComponentRendersWithAndWithoutMetadata() throws {
        for sample in [JSON.object(["os": .string("Ubuntu"), "region": .string("🇺🇸")]), JSON.null] {
            let renderer = ImageRenderer(content: NodeIdentityIcons(node: sample).padding(8))
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(image.size.width, 0)
            XCTAssertGreaterThan(image.size.height, 0)
        }
    }
}
