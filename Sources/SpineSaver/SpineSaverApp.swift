import AppKit
import SwiftUI

@main
struct SpineSaverApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            StatusView(
                model: appDelegate.model,
                snoozeEditor: appDelegate.model.menuSnoozeEditor,
                onOpenSettings: { appDelegate.openSettings() },
                onOpenHistory: { appDelegate.openHistory() }
            )
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model: AppModel
    private lazy var settingsController = SettingsWindowController(
        model: model,
        onOpenHistory: { [weak self] in self?.openHistory() }
    )
    private lazy var historyController = HistoryWindowController(model: model)

    override init() {
        let activity = WorkspaceActivityMonitor()
        let presenter = ReminderPresenter()
        model = AppModel(activity: activity, presenter: presenter)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        model.onOpenSettings = { [weak self] in self?.openSettings() }
        model.start()
        if QAEnvironment.openSettings { openSettings() }
        if QAEnvironment.openHistory { openHistory() }
        if QAEnvironment.showReminder { model.showReminderForQA() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }

    func openSettings() {
        settingsController.show()
    }

    func openHistory() {
        historyController.show()
    }
}
