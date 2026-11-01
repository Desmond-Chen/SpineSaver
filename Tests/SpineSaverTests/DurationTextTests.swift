import XCTest
import SpineSaverCore

final class DurationTextTests: XCTestCase {
    func testCompact() {
        XCTAssertEqual(DurationText.compact(seconds: 0), "0 分")
        XCTAssertEqual(DurationText.compact(seconds: 59), "1 分")
        XCTAssertEqual(DurationText.compact(seconds: 60), "1 分")
        XCTAssertEqual(DurationText.compact(seconds: 2700), "45 分")
        XCTAssertEqual(DurationText.compact(seconds: 3600), "1 小时")
        XCTAssertEqual(DurationText.compact(seconds: 4800), "1 小时 20 分")
        XCTAssertEqual(DurationText.compact(seconds: -5), "0 分")
    }

    func testAxis() {
        XCTAssertEqual(DurationText.axis(seconds: 0), "0 分")
        XCTAssertEqual(DurationText.axis(seconds: 4800), "80 分")
    }
}
