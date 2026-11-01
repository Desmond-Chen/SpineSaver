import XCTest
import SpineSaverCore

private final class ManualTime: TimeProvider {
    var value: ClockReading

    init(awake: TimeInterval = 0, continuous: TimeInterval = 0) {
        value = ClockReading(awake: awake, continuous: continuous, date: Date(timeIntervalSince1970: 0))
    }

    func reading() -> ClockReading { value }

    func advance(seconds: TimeInterval) {
        value.awake += seconds
        value.continuous += seconds
    }

    func advanceContinuous(_ seconds: TimeInterval) {
        value.continuous += seconds
    }
}

final class ScreenTimeLedgerTests: XCTestCase {
    func testContinuousMinute() {
        let time = ManualTime()
        var ledger = ScreenTimeLedger(reading: time.value)
        _ = ledger.tick(time.value, available: true, isCounting: true)
        time.advance(seconds: 60)
        let slices = ledger.tick(time.value, available: true, isCounting: true)
        XCTAssertEqual(slices.count, 1)
        XCTAssertEqual(slices[0].seconds, 60, accuracy: 0.001)
        XCTAssertEqual(ledger.tick(time.value, available: true, isCounting: true), [])
    }

    func testPauseFlushAndResumeDoesNotCountGap() {
        let time = ManualTime()
        var ledger = ScreenTimeLedger(reading: time.value)
        _ = ledger.tick(time.value, available: true, isCounting: true)
        time.advance(seconds: 30)
        _ = ledger.tick(time.value, available: true, isCounting: true)
        let paused = ledger.tick(time.value, available: true, isCounting: false)
        XCTAssertEqual(paused.count, 1)
        XCTAssertEqual(paused[0].seconds, 30, accuracy: 0.001)
        time.advance(seconds: 300)
        _ = ledger.tick(time.value, available: true, isCounting: true)
        time.advance(seconds: 60)
        let resumed = ledger.tick(time.value, available: true, isCounting: true)
        XCTAssertEqual(resumed.count, 1)
        XCTAssertEqual(resumed[0].seconds, 60, accuracy: 0.001)
    }

    func testSleepAddsNoScreenTime() {
        let time = ManualTime()
        var ledger = ScreenTimeLedger(reading: time.value)
        _ = ledger.tick(time.value, available: true, isCounting: true)
        time.advanceContinuous(30 * 60)
        XCTAssertEqual(ledger.tick(time.value, available: true, isCounting: true), [])
    }
}
