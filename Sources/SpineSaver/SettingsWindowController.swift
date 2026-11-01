import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: AppModel
    private let onOpenHistory: () -> Void
    private var window: NSWindow?

    init(model: AppModel, onOpenHistory: @escaping () -> Void) {
        self.model = model
        self.onOpenHistory = onOpenHistory
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(model: model, onOpenHistory: onOpenHistory))
            let window = NSWindow(contentViewController: hosting)
            window.title = "SpineSaver 设置"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
