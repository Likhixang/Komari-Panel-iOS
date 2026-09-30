import Foundation
import SwiftUI

/// Offline identity lookup. Asset names are shared by SwiftUI, UIKit and tests.
/// Only explicit distro/platform/OS names identify a distribution: kernel strings
/// may identify an OS family but never turn an unknown Linux into Ubuntu/RHEL.
enum NodeIdentity {
    static func osAssetName(for node: JSON) -> String? {
        let values = ["distro", "distribution", "platform", "os"].map { node[$0].string }
        for value in values {
            if let asset = specificOS(value) { return asset }
        }
        for value in values + [node["kernel_version"].string] {
            if let asset = familyOS(value) { return asset }
        }
        return nil
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: "(?i)(?<![a-z])(?:" + pattern + ")(?![a-z])", options: .regularExpression) != nil
    }

    private static func specificOS(_ value: String) -> String? {
        let rules: [(String, String)] = [
            ("raspbian|raspberry[ -]?pi[ -]?os", "raspbian"),
            ("linux[ -]?mint|mint", "mint"), ("manjaro", "manjaro"),
            ("ubuntu|kubuntu|lubuntu|xubuntu", "ubuntu"), ("debian", "debian"),
            ("cent[ -]?os", "centos"), ("rocky(?:[ -]?linux)?", "rocky"),
            ("alma(?:[ -]?linux)?", "almalinux"),
            ("oracle(?:[ -]?linux)?|ol", "oracle"),
            ("amazon(?:[ -]?linux)?|amzn", "amazon"),
            ("red[ -]?hat(?:[ -]?enterprise[ -]?linux)?|rhel", "rhel"),
            ("fedora", "fedora"), ("arch(?:[ -]?linux)?", "arch"),
            ("alpine(?:[ -]?linux)?", "alpine"),
            ("open[ -]?suse(?:[ -]?(?:leap|tumbleweed))?", "opensuse"),
            ("suse|sles|sled", "suse"), ("gentoo", "gentoo"),
            ("kali(?:[ -]?linux)?", "kali"), ("nix[ -]?os", "nixos"),
            ("void(?:[ -]?linux)?", "void"),
            ("free[ -]?bsd", "freebsd"), ("open[ -]?bsd", "openbsd"),
            ("net[ -]?bsd", "netbsd"),
            ("windows|win32|win64|winnt|microsoft[ -]?windows", "windows"),
            ("mac[ -]?os(?:[ -]?x)?|os[ -]?x|darwin", "macos")
        ]
        return rules.first(where: { matches(value, $0.0) }).map { "OS-" + $0.1 }
    }

    private static func familyOS(_ value: String) -> String? {
        for (pattern, name) in [
            ("free[ -]?bsd", "freebsd"), ("open[ -]?bsd", "openbsd"),
            ("net[ -]?bsd", "netbsd"), ("darwin|mac[ -]?os|os[ -]?x", "macos"),
            ("windows|win32|win64|winnt", "windows"), ("linux", "linux")
        ] where matches(value, pattern) { return "OS-" + name }
        return nil
    }

    /// Strict codes, ISO alpha-3, common aliases and existing flag Unicode input.
    /// Unicode input is decoded only; the view never renders it as text/emoji.
    static func countryCode(for raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let scalars = Array(value.unicodeScalars)
        if scalars.count == 2 && scalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) }) {
            value = String(String.UnicodeScalarView(scalars.compactMap { UnicodeScalar($0.value - 0x1F1E6 + 65) }))
        } else if scalars.first?.value == 0x1F3F4, scalars.last?.value == 0xE007F {
            let tags = scalars.dropFirst().dropLast()
            guard !tags.isEmpty, tags.allSatisfy({ (0xE0061...0xE007A).contains($0.value) }) else { return nil }
            let tag = String(String.UnicodeScalarView(tags.compactMap { UnicodeScalar($0.value - 0xE0000) }))
            guard let subdivision = ["gbeng": "GB-ENG", "gbsct": "GB-SCT", "gbwls": "GB-WLS"][tag] else { return nil }
            value = subdivision
        }
        value = aliases[value] ?? alpha3ToAlpha2[value] ?? value
        return supportedCountryCodes.contains(value) ? value : nil
    }

    static func flagAssetName(for raw: String) -> String? {
        countryCode(for: raw).map { "Flag-" + $0 }
    }

    static func countryCode(for node: JSON) -> String? {
        ["region", "country_code", "country"].compactMap { countryCode(for: node[$0].string) }.first
    }

    private static let aliases = [
        "UK": "GB", "EL": "GR", "USA": "US", "UAE": "AE", "XKX": "XK", "KOS": "XK",
        "AC": "SH-AC", "TA": "SH-TA", "ENG": "GB-ENG", "SCT": "GB-SCT", "WLS": "GB-WLS",
        "UNITED KINGDOM": "GB", "UNITED STATES": "US", "HONG KONG": "HK", "MACAU": "MO"
    ]

    // BEGIN GENERATED COUNTRY TABLES (pinned ISO/flag sources in docs/node-identity-icons)
    static let supportedCountryCodes: Set<String> = [
        "AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR", "ARAB", "AS",
        "ASEAN", "AT", "AU", "AW", "AX", "AZ", "BA", "BB", "BD", "BE", "BF", "BG",
        "BH", "BI", "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS", "BT", "BV",
        "BW", "BY", "BZ", "CA", "CC", "CD", "CEFTA", "CF", "CG", "CH", "CI", "CK",
        "CL", "CM", "CN", "CO", "CP", "CR", "CU", "CV", "CW", "CX", "CY", "CZ",
        "DE", "DG", "DJ", "DK", "DM", "DO", "DZ", "EAC", "EC", "EE", "EG", "EH",
        "ER", "ES", "ES-CT", "ES-GA", "ES-PV", "ET", "EU", "FI", "FJ", "FK", "FM", "FO",
        "FR", "GA", "GB", "GB-ENG", "GB-NIR", "GB-SCT", "GB-WLS", "GD", "GE", "GF", "GG", "GH",
        "GI", "GL", "GM", "GN", "GP", "GQ", "GR", "GS", "GT", "GU", "GW", "GY",
        "HK", "HM", "HN", "HR", "HT", "HU", "IC", "ID", "IE", "IL", "IM", "IN",
        "IO", "IQ", "IR", "IS", "IT", "JE", "JM", "JO", "JP", "KE", "KG", "KH",
        "KI", "KM", "KN", "KP", "KR", "KW", "KY", "KZ", "LA", "LB", "LC", "LI",
        "LK", "LR", "LS", "LT", "LU", "LV", "LY", "MA", "MC", "MD", "ME", "MF",
        "MG", "MH", "MK", "ML", "MM", "MN", "MO", "MP", "MQ", "MR", "MS", "MT",
        "MU", "MV", "MW", "MX", "MY", "MZ", "NA", "NC", "NE", "NF", "NG", "NI",
        "NL", "NO", "NP", "NR", "NU", "NZ", "OM", "PA", "PC", "PE", "PF", "PG",
        "PH", "PK", "PL", "PM", "PN", "PR", "PS", "PT", "PW", "PY", "QA", "RE",
        "RO", "RS", "RU", "RW", "SA", "SB", "SC", "SD", "SE", "SG", "SH", "SH-AC",
        "SH-HL", "SH-TA", "SI", "SJ", "SK", "SL", "SM", "SN", "SO", "SR", "SS", "ST",
        "SV", "SX", "SY", "SZ", "TC", "TD", "TF", "TG", "TH", "TJ", "TK", "TL",
        "TM", "TN", "TO", "TR", "TT", "TV", "TW", "TZ", "UA", "UG", "UM", "UN",
        "US", "UY", "UZ", "VA", "VC", "VE", "VG", "VI", "VN", "VU", "WF", "WS",
        "XK", "YE", "YT", "ZA", "ZM", "ZW",
    ]

    static let alpha3ToAlpha2: [String: String] = [
        "ABW": "AW", "AFG": "AF", "AGO": "AO", "AIA": "AI", "ALA": "AX", "ALB": "AL",
        "AND": "AD", "ARE": "AE", "ARG": "AR", "ARM": "AM", "ASM": "AS", "ATA": "AQ",
        "ATF": "TF", "ATG": "AG", "AUS": "AU", "AUT": "AT", "AZE": "AZ", "BDI": "BI",
        "BEL": "BE", "BEN": "BJ", "BES": "BQ", "BFA": "BF", "BGD": "BD", "BGR": "BG",
        "BHR": "BH", "BHS": "BS", "BIH": "BA", "BLM": "BL", "BLR": "BY", "BLZ": "BZ",
        "BMU": "BM", "BOL": "BO", "BRA": "BR", "BRB": "BB", "BRN": "BN", "BTN": "BT",
        "BVT": "BV", "BWA": "BW", "CAF": "CF", "CAN": "CA", "CCK": "CC", "CHE": "CH",
        "CHL": "CL", "CHN": "CN", "CIV": "CI", "CMR": "CM", "COD": "CD", "COG": "CG",
        "COK": "CK", "COL": "CO", "COM": "KM", "CPV": "CV", "CRI": "CR", "CUB": "CU",
        "CUW": "CW", "CXR": "CX", "CYM": "KY", "CYP": "CY", "CZE": "CZ", "DEU": "DE",
        "DJI": "DJ", "DMA": "DM", "DNK": "DK", "DOM": "DO", "DZA": "DZ", "ECU": "EC",
        "EGY": "EG", "ERI": "ER", "ESH": "EH", "ESP": "ES", "EST": "EE", "ETH": "ET",
        "FIN": "FI", "FJI": "FJ", "FLK": "FK", "FRA": "FR", "FRO": "FO", "FSM": "FM",
        "GAB": "GA", "GBR": "GB", "GEO": "GE", "GGY": "GG", "GHA": "GH", "GIB": "GI",
        "GIN": "GN", "GLP": "GP", "GMB": "GM", "GNB": "GW", "GNQ": "GQ", "GRC": "GR",
        "GRD": "GD", "GRL": "GL", "GTM": "GT", "GUF": "GF", "GUM": "GU", "GUY": "GY",
        "HKG": "HK", "HMD": "HM", "HND": "HN", "HRV": "HR", "HTI": "HT", "HUN": "HU",
        "IDN": "ID", "IMN": "IM", "IND": "IN", "IOT": "IO", "IRL": "IE", "IRN": "IR",
        "IRQ": "IQ", "ISL": "IS", "ISR": "IL", "ITA": "IT", "JAM": "JM", "JEY": "JE",
        "JOR": "JO", "JPN": "JP", "KAZ": "KZ", "KEN": "KE", "KGZ": "KG", "KHM": "KH",
        "KIR": "KI", "KNA": "KN", "KOR": "KR", "KWT": "KW", "LAO": "LA", "LBN": "LB",
        "LBR": "LR", "LBY": "LY", "LCA": "LC", "LIE": "LI", "LKA": "LK", "LSO": "LS",
        "LTU": "LT", "LUX": "LU", "LVA": "LV", "MAC": "MO", "MAF": "MF", "MAR": "MA",
        "MCO": "MC", "MDA": "MD", "MDG": "MG", "MDV": "MV", "MEX": "MX", "MHL": "MH",
        "MKD": "MK", "MLI": "ML", "MLT": "MT", "MMR": "MM", "MNE": "ME", "MNG": "MN",
        "MNP": "MP", "MOZ": "MZ", "MRT": "MR", "MSR": "MS", "MTQ": "MQ", "MUS": "MU",
        "MWI": "MW", "MYS": "MY", "MYT": "YT", "NAM": "NA", "NCL": "NC", "NER": "NE",
        "NFK": "NF", "NGA": "NG", "NIC": "NI", "NIU": "NU", "NLD": "NL", "NOR": "NO",
        "NPL": "NP", "NRU": "NR", "NZL": "NZ", "OMN": "OM", "PAK": "PK", "PAN": "PA",
        "PCN": "PN", "PER": "PE", "PHL": "PH", "PLW": "PW", "PNG": "PG", "POL": "PL",
        "PRI": "PR", "PRK": "KP", "PRT": "PT", "PRY": "PY", "PSE": "PS", "PYF": "PF",
        "QAT": "QA", "REU": "RE", "ROU": "RO", "RUS": "RU", "RWA": "RW", "SAU": "SA",
        "SDN": "SD", "SEN": "SN", "SGP": "SG", "SGS": "GS", "SHN": "SH", "SJM": "SJ",
        "SLB": "SB", "SLE": "SL", "SLV": "SV", "SMR": "SM", "SOM": "SO", "SPM": "PM",
        "SRB": "RS", "SSD": "SS", "STP": "ST", "SUR": "SR", "SVK": "SK", "SVN": "SI",
        "SWE": "SE", "SWZ": "SZ", "SXM": "SX", "SYC": "SC", "SYR": "SY", "TCA": "TC",
        "TCD": "TD", "TGO": "TG", "THA": "TH", "TJK": "TJ", "TKL": "TK", "TKM": "TM",
        "TLS": "TL", "TON": "TO", "TTO": "TT", "TUN": "TN", "TUR": "TR", "TUV": "TV",
        "TWN": "TW", "TZA": "TZ", "UGA": "UG", "UKR": "UA", "UMI": "UM", "URY": "UY",
        "USA": "US", "UZB": "UZ", "VAT": "VA", "VCT": "VC", "VEN": "VE", "VGB": "VG",
        "VIR": "VI", "VNM": "VN", "VUT": "VU", "WLF": "WF", "WSM": "WS", "YEM": "YE",
        "ZAF": "ZA", "ZMB": "ZM", "ZWE": "ZW",
    ]
    // END GENERATED COUNTRY TABLES
}

/// Compact, intrinsic-width local images. No HTTP requests, no flag emoji text.
struct NodeIdentityIcons: View {
    let node: JSON
    var iconSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 6) {
            if let code = NodeIdentity.countryCode(for: node) {
                Image("Flag-" + code)
                    .renderingMode(.original).resizable().scaledToFit()
                    .frame(width: iconSize * 4 / 3, height: iconSize)
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .accessibilityLabel(Text(Locale.current.localizedString(forRegionCode: code) ?? code))
            } else {
                Image(systemName: "globe")
                    .frame(width: iconSize * 4 / 3, height: iconSize)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("未知地区"))
            }
            if let name = NodeIdentity.osAssetName(for: node) {
                Image(name)
                    .renderingMode(.original).resizable().scaledToFit()
                    .padding(2)
                    .frame(width: iconSize + 4, height: iconSize + 4)
                    .accessibilityLabel(Text(name.replacingOccurrences(of: "OS-", with: "")))
            } else {
                Image(systemName: "server.rack")
                    .frame(width: iconSize, height: iconSize)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("未知操作系统"))
            }
        }
        .font(.system(size: iconSize))
        .accessibilityElement(children: .combine)
    }
}
