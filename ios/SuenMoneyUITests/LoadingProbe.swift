import XCTest

/// 回归测试：切档位 / 翻期后 loading 必须复位，列表不能永久停在「加载中…」
final class LoadingProbe: XCTestCase {
    func testLoadingResetsAfterTierSwitch() throws {
        let app = XCUIApplication()
        app.launch()
        let hero = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "本月支出")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 25))
        sleep(2)

        // 高级区默认收起（鸿蒙同），先点搜索框展开
        let search = app.textFields.firstMatch
        if search.exists { search.tap(); sleep(1) }

        // ① 切到「按年」
        XCTAssertTrue(app.buttons["按年"].waitForExistence(timeout: 5), "展开后应有「按年」")
        app.buttons["按年"].firstMatch.tap(); sleep(3)
        var stillLoading = app.staticTexts["加载中…"].exists
        print("PROBE_YEAR_STUCK=\(stillLoading)")
        XCTAssertFalse(stillLoading, "切到按年后不应卡在加载中")

        // ② 切回「按月」—— 关键验证点
        app.buttons["按月"].firstMatch.tap(); sleep(3)
        stillLoading = app.staticTexts["加载中…"].exists
        print("PROBE_BACK_TO_MONTH_STUCK=\(stillLoading)")
        XCTAssertFalse(stillLoading, "切回按月后不应卡在加载中")

        // ③ 列表要真的有数据（不是只剩空态）
        let hasRows = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "合计")
        ).firstMatch.exists
        print("PROBE_HAS_ROWS=\(hasRows)")
        XCTAssertTrue(hasRows, "切回按月后应有列表内容")

        // ④ 翻期也要能恢复
        app.buttons.matching(NSPredicate(format: "label == %@", "‹")).firstMatch.tap(); sleep(3)
        stillLoading = app.staticTexts["加载中…"].exists
        print("PROBE_PREV_MONTH_STUCK=\(stillLoading)")
        XCTAssertFalse(stillLoading, "翻到上月后不应卡在加载中")

        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ios-loading-final.png"))
    }
}
