import XCTest
import SpineSaverCore

private final class ManualTime: TimeProvider {
    var value: ClockReading
    init(awake: TimeInterval = 0, continuous: TimeInterval = 0) {
        value = ClockReading(
            awake: awake,
            continuous: continuous,
            date: Date(timeIntervalSince1970: 0)
        )
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

final class BreakCycleTests: XCTestCase {
    private func makeCycle(interval: TimeInterval = 45 * 60) -> (BreakCycle, ManualTime) {
        let time = ManualTime()
        var config = BreakCycleConfiguration.standard
        config.workInterval = interval
        return (BreakCycle(config: config, reading: time.value), time)
    }

    func testPercentageHalfAndDue() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 22.5 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
        XCTAssertEqual(cycle.percent, 50)
        XCTAssertEqual(cycle.remaining, 22.5 * 60, accuracy: 0.001)

        time.advance(seconds: 22.5 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.reminderDue])
        XCTAssertEqual(cycle.percent, 100)
        XCTAssertTrue(cycle.isDue)
    }

    func testOneReminderPerOpportunity() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 45 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.reminderDue])
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
        time.advance(seconds: 30)
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
    }

    func testSnoozeReplacesDeadlineAndRemindsOnce() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 45 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.reminderDue])
        cycle.snooze(time.value)

        time.advance(seconds: 9 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
        XCTAssertTrue(cycle.isSnoozed)

        time.advance(seconds: 1 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.reminderDue])
        XCTAssertTrue(cycle.isDue)
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
    }

    func testPausePreservesUsageAndResumeDueRemindsOnce() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 10 * 60)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 10 * 60, accuracy: 0.001)

        cycle.pause(time.value)
        time.advance(seconds: 5 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
        XCTAssertEqual(cycle.used, 10 * 60, accuracy: 0.001)

        cycle.resume(time.value)
        time.advance(seconds: 60)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 11 * 60, accuracy: 0.001)

        time.advance(seconds: 34 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.reminderDue])
        cycle.pause(time.value)
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
        cycle.resume(time.value)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.reminderDue])
    }

    func testShortOffscreenPreservesUsageAndLongOffscreenResets() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 10 * 60)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 10 * 60, accuracy: 0.001)

        XCTAssertEqual(cycle.tick(time.value, available: false), [])
        time.advanceContinuous(5 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
        XCTAssertEqual(cycle.used, 10 * 60, accuracy: 0.001)

        time.advance(seconds: 10 * 60)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 20 * 60, accuracy: 0.001)

        _ = cycle.tick(time.value, available: false)
        time.advanceContinuous(10 * 60)
        let effects = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 0, accuracy: 0.001)
        XCTAssertTrue(cycle.isCounting)
        XCTAssertTrue(effects.contains(.dismissReminder))
        XCTAssertFalse(effects.contains(.reminderDue))
    }

    func testDueCycleOffscreenResetDoesNotClaimRest() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 45 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.reminderDue])
        _ = cycle.tick(time.value, available: false)
        time.advanceContinuous(11 * 60)
        let effects = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 0, accuracy: 0.001)
        XCTAssertEqual(cycle.percent, 0)
        XCTAssertFalse(effects.contains(.reminderDue))
        XCTAssertFalse(cycle.isResting)
    }

    func testManualRestFinishAndCancel() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 10 * 60)
        _ = cycle.tick(time.value, available: true)

        cycle.startRest(time.value)
        XCTAssertTrue(cycle.isResting)
        cycle.cancelRest(time.value)
        XCTAssertTrue(cycle.isCounting)
        XCTAssertEqual(cycle.used, 10 * 60, accuracy: 0.001)

        cycle.startRest(time.value)
        cycle.finishRest(time.value)
        XCTAssertTrue(cycle.isCounting)
        XCTAssertEqual(cycle.used, 0, accuracy: 0.001)
    }

    func testRestFromPausedStaysPaused() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 5 * 60)
        _ = cycle.tick(time.value, available: true)
        cycle.pause(time.value)
        cycle.startRest(time.value)
        cycle.finishRest(time.value)
        XCTAssertTrue(cycle.isPaused)
        XCTAssertEqual(cycle.used, 0, accuracy: 0.001)
    }

    func testRestAutoCompletesAtGoal() {
        var (cycle, time) = makeCycle()
        cycle.startRest(time.value)
        time.advance(seconds: 2 * 60)
        let effects = cycle.tick(time.value, available: true)
        XCTAssertEqual(effects, [.restAutoCompleted])
        XCTAssertTrue(cycle.isPaused)
        XCTAssertTrue(cycle.awaitingNextCycle)
        XCTAssertEqual(cycle.used, 0, accuracy: 0.001)
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
    }

    func testRestRemainingCountsDown() {
        var (cycle, time) = makeCycle()
        cycle.startRest(time.value)
        XCTAssertEqual(cycle.restRemaining(reading: time.value), 2 * 60, accuracy: 0.001)
        time.advance(seconds: 30)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.restRemaining(reading: time.value), 90, accuracy: 0.001)
    }

    func testRestAutoCompleteAwaitsManualStart() {
        var (cycle, time) = makeCycle()
        cycle.startRest(time.value)
        time.advance(seconds: 2 * 60)
        _ = cycle.tick(time.value, available: true)
        XCTAssertTrue(cycle.isPaused)
        XCTAssertTrue(cycle.awaitingNextCycle)
        cycle.resume(time.value)
        XCTAssertTrue(cycle.isCounting)
        XCTAssertFalse(cycle.awaitingNextCycle)
    }

    func testManualStartAfterRestBeginsCounting() {
        var (cycle, time) = makeCycle()
        cycle.startRest(time.value)
        time.advance(seconds: 2 * 60)
        _ = cycle.tick(time.value, available: true)
        cycle.resume(time.value)
        XCTAssertTrue(cycle.isCounting)
        time.advance(seconds: 60)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 60, accuracy: 0.001)
    }

    func testRestAutoCompletesOnce() {
        var (cycle, time) = makeCycle()
        cycle.startRest(time.value)
        time.advance(seconds: 2 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.restAutoCompleted])
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
    }

    func testResumePromptOpportunitySurvivesConfigurationChangeAndClaimsOnce() {
        var (cycle, time) = makeCycle()
        var gate = ResumePromptGate()
        XCTAssertNil(gate.claim(available: true, awaitingNextCycle: true))

        cycle.startRest(time.value)
        time.advance(seconds: 120)
        XCTAssertEqual(cycle.tick(time.value, available: false), [.restAutoCompleted])
        gate.recordCompletion()
        XCTAssertTrue(cycle.isPaused)
        XCTAssertTrue(cycle.awaitingNextCycle)
        XCTAssertEqual(cycle.used, 0, accuracy: 0.001)
        XCTAssertEqual(gate.state, .pending(1))
        XCTAssertNil(gate.claim(available: false, awaitingNextCycle: true))
        XCTAssertNil(gate.claim(available: true, awaitingNextCycle: false))

        var config = cycle.config
        config.workInterval = 60 * 60
        let generation = cycle.generation
        XCTAssertEqual(cycle.updateConfiguration(config), [])
        XCTAssertGreaterThan(cycle.generation, generation)
        gate.recordCompletion()
        XCTAssertEqual(gate.state, .pending(1))
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
        XCTAssertEqual(gate.claim(available: true, awaitingNextCycle: cycle.awaitingNextCycle), 1)
        XCTAssertTrue(gate.isClaimed(1))
        XCTAssertNil(gate.claim(available: true, awaitingNextCycle: true))
        gate.close(1)
        XCTAssertFalse(gate.isClaimed(1))
        XCTAssertEqual(gate.state, .closed(1))
        gate.recordCompletion()
        XCTAssertNil(gate.claim(available: true, awaitingNextCycle: true))
        time.advance(seconds: 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
        XCTAssertEqual(cycle.used, 0, accuracy: 0.001)
        XCTAssertTrue(cycle.isPaused)
    }

    func testResumePromptClearsAndRejectsStaleDismissalInNextRest() {
        var (cycle, time) = makeCycle()
        var gate = ResumePromptGate()
        cycle.startRest(time.value)
        time.advance(seconds: 120)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.restAutoCompleted])
        gate.recordCompletion()
        XCTAssertEqual(gate.claim(available: true, awaitingNextCycle: cycle.awaitingNextCycle), 1)

        cycle.resume(time.value)
        gate.clear()
        XCTAssertTrue(cycle.isCounting)
        XCTAssertFalse(cycle.awaitingNextCycle)
        XCTAssertFalse(gate.isClaimed(1))
        XCTAssertNil(gate.claim(available: true, awaitingNextCycle: false))
        cycle.startRest(time.value)
        time.advance(seconds: 120)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.restAutoCompleted])
        gate.recordCompletion()
        gate.close(1)
        XCTAssertEqual(gate.state, .pending(2))
        XCTAssertEqual(gate.claim(available: true, awaitingNextCycle: cycle.awaitingNextCycle), 2)
        XCTAssertFalse(gate.isClaimed(1))
        gate.close(1)
        XCTAssertTrue(gate.isClaimed(2))
        gate.clear()
        XCTAssertNil(gate.claim(available: true, awaitingNextCycle: true))
    }

    func testActionSettlesCompletedRestWithoutPresentingAfterNewCycleStarts() {
        var (cycle, time) = makeCycle()
        var gate = ResumePromptGate()
        cycle.startRest(time.value)
        time.advance(seconds: 120)

        let effects = cycle.tick(time.value, available: true)
        XCTAssertEqual(effects, [.restAutoCompleted])
        gate.recordCompletion()
        cycle.resume(time.value)
        if !cycle.awaitingNextCycle { gate.clear() }

        XCTAssertTrue(cycle.isCounting)
        XCTAssertFalse(cycle.awaitingNextCycle)
        XCTAssertEqual(cycle.used, 0, accuracy: 0.001)
        XCTAssertEqual(gate.state, .none)
        XCTAssertNil(gate.claim(available: true, awaitingNextCycle: cycle.awaitingNextCycle))
        XCTAssertEqual(cycle.tick(time.value, available: true), [])
    }

    func testRestBackwardClockClamps() {
        var (cycle, time) = makeCycle()
        cycle.startRest(time.value)
        time.advance(seconds: 30)
        _ = cycle.tick(time.value, available: true)
        time.value.continuous -= 60
        _ = cycle.tick(time.value, available: true)
        XCTAssertTrue(cycle.isResting)
        XCTAssertEqual(cycle.restRemaining(reading: time.value), 2 * 60, accuracy: 0.001)
    }

    func testRestDurationChangeMidRestIsFrozen() {
        var (cycle, time) = makeCycle()
        cycle.startRest(time.value)
        time.advance(seconds: 30)
        _ = cycle.tick(time.value, available: true)
        var longer = cycle.config
        longer.suggestedRestDuration = 10 * 60
        _ = cycle.updateConfiguration(longer)
        XCTAssertTrue(cycle.isResting)
        XCTAssertEqual(cycle.restRemaining(reading: time.value), 90, accuracy: 0.001)
    }

    func testRestDurationStaysFrozenForCompletion() {
        var (cycle, time) = makeCycle()
        cycle.startRest(time.value)
        XCTAssertEqual(cycle.restDuration, 2 * 60, accuracy: 0.001)

        var longer = cycle.config
        longer.suggestedRestDuration = 10 * 60
        _ = cycle.updateConfiguration(longer)
        XCTAssertEqual(cycle.restDuration, 2 * 60, accuracy: 0.001)

        time.advance(seconds: 2 * 60)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.restDuration, 2 * 60, accuracy: 0.001)
    }

    func testNextWakeDuringRestIsOneSecond() {
        var (cycle, time) = makeCycle()
        cycle.startRest(time.value)
        time.advance(seconds: 10)
        _ = cycle.tick(time.value, available: true)
        let wake = cycle.nextWake(after: time.value)
        XCTAssertNotNil(wake)
        XCTAssertGreaterThanOrEqual(wake ?? 0, 0.5)
        XCTAssertLessThanOrEqual(wake ?? 99, 1.0)
    }

    func testIntervalExtensionCancelsDueAndShorteningReminds() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 45 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.reminderDue])

        var longer = cycle.config
        longer.workInterval = 60 * 60
        XCTAssertEqual(cycle.updateConfiguration(longer), [.dismissReminder])
        XCTAssertTrue(cycle.isCounting)
        XCTAssertEqual(cycle.used, 45 * 60, accuracy: 0.001)
        XCTAssertEqual(cycle.percent, 75)

        var shorter = cycle.config
        shorter.workInterval = 30 * 60
        XCTAssertEqual(cycle.updateConfiguration(shorter), [.reminderDue])
        XCTAssertTrue(cycle.isDue)
        XCTAssertEqual(cycle.used, 30 * 60, accuracy: 0.001)
    }

    func testShorteningACountingCycleRemindsOnce() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 20 * 60)
        _ = cycle.tick(time.value, available: true)

        var shorter = cycle.config
        shorter.workInterval = 15 * 60
        XCTAssertEqual(cycle.updateConfiguration(shorter), [.reminderDue])
        XCTAssertTrue(cycle.isDue)
        XCTAssertEqual(cycle.used, 15 * 60, accuracy: 0.001)
    }

    func testBackwardClockDoesNotReduceUsage() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 5 * 60)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 5 * 60, accuracy: 0.001)

        time.value.awake -= 60
        time.value.continuous -= 60
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 5 * 60, accuracy: 0.001)

        time.advance(seconds: 60)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 6 * 60, accuracy: 0.001)
    }

    func testRepeatedTickDoesNotDoubleCount() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 10 * 60)
        _ = cycle.tick(time.value, available: true)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 10 * 60, accuracy: 0.001)
        time.advance(seconds: 60)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 11 * 60, accuracy: 0.001)
    }

    func testRestoreStartsPaused() {
        let time = ManualTime()
        var config = BreakCycleConfiguration.standard
        config.workInterval = 45 * 60
        let cycle = BreakCycle(restoring: config, used: 12 * 60, reading: time.value)
        XCTAssertTrue(cycle.isPaused)
        XCTAssertEqual(cycle.used, 12 * 60, accuracy: 0.001)
        XCTAssertEqual(cycle.percent, 26)
    }

    func testSnoozeDoesNotSurviveLongOffscreen() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 45 * 60)
        XCTAssertEqual(cycle.tick(time.value, available: true), [.reminderDue])
        cycle.snooze(time.value)

        _ = cycle.tick(time.value, available: false)
        time.advanceContinuous(11 * 60)
        let effects = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 0, accuracy: 0.001)
        XCTAssertTrue(cycle.isCounting)
        XCTAssertFalse(effects.contains(.reminderDue))
    }

    func testCycleTokenRejectsStaleSessionAndGeneration() {
        XCTAssertTrue(CycleToken.matches(
            sessionID: "session-a", generation: 3,
            currentSessionID: "session-a", currentGeneration: 3
        ))
        XCTAssertFalse(CycleToken.matches(
            sessionID: "session-b", generation: 3,
            currentSessionID: "session-a", currentGeneration: 3
        ))
        XCTAssertFalse(CycleToken.matches(
            sessionID: "session-a", generation: 2,
            currentSessionID: "session-a", currentGeneration: 3
        ))
    }

    func testPauseAndRestIntervalsAreNotCounted() {
        var (cycle, time) = makeCycle()
        time.advance(seconds: 10 * 60)
        _ = cycle.tick(time.value, available: true)

        cycle.pause(time.value)
        time.advance(seconds: 5 * 60)
        cycle.resume(time.value)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 10 * 60, accuracy: 0.001)

        cycle.startRest(time.value)
        time.advance(seconds: 2 * 60)
        cycle.finishRest(time.value)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 0, accuracy: 0.001)

        cycle.startRest(time.value)
        time.advance(seconds: 2 * 60)
        cycle.cancelRest(time.value)
        _ = cycle.tick(time.value, available: true)
        XCTAssertEqual(cycle.used, 0, accuracy: 0.001)
    }
}
