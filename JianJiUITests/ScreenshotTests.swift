import XCTest

/// README 截图采集:在模拟器中遍历各页面并导出 PNG 附件。
/// 运行:
///   xcodebuild test -project JianJi.xcodeproj -scheme JianJi \
///     -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
///     -only-testing:JianJiUITests -resultBundlePath /tmp/shots.xcresult
/// 导出:
///   xcrun xcresulttool export attachments --path /tmp/shots.xcresult --output-path docs/screenshots
final class ScreenshotTests: XCTestCase {

    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCaptureAppScreens() throws {
        app.launch()
        XCTAssertTrue(app.buttons["记一笔"].waitForExistence(timeout: 20), "未能进入首页")

        capture("01-home")
        tapTab("统计");  capture("02-statistics")
        tapTab("账单");  capture("03-bills")
        tapTab("我的");  capture("04-profile")
        tapTab("首页")

        app.buttons["记一笔"].tap()
        XCTAssertTrue(app.buttons["完成"].waitForExistence(timeout: 10), "记一笔面板未打开")
        settle()
        capture("05-add-transaction")
        app.buttons["完成"].tap()
    }

    private func tapTab(_ label: String) {
        app.buttons[label].tap()
        settle()
    }

    private func settle() {
        runloop(1.2)
    }

    private func runloop(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(
            uniformTypeIdentifier: "public.png",
            name: "\(name).png",
            payload: screenshot.pngRepresentation,
            userInfo: nil
        )
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
