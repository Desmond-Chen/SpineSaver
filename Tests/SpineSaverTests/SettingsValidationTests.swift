import XCTest
import SpineSaverCore

final class SettingsValidationTests: XCTestCase {
    func testWorkMinutes() {
        XCTAssertEqual(SettingsValidation.clampWorkMinutes(14), 15)
        XCTAssertEqual(SettingsValidation.clampWorkMinutes(121), 120)
        XCTAssertEqual(SettingsValidation.clampWorkMinutes(45), 45)
        XCTAssertFalse(SettingsValidation.canDecreaseWorkMinutes(15))
        XCTAssertFalse(SettingsValidation.canIncreaseWorkMinutes(120))
        XCTAssertTrue(SettingsValidation.canDecreaseWorkMinutes(20))
        XCTAssertTrue(SettingsValidation.canIncreaseWorkMinutes(115))
    }

    func testRestMinutes() {
        XCTAssertEqual(SettingsValidation.clampRestMinutes(1), 2)
        XCTAssertEqual(SettingsValidation.clampRestMinutes(16), 15)
        XCTAssertEqual(SettingsValidation.clampRestMinutes(5), 5)
        XCTAssertFalse(SettingsValidation.canDecreaseRestMinutes(2))
        XCTAssertFalse(SettingsValidation.canIncreaseRestMinutes(15))
        XCTAssertTrue(SettingsValidation.canDecreaseRestMinutes(3))
        XCTAssertTrue(SettingsValidation.canIncreaseRestMinutes(14))
    }

    func testSnoozeMinutesParsing() {
        XCTAssertEqual(SettingsValidation.snoozeMinutesRange, 1...20)
        XCTAssertEqual(SettingsValidation.parseSnoozeMinutes(" 007\n"), 7)
        XCTAssertEqual(SettingsValidation.parseSnoozeMinutes("5"), 5)
        XCTAssertEqual(SettingsValidation.parseSnoozeMinutes("1"), 1)
        XCTAssertEqual(SettingsValidation.parseSnoozeMinutes("20"), 20)
        XCTAssertEqual(SettingsValidation.parseSnoozeMinutes("020"), 20)
        let rejected = [
            "", " ", "\n\t", "0", "00", "21", "-1", "1.5", "1e1",
            "5分钟", "+5", "５", "1 0", String(repeating: "9", count: 400)
        ]
        for text in rejected {
            XCTAssertNil(SettingsValidation.parseSnoozeMinutes(text), "reject \(text.prefix(8))")
        }
    }
}
