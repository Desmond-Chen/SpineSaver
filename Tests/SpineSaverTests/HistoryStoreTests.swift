import XCTest
import SpineSaverCore

final class HistoryStoreTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("spinesaver-history-\(UUID().uuidString).jsonl")
    }

    func testAppendAndLoad() throws {
        let url = tempURL()
        let store = HistoryStore(fileURL: url)
        let event = HistoryEvent(
            occurredAt: Date(timeIntervalSince1970: 0),
            timeZoneIdentifier: "UTC",
            kind: .restStarted,
            reason: "中文"
        )
        try store.append(event)
        let result = try store.load()
        XCTAssertEqual(result.events, [event])
        XCTAssertEqual(result.skippedLines, 0)
        try store.deleteAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testMalformedLineSkipped() throws {
        let url = tempURL()
        try "not-json\n".write(to: url, atomically: true, encoding: .utf8)
        let store = HistoryStore(fileURL: url)
        let result = try store.load()
        XCTAssertTrue(result.events.isEmpty)
        XCTAssertEqual(result.skippedLines, 1)
        try? FileManager.default.removeItem(at: url)
    }
}
