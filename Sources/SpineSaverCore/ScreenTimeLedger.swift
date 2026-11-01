import Foundation

public struct ScreenTimeSlice: Equatable {
    public var startDate: Date
    public var seconds: TimeInterval

    public init(startDate: Date, seconds: TimeInterval) {
        self.startDate = startDate
        self.seconds = seconds
    }
}

public struct ScreenTimeLedger {
    private var lastAwake: TimeInterval
    private var lastDate: Date
    private var pendingSeconds: TimeInterval
    private var pendingStartDate: Date
    private var wasCounting: Bool

    public init(reading: ClockReading) {
        self.lastAwake = reading.awake
        self.lastDate = reading.date
        self.pendingSeconds = 0
        self.pendingStartDate = reading.date
        self.wasCounting = false
    }

    public mutating func tick(_ reading: ClockReading, available: Bool, isCounting: Bool) -> [ScreenTimeSlice] {
        let previousDate = lastDate
        let delta = max(0, reading.awake - lastAwake)
        lastAwake = reading.awake
        lastDate = reading.date

        if wasCounting {
            if pendingSeconds == 0 {
                pendingStartDate = previousDate
            }
            pendingSeconds += delta
        }

        let canCount = available && isCounting
        if !canCount {
            let slices = flush(reading: reading)
            wasCounting = false
            return slices
        }

        if !wasCounting {
            wasCounting = true
            return []
        }

        var slices: [ScreenTimeSlice] = []
        while pendingSeconds >= 60 {
            slices.append(ScreenTimeSlice(startDate: pendingStartDate, seconds: 60))
            pendingStartDate = pendingStartDate.addingTimeInterval(60)
            pendingSeconds -= 60
        }
        return slices
    }

    public mutating func flush(reading: ClockReading) -> [ScreenTimeSlice] {
        guard pendingSeconds > 0 else { return [] }
        let slice = ScreenTimeSlice(startDate: pendingStartDate, seconds: pendingSeconds)
        pendingSeconds = 0
        pendingStartDate = reading.date
        return [slice]
    }
}
