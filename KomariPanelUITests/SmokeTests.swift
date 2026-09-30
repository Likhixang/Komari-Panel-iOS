import XCTest
final class SmokeTests: XCTestCase {
    private func fixtureApp(reduceMotion: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-panels", "[]", "-selectedPanel", "ui-test-panel-\(UUID().uuidString)",
                                "--ui-test-node-expansion", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        if reduceMotion { app.launchArguments.append("--ui-test-reduce-motion") }
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func verifyExpansionAndReturn(reduceMotion: Bool) {
        let app = fixtureApp(reduceMotion: reduceMotion)
        let card = app.buttons["nodeCard-ui-test-4"]
        XCTAssertTrue(app.buttons["dashboardSort"].waitForExistence(timeout: 15))
        for _ in 0..<12 {
            if card.isHittable && card.frame.maxY < app.tabBars.firstMatch.frame.minY - 8 { break }
            app.scrollViews.firstMatch.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(card.isHittable)
        let sourceFrame = card.frame
        for _ in 0..<3 {
            card.tap()
            let detail = app.scrollViews["nodeDetailScroll"]
            XCTAssertTrue(detail.waitForExistence(timeout: 5))
            XCTAssertEqual(detail.scrollViews.count, 0, "Detail must have one scroll owner")
            capture(app, reduceMotion ? "ReducedMotion-Expanded" : "Zoom-Expanded")
            detail.swipeUp()
            XCTAssertTrue(detail.exists, "Scrolling must not dismiss the node")
            detail.swipeDown(velocity: .slow)
            XCTAssertTrue(detail.exists, "Scrolling back toward the top must not dismiss the node")
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            XCTAssertTrue(card.isHittable)
            XCTAssertEqual(card.frame.minY, sourceFrame.minY, accuracy: 3)
            XCTAssertFalse(detail.exists)
        }
        capture(app, "Zoom-Scroll-Restored")
    }

    func testNodeExpansionAndScrollRestoration() { verifyExpansionAndReturn(reduceMotion: false) }
    func testNodeExpansionWithReducedMotion() { verifyExpansionAndReturn(reduceMotion: true) }

    func testNodeNativeInteractiveReturn() {
        let app = fixtureApp()
        let card = app.buttons["nodeCard-ui-test-2"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.tap()
        let detail = app.scrollViews["nodeDetailScroll"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        // Native edge gesture, not a DragGesture covering the entire ScrollView.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.55))
        let cancelledEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.14, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: cancelledEnd, withVelocity: .slow, thenHoldForDuration: 0.5)
        XCTAssertTrue(detail.exists, "A cancelled interactive return must keep the detail visible")
        capture(app, "Zoom-Interactive-Cancelled")
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["dashboardSort"].waitForExistence(timeout: 5))
        XCTAssertTrue(card.isHittable)
        capture(app, "Zoom-Interactive-Returned")
    }

    func testReadmeScreenshots() {
        for language in ["zh-Hans", "en"] {
            let app = XCUIApplication()
            app.launchArguments += ["-panels", "[]", "-selectedPanel", "ui-test-readme",
                                    "--ui-test-node-expansion", "-AppleLanguages", "(\(language))",
                                    "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                                    "-appAppearance", "light"]
            app.launch()
            let card = app.buttons["nodeCard-ui-test-2"]
            XCTAssertTrue(card.waitForExistence(timeout: 15))
            XCTAssertTrue(app.navigationBars[language == "en" ? "Overview" : "总览"].exists)
            capture(app, "README-\(language)-overview")
            card.tap()
            XCTAssertTrue(app.scrollViews["nodeDetailScroll"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts[language == "en" ? "Traffic Quota" : "流量配额"].exists)
            capture(app, "README-\(language)-detail")
            app.terminate()
        }
    }

    func testNodeExpansionDismissesSearchKeyboard() {
        let app = fixtureApp()
        let search = app.textFields["dashboardSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.tap()
        search.typeText("节点 4")
        let card = app.buttons["nodeCard-ui-test-4"]
        if !card.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(card.isHittable)
        card.tap()
        XCTAssertTrue(app.scrollViews["nodeDetailScroll"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "节点 4")
    }

    func testDashboardSortHideAndRestore() {
        let app = fixtureApp()
        XCTAssertTrue(app.buttons["dashboardSort"].waitForExistence(timeout: 15))
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nodeCard-"))
        XCTAssertEqual(cards.element(boundBy: 0).identifier, "nodeCard-ui-test-2")
        app.buttons["dashboardSort"].tap()
        let firstRow = app.cells.containing(.staticText, identifier: "sortNode-ui-test-2").firstMatch
        let secondRow = app.cells.containing(.staticText, identifier: "sortNode-ui-test-1").firstMatch
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        XCTAssertTrue(secondRow.exists)
        secondRow.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
            .press(forDuration: 0.8, thenDragTo: firstRow.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.15)))
        capture(app, "Custom-Node-Order")
        app.buttons["doneOrderingNodes"].tap()
        XCTAssertEqual(cards.element(boundBy: 0).identifier, "nodeCard-ui-test-1")
        app.buttons["dashboardHiddenNodes"].tap()
        let hidden = app.switches["hideNode-ui-test-1"]
        XCTAssertTrue(hidden.waitForExistence(timeout: 5))
        // SwiftUI exposes this labeled Toggle as a full-width switch element.
        // Its center is the row label, not the trailing UISwitch hit target.
        XCTAssertTrue(hidden.isHittable)
        hidden.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        let isHidden = NSPredicate(format: "value == %@", "1")
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: isHidden, object: hidden)], timeout: 5) == .completed)
        XCTAssertEqual(hidden.value as? String, "1")
        app.buttons["doneHidingNodes"].tap()
        XCTAssertFalse(app.buttons["nodeCard-ui-test-1"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["dashboardHiddenNodes"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["nodeCard-ui-test-1"].exists)
        app.buttons["dashboardHiddenNodes"].tap()
        XCTAssertEqual(hidden.value as? String, "1")
        app.buttons["restoreAllNodes"].tap()
        XCTAssertEqual(hidden.value as? String, "0")
        app.buttons["doneHidingNodes"].tap()
        XCTAssertTrue(app.buttons["nodeCard-ui-test-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(cards.element(boundBy: 0).identifier, "nodeCard-ui-test-1")
        capture(app, "Sort-Hide-Restored")
    }
    func testEmptyDashboardSearchAndFilterSurviveTabSwitch() throws {
        let app = XCUIApplication()
        // Argument-domain defaults isolate this test from saved connections;
        // no production fixture or fabricated monitoring data is installed.
        app.launchArguments += ["-panels", "[]", "-selectedPanel", ""]
        app.launch()
        let search = app.textFields["dashboardSearch"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["collapseNode"].exists)
        search.tap()
        search.typeText("no-such-node\n")
        XCTAssertTrue(app.staticTexts["添加你的第一个面板"].exists)
        let filter = app.buttons["dashboardOnlineFilter"]
        filter.tap()
        XCTAssertTrue(filter.label.contains("仅看在线"))
        app.tabBars.buttons["面板"].tap()
        XCTAssertTrue(app.buttons["addPanel"].waitForExistence(timeout: 5))
        app.tabBars.buttons["总览"].tap()
        XCTAssertEqual(search.value as? String, "no-such-node")
        XCTAssertTrue(filter.label.contains("仅看在线"))
        app.buttons["clearDashboardSearch"].tap()
        XCTAssertEqual(search.value as? String, "搜索节点名、分组或 IP")
        XCTAssertFalse(app.buttons["collapseNode"].exists)
    }
    private func dismissIconConfirmation(in app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) { alert.buttons.firstMatch.tap() }
        else if app.alerts.firstMatch.exists { app.alerts.firstMatch.buttons.firstMatch.tap() }
    }

    func testCustomAccentAndAbout() throws {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Icon changed") { alert in
            if alert.buttons.firstMatch.exists { alert.buttons.firstMatch.tap(); return true }; return false
        }
        app.launch()
        app.tabBars.buttons["面板"].tap()
        app.buttons["外观"].tap()
        XCTAssertFalse(app.buttons["恢复 iOS 蓝"].exists)
        XCTAssertTrue(app.segmentedControls["appAppearance"].exists)
        XCTAssertFalse(app.segmentedControls["iconAppearance"].exists)
        app.segmentedControls["appAppearance"].buttons["深色"].tap()
        XCTAssertTrue(app.segmentedControls["appAppearance"].buttons["深色"].isSelected)
        app.segmentedControls["appAppearance"].buttons["浅色"].tap()
        XCTAssertTrue(app.segmentedControls["appAppearance"].buttons["浅色"].isSelected)
        app.segmentedControls["appAppearance"].buttons["跟随系统"].tap()
        app.buttons["customAccent"].tap()
        XCTAssertTrue(app.otherElements["accentColorPicker"].exists || app.buttons["accentColorPicker"].exists)
        let input = app.textFields["accentHexInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.press(forDuration: 1.2)
        if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap() }
        else if app.menuItems["全选"].exists { app.menuItems["全选"].tap() }
        else { input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 7)) }
        input.typeText("#FF8800")
        app.buttons["saveCustomAccent"].tap()
        XCTAssertFalse(app.textFields["accentHexInput"].exists)
        app.buttons["customAccent"].tap()
        XCTAssertEqual(app.textFields["accentHexInput"].value as? String, "#FF8800")
        app.buttons["取消"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["关于"].tap()
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "以上为对接项目")).firstMatch.exists)
    }
    func testZHomeScreenAutomaticIconEvidence() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-panels", "[]", "-selectedPanel", ""]
        app.launch()
        XCTAssertTrue(app.buttons["dashboardSort"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["iconMigrationError"].exists)
        app.terminate()
        XCTAssertEqual(app.state, .notRunning)
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icon = springboard.icons["Monitor Panel"].firstMatch
        for _ in 0..<4 {
            if icon.exists && icon.isHittable { break }
            springboard.swipeLeft()
        }
        XCTAssertTrue(icon.waitForExistence(timeout: 5))
        guard icon.isHittable else {
            capture(springboard, "Home-Icon-Not-Visible")
            XCTFail("Monitor Panel must be on a visible Home Screen page")
            return
        }
        icon.press(forDuration: 1.5)
        func tapSystemControl(_ names: [String]) {
            let predicate = NSPredicate(format: "label IN %@", names)
            let control = springboard.descendants(matching: .any).matching(predicate).firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), names.joined(separator: "/"))
            control.tap()
        }
        tapSystemControl(["Edit Home Screen", "编辑主屏幕"])
        tapSystemControl(["Edit", "编辑"])
        tapSystemControl(["Customize", "自定", "自定义"])
        tapSystemControl(["Automatic", "Auto", "自动"])
        capture(springboard, "Home-Automatic-Selected")
        // Dismiss the customization sheet without launching the app.
        springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)).tap()
        XCUIDevice.shared.press(.home)
        XCTAssertEqual(app.state, .notRunning)
        XCTAssertTrue(icon.isHittable)
        let frame = icon.frame
        let screen = springboard.frame
        let metadata: [String: Double] = ["x": frame.minX, "y": frame.minY,
            "width": frame.width, "height": frame.height,
            "screenWidth": screen.width, "screenHeight": screen.height]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "Home-Icon-Frame"
        attachment.lifetime = .keepAlways
        add(attachment)
        capture(springboard, "Home-App-Terminated")
    }

    func testFirstLaunchAndPanelForm() throws {
        let app = XCUIApplication()
        addUIInterruptionMonitor(withDescription: "Icon changed") { alert in
            if alert.buttons.firstMatch.exists { alert.buttons.firstMatch.tap(); return true }; return false
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["面板"].waitForExistence(timeout: 15))
        app.tabBars.buttons["面板"].tap()
        XCTAssertTrue(app.buttons["addPanel"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Panels-Liquid-Glass"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["addPanel"].tap()
        XCTAssertTrue(app.secureTextFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["验证并保存"].isEnabled == false)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["addPanel"].waitForExistence(timeout: 5))
    }
}
