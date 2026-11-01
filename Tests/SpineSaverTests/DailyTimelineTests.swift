import XCTest
import SpineSaverCore

final class DailyTimelineTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testCrossMidnightIsClipped() {
        let event = HistoryEvent(occurredAt: date(2026, 10, 31, 23, 59), timeZoneIdentifier: "UTC", kind: .screenTime, screenSeconds: 120)
        let segments = DailyTimeline.segments(events: [event], day: date(2026, 11, 1), referenceDate: date(2026, 11, 1, 23, 59), calendar: utc)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].duration, 60, accuracy: 0.001)
    }

    func testContiguousSlicesAreMerged() {
        let events = (0..<45).map { index in
            HistoryEvent(occurredAt: date(2026, 11, 1, 9, 0).addingTimeInterval(Double(index) * 60), timeZoneIdentifier: "UTC", kind: .screenTime, screenSeconds: 60)
        }
        let segments = DailyTimeline.segments(events: events, day: date(2026, 11, 1), referenceDate: date(2026, 11, 1, 23, 59), calendar: utc)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].duration, 45 * 60, accuracy: 0.001)
    }

    func testGapIsKept() {
        let events = [
            HistoryEvent(occurredAt: date(2026, 11, 1, 9, 0), timeZoneIdentifier: "UTC", kind: .screenTime, screenSeconds: 60),
            HistoryEvent(occurredAt: date(2026, 11, 1, 9, 2), timeZoneIdentifier: "UTC", kind: .screenTime, screenSeconds: 60)
        ]
        XCTAssertEqual(DailyTimeline.segments(events: events, day: date(2026, 11, 1), referenceDate: date(2026, 11, 1, 23, 59), calendar: utc).count, 2)
    }

    func testCompletedRestIsNotDoubleCounted() {
        let events = [
            HistoryEvent(occurredAt: date(2026, 11, 1, 10, 0), timeZoneIdentifier: "UTC", kind: .restStarted, restSeconds: 120),
            HistoryEvent(occurredAt: date(2026, 11, 1, 10, 2), timeZoneIdentifier: "UTC", kind: .restAutoCompleted, restSeconds: 120)
        ]
        let segments = DailyTimeline.segments(events: events, day: date(2026, 11, 1), referenceDate: date(2026, 11, 1, 23, 59), calendar: utc)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .rest)
        XCTAssertEqual(segments[0].duration, 120, accuracy: 0.001)
    }

    func testInProgressRestStopsAtReference() {
        let events = [HistoryEvent(occurredAt: date(2026, 11, 1, 11, 0), timeZoneIdentifier: "UTC", kind: .restStarted, restSeconds: 600)]
        let segments = DailyTimeline.segments(events: events, day: date(2026, 11, 1), referenceDate: date(2026, 11, 1, 11, 2), calendar: utc)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].duration, 120, accuracy: 0.001)
    }

    func testCancelledRestIsSeparate() {
        let events = [HistoryEvent(occurredAt: date(2026, 11, 1, 12, 0), timeZoneIdentifier: "UTC", kind: .restCancelled, restSeconds: 60)]
        let segments = DailyTimeline.segments(events: events, day: date(2026, 11, 1), referenceDate: date(2026, 11, 1, 23, 59), calendar: utc)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].kind, .restCancelled)
        let summary = DailyTimeline.summary(events: events, day: date(2026, 11, 1), calendar: utc)
        XCTAssertEqual(summary.restSeconds, 0, accuracy: 0.001)
        XCTAssertEqual(summary.cancelledRestCount, 1)
    }

    func testHourlySplitsAtBoundary() {
        let events = [HistoryEvent(occurredAt: date(2026, 11, 1, 9, 30), timeZoneIdentifier: "UTC", kind: .screenTime, screenSeconds: 3600)]
        let totals = DailyTimeline.hourlyTotals(events: events, day: date(2026, 11, 1), referenceDate: date(2026, 11, 1, 23, 59), calendar: utc)
        XCTAssertEqual(totals.count, 24)
        XCTAssertEqual(totals[9].workSeconds, 1800, accuracy: 0.001)
        XCTAssertEqual(totals[10].workSeconds, 1800, accuracy: 0.001)
    }

    func testEmptyDay() {
        let day = date(2026, 11, 1)
        XCTAssertTrue(DailyTimeline.segments(events: [], day: day, referenceDate: day, calendar: utc).isEmpty)
        let totals = DailyTimeline.hourlyTotals(events: [], day: day, referenceDate: day, calendar: utc)
        XCTAssertEqual(totals.count, 24)
        XCTAssertTrue(totals.allSatisfy { $0.workSeconds == 0 && $0.restSeconds == 0 })
        XCTAssertEqual(DailyTimeline.summary(events: [], day: day, calendar: utc), TodaySummary())
    }

    func testDSTFallBackMergesRepeatedHour() {
        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let day = la.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 0))!
        let events = [HistoryEvent(occurredAt: day, timeZoneIdentifier: "America/Los_Angeles", kind: .screenTime, screenSeconds: 25 * 3600)]
        let totals = DailyTimeline.hourlyTotals(events: events, day: day, referenceDate: day.addingTimeInterval(25 * 3600), calendar: la)
        XCTAssertEqual(totals.count, 24)
        XCTAssertEqual(totals.reduce(0) { $0 + $1.workSeconds }, 25 * 3600, accuracy: 0.001)
        XCTAssertEqual(totals[1].workSeconds, 2 * 3600, accuracy: 0.001)
    }
}
