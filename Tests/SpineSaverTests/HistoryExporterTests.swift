import XCTest
import SpineSaverCore

final class HistoryExporterTests: XCTestCase {
    func testJSONMetadataAndEvents() throws {
        let event = HistoryEvent(
            occurredAt: Date(timeIntervalSince1970: 0),
            timeZoneIdentifier: "UTC",
            kind: .restStarted,
            reason: "中文"
        )
        let data = HistoryExporter.json(
            events: [event],
            exportedAt: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(identifier: "UTC")!
        )
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertEqual(object["units"] as? String, "seconds")
        XCTAssertEqual(object["timeZone"] as? String, "UTC")
        XCTAssertNotNil(object["fieldDescriptions"])
        XCTAssertEqual((object["events"] as? [[String: Any]])?.count, 1)
        XCTAssertFalse(data.starts(with: [0xEF, 0xBB, 0xBF]))
    }

    func testCSVMetadataAndEscaping() {
        let event = HistoryEvent(
            occurredAt: Date(timeIntervalSince1970: 0),
            timeZoneIdentifier: "UTC",
            kind: .restStarted,
            reason: "中文, \"quoted\""
        )
        let data = HistoryExporter.csv(
            events: [event],
            exportedAt: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(identifier: "UTC")!
        )
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(data.starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertTrue(text.contains("# schemaVersion=1"))
        XCTAssertTrue(text.contains("restStarted"))
        XCTAssertTrue(text.contains("\"中文, \"\"quoted\"\"\""))

        let newline = HistoryEvent(
            occurredAt: Date(timeIntervalSince1970: 0),
            timeZoneIdentifier: "UTC",
            kind: .restStarted,
            reason: "line1\nline2"
        )
        let newlineData = HistoryExporter.csv(
            events: [newline],
            exportedAt: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(identifier: "UTC")!
        )
        XCTAssertTrue(String(decoding: newlineData, as: UTF8.self).contains("\"line1\nline2\""))
    }

    func testEmptyExport() {
        let data = HistoryExporter.csv(
            events: [],
            exportedAt: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(identifier: "UTC")!
        )
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("schemaVersion,id,occurredAt"))
    }
}
