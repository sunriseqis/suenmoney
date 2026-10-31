import XCTest

/// 验证：分期只在信用卡时出现；切到现金后自动清除分期
/// 注意：分期控件已从标题行 chip 改为表单内 Toggle 行「分期付款」
final class InstallmentProbe: XCTestCase {
    func testInstallmentOnlyForCredit() throws {
        let app = XCUIApplication()
        app.launch()
        let hero = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "本月支出")).firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 25))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
            .press(forDuration: 0.15, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.staticTexts["记一笔"].waitForExistence(timeout: 8))

        // ① 现金 → 不应有「分期付款」行
        sleep(1)
        var hasInstallment = app.staticTexts["分期付款"].exists
        print("PROBE_CASH_HAS_INSTALLMENT=\(hasInstallment)")
        XCTAssertFalse(hasInstallment, "现金支付时不应出现「分期付款」")

        // ② 切信用卡（左列「招行」）
        let credit = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "招行")).firstMatch
        if credit.exists {
            credit.tap(); sleep(1)
            hasInstallment = app.staticTexts["分期付款"].exists
            print("PROBE_CREDIT_HAS_INSTALLMENT=\(hasInstallment)")
            XCTAssertTrue(hasInstallment, "信用卡应出现「分期付款」")

            // ③ 打开分期 Toggle
            let toggles = app.switches.allElementsBoundByIndex
            print("PROBE_TOGGLE_COUNT=\(toggles.count)")
            if let t = toggles.first {
                t.tap(); sleep(1)
                // 期数 chips 应出现在分期行下方
                print("PROBE_PERIOD_CHIP=\(app.buttons["3 期"].exists)")
                XCTAssertTrue(app.buttons["3 期"].exists, "开分期后应出现期数 chips")
            }

            // ④ 切回现金 → 分期行应消失
            let cash = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "现金")).firstMatch
            if cash.exists {
                cash.tap(); sleep(1)
                let stillHas = app.staticTexts["分期付款"].exists
                print("PROBE_BACK_TO_CASH_HAS_INSTALLMENT=\(stillHas)")
                XCTAssertFalse(stillHas, "切回现金后「分期付款」应消失")
            }
        }
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ios-inst-final.png"))
    }
}
