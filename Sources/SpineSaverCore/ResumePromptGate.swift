/// One in-memory presentation opportunity per completed rest. A configuration
/// change can invalidate an action token without creating another opportunity.
public struct ResumePromptGate {
    public enum State: Equatable {
        case none
        case pending(Int)
        case claimed(Int)
        case closed(Int)
    }

    public private(set) var state: State = .none
    private var lastOpportunityID = 0

    public init() {}

    /// Call only for a new `.restAutoCompleted` effect. Repeated delivery while
    /// an opportunity is live or closed cannot reopen it.
    public mutating func recordCompletion() {
        guard state == .none else { return }
        lastOpportunityID += 1
        state = .pending(lastOpportunityID)
    }

    /// An unavailable screen or an action that replaced the waiting state
    /// leaves the opportunity pending until the final cycle state is known.
    public mutating func claim(available: Bool, awaitingNextCycle: Bool) -> Int? {
        guard available, awaitingNextCycle, case .pending(let id) = state else { return nil }
        state = .claimed(id)
        return id
    }

    /// A callback must still belong to the currently presented opportunity.
    public func isClaimed(_ opportunityID: Int) -> Bool {
        state == .claimed(opportunityID)
    }

    /// A stale dismissal must not close a newer opportunity.
    public mutating func close(_ opportunityID: Int) {
        guard state == .pending(opportunityID) || state == .claimed(opportunityID) else { return }
        state = .closed(opportunityID)
    }

    /// Resume, cancellation or a new cycle invalidates the old opportunity.
    /// The ID counter intentionally survives clearing within this app session.
    public mutating func clear() {
        state = .none
    }
}
