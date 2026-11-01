import Foundation

public struct HistoryExportDocument: Codable, Equatable {
    public var schemaVersion: Int
    public var exportedAt: Date
    public var timeZone: String
    public var units: String
    public var fieldDescriptions: [String: String]
    public var events: [HistoryEvent]

    public init(
        schemaVersion: Int = 1,
        exportedAt: Date,
        timeZone: String,
        units: String = "seconds",
        fieldDescriptions: [String: String],
        events: [HistoryEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.timeZone = timeZone
        self.units = units
        self.fieldDescriptions = fieldDescriptions
        self.events = events
    }
}

public enum HistoryExporter {
    public static func json(
        events: [HistoryEvent],
        exportedAt: Date = Date(),
        timeZone: TimeZone = .current
    ) -> Data {
        let document = HistoryExportDocument(
            exportedAt: exportedAt,
            timeZone: timeZone.identifier,
            fieldDescriptions: fieldDescriptions,
            events: events
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(document)) ?? Data()
    }

    public static func csv(
        events: [HistoryEvent],
        exportedAt: Date = Date(),
        timeZone: TimeZone = .current
    ) -> Data {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var lines: [String] = [
            "# schemaVersion=1",
            "# exportedAt=\(iso.string(from: exportedAt))",
            "# timeZone=\(timeZone.identifier)",
            "# units=seconds",
            "# fieldDescriptions=occurredAt:ISO8601;kind:event type;screenSeconds:seconds;restSeconds:seconds;reason:optional;appVersion:app version"
        ]
        lines.append("schemaVersion,id,occurredAt,timeZoneIdentifier,kind,screenSeconds,restSeconds,reason,appVersion")
        for event in events {
            let fields = [
                String(event.schemaVersion),
                event.id,
                iso.string(from: event.occurredAt),
                event.timeZoneIdentifier,
                event.kind.rawValue,
                event.screenSeconds.map { String($0) } ?? "",
                event.restSeconds.map { String($0) } ?? "",
                event.reason ?? "",
                event.appVersion
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        let text = "\u{FEFF}" + lines.joined(separator: "\n") + "\n"
        return Data(text.utf8)
    }

    private static let fieldDescriptions: [String: String] = [
        "occurredAt": "ISO8601 timestamp with offset",
        "kind": "event type",
        "screenSeconds": "seconds",
        "restSeconds": "seconds",
        "reason": "optional reason",
        "appVersion": "app version"
    ]

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") else {
            return value
        }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
