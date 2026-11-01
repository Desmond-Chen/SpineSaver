import AppKit
import CoreGraphics

/// Turns public workspace/display notifications into a single "screen available"
/// signal. Overlapping reasons (sleep + display sleep + session switch) must not
/// be counted twice, so the monitor only exposes the union as a boolean.
@MainActor
final class WorkspaceActivityMonitor {
    private(set) var isAvailable: Bool = true
    var onChange: ((Bool) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var sessionActive = true
    private var sleeping = false

    func start() {
        let center = NSWorkspace.shared.notificationCenter

        observers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setSleeping(true) }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setSleeping(false) }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateFromSystem() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateFromSystem() }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setSessionActive(false) }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.setSessionActive(true) }
        })

        updateFromSystem()
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func setSleeping(_ value: Bool) {
        sleeping = value
        updateFromSystem()
    }

    private func setSessionActive(_ value: Bool) {
        sessionActive = value
        updateFromSystem()
    }

    private func updateFromSystem() {
        let displaysAsleep = Self.allDisplaysAsleep()
        setAvailable(sessionActive && !sleeping && !displaysAsleep)
    }

    private func setAvailable(_ value: Bool) {
        guard isAvailable != value else { return }
        isAvailable = value
        onChange?(value)
    }

    static func allDisplaysAsleep() -> Bool {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return true
        }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else {
            return true
        }
        return displays.prefix(Int(count)).allSatisfy { CGDisplayIsAsleep($0) != 0 }
    }
}
