import Foundation

/// Pure display-state resolution for the history window's primary surface.
public enum HistoryDisplayState: Equatable {
    /// A read failed and no successful snapshot exists yet.
    case readFailureNoSnapshot
    /// A read failed after a successful snapshot that contained no events.
    case staleEmpty
    /// The last read succeeded and the snapshot has no events.
    case empty
    /// The snapshot has events to render.
    case content
}

public enum HistoryDisplayStateResolver {
    /// Resolves the primary display state. Invariant: a read failure must
    /// never resolve to the normal `empty` ("暂无记录") state.
    public static func resolve(
        hasSnapshot: Bool,
        eventCount: Int,
        readErrorMessage: String?
    ) -> HistoryDisplayState {
        if readErrorMessage != nil {
            if !hasSnapshot { return .readFailureNoSnapshot }
            return eventCount == 0 ? .staleEmpty : .content
        }
        return eventCount == 0 ? .empty : .content
    }
}
