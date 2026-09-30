import XCTest
import Foundation
@testable import KomariPanel

final class LocalizationTests: XCTestCase {
    private let languages = ["zh-Hans", "en", "zh-Hant", "ja", "ko"]

    private func languageBundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), "Missing bundled language: \(language)")
        return try XCTUnwrap(Bundle(path: path))
    }

    func testAllFiveBundledCatalogsHaveIdenticalNonemptyKeys() throws {
        var reference: Set<String>?
        for language in languages {
            let bundle = try languageBundle(language)
            let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
            let data = try Data(contentsOf: url)
            let catalog = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String])
            XCTAssertFalse(catalog.isEmpty, language)
            XCTAssertTrue(catalog.values.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, language)
            let keys = Set(catalog.keys)
            if let reference { XCTAssertEqual(keys, reference, language) }
            else { reference = keys }
            for key in ["服务器响应超时。", "哪吒 V1", "跟随系统", "不限额", "超时", "是", "否", "许可文件未能读取"] {
                XCTAssertTrue(keys.contains(key), "\(language): \(key)")
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                if language == "en" { XCTAssertNotEqual(value, key, "English fell back to source: \(key)") }
            }
        }
    }

    func testInterpolationsResolveUsingRealLanguageBundles() throws {
        for language in languages {
            let bundle = try languageBundle(language)
            let count = 7
            let name = "server-value-%@-节点"
            let countKey = "选择节点（%lld）"
            let countFormat = bundle.localizedString(forKey: countKey, value: nil, table: nil)
            XCTAssertNotEqual(bundle.localizedString(forKey: countKey, value: "__missing__", table: nil), "__missing__", language)
            XCTAssertEqual(String(localized: "选择节点（\(count)）", bundle: bundle),
                           String(format: countFormat, Int64(count)), language)
            let nameKey = "新增%@"
            let nameFormat = bundle.localizedString(forKey: nameKey, value: nil, table: nil)
            let rendered = String(localized: "新增\(name)", bundle: bundle)
            XCTAssertEqual(rendered, String(format: nameFormat, name), language)
            XCTAssertTrue(rendered.contains(name), "Interpolated server data must stay verbatim")
        }
    }

    func testRuntimeErrorAndTitlePathsUseMainBundle() {
        XCTAssertEqual(KomariAPIError.timedOut.errorDescription, NSLocalizedString("服务器响应超时。", comment: ""))
        XCTAssertEqual(KomariAPIError.httpStatus(401).errorDescription,
                       String(format: NSLocalizedString("服务器返回 HTTP %lld.", comment: ""), Int64(401)))
        XCTAssertEqual(KomariAPIError.rpc(-32601).errorDescription,
                       String(format: NSLocalizedString("RPC 请求失败（错误码 %lld).", comment: ""), Int64(-32601)))
        XCTAssertEqual(KeychainError(status: -50).errorDescription,
                       String(localized: "安全凭据存储失败（错误码 \(Int(-50)))."))
        XCTAssertEqual(BackendKind.nezha.title, NSLocalizedString("哪吒 V1", comment: ""))
        XCTAssertEqual(AppearanceMode.system.title, NSLocalizedString("跟随系统", comment: ""))
        XCTAssertEqual(AppearanceMode.light.title, NSLocalizedString("浅色", comment: ""))
        XCTAssertEqual(AppearanceMode.dark.title, NSLocalizedString("深色", comment: ""))
    }
}
