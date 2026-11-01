import Foundation

public struct HistoryBucket: Equatable, Identifiable {
    public var startDate: Date
    public var screenSeconds: Double
    public var reminderCount: Int
    public var snoozeCount: Int
    public var restStartedCount: Int
    public var restAutoCompletedCount: Int
    public var restFinishedEarlyCount: Int
    public var restCancelledCount: Int
    public var restAbandonedCount: Int

    public var id: Date { startDate }

    public init(
        startDate: Date,
        screenSeconds: Double = 0,
        reminderCount: Int = 0,
        snoozeCount: Int = 0,
        restStartedCount: Int = 0,
        restAutoCompletedCount: Int = 0,
        restFinishedEarlyCount: Int = 0,
        restCancelledCount: Int = 0,
        restAbandonedCount: Int = 0
    ) {
        self.startDate = startDate
        self.screenSeconds = screenSeconds
        self.reminderCount = reminderCount
        self.snoozeCount = snoozeCount
        self.restStartedCount = restStartedCount
        self.restAutoCompletedCount = restAutoCompletedCount
        self.restFinishedEarlyCount = restFinishedEarlyCount
        self.restCancelledCount = restCancelledCount
        self.restAbandonedCount = restAbandonedCount
    }
}

public enum HistoryAggregator {
    public static func daily(
        events: [HistoryEvent],
        from: Date,
        to: Date,
        calendar: Calendar
    ) -> [HistoryBucket] {
        let start = calendar.startOfDay(for: from)
        let end = calendar.startOfDay(for: to)
        var buckets: [Date: HistoryBucket] = [:]
        var day = start
        while day <= end {
            buckets[day] = HistoryBucket(startDate: day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        for event in events {
            switch event.kind {
            case .screenTime:
                guard let seconds = event.screenSeconds, seconds > 0 else { continue }
                for (dayStart, part) in split(start: event.occurredAt, seconds: seconds, calendar: calendar) {
                    mutate(&buckets, at: dayStart) { $0.screenSeconds += part }
                }
            case .reminderPresented:
                mutate(&buckets, at: calendar.startOfDay(for: event.occurredAt)) { $0.reminderCount += 1 }
            case .snoozed:
                mutate(&buckets, at: calendar.startOfDay(for: event.occurredAt)) { $0.snoozeCount += 1 }
            case .restStarted:
                mutate(&buckets, at: calendar.startOfDay(for: event.occurredAt)) { $0.restStartedCount += 1 }
            case .restAutoCompleted:
                mutate(&buckets, at: calendar.startOfDay(for: event.occurredAt)) { $0.restAutoCompletedCount += 1 }
            case .restFinishedEarly:
                mutate(&buckets, at: calendar.startOfDay(for: event.occurredAt)) { $0.restFinishedEarlyCount += 1 }
            case .restCancelled:
                mutate(&buckets, at: calendar.startOfDay(for: event.occurredAt)) { $0.restCancelledCount += 1 }
            case .restAbandoned:
                mutate(&buckets, at: calendar.startOfDay(for: event.occurredAt)) { $0.restAbandonedCount += 1 }
            }
        }

        return buckets.values.sorted { $0.startDate < $1.startDate }
    }

    public static func weekly(
        events: [HistoryEvent],
        from: Date,
        to: Date,
        calendar: Calendar
    ) -> [HistoryBucket] {
        var iso = calendar
        iso.firstWeekday = 2
        iso.minimumDaysInFirstWeek = 4
        let days = daily(events: events, from: from, to: to, calendar: iso)
        var buckets: [Date: HistoryBucket] = [:]

        for day in days {
            let weekStart = iso.dateInterval(of: .weekOfYear, for: day.startDate)?.start
                ?? iso.startOfDay(for: day.startDate)
            if var bucket = buckets[weekStart] {
                bucket.screenSeconds += day.screenSeconds
                bucket.reminderCount += day.reminderCount
                bucket.snoozeCount += day.snoozeCount
                bucket.restStartedCount += day.restStartedCount
                bucket.restAutoCompletedCount += day.restAutoCompletedCount
                bucket.restFinishedEarlyCount += day.restFinishedEarlyCount
                bucket.restCancelledCount += day.restCancelledCount
                bucket.restAbandonedCount += day.restAbandonedCount
                buckets[weekStart] = bucket
            } else {
                var bucket = day
                bucket.startDate = weekStart
                buckets[weekStart] = bucket
            }
        }

        return buckets.values.sorted { $0.startDate < $1.startDate }
    }

    private static func mutate(
        _ buckets: inout [Date: HistoryBucket],
        at day: Date,
        _ body: (inout HistoryBucket) -> Void
    ) {
        guard var bucket = buckets[day] else { return }
        body(&bucket)
        buckets[day] = bucket
    }

    private static func split(
        start: Date,
        seconds: TimeInterval,
        calendar: Calendar
    ) -> [(Date, TimeInterval)] {
        var cursor = start
        var remaining = seconds
        var result: [(Date, TimeInterval)] = []
        while remaining > 0.0001 {
            let dayStart = calendar.startOfDay(for: cursor)
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { break }
            let available = nextDay.timeIntervalSince(cursor)
            if available <= 0 { break }
            let take = min(remaining, available)
            result.append((dayStart, take))
            cursor = cursor.addingTimeInterval(take)
            remaining -= take
        }
        return result
    }
}
