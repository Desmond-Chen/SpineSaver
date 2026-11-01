import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController {
    private let viewModel: HistoryViewModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.viewModel = HistoryViewModel(
            store: model.historyStore,
            initialRange: QAEnvironment.historyRange ?? .today
        )
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: HistoryView(model: viewModel))
            let window = NSWindow(contentViewController: hosting)
            window.title = "SpineSaver 历史"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
