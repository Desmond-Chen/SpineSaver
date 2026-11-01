import Foundation

public struct RestSnapshot: Codable, Equatable {
    public var schemaVersion: Int
    public var startedAt: Date
    public var duration: TimeInterval
    public var previousPhase: String
    public var previousUsed: TimeInterval
    public var previousReminderPresented: Bool

    public init(
        schemaVersion: Int = 1,
        startedAt: Date,
        duration: TimeInterval,
        previousPhase: String,
        previousUsed: TimeInterval,
        previousReminderPresented: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.startedAt = startedAt
        self.duration = duration
        self.previousPhase = previousPhase
        self.previousUsed = previousUsed
        self.previousReminderPresented = previousReminderPresented
    }

    public func abandonment(at date: Date) -> RestAbandonment {
        RestAbandonment(
            reason: .appRelaunch,
            elapsedSeconds: max(0, date.timeIntervalSince(startedAt))
        )
    }
}

public struct RestAbandonment: Equatable {
    public enum Reason: String, Codable {
        case appRelaunch
    }

    public var reason: Reason
    public var elapsedSeconds: TimeInterval

    public init(reason: Reason, elapsedSeconds: TimeInterval) {
        self.reason = reason
        self.elapsedSeconds = elapsedSeconds
    }
}
