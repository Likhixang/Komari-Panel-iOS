import XCTest
@testable import KomariPanel

final class DashboardPreferencesTests: XCTestCase {
    private let nodes: [JSON] = [
        .object(["uuid": .string("b"), "name": .string("Beta")]),
        .object(["uuid": .string("a"), "name": .string("Alpha")]),
        .object(["uuid": .string("c"), "name": .string("Gamma")])
    ]
    private func ids(_ preferences: DashboardPreferences) -> [String] {
        preferences.visibleNodes(nodes).map { $0["uuid"].string }
    }
    func testDefaultOrderAndLocalHidingPreserveServerMetadata() {
        var preferences = DashboardPreferences()
        XCTAssertEqual(ids(preferences), ["b", "a", "c"])
        preferences.hiddenNodeIDs = ["b"]
        XCTAssertEqual(ids(preferences), ["a", "c"])
        XCTAssertEqual(nodes[0]["hidden"], .null)
        preferences.hiddenNodeIDs = []
        XCTAssertEqual(ids(preferences), ["b", "a", "c"])
    }
    func testManualOrderSurvivesHideAndRestore() {
        var preferences = DashboardPreferences()
        preferences.orderedNodeIDs = ["c", "b", "a"]
        XCTAssertEqual(ids(preferences), ["c", "b", "a"])
        preferences.hiddenNodeIDs = ["b"]
        XCTAssertEqual(ids(preferences), ["c", "a"])
        preferences.hiddenNodeIDs = []
        XCTAssertEqual(ids(preferences), ["c", "b", "a"])
    }
    func testNewNodesAppendAndStaleOrDuplicateIDsAreSafe() {
        var preferences = DashboardPreferences()
        preferences.orderedNodeIDs = ["gone", "c", "c"]
        XCTAssertEqual(ids(preferences), ["c", "b", "a"])
    }
    func testLegacyPreferencesKeepHiddenNodes() throws {
        let old = Data(#"{"sortOrder":"latency","hiddenNodeIDs":["b"]}"#.utf8)
        let decoded = try JSONDecoder().decode(DashboardPreferences.self, from: old)
        XCTAssertEqual(decoded.hiddenNodeIDs, ["b"])
        XCTAssertEqual(decoded.orderedNodeIDs, [])
        XCTAssertEqual(ids(decoded), ["a", "c"])
    }
    func testPreferencesRoundTripAndPanelIsolation() throws {
        var first = DashboardPreferences()
        first.orderedNodeIDs = ["c", "b", "a"]
        first.hiddenNodeIDs = ["b"]
        let saved = ["panel-one": first, "panel-two": DashboardPreferences()]
        let decoded = try JSONDecoder().decode([String: DashboardPreferences].self,
                                               from: JSONEncoder().encode(saved))
        XCTAssertEqual(decoded["panel-one"]?.hiddenNodeIDs, ["b"])
        XCTAssertEqual(decoded["panel-one"]?.orderedNodeIDs, ["c", "b", "a"])
        XCTAssertEqual(decoded["panel-two"]?.hiddenNodeIDs, [])
        XCTAssertEqual(decoded["panel-two"]?.orderedNodeIDs, [])
    }
}
