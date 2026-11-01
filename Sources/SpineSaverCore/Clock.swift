import Foundation

public struct ClockReading: Equatable {
    public var awake: TimeInterval
    public var continuous: TimeInterval
    public var date: Date

    public init(awake: TimeInterval, continuous: TimeInterval, date: Date) {
        self.awake = awake
        self.continuous = continuous
        self.date = date
    }
}

public protocol TimeProvider: AnyObject {
    func reading() -> ClockReading
}

/// Two monotonic signals: `awake` pauses while the machine sleeps,
/// `continuous` keeps running through sleep. `date` is for display only.
public final class SystemTimeProvider: TimeProvider {
    private let continuousOrigin: ContinuousClock.Instant
    private let awakeOrigin: TimeInterval

    public init() {
        continuousOrigin = ContinuousClock.now
        awakeOrigin = ProcessInfo.processInfo.systemUptime
    }

    public func reading() -> ClockReading {
        let continuous = continuousOrigin.duration(to: .now).timeInterval
        let awake = max(0, ProcessInfo.processInfo.systemUptime - awakeOrigin)
        return ClockReading(awake: awake, continuous: continuous, date: Date())
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
