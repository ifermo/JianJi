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

    /// 语音链路截图:通过 DEBUG 启动参数呈现浮层与确认单,不依赖麦克风。
    @MainActor
    func testCaptureVoiceScreens() throws {
        app.launchArguments = ["-VoiceDemoOverlay"]
        app.launch()
        XCTAssertTrue(app.staticTexts["正在聆听"].waitForExistence(timeout: 20)
            || app.buttons["取消"].waitForExistence(timeout: 5), "语音浮层未出现")
        settle()
        capture("06-voice-listening")

        app.launchArguments = ["-VoiceDemoConfirm"]
        app.launch()
        XCTAssertTrue(app.buttons["确认入账"].waitForExistence(timeout: 20), "语音确认单未出现")
        settle()
        capture("07-voice-confirm")
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
