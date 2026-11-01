import Foundation

public enum TimelineKind: String, Equatable, CaseIterable {
    case work
    case rest
    case restCancelled
    case reminder
}

public struct TimelineSegment: Equatable {
    public var kind: TimelineKind
    public var start: Date
    public var end: Date

    public init(kind: TimelineKind, start: Date, end: Date) {
        self.kind = kind
        self.start = start
        self.end = end
    }

    public var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

public struct HourlyTotal: Equatable {
    public var hour: Int
    public var workSeconds: Double
    public var restSeconds: Double
    public var cancelledRestSeconds: Double

    public init(hour: Int, workSeconds: Double = 0, restSeconds: Double = 0, cancelledRestSeconds: Double = 0) {
        self.hour = hour
        self.workSeconds = workSeconds
        self.restSeconds = restSeconds
        self.cancelledRestSeconds = cancelledRestSeconds
    }
}

public struct TodaySummary: Equatable {
    public var workSeconds: Double
    public var restSeconds: Double
    public var restCount: Int
    public var cancelledRestCount: Int
    public var reminderCount: Int
    public var snoozeCount: Int

    public init(
        workSeconds: Double = 0,
        restSeconds: Double = 0,
        restCount: Int = 0,
        cancelledRestCount: Int = 0,
        reminderCount: Int = 0,
        snoozeCount: Int = 0
    ) {
        self.workSeconds = workSeconds
        self.restSeconds = restSeconds
        self.restCount = restCount
        self.cancelledRestCount = cancelledRestCount
        self.reminderCount = reminderCount
        self.snoozeCount = snoozeCount
    }
}

/// Rebuilds one calendar day of work and rest from the existing event log.
/// No new event kinds: every interval is derived from a timestamp plus the
/// duration the app already recorded on that event.
public enum DailyTimeline {
    public static func segments(
        events: [HistoryEvent],
        day: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> [TimelineSegment] {
        let window = dayWindow(for: day, calendar: calendar)
        var raw: [TimelineSegment] = []
        var pendingRest: [TimelineSegment] = []

        for event in events {
            switch event.kind {
            case .screenTime:
                guard let seconds = event.screenSeconds, seconds > 0 else { continue }
                raw.append(TimelineSegment(
                    kind: .work,
                    start: event.occurredAt,
                    end: event.occurredAt.addingTimeInterval(seconds)
                ))
            case .restAutoCompleted, .restFinishedEarly:
                guard let seconds = event.restSeconds, seconds > 0 else { continue }
                raw.append(TimelineSegment(
                    kind: .rest,
                    start: event.occurredAt.addingTimeInterval(-seconds),
                    end: event.occurredAt
                ))
            case .restCancelled:
                guard let seconds = event.restSeconds, seconds > 0 else { continue }
                raw.append(TimelineSegment(
                    kind: .restCancelled,
                    start: event.occurredAt.addingTimeInterval(-seconds),
                    end: event.occurredAt
                ))
            case .reminderPresented:
                raw.append(TimelineSegment(kind: .reminder, start: event.occurredAt, end: event.occurredAt))
            case .restStarted:
                guard let seconds = event.restSeconds, seconds > 0 else { continue }
                pendingRest.append(TimelineSegment(
                    kind: .rest,
                    start: event.occurredAt,
                    end: event.occurredAt.addingTimeInterval(min(seconds, max(0, referenceDate.timeIntervalSince(event.occurredAt))))
                ))
            case .snoozed, .restAbandoned:
                continue
            }
        }

        // A rest that has no terminal event yet is still running; only add it
        // when no confirmed rest interval already covers it.
        for pending in pendingRest {
            let overlapsConfirmed = raw.contains { confirmed in
                (confirmed.kind == .rest || confirmed.kind == .restCancelled)
                    && confirmed.start < pending.end
                    && pending.start < confirmed.end
            }
            if !overlapsConfirmed {
                raw.append(pending)
            }
        }

        let clipped = raw.compactMap { clip($0, to: window) }.sorted(by: isOrderedBefore)
        return coalesced(clipped)
    }

    public static func hourlyTotals(
        events: [HistoryEvent],
        day: Date,
        referenceDate: Date,
        calendar: Calendar
    ) -> [HourlyTotal] {
        var totals = (0..<24).map { HourlyTotal(hour: $0) }
        for segment in segments(events: events, day: day, referenceDate: referenceDate, calendar: calendar)
        where segment.duration > 0 {
            var cursor = segment.start
            while cursor < segment.end {
                let hour = calendar.component(.hour, from: cursor)
                let boundary = calendar.dateInterval(of: .hour, for: cursor)?.end
                    ?? cursor.addingTimeInterval(3600)
                let stepEnd = min(segment.end, boundary)
                let seconds = stepEnd.timeIntervalSince(cursor)
                if seconds <= 0 { break }
                if hour >= 0, hour < 24 {
                    switch segment.kind {
                    case .work:
                        totals[hour].workSeconds += seconds
                    case .rest:
                        totals[hour].restSeconds += seconds
                    case .restCancelled:
                        totals[hour].cancelledRestSeconds += seconds
                    case .reminder:
                        break
                    }
                }
                cursor = stepEnd
            }
        }
        return totals
    }

    public static func summary(
        events: [HistoryEvent],
        day: Date,
        calendar: Calendar
    ) -> TodaySummary {
        let window = dayWindow(for: day, calendar: calendar)
        var result = TodaySummary()
        for event in events where event.occurredAt >= window.start && event.occurredAt < window.end {
            switch event.kind {
            case .restAutoCompleted, .restFinishedEarly:
                result.restCount += 1
            case .restCancelled:
                result.cancelledRestCount += 1
            case .reminderPresented:
                result.reminderCount += 1
            case .snoozed:
                result.snoozeCount += 1
            case .screenTime, .restStarted, .restAbandoned:
                break
            }
        }
        // Only finished rests feed the summary: a rest still running has no terminal
        // event, so its planned duration must never be counted as time taken.
        for segment in segments(events: events, day: day, referenceDate: window.start, calendar: calendar) {
            switch segment.kind {
            case .work:
                result.workSeconds += segment.duration
            case .rest:
                result.restSeconds += segment.duration
            case .restCancelled, .reminder:
                break
            }
        }
        return result
    }

    private static func dayWindow(for day: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(24 * 3600)
        return (start, end)
    }

    private static func clip(
        _ segment: TimelineSegment,
        to window: (start: Date, end: Date)
    ) -> TimelineSegment? {
        if segment.start == segment.end {
            guard segment.start >= window.start, segment.start < window.end else { return nil }
            return segment
        }
        let start = max(segment.start, window.start)
        let end = min(segment.end, window.end)
        guard end > start else { return nil }
        return TimelineSegment(kind: segment.kind, start: start, end: end)
    }

    private static func isOrderedBefore(_ lhs: TimelineSegment, _ rhs: TimelineSegment) -> Bool {
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        return kindOrder(lhs.kind) < kindOrder(rhs.kind)
    }

    private static func kindOrder(_ kind: TimelineKind) -> Int {
        switch kind {
        case .work: return 0
        case .rest: return 1
        case .restCancelled: return 2
        case .reminder: return 3
        }
    }

    private static func coalesced(_ segments: [TimelineSegment]) -> [TimelineSegment] {
        var merged: [TimelineSegment] = []
        for segment in segments {
            if var last = merged.last,
               last.kind == segment.kind,
               segment.start.timeIntervalSince(last.end) <= 1 {
                if segment.end > last.end { last.end = segment.end }
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }
        return merged
    }
}
