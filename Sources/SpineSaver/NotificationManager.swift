import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    enum Action: Equatable {
        case rest(sessionID: String, generation: Int)
        case snooze(sessionID: String, generation: Int, minutes: Int)
        case resume(sessionID: String, generation: Int, opportunityID: String)
    }

    static let categoryIdentifier = "SPINESAVER_BREAK"
    static let restActionIdentifier = "SPINESAVER_REST"
    /// Legacy action identifier: notifications already delivered with the old
    /// category registration keep their ten-minute meaning. Newly registered
    /// notifications use `snooze5ActionIdentifier`.
    static let snoozeActionIdentifier = "SPINESAVER_SNOOZE"
    static let snooze5ActionIdentifier = "SPINESAVER_SNOOZE_5"
    static let legacySnoozeMinutes = 10
    static let defaultSnoozeMinutes = 5
    static let sessionKey = "sessionID"
    static let generationKey = "generation"
    static let resumeCategoryIdentifier = "SPINESAVER_RESUME"
    static let startNextCycleActionIdentifier = "SPINESAVER_START_NEXT_CYCLE"
    static let opportunityKey = "opportunityID"

    var onAction: ((Action) -> Void)?
    var onDeliveryError: ((String) -> Void)?

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let rest = UNNotificationAction(
            identifier: Self.restActionIdentifier,
            title: "开始休息",
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: Self.snooze5ActionIdentifier,
            title: "5 分钟后提醒",
            options: []
        )
        let startNext = UNNotificationAction(
            identifier: Self.startNextCycleActionIdentifier,
            title: "开始新一轮",
            options: []
        )
        let breakCategory = UNNotificationCategory(
            identifier: Self.categoryIdentifier,
            actions: [rest, snooze],
            intentIdentifiers: [],
            options: []
        )
        let resumeCategory = UNNotificationCategory(
            identifier: Self.resumeCategoryIdentifier,
            actions: [startNext],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([breakCategory, resumeCategory])
    }

    func requestAuthorization() async -> Bool {
        await withCheckedContinuation { [weak self] continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    DispatchQueue.main.async { [weak self] in
                        self?.onDeliveryError?(error.localizedDescription)
                    }
                }
                continuation.resume(returning: granted)
            }
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// The token binds a notification action to the app session and cycle that
    /// produced it, so a notification left in Notification Center cannot mutate
    /// a later cycle after the user has already rested or the app relaunched.
    func deliver(sessionID: String, generation: Int, body: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "起来走一走"
        content.body = body ?? "也可以喝点水，按需去洗手间。"
        content.categoryIdentifier = Self.categoryIdentifier
        content.sound = .default
        content.userInfo = [
            Self.sessionKey: sessionID,
            Self.generationKey: generation
        ]

        let request = UNNotificationRequest(
            identifier: "spinesaver-break-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.onDeliveryError?(error.localizedDescription)
            }
        }
    }

    func deliverResume(sessionID: String, generation: Int, opportunityID: String) {
        let content = UNMutableNotificationContent()
        content.title = "休息倒计时已结束"
        content.body = "休息倒计时已结束"
        content.categoryIdentifier = Self.resumeCategoryIdentifier
        content.userInfo = [
            Self.sessionKey: sessionID,
            Self.generationKey: generation,
            Self.opportunityKey: opportunityID
        ]

        let request = UNNotificationRequest(
            identifier: "spinesaver-resume-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async {
                self?.onDeliveryError?(error.localizedDescription)
            }
        }
    }

    static func decodeAction(
        actionIdentifier: String,
        categoryIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> Action? {
        if actionIdentifier == UNNotificationDefaultActionIdentifier
            || actionIdentifier == UNNotificationDismissActionIdentifier {
            return nil
        }
        switch actionIdentifier {
        case restActionIdentifier:
            guard categoryIdentifier == Self.categoryIdentifier,
                  let identity = strictIdentity(userInfo) else { return nil }
            return .rest(sessionID: identity.sessionID, generation: identity.generation)
        case snoozeActionIdentifier:
            guard categoryIdentifier == Self.categoryIdentifier,
                  let identity = strictIdentity(userInfo) else { return nil }
            return .snooze(
                sessionID: identity.sessionID,
                generation: identity.generation,
                minutes: legacySnoozeMinutes
            )
        case snooze5ActionIdentifier:
            guard categoryIdentifier == Self.categoryIdentifier,
                  let identity = strictIdentity(userInfo) else { return nil }
            return .snooze(
                sessionID: identity.sessionID,
                generation: identity.generation,
                minutes: defaultSnoozeMinutes
            )
        case startNextCycleActionIdentifier:
            guard categoryIdentifier == resumeCategoryIdentifier else { return nil }
            guard let identity = resumeIdentity(userInfo) else { return nil }
            return .resume(
                sessionID: identity.sessionID,
                generation: identity.generation,
                opportunityID: identity.opportunityID
            )
        default:
            return nil
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        guard let action = Self.decodeAction(
            actionIdentifier: response.actionIdentifier,
            categoryIdentifier: content.categoryIdentifier,
            userInfo: content.userInfo
        ) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onAction?(action)
        }
    }

    private static func strictIdentity(
        _ userInfo: [AnyHashable: Any]
    ) -> (sessionID: String, generation: Int)? {
        guard let sessionID = nonEmptyString(userInfo[sessionKey]),
              let generation = strictGeneration(userInfo[generationKey]) else {
            return nil
        }
        return (sessionID, generation)
    }

    private static func resumeIdentity(
        _ userInfo: [AnyHashable: Any]
    ) -> (sessionID: String, generation: Int, opportunityID: String)? {
        guard let sessionID = nonEmptyString(userInfo[sessionKey]),
              let generation = strictGeneration(userInfo[generationKey]),
              let opportunityID = nonEmptyString(userInfo[opportunityKey]) else {
            return nil
        }
        return (sessionID, generation, opportunityID)
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        guard !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return string
    }

    private static func strictGeneration(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        switch String(cString: number.objCType) {
        case "C", "S", "I", "L", "Q":
            let unsigned = number.uint64Value
            guard unsigned <= UInt64(Int.max) else { return nil }
            return Int(unsigned)
        case "c", "s", "i", "l", "q":
            return number.intValue
        default:
            return nil
        }
    }
}
