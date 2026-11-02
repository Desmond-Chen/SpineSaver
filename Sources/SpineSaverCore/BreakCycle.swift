import Foundation

public struct BreakCycleConfiguration: Equatable {
    public var workInterval: TimeInterval
    public var snoozeInterval: TimeInterval
    public var offscreenResetThreshold: TimeInterval
    public var suggestedRestDuration: TimeInterval

    public init(
        workInterval: TimeInterval,
        snoozeInterval: TimeInterval,
        offscreenResetThreshold: TimeInterval,
        suggestedRestDuration: TimeInterval
    ) {
        self.workInterval = workInterval
        self.snoozeInterval = snoozeInterval
        self.offscreenResetThreshold = offscreenResetThreshold
        self.suggestedRestDuration = suggestedRestDuration
    }

    public static let standard = BreakCycleConfiguration(
        workInterval: 45 * 60,
        snoozeInterval: 5 * 60,
        offscreenResetThreshold: 10 * 60,
        suggestedRestDuration: 2 * 60
    )
}

public enum BreakPhase: Equatable {
    case counting
    case due
    case snoozed(until: TimeInterval)
    case paused
    case resting(startedAt: TimeInterval)
}

public enum BreakEffect: Equatable {
    case reminderDue
    case dismissReminder
    case restAutoCompleted
}

/// Pure, injected-clock state machine. The UI owns presentation; this type owns
/// the single source of truth for progress and reminder opportunities.
public struct BreakCycle {
    public private(set) var config: BreakCycleConfiguration
    public private(set) var phase: BreakPhase
    public private(set) var used: TimeInterval
    public private(set) var generation: Int
    public private(set) var awaitingNextCycle: Bool

    private var lastAwake: TimeInterval
    private var lastContinuous: TimeInterval
    private var available: Bool
    private var offscreenSince: TimeInterval?
    private var reminderPresented: Bool
    private var restPreviousPhase: BreakPhase
    private var restPreviousUsed: TimeInterval
    private var restPreviousReminderPresented: Bool
    private var restDurationSnapshot: TimeInterval
    private var lastRestDuration: TimeInterval
    private var restStartedAtDate: Date?

    public init(
        config: BreakCycleConfiguration = .standard,
        reading: ClockReading,
        available: Bool = true
    ) {
        self.config = config
        self.phase = .counting
        self.used = 0
        self.generation = 0
        self.awaitingNextCycle = false
        self.restDurationSnapshot = 0
        self.lastRestDuration = 0
        self.restStartedAtDate = nil
        self.lastAwake = reading.awake
        self.lastContinuous = reading.continuous
        self.available = available
        self.offscreenSince = available ? nil : reading.continuous
        self.reminderPresented = false
        self.restPreviousPhase = .counting
        self.restPreviousUsed = 0
        self.restPreviousReminderPresented = false
    }

    /// Restoring always starts paused: a relaunch never silently continues
    /// accumulating time that the app could not observe.
    public init(
        restoring config: BreakCycleConfiguration = .standard,
        used: TimeInterval,
        reading: ClockReading,
        available: Bool = true
    ) {
        self.init(config: config, reading: reading, available: available)
        self.used = min(max(0, used), config.workInterval)
        self.phase = .paused
        self.reminderPresented = false
    }

    public var percent: Int {
        guard config.workInterval > 0 else { return 0 }
        if used >= config.workInterval { return 100 }
        return min(99, max(0, Int(floor(100 * used / config.workInterval))))
    }

    public var remaining: TimeInterval {
        max(0, config.workInterval - used)
    }

    /// The rest duration frozen at the start of the current (or most recent) rest.
    public var restDuration: TimeInterval {
        restDurationSnapshot > 0 ? restDurationSnapshot : lastRestDuration
    }

    /// Seconds left in the current rest, clamped to the duration frozen at start.
    public func restRemaining(reading: ClockReading) -> TimeInterval {
        guard case .resting(let startedAt) = phase else { return 0 }
        let duration = restDuration
        let elapsed = max(0, reading.continuous - startedAt)
        return max(0, min(duration, duration - elapsed))
    }

    public func restSnapshot() -> RestSnapshot? {
        guard case .resting = phase, let startedAt = restStartedAtDate else { return nil }
        let duration = restDuration
        return RestSnapshot(
            startedAt: startedAt,
            duration: duration,
            previousPhase: Self.phaseKey(restPreviousPhase),
            previousUsed: restPreviousUsed,
            previousReminderPresented: restPreviousReminderPresented
        )
    }

    private static func phaseKey(_ phase: BreakPhase) -> String {
        switch phase {
        case .counting: return "counting"
        case .due: return "due"
        case .snoozed: return "snoozed"
        case .paused: return "paused"
        case .resting: return "counting"
        }
    }

    public var isAvailable: Bool { available }
    public var isCounting: Bool { if case .counting = phase { return true }; return false }
    public var isDue: Bool { if case .due = phase { return true }; return false }
    public var isPaused: Bool { if case .paused = phase { return true }; return false }
    public var isResting: Bool { if case .resting = phase { return true }; return false }
    public var isSnoozed: Bool { if case .snoozed = phase { return true }; return false }

    /// Observed work continues after the reminder reaches 100%, including snooze.
    /// Screen availability is a separate input to the ledger.
    public var isObservedWorkEligible: Bool {
        switch phase {
        case .counting, .due, .snoozed: return true
        case .paused, .resting: return false
        }
    }

    public mutating func tick(_ reading: ClockReading, available newAvailable: Bool) -> [BreakEffect] {
        var effects: [BreakEffect] = []
        let awakeDelta = max(0, reading.awake - lastAwake)

        if available && newAvailable {
            if phase == .counting {
                used = min(config.workInterval, used + awakeDelta)
            }
        } else if available && !newAvailable {
            if phase == .counting {
                used = min(config.workInterval, used + awakeDelta)
            }
            available = false
            offscreenSince = reading.continuous
        } else if !available && newAvailable {
            let offscreen = max(0, reading.continuous - (offscreenSince ?? reading.continuous))
            available = true
            offscreenSince = nil
            if offscreen >= config.offscreenResetThreshold, !isPaused, !isResting {
                resetForNewCycle()
                effects.append(.dismissReminder)
            }
        }

        if case .snoozed(let until) = phase, newAvailable, reading.continuous >= until {
            phase = .due
            reminderPresented = false
        }

        if phase == .counting, used >= config.workInterval - 0.0001 {
            used = config.workInterval
            phase = .due
        }

        if phase == .due, newAvailable, !reminderPresented {
            reminderPresented = true
            effects.append(.reminderDue)
        }

        if case .resting = phase, restRemaining(reading: reading) <= 0 {
            used = 0
            phase = .paused
            reminderPresented = false
            awaitingNextCycle = true
            restDurationSnapshot = 0
            restStartedAtDate = nil
            generation += 1
            effects.append(.restAutoCompleted)
        }

        lastAwake = reading.awake
        lastContinuous = reading.continuous
        return effects
    }

    public mutating func startRest(_ reading: ClockReading) {
        guard !isResting else { return }
        restPreviousPhase = normalizedPhaseForRest
        restPreviousUsed = used
        restPreviousReminderPresented = reminderPresented
        phase = .resting(startedAt: reading.continuous)
        reminderPresented = true
        awaitingNextCycle = false
        restDurationSnapshot = config.suggestedRestDuration
        lastRestDuration = config.suggestedRestDuration
        restStartedAtDate = reading.date
        generation += 1
        reanchor(reading)
    }

    public mutating func finishRest(_ reading: ClockReading) {
        guard isResting else { return }
        let stayPaused = restPreviousPhase == .paused
        used = 0
        phase = stayPaused ? .paused : .counting
        reminderPresented = false
        awaitingNextCycle = false
        restDurationSnapshot = 0
        restStartedAtDate = nil
        generation += 1
        reanchor(reading)
    }

    public mutating func cancelRest(_ reading: ClockReading) {
        guard isResting else { return }
        used = restPreviousUsed
        phase = restPreviousPhase
        reminderPresented = restPreviousReminderPresented
        awaitingNextCycle = false
        restDurationSnapshot = 0
        restStartedAtDate = nil
        generation += 1
        reanchor(reading)
    }

    public mutating func pause(_ reading: ClockReading) {
        guard !isPaused, !isResting else { return }
        phase = .paused
        reminderPresented = true
        awaitingNextCycle = false
        generation += 1
        reanchor(reading)
    }

    public mutating func resume(_ reading: ClockReading) {
        guard isPaused else { return }
        if used >= config.workInterval - 0.0001 {
            used = config.workInterval
            phase = .due
        } else {
            phase = .counting
        }
        reminderPresented = false
        awaitingNextCycle = false
        generation += 1
        reanchor(reading)
    }

    /// Snoozes the due reminder by the configured default interval.
    /// Returns false (without mutating) when the cycle is not due.
    @discardableResult
    public mutating func snooze(_ reading: ClockReading) -> Bool {
        guard isDue else { return false }
        applySnooze(until: reading.continuous + config.snoozeInterval, reading)
        return true
    }

    /// Snoozes the due reminder for this cycle only, by a validated number of
    /// whole minutes (1...20). Returns the accepted duration in seconds, or
    /// nil — without mutating — when the minutes are out of range or the
    /// cycle is not due.
    @discardableResult
    public mutating func snooze(_ reading: ClockReading, minutes: Int) -> TimeInterval? {
        guard SettingsValidation.snoozeMinutesRange.contains(minutes), isDue else { return nil }
        let duration = TimeInterval(minutes) * 60
        applySnooze(until: reading.continuous + duration, reading)
        return duration
    }

    private mutating func applySnooze(until: TimeInterval, _ reading: ClockReading) {
        phase = .snoozed(until: until)
        reminderPresented = true
        awaitingNextCycle = false
        generation += 1
        reanchor(reading)
    }

    @discardableResult
    public mutating func updateConfiguration(_ newConfig: BreakCycleConfiguration) -> [BreakEffect] {
        guard newConfig != config else { return [] }
        let previousWorkInterval = config.workInterval

        // A change that does not touch the work interval (rest duration,
        // snooze default, offscreen threshold) never disturbs an accepted
        // snooze deadline.
        if case .snoozed = phase, newConfig.workInterval == previousWorkInterval {
            config = newConfig
            generation += 1
            return []
        }

        let wasDueOrSnoozed: Bool
        let wasSnoozed: Bool
        switch phase {
        case .due:
            wasDueOrSnoozed = true
            wasSnoozed = false
        case .snoozed:
            wasDueOrSnoozed = true
            wasSnoozed = true
        default:
            wasDueOrSnoozed = false
            wasSnoozed = false
        }

        config = newConfig
        used = min(used, config.workInterval)
        var effects: [BreakEffect] = []

        switch phase {
        case .resting, .paused:
            break
        case .counting, .due, .snoozed:
            awaitingNextCycle = false
            if used >= config.workInterval - 0.0001 {
                used = config.workInterval
                phase = .due
                if wasSnoozed {
                    // Coming out of a snooze into due: the follow-up reminder
                    // has not been seen yet, so this due must present one
                    // instead of sitting silently with no deadline.
                    reminderPresented = false
                }
                if !reminderPresented {
                    reminderPresented = true
                    effects.append(.reminderDue)
                }
            } else {
                phase = .counting
                reminderPresented = false
                if wasDueOrSnoozed {
                    effects.append(.dismissReminder)
                }
            }
        }

        generation += 1
        return effects
    }

    /// Seconds until the next visible percentage change or deadline.
    /// `nil` means no time-based wake-up is needed (paused/due/unavailable).
    public func nextWake(after reading: ClockReading) -> TimeInterval? {
        guard available else { return nil }
        switch phase {
        case .counting:
            guard config.workInterval > 0 else { return nil }
            let currentPercent = Int(floor(100 * used / config.workInterval))
            let nextPercent = min(99, currentPercent + 1)
            if nextPercent <= currentPercent {
                return max(0.5, remaining)
            }
            let target = config.workInterval * Double(nextPercent) / 100
            let delta = max(0.5, target - used)
            return min(delta, max(0.5, remaining))
        case .snoozed(let until):
            return max(0.5, until - reading.continuous)
        case .resting:
            return min(1.0, max(0.5, restRemaining(reading: reading)))
        case .due, .paused:
            return nil
        }
    }

    private var normalizedPhaseForRest: BreakPhase {
        switch phase {
        case .snoozed:
            return .due
        case .counting, .due, .paused:
            return phase
        case .resting:
            return restPreviousPhase
        }
    }

    private mutating func resetForNewCycle() {
        used = 0
        phase = .counting
        reminderPresented = false
        awaitingNextCycle = false
        restDurationSnapshot = 0
        restStartedAtDate = nil
        generation += 1
    }

    /// User actions happen between scheduled ticks. Re-anchoring prevents the
    /// pause/rest interval from being counted as screen-available time later.
    private mutating func reanchor(_ reading: ClockReading) {
        lastAwake = reading.awake
        lastContinuous = reading.continuous
    }
}
