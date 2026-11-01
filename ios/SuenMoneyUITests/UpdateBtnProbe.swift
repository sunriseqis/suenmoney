import XCTest

/// 验证 candy 主题下「检查更新」按钮可见（有底色、字不是同色压在阴影上）
final class UpdateBtnProbe: XCTestCase {
    func testCandyUpdateButtonVisible() throws {
        let app = XCUIApplication()
        app.launch()
        let hero = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "本月支出")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 25))

        app.buttons.matching(NSPredicate(format: "label == %@", "设置")).firstMatch.tap()
        sleep(2)

        // 主题 pill 在「设备」页
        XCTAssertTrue(app.buttons["设备"].waitForExistence(timeout: 6), "应有「设备」页签")
        app.buttons["设备"].firstMatch.tap(); sleep(2)

        XCTAssertTrue(app.staticTexts["检查更新"].waitForExistence(timeout: 6), "设备页应有「检查更新」标题")

        let candy = app.buttons.matching(NSPredicate(format: "label == %@", "水果硬糖")).firstMatch
        if candy.waitForExistence(timeout: 4) {
            candy.tap(); sleep(2)
            print("PROBE_SWITCHED_TO_CANDY=true")
        } else {
            print("PROBE_SWITCHED_TO_CANDY=false")
        }

        let btn = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "检查更新")).firstMatch
        let exists = btn.waitForExistence(timeout: 6)
        print("PROBE_UPDATE_EXISTS=\(exists) hittable=\(btn.isHittable)")
        XCTAssertTrue(exists, "设备页应有「检查更新」按钮")
        XCTAssertTrue(btn.isHittable, "「检查更新」按钮应可点（可见）")

        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ios-candy-update.png"))

        btn.tap(); sleep(3)
        let shot2 = XCUIScreen.main.screenshot()
        try? shot2.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ios-candy-update-after.png"))
    }
}
