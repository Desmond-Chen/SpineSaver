import Foundation

public enum HistoryEventKind: String, Codable, CaseIterable {
    case screenTime
    case reminderPresented
    case snoozed
    case restStarted
    case restAutoCompleted
    case restFinishedEarly
    case restCancelled
    case restAbandoned
}

public struct HistoryEvent: Codable, Equatable, Identifiable {
    public var schemaVersion: Int
    public var id: String
    public var occurredAt: Date
    public var timeZoneIdentifier: String
    public var kind: HistoryEventKind
    public var screenSeconds: Double?
    public var restSeconds: Double?
    public var reason: String?
    public var appVersion: String

    public init(
        schemaVersion: Int = 1,
        id: String = UUID().uuidString,
        occurredAt: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier,
        kind: HistoryEventKind,
        screenSeconds: Double? = nil,
        restSeconds: Double? = nil,
        reason: String? = nil,
        appVersion: String = "unknown"
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.occurredAt = occurredAt
        self.timeZoneIdentifier = timeZoneIdentifier
        self.kind = kind
        self.screenSeconds = screenSeconds
        self.restSeconds = restSeconds
        self.reason = reason
        self.appVersion = appVersion
    }
}
