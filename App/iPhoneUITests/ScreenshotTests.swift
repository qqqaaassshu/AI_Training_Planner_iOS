import XCTest

/// 依次打开各页面并截图（演示数据）。截图由 CI 导出为构建产物。
/// 找不到某个元素时记录失败但继续，尽量多截几张。
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testScreenshots() {
        snap("01-今日")

        tap(app.staticTexts["身体维护训练"])
        snap("02-任务详情")
        app.swipeUp()
        snap("03-任务详情-下方")
        back()

        tap(app.tabBars.buttons["记录"])
        snap("04-记录")

        tap(app.tabBars.buttons["计划"])
        snap("05-计划")
        tap(app.buttons["版本"])
        snap("06-版本历史")
        tap(app.staticTexts["V1"])
        snap("07-版本详情")
        back()
        back()

        tap(app.buttons["导入"])
        tap(app.buttons["载入示例"])
        dragUp()
        snap("08-导入预览")
        tap(app.buttons["取消"])

        tap(app.tabBars.buttons["AI"])
        snap("09-AI")
        // “每周复盘”也是分析类型选择器里的选项，点分析摘要进入详情
        tap(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "近 7 天完成")))
        snap("10-分析详情")
        dragUp()
        snap("11-分析详情-建议")
        back()

        tap(app.buttons["AI 设置"])
        snap("12-AI设置")
        back()
        tap(app.buttons["个人档案"])
        snap("13-个人档案")
    }

    private func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let target = element.firstMatch
        if target.waitForExistence(timeout: 5) {
            target.tap()
        } else {
            XCTFail("找不到 \(element)", file: file, line: line)
        }
    }

    /// 从屏幕下方往上拖（避开顶部的文本框）
    private func dragUp() {
        let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25)))
    }

    private func back() {
        let button = app.navigationBars.buttons.element(boundBy: 0)
        if button.waitForExistence(timeout: 3) { button.tap() }
    }

    private func snap(_ name: String) {
        sleep(1)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
