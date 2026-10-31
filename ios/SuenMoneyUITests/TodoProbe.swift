import XCTest

/// 验证：待办条展开后每条都有「忽略」+「处理/入账」两个按钮
final class TodoProbe: XCTestCase {
    func testTodoButtons() throws {
        let app = XCUIApplication()
        app.launch()
        let hero = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "本月支出")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 25))

        // 展开待办条
        let bar = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "笔待处理")).firstMatch
        if bar.exists { bar.tap(); sleep(1) }

        let all = app.buttons.allElementsBoundByIndex.map { $0.label }
        print("PROBE_BUTTONS=\(all)")
        XCTAssertTrue(all.contains("忽略"), "应有「忽略」按钮")
        XCTAssertTrue(all.contains("处理") || all.contains("入账"), "应有「处理/入账」按钮")

        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ios-todo-open.png"))
    }
}
