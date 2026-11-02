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
        value.date += seconds
    }

    func advanceContinuous(_ seconds: TimeInterval) {
        value.continuous += seconds
        value.date += seconds
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

    func testObservedWorkContinuesAtHundredPercentThroughDueAndSnooze() {
        let time = ManualTime()
        var config = BreakCycleConfiguration.standard
        config.workInterval = 60
        var cycle = BreakCycle(config: config, reading: time.value)
        var ledger = ScreenTimeLedger(reading: time.value)
        _ = ledger.tick(time.value, available: true, isCounting: cycle.isObservedWorkEligible)
        var slices: [ScreenTimeSlice] = []

        // 60 counting + 120 due + 60 snoozed, all with an available screen.
        for _ in 0..<3 {
            time.advance(seconds: 60)
            _ = cycle.tick(time.value, available: true)
            slices += ledger.tick(time.value, available: true, isCounting: cycle.isObservedWorkEligible)
        }
        XCTAssertEqual(cycle.snooze(time.value, minutes: 1), 60)
        slices += ledger.tick(time.value, available: true, isCounting: cycle.isObservedWorkEligible)
        for _ in 0..<2 {
            time.advance(seconds: 30)
            _ = cycle.tick(time.value, available: true)
            slices += ledger.tick(time.value, available: true, isCounting: cycle.isObservedWorkEligible)
        }

        XCTAssertEqual(slices.map(\.seconds), [60, 60, 60, 60])
        XCTAssertEqual(slices.map(\.startDate.timeIntervalSince1970), [0, 60, 120, 180])
        XCTAssertEqual(slices.reduce(0) { $0 + $1.seconds }, 240)
        XCTAssertEqual(cycle.used, 60)
        XCTAssertEqual(cycle.percent, 100)
        time.advanceContinuous(600)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(ledger.tick(time.value, available: true, isCounting: cycle.isObservedWorkEligible), [])
    }

    func testPausedRestingAwaitingAndOffscreenExcludeObservedWork() {
        for state in ["paused", "resting", "awaiting", "offscreen"] {
            let time = ManualTime()
            var cycle = BreakCycle(reading: time.value)
            let available = state != "offscreen"
            switch state {
            case "paused": cycle.pause(time.value)
            case "resting": cycle.startRest(time.value)
            case "awaiting":
                cycle.startRest(time.value)
                time.advance(seconds: 120)
                _ = cycle.tick(time.value, available: true)
                XCTAssertTrue(cycle.awaitingNextCycle)
            default: _ = cycle.tick(time.value, available: false)
            }
            var ledger = ScreenTimeLedger(reading: time.value)
            _ = ledger.tick(time.value, available: available, isCounting: cycle.isObservedWorkEligible)

            time.advance(seconds: 60)
            _ = cycle.tick(time.value, available: available)
            XCTAssertEqual(ledger.tick(time.value, available: available, isCounting: cycle.isObservedWorkEligible), [], state)
            XCTAssertEqual(ledger.flush(reading: time.value), [], state)
        }
    }

    func testExitSettlesUnobservedRemainderOnlyOnce() {
        let time = ManualTime()
        let cycle = BreakCycle(reading: time.value)
        var ledger = ScreenTimeLedger(reading: time.value)
        _ = ledger.tick(time.value, available: true, isCounting: cycle.isObservedWorkEligible)

        time.advance(seconds: 37)
        let exiting = ledger.tick(time.value, available: false, isCounting: false)
        XCTAssertEqual(exiting, [ScreenTimeSlice(startDate: Date(timeIntervalSince1970: 0), seconds: 37)])
        XCTAssertEqual(ledger.flush(reading: time.value), [])
        time.advance(seconds: 100)
        XCTAssertEqual(ledger.tick(time.value, available: false, isCounting: false), [])
        XCTAssertEqual(ledger.flush(reading: time.value), [])
    }
}
