import Foundation
import SpineSaverCore

enum ReminderStyle: String, CaseIterable, Identifiable {
    case miniPanel
    case systemNotification

    var id: String { rawValue }

    var title: String {
        switch self {
        case .miniPanel: return "迷你弹窗"
        case .systemNotification: return "系统通知"
        }
    }

    var explanation: String {
        switch self {
        case .miniPanel:
            return "不抢输入焦点，显示在当前屏幕右上角；系统专注模式不会自动隐藏它。"
        case .systemNotification:
            return "遵循 macOS 通知与专注模式；若未授权或被隐藏，菜单栏仍会停在到点状态。"
        }
    }
}

struct AppSettings: Equatable {
    var workMinutes: Int = 45
    var restMinutes: Int = 2
    var reminderStyle: ReminderStyle = .miniPanel
    var launchAtLogin: Bool = false

    var cycleConfiguration: BreakCycleConfiguration {
        var config = BreakCycleConfiguration.standard
        config.workInterval = Double(workMinutes) * 60
        config.suggestedRestDuration = Double(restMinutes) * 60
        return config
    }
}

protocol PreferencesStoring: AnyObject {
    func loadSettings() -> AppSettings
    func saveSettings(_ settings: AppSettings)
    func loadUsage() -> TimeInterval?
    func saveUsage(_ seconds: TimeInterval)
    func loadRestSnapshot() -> RestSnapshot?
    func saveRestSnapshot(_ snapshot: RestSnapshot)
    func clearRestSnapshot()
}

final class PreferencesStore: PreferencesStoring {
    private enum Key {
        static let workMinutes = "spinesaver.workMinutes"
        static let restMinutes = "spinesaver.restMinutes"
        static let reminderStyle = "spinesaver.reminderStyle"
        static let launchAtLogin = "spinesaver.launchAtLogin"
        static let usedSeconds = "spinesaver.usedSeconds"
        static let hasUsage = "spinesaver.hasUsage"
        static let restSnapshot = "spinesaver.restSnapshot"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func loadSettings() -> AppSettings {
        var settings = AppSettings()
        let minutes = defaults.integer(forKey: Key.workMinutes)
        if minutes >= 15, minutes <= 120 {
            settings.workMinutes = minutes
        }
        let rest = defaults.integer(forKey: Key.restMinutes)
        if rest >= 2, rest <= 15 {
            settings.restMinutes = rest
        }
        if let raw = defaults.string(forKey: Key.reminderStyle),
           let style = ReminderStyle(rawValue: raw) {
            settings.reminderStyle = style
        }
        settings.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
        return settings
    }

    func saveSettings(_ settings: AppSettings) {
        defaults.set(settings.workMinutes, forKey: Key.workMinutes)
        defaults.set(settings.restMinutes, forKey: Key.restMinutes)
        defaults.set(settings.reminderStyle.rawValue, forKey: Key.reminderStyle)
        defaults.set(settings.launchAtLogin, forKey: Key.launchAtLogin)
    }

    func loadUsage() -> TimeInterval? {
        guard defaults.bool(forKey: Key.hasUsage) else { return nil }
        return max(0, defaults.double(forKey: Key.usedSeconds))
    }

    func saveUsage(_ seconds: TimeInterval) {
        defaults.set(max(0, seconds), forKey: Key.usedSeconds)
        defaults.set(true, forKey: Key.hasUsage)
    }

    func loadRestSnapshot() -> RestSnapshot? {
        guard let data = defaults.data(forKey: Key.restSnapshot) else { return nil }
        return try? JSONDecoder().decode(RestSnapshot.self, from: data)
    }

    func saveRestSnapshot(_ snapshot: RestSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Key.restSnapshot)
    }

    func clearRestSnapshot() {
        defaults.removeObject(forKey: Key.restSnapshot)
    }
}
