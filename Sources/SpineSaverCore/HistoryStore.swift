import Foundation

public struct HistoryLoadResult: Equatable {
    public var events: [HistoryEvent]
    public var skippedLines: Int

    public init(events: [HistoryEvent], skippedLines: Int) {
        self.events = events
        self.skippedLines = skippedLines
    }
}

public final class HistoryStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("SpineSaver", isDirectory: true)
            .appendingPathComponent("history.jsonl")
    }

    public func append(_ event: HistoryEvent) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        var data = try Self.encoder.encode(event)
        data.append(0x0A)
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    public func load() throws -> HistoryLoadResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return HistoryLoadResult(events: [], skippedLines: 0)
        }
        let data = try Data(contentsOf: fileURL)
        let text = String(decoding: data, as: UTF8.self)
        var events: [HistoryEvent] = []
        var skippedLines = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            guard let lineData = line.data(using: .utf8),
                  let event = try? Self.decoder.decode(HistoryEvent.self, from: lineData) else {
                skippedLines += 1
                continue
            }
            events.append(event)
        }
        return HistoryLoadResult(events: events, skippedLines: skippedLines)
    }

    public func deleteAll() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    public func dateRange() throws -> ClosedRange<Date>? {
        let events = try load().events
        guard let first = events.map(\.occurredAt).min(),
              let last = events.map(\.occurredAt).max() else {
            return nil
        }
        return first...last
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoFormatter.string(from: date))
        }
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = isoFormatter.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date")
            }
            return date
        }
        return decoder
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
