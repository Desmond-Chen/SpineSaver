import Foundation

public enum SettingsValidation {
    public static let workMinutesRange = 15...120
    public static let workMinutesStep = 5
    public static let restMinutesRange = 2...15
    public static let restMinutesStep = 1

    public static func clampWorkMinutes(_ value: Int) -> Int {
        min(workMinutesRange.upperBound, max(workMinutesRange.lowerBound, value))
    }

    public static func canDecreaseWorkMinutes(_ value: Int) -> Bool {
        value > workMinutesRange.lowerBound
    }

    public static func canIncreaseWorkMinutes(_ value: Int) -> Bool {
        value < workMinutesRange.upperBound
    }

    public static func clampRestMinutes(_ value: Int) -> Int {
        min(restMinutesRange.upperBound, max(restMinutesRange.lowerBound, value))
    }

    public static func canDecreaseRestMinutes(_ value: Int) -> Bool {
        value > restMinutesRange.lowerBound
    }

    public static func canIncreaseRestMinutes(_ value: Int) -> Bool {
        value < restMinutesRange.upperBound
    }
}
