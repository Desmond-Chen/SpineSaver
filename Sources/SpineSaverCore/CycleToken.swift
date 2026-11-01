import Foundation

/// A notification action is valid only for the app session and cycle that
/// produced it. A notification left in Notification Center must not mutate a
/// later cycle or a relaunched app.
public enum CycleToken {
    public static func matches(
        sessionID: String,
        generation: Int,
        currentSessionID: String,
        currentGeneration: Int
    ) -> Bool {
        sessionID == currentSessionID && generation == currentGeneration
    }
}
