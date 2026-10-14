import XCTest

/// 手表各页面截图（演示数据）
final class WatchScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testScreenshots() {
        snap("w01-今日")

        tap(app.buttons["提醒"])
        snap("w02-提醒状态")
        app.swipeUp()
        snap("w03-提醒状态-下方")
        back()

        tap(app.staticTexts["散步20分钟"])
        snap("w04-习惯")
        back()

        tap(app.staticTexts["身体维护训练"])
        snap("w05-训练-第一组")
        tap(app.buttons["完成本组"])
        snap("w06-组间休息")
        tap(app.buttons["跳过休息"])
        snap("w07-训练-第二组")
        tap(app.buttons["结束并保存"])
        snap("w08-训练结束")
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let target = element.firstMatch
        if target.waitForExistence(timeout: 5) {
            target.tap()
        } else {
            XCTFail("找不到 \(element)", file: file, line: line)
        }
    }

    private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.waitForExistence(timeout: 3) { button.tap() } else { app.swipeRight() }
    }

    private func snap(_ name: String) {
        sleep(1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
