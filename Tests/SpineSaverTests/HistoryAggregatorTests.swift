import XCTest
import SpineSaverCore

final class HistoryAggregatorTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private var losAngeles: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func testDailyScreenTimeSplitsAtMidnight() {
        let calendar = utc
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 59))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let event = HistoryEvent(
            occurredAt: start,
            timeZoneIdentifier: "UTC",
            kind: .screenTime,
            screenSeconds: 120
        )
        let buckets = HistoryAggregator.daily(events: [event], from: start, to: end, calendar: calendar)
        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].screenSeconds, 60, accuracy: 0.001)
        XCTAssertEqual(buckets[1].screenSeconds, 60, accuracy: 0.001)
    }

    func testDSTSpringForward() {
        let calendar = losAngeles
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let event = HistoryEvent(
            occurredAt: start,
            timeZoneIdentifier: "America/Los_Angeles",
            kind: .screenTime,
            screenSeconds: 24 * 3600
        )
        let buckets = HistoryAggregator.daily(events: [event], from: start, to: end, calendar: calendar)
        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].screenSeconds, 23 * 3600, accuracy: 1)
        XCTAssertEqual(buckets[1].screenSeconds, 1 * 3600, accuracy: 1)
    }

    func testDSTFallBack() {
        let calendar = losAngeles
        let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let event = HistoryEvent(
            occurredAt: start,
            timeZoneIdentifier: "America/Los_Angeles",
            kind: .screenTime,
            screenSeconds: 25 * 3600
        )
        let buckets = HistoryAggregator.daily(events: [event], from: start, to: end, calendar: calendar)
        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].screenSeconds, 25 * 3600, accuracy: 1)
        XCTAssertEqual(buckets[1].screenSeconds, 0, accuracy: 1)
    }

    func testEmptyRange() {
        let calendar = utc
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3))!
        let buckets = HistoryAggregator.daily(events: [], from: start, to: end, calendar: calendar)
        XCTAssertEqual(buckets.count, 3)
        XCTAssertTrue(buckets.allSatisfy { $0.screenSeconds == 0 && $0.reminderCount == 0 })
    }

    func testCountsAndWeekly() {
        let calendar = utc
        let jan1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 10))!
        let jan2 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 10))!
        let jan5 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 10))!
        let events = [
            HistoryEvent(occurredAt: jan1, timeZoneIdentifier: "UTC", kind: .reminderPresented),
            HistoryEvent(occurredAt: jan1, timeZoneIdentifier: "UTC", kind: .snoozed),
            HistoryEvent(occurredAt: jan2, timeZoneIdentifier: "UTC", kind: .restStarted),
            HistoryEvent(occurredAt: jan5, timeZoneIdentifier: "UTC", kind: .restAutoCompleted)
        ]
        let daily = HistoryAggregator.daily(events: events, from: jan1, to: jan5, calendar: calendar)
        XCTAssertEqual(daily.count, 5)
        XCTAssertEqual(daily[0].reminderCount, 1)
        XCTAssertEqual(daily[0].snoozeCount, 1)
        XCTAssertEqual(daily[1].restStartedCount, 1)
        XCTAssertEqual(daily[4].restAutoCompletedCount, 1)

        let weekly = HistoryAggregator.weekly(events: events, from: jan1, to: jan5, calendar: calendar)
        XCTAssertEqual(weekly.count, 2)
        XCTAssertEqual(weekly[0].reminderCount, 1)
        XCTAssertEqual(weekly[0].snoozeCount, 1)
        XCTAssertEqual(weekly[0].restStartedCount, 1)
        XCTAssertEqual(weekly[1].restAutoCompletedCount, 1)
    }
}
