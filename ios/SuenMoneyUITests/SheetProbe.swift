import XCTest

/// 验证：下拉手势能打开记账抽屉；抽屉高度贴合内容
final class SheetProbe: XCTestCase {
    func testPullToOpen() throws {
        let app = XCUIApplication()
        app.launch()
        let hero = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "本月支出")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 25))

        // 从屏幕上部往下拖（模拟下拉记账）
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.15, thenDragTo: end)
        sleep(2)

        let opened = app.staticTexts["记一笔"].waitForExistence(timeout: 6)
        print("PROBE_SHEET_OPEN=\(opened)")
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ios-sheet-probe.png"))
        XCTAssertTrue(opened, "下拉应打开记账抽屉")
    }
}
