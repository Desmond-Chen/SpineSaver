import Foundation

public struct ReminderScenePicker {
    public private(set) var lastID: SceneID?

    public init(lastID: SceneID? = nil) {
        self.lastID = lastID
    }

    /// Remember a scene shown outside the random path so the next pick still differs.
    public mutating func remember(_ id: SceneID) {
        lastID = id
    }

    /// Uniform pick that never repeats the previous scene.
    public mutating func next<G: RandomNumberGenerator>(using generator: inout G) -> ReminderScene {
        let candidates = ReminderSceneCatalog.all.filter { $0.id != lastID }
        let pool = candidates.isEmpty ? ReminderSceneCatalog.all : candidates
        let index = Int.random(in: 0..<pool.count, using: &generator)
        let scene = pool[index]
        lastID = scene.id
        return scene
    }
}
