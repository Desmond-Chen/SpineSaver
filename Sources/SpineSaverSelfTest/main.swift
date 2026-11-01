import Darwin
import Foundation
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

private var failures = 0
private var checks = 0

private func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if condition() {
        print("PASS \(name)")
    } else {
        failures += 1
        print("FAIL \(name)")
    }
}

private func equal<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    check(actual == expected, "\(name) — got \(actual), expected \(expected)")
}

private func close(_ actual: Double, _ expected: Double, _ name: String) {
    check(abs(actual - expected) < 0.001, "\(name) — got \(actual), expected \(expected)")
}

private func makeCycle(interval: TimeInterval = 45 * 60) -> (BreakCycle, ManualTime) {
    let time = ManualTime()
    var config = BreakCycleConfiguration.standard
    config.workInterval = interval
    return (BreakCycle(config: config, reading: time.value), time)
}

// 1. Percentage at half and due.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 22.5 * 60)
    equal(cycle.tick(time.value, available: true), [], "half cycle has no reminder")
    equal(cycle.percent, 50, "22m30s is 50%")
    close(cycle.remaining, 22.5 * 60, "remaining at half")
    time.advance(seconds: 22.5 * 60)
    equal(cycle.tick(time.value, available: true), [.reminderDue], "due emits one reminder")
    equal(cycle.percent, 100, "due is 100%")
    check(cycle.isDue, "due phase")
}

// 2. One reminder per opportunity.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 45 * 60)
    equal(cycle.tick(time.value, available: true), [.reminderDue], "first due")
    equal(cycle.tick(time.value, available: true), [], "repeated tick does not repeat")
    time.advance(seconds: 30)
    equal(cycle.tick(time.value, available: true), [], "late tick does not repeat")
}

// 3. Snooze replaces deadline and reminds once.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 45 * 60)
    _ = cycle.tick(time.value, available: true)
    cycle.snooze(time.value)
    time.advance(seconds: 9 * 60)
    equal(cycle.tick(time.value, available: true), [], "snooze not yet due")
    check(cycle.isSnoozed, "snoozed phase")
    time.advance(seconds: 60)
    equal(cycle.tick(time.value, available: true), [.reminderDue], "snooze fires once")
    check(cycle.isDue, "snooze ends due")
    equal(cycle.tick(time.value, available: true), [], "snooze does not repeat")
}

// 4. Pause and resume.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 10 * 60)
    _ = cycle.tick(time.value, available: true)
    cycle.pause(time.value)
    time.advance(seconds: 5 * 60)
    equal(cycle.tick(time.value, available: true), [], "pause does not remind")
    close(cycle.used, 10 * 60, "pause preserves usage")
    cycle.resume(time.value)
    time.advance(seconds: 60)
    _ = cycle.tick(time.value, available: true)
    close(cycle.used, 11 * 60, "resume accumulates")
    time.advance(seconds: 34 * 60)
    equal(cycle.tick(time.value, available: true), [.reminderDue], "resume reaches due")
    cycle.pause(time.value)
    equal(cycle.tick(time.value, available: true), [], "paused due does not repeat")
    cycle.resume(time.value)
    equal(cycle.tick(time.value, available: true), [.reminderDue], "resume due reminds once")
}

// 5. Short offscreen preserves, long offscreen resets.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 10 * 60)
    _ = cycle.tick(time.value, available: true)
    _ = cycle.tick(time.value, available: false)
    time.advanceContinuous(5 * 60)
    equal(cycle.tick(time.value, available: true), [], "short offscreen no reminder")
    close(cycle.used, 10 * 60, "short offscreen preserves")
    time.advance(seconds: 10 * 60)
    _ = cycle.tick(time.value, available: true)
    close(cycle.used, 20 * 60, "returned usage accumulates")
    _ = cycle.tick(time.value, available: false)
    time.advanceContinuous(10 * 60)
    let effects = cycle.tick(time.value, available: true)
    close(cycle.used, 0, "long offscreen resets")
    check(cycle.isCounting, "long offscreen returns to counting")
    check(effects.contains(.dismissReminder), "long offscreen dismisses reminder")
    check(!effects.contains(.reminderDue), "long offscreen does not claim due")
}

// 6. Due + long offscreen never claims rest.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 45 * 60)
    equal(cycle.tick(time.value, available: true), [.reminderDue], "due before leaving")
    _ = cycle.tick(time.value, available: false)
    time.advanceContinuous(11 * 60)
    let effects = cycle.tick(time.value, available: true)
    close(cycle.used, 0, "due resets after long offscreen")
    equal(cycle.percent, 0, "due reset percent")
    check(!effects.contains(.reminderDue), "due reset no reminder")
    check(!cycle.isResting, "due reset is not a rest claim")
}

// 7. Manual rest finish and cancel.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 10 * 60)
    _ = cycle.tick(time.value, available: true)
    cycle.startRest(time.value)
    check(cycle.isResting, "start rest")
    cycle.cancelRest(time.value)
    check(cycle.isCounting, "cancel rest returns to counting")
    close(cycle.used, 10 * 60, "cancel rest restores usage")
    cycle.startRest(time.value)
    cycle.finishRest(time.value)
    check(cycle.isCounting, "finish rest starts a new cycle")
    close(cycle.used, 0, "finish rest resets usage")
}

// 8. Rest from paused stays paused.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 5 * 60)
    _ = cycle.tick(time.value, available: true)
    cycle.pause(time.value)
    cycle.startRest(time.value)
    cycle.finishRest(time.value)
    check(cycle.isPaused, "rest from paused stays paused")
    close(cycle.used, 0, "rest from paused resets usage")
}

// 9. Rest auto-completes and waits for manual start.
do {
    var (cycle, time) = makeCycle()
    cycle.startRest(time.value)
    time.advance(seconds: 2 * 60)
    equal(cycle.tick(time.value, available: true), [.restAutoCompleted], "rest auto-completes once")
    check(cycle.isPaused, "rest auto-complete pauses")
    check(cycle.awaitingNextCycle, "rest auto-complete awaits manual start")
    close(cycle.used, 0, "rest auto-complete resets usage")
    equal(cycle.tick(time.value, available: true), [], "rest auto-complete does not repeat")
    cycle.resume(time.value)
    check(cycle.isCounting, "manual start begins counting")
    check(!cycle.awaitingNextCycle, "manual start clears awaiting")
}

// 9a. Resume prompt opportunity lifecycle and stale callback protection.
do {
    var (cycle, time) = makeCycle()
    var gate = ResumePromptGate()
    check(gate.claim(available: true, awaitingNextCycle: true) == nil, "resume gate starts empty")
    cycle.startRest(time.value)
    time.advance(seconds: 120)
    equal(cycle.tick(time.value, available: false), [.restAutoCompleted], "offscreen rest emits completion")
    gate.recordCompletion()
    check(cycle.isPaused && cycle.awaitingNextCycle && cycle.used == 0, "completion awaits manual start at zero")
    equal(gate.state, .pending(1), "completion creates first opportunity")
    check(gate.claim(available: false, awaitingNextCycle: true) == nil, "unavailable screen defers resume prompt")
    check(gate.claim(available: true, awaitingNextCycle: false) == nil, "nonwaiting state defers resume prompt")
    var config = cycle.config
    config.workInterval = 60 * 60
    let generation = cycle.generation
    equal(cycle.updateConfiguration(config), [], "configuration change preserves waiting")
    check(cycle.generation > generation, "configuration change advances action generation")
    gate.recordCompletion()
    equal(gate.state, .pending(1), "repeated completion does not create opportunity")
    equal(cycle.tick(time.value, available: true), [], "return does not repeat completion")
    equal(gate.claim(available: true, awaitingNextCycle: cycle.awaitingNextCycle), 1, "return claims first opportunity")
    check(gate.isClaimed(1), "claimed opportunity accepts its current identity")
    check(gate.claim(available: true, awaitingNextCycle: true) == nil, "repeated tick cannot claim twice")
    gate.close(1)
    check(!gate.isClaimed(1), "closed opportunity rejects old action")
    gate.recordCompletion()
    equal(gate.state, .closed(1), "closed opportunity never reopens")
    check(gate.claim(available: true, awaitingNextCycle: true) == nil, "closed opportunity cannot be reclaimed")
    time.advance(seconds: 60)
    equal(cycle.tick(time.value, available: true), [], "waiting does not emit work effects")
    close(cycle.used, 0, "waiting does not count screen time")
    check(cycle.isPaused, "waiting remains paused")

    cycle.resume(time.value)
    gate.clear()
    check(cycle.isCounting && !cycle.awaitingNextCycle, "manual start resumes work")
    check(!gate.isClaimed(1), "manual start invalidates old action")
    cycle.startRest(time.value)
    time.advance(seconds: 120)
    equal(cycle.tick(time.value, available: true), [.restAutoCompleted], "new rest emits new completion")
    gate.recordCompletion()
    gate.close(1)
    equal(gate.state, .pending(2), "old dismissal cannot close new opportunity")
    equal(gate.claim(available: true, awaitingNextCycle: cycle.awaitingNextCycle), 2, "new completion gets new identity")
    gate.close(1)
    check(gate.isClaimed(2) && !gate.isClaimed(1), "old action cannot replace new claim")
    gate.clear()
    check(gate.claim(available: true, awaitingNextCycle: true) == nil, "clearing invalidates the new claim")
}

// 10. Interval extension cancels due, shortening reminds.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 45 * 60)
    equal(cycle.tick(time.value, available: true), [.reminderDue], "due before config change")
    var longer = cycle.config
    longer.workInterval = 60 * 60
    equal(cycle.updateConfiguration(longer), [.dismissReminder], "extension dismisses due reminder")
    check(cycle.isCounting, "extension returns to counting")
    close(cycle.used, 45 * 60, "extension preserves usage")
    equal(cycle.percent, 75, "extension percentage")
    var shorter = cycle.config
    shorter.workInterval = 30 * 60
    equal(cycle.updateConfiguration(shorter), [.reminderDue], "shortening reminds")
    check(cycle.isDue, "shortening due")
    close(cycle.used, 30 * 60, "shortening clamps usage")
}

// 11. Shortening a counting cycle reminds once.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 20 * 60)
    _ = cycle.tick(time.value, available: true)
    var shorter = cycle.config
    shorter.workInterval = 15 * 60
    equal(cycle.updateConfiguration(shorter), [.reminderDue], "shortened counting reminds")
    check(cycle.isDue, "shortened counting due")
    close(cycle.used, 15 * 60, "shortened counting clamps")
}

// 12. Backward clock does not reduce usage.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 5 * 60)
    _ = cycle.tick(time.value, available: true)
    time.value.awake -= 60
    time.value.continuous -= 60
    _ = cycle.tick(time.value, available: true)
    close(cycle.used, 5 * 60, "backward clock preserves usage")
    time.advance(seconds: 60)
    _ = cycle.tick(time.value, available: true)
    close(cycle.used, 6 * 60, "clock re-anchors")
}

// 13. Repeated tick does not double count.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 10 * 60)
    _ = cycle.tick(time.value, available: true)
    _ = cycle.tick(time.value, available: true)
    close(cycle.used, 10 * 60, "repeated tick no double count")
    time.advance(seconds: 60)
    _ = cycle.tick(time.value, available: true)
    close(cycle.used, 11 * 60, "next tick accumulates")
}

// 14. Restore starts paused.
do {
    let time = ManualTime()
    let cycle = BreakCycle(restoring: .standard, used: 12 * 60, reading: time.value)
    check(cycle.isPaused, "restore starts paused")
    close(cycle.used, 12 * 60, "restore preserves usage")
    equal(cycle.percent, 26, "restore percentage")
}

// 15. Snooze does not survive long offscreen.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 45 * 60)
    equal(cycle.tick(time.value, available: true), [.reminderDue], "snooze setup due")
    cycle.snooze(time.value)
    _ = cycle.tick(time.value, available: false)
    time.advanceContinuous(11 * 60)
    let effects = cycle.tick(time.value, available: true)
    close(cycle.used, 0, "snooze reset after long offscreen")
    check(cycle.isCounting, "snooze reset phase")
    check(!effects.contains(.reminderDue), "snooze reset no reminder")
}

// 16. Next wake stays reasonable near the deadline.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 44 * 60 + 50)
    _ = cycle.tick(time.value, available: true)
    if let wake = cycle.nextWake(after: time.value) {
        check(wake <= 10.5, "near-deadline wake is not a polling loop")
    } else {
        check(false, "near-deadline wake exists")
    }
}

// 17. Pause interval is not counted after resume.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 10 * 60)
    _ = cycle.tick(time.value, available: true)
    cycle.pause(time.value)
    time.advance(seconds: 5 * 60)
    cycle.resume(time.value)
    _ = cycle.tick(time.value, available: true)
    close(cycle.used, 10 * 60, "pause interval is not counted")
}

// 18. Rest interval is not counted after finishing rest.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 10 * 60)
    _ = cycle.tick(time.value, available: true)
    cycle.startRest(time.value)
    time.advance(seconds: 2 * 60)
    cycle.finishRest(time.value)
    _ = cycle.tick(time.value, available: true)
    close(cycle.used, 0, "rest interval is not counted")
}

// 19. Notification action tokens reject a stale session or cycle.
check(CycleToken.matches(sessionID: "session-a", generation: 3, currentSessionID: "session-a", currentGeneration: 3), "matching notification token")
check(!CycleToken.matches(sessionID: "session-b", generation: 3, currentSessionID: "session-a", currentGeneration: 3), "stale notification session rejected")
check(!CycleToken.matches(sessionID: "session-a", generation: 2, currentSessionID: "session-a", currentGeneration: 3), "stale notification generation rejected")

// 20. Cancelled rest restores the original usage without adding rest time.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 10 * 60)
    _ = cycle.tick(time.value, available: true)
    cycle.startRest(time.value)
    time.advance(seconds: 2 * 60)
    cycle.cancelRest(time.value)
    _ = cycle.tick(time.value, available: true)
    close(cycle.used, 10 * 60, "cancel rest restores without rest time")
}

// 21. Rest snapshot round-trips and abandons on relaunch.
do {
    var (cycle, time) = makeCycle()
    cycle.startRest(time.value)
    if let snapshot = cycle.restSnapshot() {
        check(true, "rest snapshot exists while resting")
        equal(snapshot.duration, 2 * 60, "rest snapshot freezes duration")
        if let data = try? JSONEncoder().encode(snapshot),
           let decoded = try? JSONDecoder().decode(RestSnapshot.self, from: data) {
            equal(decoded, snapshot, "rest snapshot round-trips")
        } else {
            check(false, "rest snapshot round-trips")
        }
        let abandonment = snapshot.abandonment(at: time.value.date.addingTimeInterval(30))
        equal(abandonment.reason, .appRelaunch, "relaunch abandonment reason")
        close(abandonment.elapsedSeconds, 30, "relaunch abandonment elapsed")
    } else {
        check(false, "rest snapshot exists while resting")
    }
    cycle.finishRest(time.value)
    check(cycle.restSnapshot() == nil, "rest snapshot cleared after finish")
}

// 22. Sleep freezes work and completes rest on wake.
do {
    var (cycle, time) = makeCycle()
    time.advance(seconds: 10 * 60)
    _ = cycle.tick(time.value, available: true)
    time.advanceContinuous(30 * 60)
    _ = cycle.tick(time.value, available: true)
    close(cycle.used, 10 * 60, "sleep does not add work time")
}
do {
    var (cycle, time) = makeCycle()
    cycle.startRest(time.value)
    time.advanceContinuous(2 * 60)
    equal(cycle.tick(time.value, available: true), [.restAutoCompleted], "rest completes after sleep")
    check(cycle.isPaused, "rest after sleep pauses")
    check(cycle.awaitingNextCycle, "rest after sleep awaits manual start")
}

// 23. Menu bar labels.
do {
    equal(MenuBarText.label(phase: .counting, percent: 75, restRemaining: 0, awaitingNextCycle: false), "● 75%", "work menu label")
    equal(MenuBarText.label(phase: .resting(startedAt: 0), percent: 0, restRemaining: 97, awaitingNextCycle: false), "☕ 01:37", "rest menu label")
    equal(MenuBarText.label(phase: .paused, percent: 0, restRemaining: 0, awaitingNextCycle: true), "▶ 开始", "awaiting menu label")
    equal(MenuBarText.label(phase: .paused, percent: 0, restRemaining: 0, awaitingNextCycle: false), "● 0%", "ordinary pause menu label")
    equal(MenuBarText.label(phase: .counting, percent: 0, restRemaining: 0, awaitingNextCycle: false), "● 0%", "work zero-percent menu label")
    equal(MenuBarText.label(phase: .resting(startedAt: 0), percent: 0, restRemaining: 97, awaitingNextCycle: false), "☕ 01:37", "rest countdown menu label")
    check(MenuBarText.accessibilityLabel(phase: .resting(startedAt: 0), percent: 0, restRemaining: 97, awaitingNextCycle: false).contains("休息中"), "rest accessibility label")
    check(MenuBarText.accessibilityLabel(phase: .paused, percent: 0, restRemaining: 0, awaitingNextCycle: true).contains("待开始新一轮"), "awaiting accessibility label")
}

// 24. Settings validation.
do {
    equal(SettingsValidation.clampWorkMinutes(14), 15, "work min clamp")
    equal(SettingsValidation.clampWorkMinutes(121), 120, "work max clamp")
    check(!SettingsValidation.canDecreaseWorkMinutes(15), "work decrease disabled at min")
    check(!SettingsValidation.canIncreaseWorkMinutes(120), "work increase disabled at max")
    equal(SettingsValidation.clampRestMinutes(1), 2, "rest min clamp")
    equal(SettingsValidation.clampRestMinutes(16), 15, "rest max clamp")
    check(!SettingsValidation.canDecreaseRestMinutes(2), "rest decrease disabled at min")
    check(!SettingsValidation.canIncreaseRestMinutes(15), "rest increase disabled at max")
}

// 25. History store JSONL.
do {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("spinesaver-history-\(UUID().uuidString).jsonl")
    let store = HistoryStore(fileURL: url)
    let event = HistoryEvent(occurredAt: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC", kind: .restStarted, reason: "中文")
    try! store.append(event)
    let result = try! store.load()
    equal(result.events, [event], "history store round-trips")
    equal(result.skippedLines, 0, "history store skips no valid lines")
    try! store.deleteAll()
    check(!FileManager.default.fileExists(atPath: url.path), "history store deletes")
}
do {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("spinesaver-history-\(UUID().uuidString).jsonl")
    try! "not-json\n".write(to: url, atomically: true, encoding: .utf8)
    let store = HistoryStore(fileURL: url)
    let result = try! store.load()
    check(result.events.isEmpty, "history store skips malformed")
    equal(result.skippedLines, 1, "history store counts malformed")
    try? FileManager.default.removeItem(at: url)
}

// 26. Screen time ledger.
do {
    let time = ManualTime()
    var ledger = ScreenTimeLedger(reading: time.value)
    _ = ledger.tick(time.value, available: true, isCounting: true)
    time.advance(seconds: 60)
    let first = ledger.tick(time.value, available: true, isCounting: true)
    equal(first.count, 1, "ledger emits one minute")
    close(first[0].seconds, 60, "ledger minute seconds")
    equal(ledger.tick(time.value, available: true, isCounting: true), [], "ledger repeated tick no double")
}
do {
    let time = ManualTime()
    var ledger = ScreenTimeLedger(reading: time.value)
    _ = ledger.tick(time.value, available: true, isCounting: true)
    time.advance(seconds: 30)
    _ = ledger.tick(time.value, available: true, isCounting: true)
    let paused = ledger.tick(time.value, available: true, isCounting: false)
    equal(paused.count, 1, "ledger flushes on pause")
    close(paused[0].seconds, 30, "ledger pause flush seconds")
    time.advance(seconds: 300)
    _ = ledger.tick(time.value, available: true, isCounting: true)
    time.advance(seconds: 60)
    let resumed = ledger.tick(time.value, available: true, isCounting: true)
    equal(resumed.count, 1, "ledger resumes one minute")
    close(resumed[0].seconds, 60, "ledger resume seconds")
}
do {
    let time = ManualTime()
    var ledger = ScreenTimeLedger(reading: time.value)
    _ = ledger.tick(time.value, available: true, isCounting: true)
    time.advanceContinuous(30 * 60)
    equal(ledger.tick(time.value, available: true, isCounting: true), [], "sleep adds no screen time")
}

// 27. History aggregation.
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 59))!
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
    let event = HistoryEvent(occurredAt: start, timeZoneIdentifier: "UTC", kind: .screenTime, screenSeconds: 120)
    let buckets = HistoryAggregator.daily(events: [event], from: start, to: end, calendar: calendar)
    equal(buckets.count, 2, "daily split bucket count")
    close(buckets[0].screenSeconds, 60, "daily split first")
    close(buckets[1].screenSeconds, 60, "daily split second")
}
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0))!
    let end = calendar.date(byAdding: .day, value: 1, to: start)!
    let event = HistoryEvent(occurredAt: start, timeZoneIdentifier: "America/Los_Angeles", kind: .screenTime, screenSeconds: 24 * 3600)
    let buckets = HistoryAggregator.daily(events: [event], from: start, to: end, calendar: calendar)
    equal(buckets.count, 2, "DST bucket count")
    close(buckets[0].screenSeconds, 23 * 3600, "DST spring first day")
    close(buckets[1].screenSeconds, 3600, "DST spring second day")
}
do {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
    let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3))!
    let buckets = HistoryAggregator.daily(events: [], from: start, to: end, calendar: calendar)
    equal(buckets.count, 3, "empty range bucket count")
    check(buckets.allSatisfy { $0.screenSeconds == 0 }, "empty range zero seconds")
}

// 28. History export.
do {
    let event = HistoryEvent(occurredAt: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC", kind: .restStarted, reason: "中文, \"quoted\"")
    let json = HistoryExporter.json(events: [event], exportedAt: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "UTC")!)
    let object = try! JSONSerialization.jsonObject(with: json) as! [String: Any]
    equal(object["schemaVersion"] as? Int, 1, "export json schema")
    equal(object["units"] as? String, "seconds", "export json units")
    check((object["events"] as? [[String: Any]])?.count == 1, "export json events")
    let csvData = HistoryExporter.csv(events: [event], exportedAt: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "UTC")!)
    check(csvData.starts(with: [0xEF, 0xBB, 0xBF]), "export csv UTF-8 BOM")
    check(!json.starts(with: [0xEF, 0xBB, 0xBF]), "export json no BOM")
    let csv = String(decoding: csvData, as: UTF8.self)
    check(csv.contains("# schemaVersion=1"), "export csv metadata")
    check(csv.contains("restStarted"), "export csv kind")
    check(csv.contains("\"中文, \"\"quoted\"\"\""), "export csv escaping")
    let empty = String(decoding: HistoryExporter.csv(events: [], exportedAt: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "UTC")!), as: UTF8.self)
    check(empty.contains("schemaVersion,id"), "export empty csv header")
    let newlineEvent = HistoryEvent(occurredAt: Date(timeIntervalSince1970: 0), timeZoneIdentifier: "UTC", kind: .restStarted, reason: "line1\nline2")
    let newlineCSV = String(decoding: HistoryExporter.csv(events: [newlineEvent], exportedAt: Date(timeIntervalSince1970: 0), timeZone: TimeZone(identifier: "UTC")!), as: UTF8.self)
    check(newlineCSV.contains("\"line1\nline2\""), "export csv newline quoted")
}

// 29. Rest duration stays frozen for completion.
do {
    var (cycle, time) = makeCycle()
    cycle.startRest(time.value)
    close(cycle.restDuration, 2 * 60, "rest duration frozen at start")
    var longer = cycle.config
    longer.suggestedRestDuration = 10 * 60
    _ = cycle.updateConfiguration(longer)
    close(cycle.restDuration, 2 * 60, "rest duration frozen after config change")
    time.advance(seconds: 2 * 60)
    _ = cycle.tick(time.value, available: true)
    close(cycle.restDuration, 2 * 60, "rest duration frozen after auto complete")
}

// 30. Duration text units (task 4).
do {
    equal(DurationText.compact(seconds: 0), "0 分", "duration zero")
    equal(DurationText.compact(seconds: 59), "1 分", "duration rounds a partial minute")
    equal(DurationText.compact(seconds: 60), "1 分", "duration one minute")
    equal(DurationText.compact(seconds: 2700), "45 分", "duration 45 minutes")
    equal(DurationText.compact(seconds: 3600), "1 小时", "duration whole hour")
    equal(DurationText.compact(seconds: 4800), "1 小时 20 分", "duration hour and minutes")
    equal(DurationText.compact(seconds: -5), "0 分", "duration clamps negative")
    equal(DurationText.axis(seconds: 4800), "80 分", "duration axis keeps minutes")
    equal(DurationText.axis(seconds: 0), "0 分", "duration axis zero")
}

// 31. Daily timeline rebuild (task 5).
do {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }
    let day = utcDate(2026, 11, 1)
    let midnight = utcDate(2026, 11, 1, 0, 0)
    let reference = utcDate(2026, 11, 1, 23, 59)

    let crossMidnight = HistoryEvent(occurredAt: utcDate(2026, 10, 31, 23, 59), timeZoneIdentifier: "UTC", kind: .screenTime, screenSeconds: 120)
    let a = DailyTimeline.segments(events: [crossMidnight], day: day, referenceDate: reference, calendar: utc)
    equal(a.count, 1, "timeline clips a cross-midnight slice")
    close(a[0].start.timeIntervalSince(midnight), 0, "timeline clipped start is midnight")
    close(a[0].duration, 60, "timeline clipped duration is one minute")

    let contiguous = (0..<45).map { index in
        HistoryEvent(occurredAt: utcDate(2026, 11, 1, 9, 0).addingTimeInterval(Double(index) * 60), timeZoneIdentifier: "UTC", kind: .screenTime, screenSeconds: 60)
    }
    let b = DailyTimeline.segments(events: contiguous, day: day, referenceDate: reference, calendar: utc)
    equal(b.count, 1, "timeline merges contiguous slices")
    close(b[0].duration, 45 * 60, "timeline merged duration")

    let gapped = [
        HistoryEvent(occurredAt: utcDate(2026, 11, 1, 9, 0), timeZoneIdentifier: "UTC", kind: .screenTime, screenSeconds: 60),
        HistoryEvent(occurredAt: utcDate(2026, 11, 1, 9, 2), timeZoneIdentifier: "UTC", kind: .screenTime, screenSeconds: 60)
    ]
    equal(DailyTimeline.segments(events: gapped, day: day, referenceDate: reference, calendar: utc).count, 2, "timeline keeps a two-minute gap")

    let completed = [
        HistoryEvent(occurredAt: utcDate(2026, 11, 1, 10, 0), timeZoneIdentifier: "UTC", kind: .restStarted, restSeconds: 120),
        HistoryEvent(occurredAt: utcDate(2026, 11, 1, 10, 2), timeZoneIdentifier: "UTC", kind: .restAutoCompleted, restSeconds: 120)
    ]
    let d = DailyTimeline.segments(events: completed, day: day, referenceDate: reference, calendar: utc)
    equal(d.count, 1, "timeline does not double count a completed rest")
    equal(d[0].kind, TimelineKind.rest, "timeline completed rest kind")
    close(d[0].start.timeIntervalSince(utcDate(2026, 11, 1, 10, 0)), 0, "timeline rest start")
    close(d[0].duration, 120, "timeline rest duration")

    let inProgress = [HistoryEvent(occurredAt: utcDate(2026, 11, 1, 11, 0), timeZoneIdentifier: "UTC", kind: .restStarted, restSeconds: 600)]
    let e = DailyTimeline.segments(events: inProgress, day: day, referenceDate: utcDate(2026, 11, 1, 11, 2), calendar: utc)
    equal(e.count, 1, "timeline shows an in-progress rest")
    close(e[0].duration, 120, "timeline in-progress rest stops at referenceDate")

    let cancelled = [HistoryEvent(occurredAt: utcDate(2026, 11, 1, 12, 0), timeZoneIdentifier: "UTC", kind: .restCancelled, restSeconds: 60)]
    let f = DailyTimeline.segments(events: cancelled, day: day, referenceDate: reference, calendar: utc)
    equal(f.count, 1, "timeline cancelled rest segment")
    equal(f[0].kind, TimelineKind.restCancelled, "timeline cancelled rest kind")
    let fSummary = DailyTimeline.summary(events: cancelled, day: day, calendar: utc)
    close(fSummary.restSeconds, 0, "timeline cancelled rest is not rest seconds")
    equal(fSummary.cancelledRestCount, 1, "timeline cancelled rest count")
    let fHourly = DailyTimeline.hourlyTotals(events: cancelled, day: day, referenceDate: reference, calendar: utc)
    close(fHourly[11].cancelledRestSeconds, 60, "timeline hourly cancelled rest")

    let oneHour = [HistoryEvent(occurredAt: utcDate(2026, 11, 1, 9, 30), timeZoneIdentifier: "UTC", kind: .screenTime, screenSeconds: 3600)]
    let g = DailyTimeline.hourlyTotals(events: oneHour, day: day, referenceDate: reference, calendar: utc)
    equal(g.count, 24, "timeline hourly has 24 buckets")
    close(g[9].workSeconds, 1800, "timeline hourly first half")
    close(g[10].workSeconds, 1800, "timeline hourly second half")

    equal(DailyTimeline.segments(events: [], day: day, referenceDate: reference, calendar: utc).count, 0, "timeline empty segments")
    let h = DailyTimeline.hourlyTotals(events: [], day: day, referenceDate: reference, calendar: utc)
    check(h.count == 24 && h.allSatisfy { $0.workSeconds == 0 && $0.restSeconds == 0 }, "timeline empty hourly")
    let hSummary = DailyTimeline.summary(events: [], day: day, calendar: utc)
    check(hSummary.workSeconds == 0 && hSummary.restSeconds == 0 && hSummary.reminderCount == 0, "timeline empty summary")

    let runningRestOnly = [HistoryEvent(occurredAt: utcDate(2026, 11, 1, 17, 0), timeZoneIdentifier: "UTC", kind: .restStarted, restSeconds: 600)]
    let runningSummary = DailyTimeline.summary(events: runningRestOnly, day: day, calendar: utc)
    close(runningSummary.restSeconds, 0, "timeline summary ignores a rest still running")
    equal(runningSummary.restCount, 0, "timeline summary does not count a running rest")

    var la = Calendar(identifier: .gregorian)
    la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    let laDay = la.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
    let dst = [HistoryEvent(occurredAt: laDay, timeZoneIdentifier: "America/Los_Angeles", kind: .screenTime, screenSeconds: 25 * 3600)]
    let i = DailyTimeline.hourlyTotals(events: dst, day: laDay, referenceDate: laDay.addingTimeInterval(25 * 3600), calendar: la)
    close(i.reduce(0) { $0 + $1.workSeconds }, 25 * 3600, "timeline DST total")
    close(i[1].workSeconds, 2 * 3600, "timeline DST repeated hour merges")
}

// 32. Reminder scenes (task 6).
do {
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    equal(ReminderSceneCatalog.all.count, 6, "scene catalog has six entries")
    equal(Set(ReminderSceneCatalog.all.map(\.id)).count, 6, "scene ids are unique")
    equal(SceneID.allCases.count, 6, "scene id cases")

    var generator = Seeded(state: 42)
    var picker = ReminderScenePicker()
    var picks: [SceneID] = []
    for _ in 0..<50 { picks.append(picker.next(using: &generator).id) }
    var noRepeat = true
    for index in 1..<picks.count where picks[index] == picks[index - 1] { noRepeat = false }
    check(noRepeat, "scene picker never repeats back to back")

    var generatorA = Seeded(state: 7)
    var pickerA = ReminderScenePicker()
    let runA = (0..<12).map { _ in pickerA.next(using: &generatorA).id.rawValue }
    var generatorB = Seeded(state: 7)
    var pickerB = ReminderScenePicker()
    let runB = (0..<12).map { _ in pickerB.next(using: &generatorB).id.rawValue }
    equal(runA, runB, "scene picker is deterministic for a fixed seed")

    var generatorC = Seeded(state: 99)
    var pickerC = ReminderScenePicker(lastID: .walk)
    check(pickerC.next(using: &generatorC).id != .walk, "scene picker avoids the previous scene")

    check(SceneSymbolResolver.resolvedSymbol(for: ReminderSceneCatalog.scene(for: .restroom), isAvailable: { _ in false }) == "figure.walk", "scene symbol falls back when missing")
    check(SceneSymbolResolver.resolvedSymbol(for: ReminderSceneCatalog.scene(for: .restroom), isAvailable: { _ in true }) == "toilet.fill", "scene symbol keeps the real name when available")

    let banned = ["已起身", "已休息", "你完成了", "你已"]
    var copyClean = true
    for scene in ReminderSceneCatalog.all {
        for word in banned where scene.title.contains(word) || scene.detail.contains(word) { copyClean = false }
    }
    check(copyClean, "scene copy never claims a completed action")

    check(ReminderSceneCatalog.fallback.id == .walk, "scene fallback is walk")
    check(ReminderSceneCatalog.scene(for: .breathe).title == "慢慢呼吸三次", "scene lookup by id")
}

// 33. Reminder scene memory (task 11).
do {
    var picker = ReminderScenePicker()
    picker.remember(.restroom)
    equal(picker.lastID, SceneID.restroom, "scene picker remembers a forced scene")
    var generator = SystemRandomNumberGenerator()
    check(picker.next(using: &generator).id != .restroom, "scene picker skips a remembered scene")
    picker.remember(.breathe)
    equal(picker.lastID, SceneID.breathe, "scene picker remember replaces the previous id")
}

if failures == 0 {
    print("SELFTEST PASSED (\(checks) checks)")
    exit(0)
} else {
    print("SELFTEST FAILED (\(failures) of \(checks) checks)")
    exit(1)
}
