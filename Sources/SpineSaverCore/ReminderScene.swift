import Foundation

public enum SceneID: String, CaseIterable, Hashable {
    case walk
    case stretch
    case hydrate
    case restroom
    case farLook
    case breathe
}

public struct ReminderScene: Equatable, Identifiable {
    public var id: SceneID
    public var title: String
    public var detail: String
    public var symbolName: String

    public init(id: SceneID, title: String, detail: String, symbolName: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.symbolName = symbolName
    }

    /// Spoken label for the whole panel. The picture itself is decorative.
    public var accessibilityLabel: String {
        "SpineSaver 提醒：\(title)"
    }
}

public enum ReminderSceneCatalog {
    public static let all: [ReminderScene] = [
        ReminderScene(
            id: .walk,
            title: "起来走一走",
            detail: "也可以顺手接杯水，按需去洗手间。",
            symbolName: "figure.walk"
        ),
        ReminderScene(
            id: .stretch,
            title: "伸个懒腰，松开肩颈",
            detail: "手臂向上，慢慢左右转一转。",
            symbolName: "figure.flexibility"
        ),
        ReminderScene(
            id: .hydrate,
            title: "去接杯水",
            detail: "顺便离开座位走两步。",
            symbolName: "cup.and.saucer.fill"
        ),
        ReminderScene(
            id: .restroom,
            title: "按需去趟洗手间",
            detail: "不用忍着，回来再继续。",
            symbolName: "toilet.fill"
        ),
        ReminderScene(
            id: .farLook,
            title: "看看远处",
            detail: "望向 6 米外约 20 秒，让眼睛歇一下。",
            symbolName: "eye.fill"
        ),
        ReminderScene(
            id: .breathe,
            title: "慢慢呼吸三次",
            detail: "吸气，再慢慢呼出，重复三次。",
            symbolName: "lungs.fill"
        )
    ]

    public static var fallback: ReminderScene {
        scene(for: .walk)
    }

    public static func scene(for id: SceneID) -> ReminderScene {
        all.first { $0.id == id } ?? all[0]
    }
}

public enum SceneSymbolResolver {
    /// Older systems may not have a symbol; return a safe one instead of a blank image.
    public static func resolvedSymbol(
        for scene: ReminderScene,
        isAvailable: (String) -> Bool
    ) -> String {
        isAvailable(scene.symbolName) ? scene.symbolName : ReminderSceneCatalog.fallback.symbolName
    }
}
