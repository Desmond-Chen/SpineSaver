import XCTest
import SpineSaverCore

final class MenuBarTextTests: XCTestCase {
    func testWorkLabel() {
        XCTAssertEqual(MenuBarText.label(phase: .counting, percent: 75, restRemaining: 0, awaitingNextCycle: false), "● 75%")
        XCTAssertEqual(MenuBarText.label(phase: .due, percent: 100, restRemaining: 0, awaitingNextCycle: false), "● 100%")
        XCTAssertEqual(MenuBarText.label(phase: .snoozed(until: 10), percent: 80, restRemaining: 0, awaitingNextCycle: false), "● 80%")
        XCTAssertEqual(MenuBarText.label(phase: .paused, percent: 40, restRemaining: 0, awaitingNextCycle: false), "● 40%")
    }

    func testRestLabel() {
        XCTAssertEqual(MenuBarText.label(phase: .resting(startedAt: 0), percent: 0, restRemaining: 97, awaitingNextCycle: false), "☕ 01:37")
        XCTAssertEqual(MenuBarText.clock(0.1), "00:01")
        XCTAssertEqual(MenuBarText.clock(0), "00:00")
    }

    func testAwaitingLabel() {
        XCTAssertEqual(MenuBarText.label(phase: .paused, percent: 0, restRemaining: 0, awaitingNextCycle: true), "▶ 开始")
        XCTAssertEqual(
            MenuBarText.accessibilityLabel(phase: .paused, percent: 0, restRemaining: 0, awaitingNextCycle: true),
            "SpineSaver 休息倒计时已结束，待开始新一轮"
        )
    }

    func testAccessibility() {
        XCTAssertEqual(
            MenuBarText.accessibilityLabel(phase: .resting(startedAt: 0), percent: 0, restRemaining: 97, awaitingNextCycle: false),
            "SpineSaver 休息中，剩余 1 分 37 秒"
        )
        XCTAssertEqual(
            MenuBarText.accessibilityLabel(phase: .counting, percent: 75, restRemaining: 0, awaitingNextCycle: false),
            "SpineSaver 工作中，本轮进度 75%"
        )
    }
}
