import XCTest

/// 冒烟测试：驱动真实 UI 跑通五个屏，截图写到 /tmp。
/// 每个 test 重新 launch —— 令牌在 Keychain，重启后仍登录；当前屏是 @State（初始流水页）。
final class LoginSmokeTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/ios-\(name).png"))
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    private func waitLedger() -> Bool {
        app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "本月支出"))
            .firstMatch.waitForExistence(timeout: 25)
    }

    func test01_login() throws {
        if waitLedger() { snap("02-ledger"); return }

        XCTAssertTrue(app.staticTexts["SuenMoney"].waitForExistence(timeout: 15))
        snap("01-login")

        let user = app.textFields["login.username"]
        XCTAssertTrue(user.waitForExistence(timeout: 5), "登录名框\n\(app.debugDescription)")
        user.tap()
        user.typeText("suen")

        let pwd = app.secureTextFields["login.password"]
        XCTAssertTrue(pwd.waitForExistence(timeout: 5), "口令框\n\(app.debugDescription)")
        pwd.tap()
        pwd.typeText("suenmoney2026")
        snap("01b-filled")

        // 键盘回车提交（登录按钮可能被键盘遮住，不点它）
        pwd.typeText("\n")

        if waitLedger() {
            snap("02-ledger")
        } else {
            sleep(2)
            snap("01c-after-login")
            XCTFail("登录后未进入流水页\n\(app.debugDescription)")
        }
    }

    func test02_dashboard() throws {
        guard waitLedger() else { throw XCTSkip("未登录") }
        app.buttons.matching(NSPredicate(format: "label == %@", "概况")).firstMatch.tap()
        sleep(3); snap("03-dashboard")
    }

    func test03_report() throws {
        guard waitLedger() else { throw XCTSkip("未登录") }
        app.buttons.matching(NSPredicate(format: "label == %@", "报表")).firstMatch.tap()
        sleep(3); snap("04-report")
    }

    func test04_settings() throws {
        guard waitLedger() else { throw XCTSkip("未登录") }
        app.buttons.matching(NSPredicate(format: "label == %@", "设置")).firstMatch.tap()
        sleep(3); snap("05-settings")
    }

    func test05_expense_sheet() throws {
        guard waitLedger() else { throw XCTSkip("未登录") }
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.78))
        start.press(forDuration: 0.12, thenDragTo: end)
        sleep(2); snap("06-sheet")
    }
}

// MARK: - 主题与质感
extension LoginSmokeTests {
    /// 切到浅色（candy）主题并截图 —— candy 的「贴纸硬阴影」是最容易做丢的质感
    func test06_candy_theme() throws {
        guard waitLedger() else { throw XCTSkip("未登录") }
        app.buttons.matching(NSPredicate(format: "label == %@", "设置")).firstMatch.tap()
        sleep(2)
        // 主题在「设备」tab 下
        app.buttons.matching(NSPredicate(format: "label == %@", "设备")).firstMatch.tap()
        sleep(2)
        let light = app.buttons.matching(NSPredicate(format: "label == %@", "水果硬糖")).firstMatch
        XCTAssertTrue(light.waitForExistence(timeout: 5), "设置页应有主题三 pill（水果硬糖/赛博朋克/跟随系统）")
        light.tap()
        sleep(2)
        snap("07-candy-settings")
        app.buttons.matching(NSPredicate(format: "label == %@", "账目")).firstMatch.tap()
        sleep(1)
        // 回流水
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        sleep(2)
        snap("08-candy-ledger")
    }
}
