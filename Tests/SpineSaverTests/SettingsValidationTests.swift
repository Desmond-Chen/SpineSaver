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
}
