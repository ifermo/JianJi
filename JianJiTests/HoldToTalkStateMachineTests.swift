import XCTest
@testable import JianJi

final class HoldToTalkStateMachineTests: XCTestCase {
    func testTapOpensManual() {
        var machine = HoldToTalkStateMachine()
        XCTAssertEqual(machine.handle(.pressBegan), .none)
        XCTAssertEqual(machine.phase, .pressing)
        XCTAssertEqual(machine.handle(.released), .openManual)
        XCTAssertEqual(machine.phase, .idle)
    }

    func testHoldStartsAndStopsCapture() {
        var machine = HoldToTalkStateMachine()
        _ = machine.handle(.pressBegan)
        XCTAssertEqual(machine.handle(.thresholdReached), .beginCapture)
        XCTAssertEqual(machine.phase, .recording)
        XCTAssertEqual(machine.handle(.released), .stopCapture)
        XCTAssertEqual(machine.phase, .finalizing)
    }

    func testSlideUpCancels() {
        var machine = HoldToTalkStateMachine()
        _ = machine.handle(.pressBegan)
        _ = machine.handle(.thresholdReached)
        XCTAssertEqual(machine.handle(.moved(-90)), .none)
        XCTAssertTrue(machine.isCancelArmed)
        XCTAssertEqual(machine.handle(.released), .cancelCapture)
        XCTAssertEqual(machine.phase, .idle)
    }

    func testSlideBackDisarms() {
        var machine = HoldToTalkStateMachine()
        _ = machine.handle(.pressBegan)
        _ = machine.handle(.thresholdReached)
        _ = machine.handle(.moved(-90))
        XCTAssertTrue(machine.isCancelArmed)
        _ = machine.handle(.moved(-60))
        XCTAssertTrue(machine.isCancelArmed)
        _ = machine.handle(.moved(-40))
        XCTAssertFalse(machine.isCancelArmed)
        XCTAssertEqual(machine.handle(.released), .stopCapture)
        XCTAssertEqual(machine.phase, .finalizing)
    }

    func testSystemCancelWhileRecording() {
        var machine = HoldToTalkStateMachine()
        _ = machine.handle(.pressBegan)
        _ = machine.handle(.thresholdReached)
        XCTAssertEqual(machine.handle(.cancelled), .cancelCapture)
        XCTAssertEqual(machine.phase, .idle)
    }

    func testMaxDurationStopsCapture() {
        var machine = HoldToTalkStateMachine()
        _ = machine.handle(.pressBegan)
        _ = machine.handle(.thresholdReached)
        XCTAssertEqual(machine.handle(.maxDurationReached), .stopCapture)
        XCTAssertEqual(machine.phase, .finalizing)
    }

    func testMaxDurationWinsAsCancelWhenArmed() {
        var machine = HoldToTalkStateMachine()
        _ = machine.handle(.pressBegan)
        _ = machine.handle(.thresholdReached)
        _ = machine.handle(.moved(-90))
        XCTAssertEqual(machine.handle(.maxDurationReached), .cancelCapture)
        XCTAssertEqual(machine.phase, .idle)
    }

    func testRepeatedPressIsIgnored() {
        var machine = HoldToTalkStateMachine()
        _ = machine.handle(.pressBegan)
        _ = machine.handle(.thresholdReached)
        XCTAssertEqual(machine.handle(.pressBegan), .none)
        XCTAssertEqual(machine.phase, .recording)
        XCTAssertEqual(machine.handle(.released), .stopCapture)
        XCTAssertEqual(machine.handle(.released), .none)
    }

    func testReleaseWithoutPressIsIgnored() {
        var machine = HoldToTalkStateMachine()
        XCTAssertEqual(machine.handle(.released), .none)
        XCTAssertEqual(machine.phase, .idle)
        XCTAssertEqual(machine.handle(.thresholdReached), .none)
    }
}
