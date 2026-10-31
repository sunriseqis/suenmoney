import XCTest

/// 验证设置页补齐的三个模块：分类图标/颜色选择器、新建计划、服务器地址编辑
final class SettingsProbe: XCTestCase {
    func testSettingsModules() throws {
        let app = XCUIApplication()
        app.launch()
        let hero = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "本月支出")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 25))
        app.buttons.matching(NSPredicate(format: "label == %@", "设置")).firstMatch.tap()
        sleep(3)

        // ① 分类管理：rail 一级 + 二级列表 + 新增类别
        XCTAssertTrue(app.staticTexts["分类管理"].exists, "应有分类管理卡")
        XCTAssertTrue(app.buttons["新增类别"].exists, "应有「新增类别」")
        let shot1 = XCUIScreen.main.screenshot()
        try? shot1.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ios-settings-cat.png"))

        // ② 打开新增类别 → 图标/颜色选择器
        app.buttons["新增类别"].tap(); sleep(2)
        let icons = app.images.allElementsBoundByIndex.count
        print("PROBE_SHEET_IMAGES=\(icons)")
        let shot2 = XCUIScreen.main.screenshot()
        try? shot2.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ios-settings-form.png"))
        app.buttons["取消"].firstMatch.tap(); sleep(1)

        // ③ 计划与还款 → 新建计划
        app.buttons["计划与还款"].firstMatch.tap(); sleep(2)
        let newPlan = app.buttons["新建计划"].firstMatch
        XCTAssertTrue(newPlan.waitForExistence(timeout: 5), "应有「新建计划」")
        newPlan.tap(); sleep(2)
        let planShot = XCUIScreen.main.screenshot()
        try? planShot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ios-settings-plan.png"))
        print("PROBE_PLAN_SHEET=\(app.staticTexts["新建计划"].exists)")
        app.buttons["取消"].firstMatch.tap(); sleep(1)

        // ④ 设备 → 服务器卡
        app.buttons["设备"].firstMatch.tap(); sleep(2)
        XCTAssertTrue(app.staticTexts["服务器"].exists, "应有服务器卡")
        let shot3 = XCUIScreen.main.screenshot()
        try? shot3.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ios-settings-device.png"))
    }
}
