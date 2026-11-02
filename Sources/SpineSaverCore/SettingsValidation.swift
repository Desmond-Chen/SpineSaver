import Foundation

public enum SettingsValidation {
    public static let workMinutesRange = 15...120
    public static let workMinutesStep = 5
    public static let restMinutesRange = 2...15
    public static let restMinutesStep = 1
    /// Single-use custom snooze window, in whole minutes (plan task 2).
    public static let snoozeMinutesRange = 1...20

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

    /// Parses a single-use snooze duration. Only ASCII decimal integers in
    /// `snoozeMinutesRange` are valid; surrounding whitespace is trimmed and
    /// leading zeros are allowed. Everything else — empty text, 0, out of
    /// range, signs, decimal points, exponents, units, full-width digits,
    /// internal whitespace or an integer too large for Int — returns nil.
    public static func parseSnoozeMinutes(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.allSatisfy({ $0.isASCII && $0.isNumber }),
              let minutes = Int(trimmed),
              snoozeMinutesRange.contains(minutes) else { return nil }
        return minutes
    }
}
