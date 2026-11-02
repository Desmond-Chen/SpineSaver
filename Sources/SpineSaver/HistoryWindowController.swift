import AppKit
import Combine
import SwiftUI

@MainActor
final class HistoryWindowController {
    private let viewModel: HistoryViewModel
    private var window: NSWindow?
    private var historySubscription: AnyCancellable?

    init(model: AppModel) {
        self.viewModel = HistoryViewModel(
            store: model.historyStore,
            initialRange: QAEnvironment.historyRange ?? .today
        )
        var lastRevision = model.historyRevision
        historySubscription = model.$historyRevision.removeDuplicates()
            .combineLatest(model.$historyWarning.removeDuplicates())
            .sink { [weak self] revision, warning in
                guard let self else { return }
                self.viewModel.writerWarning = warning
                let didAppend = revision != lastRevision
                lastRevision = revision
                if didAppend, self.window?.isVisible == true {
                    self.viewModel.reload()
                }
            }
    }

    func show() {
        viewModel.reload()
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
