import Foundation

public enum MenuBarText {
    public static func label(
        phase: BreakPhase,
        percent: Int,
        restRemaining: TimeInterval,
        awaitingNextCycle: Bool
    ) -> String {
        switch phase {
        case .resting:
            return "☕ \(clock(restRemaining))"
        case .paused where awaitingNextCycle:
            return "▶ 开始"
        case .counting, .due, .paused, .snoozed:
            return "● \(clampedPercent(percent))%"
        }
    }

    public static func accessibilityLabel(
        phase: BreakPhase,
        percent: Int,
        restRemaining: TimeInterval,
        awaitingNextCycle: Bool
    ) -> String {
        switch phase {
        case .resting:
            return "SpineSaver 休息中，剩余 \(spoken(restRemaining))"
        case .paused where awaitingNextCycle:
            return "SpineSaver 休息倒计时已结束，待开始新一轮"
        case .counting:
            return "SpineSaver 工作中，本轮进度 \(clampedPercent(percent))%"
        case .due:
            return "SpineSaver 已到点，本轮进度 \(clampedPercent(percent))%"
        case .snoozed:
            return "SpineSaver 已推迟，本轮进度 \(clampedPercent(percent))%"
        case .paused:
            return "SpineSaver 已暂停，本轮进度 \(clampedPercent(percent))%"
        }
    }

    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private static func spoken(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        return "\(total / 60) 分 \(total % 60) 秒"
    }

    private static func clampedPercent(_ percent: Int) -> Int {
        min(100, max(0, percent))
    }
}
