import XCTest
import UIKit
import SwiftUI
@testable import KomariPanel

final class BackendTests: XCTestCase {
    @MainActor func testCompactCardRendering() throws {
        let node = JSON.object(["name": .string("布局检查 · 无指标"), "os": .string("Ubuntu"), "region": .string("US")])
        let view = RichNodeCard(node: node, status: .null, fresh: false).frame(width: 350).padding(16).background(Color(.systemGroupedBackground))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        XCTAssertLessThan(image.size.height, 320)
        let attachment = XCTAttachment(image: image)
        attachment.name = "CompactCard-MissingData"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor func testAppThemeAndPrimaryIconWithMigrationRegistrations() throws {
        XCTAssertNil(AppearanceMode.system.scheme)
        XCTAssertEqual(AppearanceMode.light.scheme, .light)
        XCTAssertEqual(AppearanceMode.dark.scheme, .dark)
        // Simulator builds are thinned for the destination device. The universal
        // device archive validates both idioms separately in the CI packaging gate.
        let key = UIDevice.current.userInterfaceIdiom == .pad ? "CFBundleIcons~ipad" : "CFBundleIcons"
        for key in [key] {
            let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: key) as? [String: Any])
            let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
            XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
            let alternatives = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any])
            XCTAssertNotNil(alternatives["AppIconDark"])
            XCTAssertNotNil(alternatives["AppIconLight"])
        }
    }
    func testExistingPanelsMigrate() throws {
        let p = try JSONDecoder().decode(Panel.self, from: Data(#"{"id":"old","name":"Old","address":"https://example.com","allowHTTP":false}"#.utf8))
        XCTAssertEqual(p.kind, .komari)
    }
    func testHexValidation() {
        XCTAssertEqual(hexRGB("#007AFF"), 0x007AFF)
        XCTAssertEqual(hexRGB("ffffff"), 0xffffff)
        XCTAssertNil(hexRGB("#abc")); XCTAssertNil(hexRGB("#GGGGGG"))
    }
    func testDStatusNormalization() throws {
        let live = try XCTUnwrap(JSON.from(#"{"order":["a"],"data":{"a":{"name":"A","stat":{"cpu":{"multi":0.12},"mem":{"virtual":{"used":100,"total":400}},"net":{"delta":{"in":1200,"out":800},"total":{"in":9000,"out":4000}},"offline":false},"traffic_stats":{"used":12300,"limit":0,"unlimited":true}}}}"#))
        let result = MonitorAPI.normalizeDStatus(live, inventory: .object(["data": .array([])]))
        XCTAssertEqual(result.nodes.count, 1)
        XCTAssertEqual(result.statuses["a"]["cpu"], .number(12))
        XCTAssertEqual(result.statuses["a"]["online"], .bool(true))
        XCTAssertEqual(result.statuses["a"]["disk"], .null)
        XCTAssertEqual(result.statuses["a"]["latency"], .null)
    }
    func testNezhaLegacyFields() throws {
        let j = try XCTUnwrap(JSON.from(#"{"result":[{"id":2,"name":"Old","last_active":1000,"host":{"MemTotal":400,"DiskTotal":800,"Platform":"ubuntu"},"status":{"CPU":5,"MemUsed":100,"NetOutSpeed":20}}]}"#))
        let result = MonitorAPI.normalizeNezha(j, legacy: true, now: Date(timeIntervalSince1970: 1005))
        XCTAssertEqual(result.nodes.first?["uuid"], .string("2"))
        XCTAssertEqual(result.statuses["2"]["ram"], .number(100))
        XCTAssertEqual(result.statuses["2"]["online"], .bool(true))
        XCTAssertEqual(result.statuses["2"]["load5"], .null)
    }
    func testNezhaCurrentFieldsAndOffline() throws {
        let j = try XCTUnwrap(JSON.from(#"{"servers":[{"id":3,"name":"New","last_active":"1970-01-01T00:16:40Z","host":{"mem_total":400},"state":{"cpu":5,"mem_used":100,"load_5":0.24}}]}"#))
        let result = MonitorAPI.normalizeNezha(j, legacy: false, now: Date(timeIntervalSince1970: 1100))
        XCTAssertEqual(result.statuses["3"]["online"], .bool(false))
        XCTAssertEqual(result.statuses["3"]["load5"], .number(0.24))
    }
    func testAuthHeadersAndAnonymousDStatus() throws {
        let legacy = try MonitorAPI(kind: .nezhaV0, address: "https://example.com/prefix", key: "test-token", allowHTTP: false)
        XCTAssertEqual(legacy.request("api/v1/server/details").value(forHTTPHeaderField: "Authorization"), "test-token")
        let current = try MonitorAPI(kind: .nezha, address: "https://example.com/prefix", key: "test-token", allowHTTP: false)
        XCTAssertEqual(current.request("api/v1/server").value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        XCTAssertEqual(current.request("api/v1/server").url?.path, "/prefix/api/v1/server")
        let publicAPI = try MonitorAPI(kind: .dstatus, address: "https://example.com", key: "ignored-token", allowHTTP: false)
        XCTAssertNil(publicAPI.request("api/servers").value(forHTTPHeaderField: "Authorization"))
        XCTAssertThrowsError(try MonitorAPI(kind: .nezha, address: "http://example.com", key: "test-token", allowHTTP: false))
    }
}
