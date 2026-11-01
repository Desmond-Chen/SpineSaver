import Foundation

/// Shared duration wording so every surface renders the same unit.
public enum DurationText {
    /// Human summary: "0 分", "45 分", "1 小时", "1 小时 20 分".
    public static func compact(seconds: Double) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        if minutes < 60 { return "\(minutes) 分" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分"
    }

    /// Axis tick wording: whole minutes with the unit, never hours, so ticks stay readable.
    public static func axis(seconds: Double) -> String {
        "\(Int((max(0, seconds) / 60).rounded())) 分"
    }
}
