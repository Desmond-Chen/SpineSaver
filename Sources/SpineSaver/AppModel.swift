import AppKit
import Foundation
import ServiceManagement
import SpineSaverCore

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var cycle: BreakCycle {
        didSet { menuSnoozeEditor.invalidate(unless: workPromptToken) }
    }
    @Published private(set) var settings: AppSettings
    @Published private(set) var settingsError: String?
    @Published private(set) var reminderChannelWarning: String?
    @Published private(set) var historyWarning: String?
    private(set) var pendingRestAbandonment: RestAbandonment? = nil

    var onOpenSettings: (() -> Void)?
    let menuSnoozeEditor = SnoozeEditorModel()

    private let time: TimeProvider
    private let store: PreferencesStoring
    let historyStore: HistoryStore
    private let activity: WorkspaceActivityMonitor
    private let notifications: NotificationManager
    private var scenePicker: ReminderScenePicker
    private let presenter: ReminderPresenter
    private var timer: Timer?
    private var screenTimeLedger: ScreenTimeLedger
    private var lastPersistedMinute = -1
    private let sessionID = UUID().uuidString
    private var resumePromptGate = ResumePromptGate()
    private var resumePanelVisible = false
    private var resumeNotificationAuthorizationID: Int?
    private var resumeNotificationDelivered = false
    private var reminderStyleRevision = 0

    init(
        time: TimeProvider = SystemTimeProvider(),
        store: PreferencesStoring? = nil,
        activity: WorkspaceActivityMonitor,
        notifications: NotificationManager = NotificationManager(),
        presenter: ReminderPresenter
    ) {
        self.time = time
        let resolvedStore: PreferencesStoring
        if let store {
            resolvedStore = store
        } else if let suite = QAEnvironment.suiteName,
                  let defaults = UserDefaults(suiteName: suite) {
            if QAEnvironment.reset { defaults.removePersistentDomain(forName: suite) }
            resolvedStore = PreferencesStore(defaults: defaults)
        } else {
            resolvedStore = PreferencesStore()
        }
        self.store = resolvedStore
        self.historyStore = HistoryStore(fileURL: QAEnvironment.historyPath ?? HistoryStore.defaultFileURL())
        self.activity = activity
        self.notifications = notifications
        self.presenter = presenter
        self.scenePicker = ReminderScenePicker(lastID: resolvedStore.loadLastReminderSceneID())

        let loaded = resolvedStore.loadSettings()
        self.settings = loaded
        let reading = time.reading()
        self.screenTimeLedger = ScreenTimeLedger(reading: reading)
        var config = loaded.cycleConfiguration
        if let interval = QAEnvironment.intervalSeconds { config.workInterval = interval }
        if let snooze = QAEnvironment.snoozeSeconds { config.snoozeInterval = snooze }
        if let offscreen = QAEnvironment.offscreenSeconds { config.offscreenResetThreshold = offscreen }
        if let rest = QAEnvironment.restSeconds { config.suggestedRestDuration = rest }

        if QAEnvironment.startCounting {
            self.cycle = BreakCycle(config: config, reading: reading, available: activity.isAvailable)
        } else if let snapshot = resolvedStore.loadRestSnapshot() {
            self.pendingRestAbandonment = snapshot.abandonment(at: reading.date)
            // The snapshot's previousUsed is the authoritative usage at rest start;
            // the separately saved usage can be stale or zero if the app was killed early.
            let savedUsage = resolvedStore.loadUsage() ?? 0
            self.cycle = BreakCycle(
                restoring: config,
                used: max(savedUsage, snapshot.previousUsed),
                reading: reading,
                available: activity.isAvailable
            )
            resolvedStore.clearRestSnapshot()
        } else if let saved = resolvedStore.loadUsage() {
            self.cycle = BreakCycle(
                restoring: config,
                used: saved,
                reading: reading,
                available: activity.isAvailable
            )
        } else {
            self.cycle = BreakCycle(
                config: config,
                reading: reading,
                available: activity.isAvailable
            )
        }
        self.settings.launchAtLogin = Self.launchAtLoginIsEnabled
    }

    func start() {
        if let abandonment = pendingRestAbandonment {
            record(.restAbandoned, restSeconds: abandonment.elapsedSeconds, reason: abandonment.reason.rawValue, at: time.reading().date)
            pendingRestAbandonment = nil
        }
        activity.onChange = { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        presenter.onStartRest = { [weak self] in self?.startRest() }
        presenter.onSnooze = { [weak self] token, minutes in
            guard let self else { return false }
            return self.snooze(minutes: minutes, sourceToken: token)
        }
        presenter.onResumeStart = { [weak self] token in
            self?.resumeFromPrompt(
                sessionID: token.sessionID,
                generation: token.generation,
                opportunityID: token.opportunityID
            )
        }
        presenter.onResumeLater = { [weak self] token in
            self?.closeResumePrompt(
                sessionID: token.sessionID,
                generation: token.generation,
                opportunityID: token.opportunityID
            )
        }
        notifications.onAction = { [weak self] action in
            Task { @MainActor in
                guard let self else { return }
                if case .resume(let session, let generation, let opportunityID) = action {
                    guard let id = Int(opportunityID), id > 0,
                          String(id) == opportunityID else { return }
                    self.resumeFromPrompt(sessionID: session, generation: generation, opportunityID: id)
                    return
                }
                // Work-notification rest/snooze identity is validated after
                // the settle tick, inside the actions below: a notification
                // must not act on the pre-settle generation.
                switch action {
                case .rest(let session, let generation):
                    self.startRest(sourceToken: .init(sessionID: session, generation: generation))
                case .snooze(let session, let generation, let minutes):
                    self.snooze(
                        minutes: minutes,
                        sourceToken: .init(sessionID: session, generation: generation)
                    )
                case .resume:
                    return
                }
            }
        }
        notifications.onDeliveryError = { [weak self] message in
            Task { @MainActor in
                guard let self, self.settings.reminderStyle == .systemNotification else { return }
                self.reminderChannelWarning = message
            }
        }
        notifications.configure()
        activity.start()
        syncLaunchAtLoginState()
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        activity.stop()
        recordScreenTime(screenTimeLedger.flush(reading: time.reading()))
        persistUsage(force: true)
    }

    var menuLabel: String {
        MenuBarText.label(
            phase: cycle.phase,
            percent: cycle.percent,
            restRemaining: cycle.restRemaining(reading: time.reading()),
            awaitingNextCycle: cycle.awaitingNextCycle
        )
    }

    var menuAccessibilityLabel: String {
        MenuBarText.accessibilityLabel(
            phase: cycle.phase,
            percent: cycle.percent,
            restRemaining: cycle.restRemaining(reading: time.reading()),
            awaitingNextCycle: cycle.awaitingNextCycle
        )
    }
    var percent: Int { cycle.percent }
    var isDue: Bool { cycle.isDue }
    var isPaused: Bool { cycle.isPaused }
    var isResting: Bool { cycle.isResting }
    var isAwaitingNextCycle: Bool { cycle.awaitingNextCycle }
    var isSnoozed: Bool { cycle.isSnoozed }
    var workPromptToken: ReminderPresenter.WorkPromptToken {
        .init(sessionID: sessionID, generation: cycle.generation)
    }

    var statusTitle: String {
        switch cycle.phase {
        case .counting:
            return "计时中"
        case .due:
            return "该休息了"
        case .snoozed:
            return "已推迟"
        case .paused:
            if cycle.awaitingNextCycle { return "休息结束" }
            return cycle.used >= cycle.config.workInterval ? "已暂停 · 已到点" : "已暂停"
        case .resting:
            return "休息中"
        }
    }

    var detailText: String {
        switch cycle.phase {
        case .counting:
            return "已累计 \(Self.formatted(cycle.used)) · 剩余 \(Self.formatted(cycle.remaining))"
        case .due:
            return "本轮已到点。关闭提醒不会清零，完成休息后才开始新一轮。"
        case .snoozed:
            return "已推迟；到时最多再提醒一次。"
        case .paused:
            if cycle.awaitingNextCycle { return "休息已完成，点“开始新一轮”开始计时。" }
            return "进度已冻结；继续后恢复累计。"
        case .resting:
            return restHint
        }
    }

    var restHint: String {
        let remaining = cycle.restRemaining(reading: time.reading())
        let minutes = max(1, Int((cycle.restDuration / 60).rounded()))
        return "建议离开屏幕 \(minutes) 分钟；剩余 \(Self.formattedCountdown(remaining))。到 00:00 自动结束，之后点“开始新一轮”。"
    }

    func showReminderForQA() {
        presenter.show(
            scene: nextReminderScene(),
            token: .init(sessionID: sessionID, generation: cycle.generation)
        )
    }

    /// Starts a rest. Menu-bar and panel actions pass no token (the settled
    /// cycle's own guards apply); a work notification passes the identity it
    /// was delivered with, validated after the settle tick. Only an accepted
    /// start records one restStarted event.
    func startRest(sourceToken: ReminderPresenter.WorkPromptToken? = nil) {
        var accepted = false
        mutateCycle { cycle, reading in
            if let sourceToken {
                guard Self.matchesCurrentCycle(
                    sourceToken, sessionID: self.sessionID, cycle: cycle
                ) else { return }
            }
            let wasResting = cycle.isResting
            cycle.startRest(reading)
            accepted = !wasResting && cycle.isResting
        }
        guard accepted else { return }
        presenter.dismiss()
        if let snapshot = cycle.restSnapshot() {
            store.saveRestSnapshot(snapshot)
        }
        record(.restStarted, restSeconds: cycle.restDuration, at: time.reading().date)
    }

    func finishRest() {
        presenter.dismiss()
        let wasResting = cycle.isResting
        let remaining = cycle.restRemaining(reading: time.reading())
        let duration = cycle.restDuration
        mutateCycle { cycle, reading in cycle.finishRest(reading) }
        store.clearRestSnapshot()
        if wasResting, !cycle.isResting, !cycle.awaitingNextCycle {
            record(.restFinishedEarly, restSeconds: max(0, duration - remaining), at: time.reading().date)
        }
    }

    func cancelRest() {
        presenter.dismiss()
        let wasResting = cycle.isResting
        let remaining = cycle.restRemaining(reading: time.reading())
        let duration = cycle.restDuration
        mutateCycle { cycle, reading in cycle.cancelRest(reading) }
        store.clearRestSnapshot()
        if wasResting, !cycle.isResting, !cycle.awaitingNextCycle {
            record(.restCancelled, restSeconds: max(0, duration - remaining), at: time.reading().date)
        }
    }

    func pause() {
        presenter.dismiss()
        mutateCycle { cycle, reading in cycle.pause(reading) }
    }

    func resume() {
        mutateCycle { cycle, reading in
            clearResumePrompt()
            cycle.resume(reading)
        }
    }

    /// Snoozes the due reminder. The default entry (menu bar) passes the
    /// validated minutes for this action only; custom menu drafts, the panel
    /// and notifications also pass the source token after the settle tick. Returns
    /// whether the snooze was accepted; only an accepted snooze dismisses the
    /// panel and records exactly one snoozed event.
    @discardableResult
    func snooze(
        minutes: Int? = nil,
        sourceToken: ReminderPresenter.WorkPromptToken? = nil
    ) -> Bool {
        var accepted = false
        mutateCycle { cycle, reading in
            if let sourceToken {
                guard Self.matchesCurrentCycle(
                    sourceToken, sessionID: self.sessionID, cycle: cycle
                ) else { return }
            }
            if let minutes {
                accepted = cycle.snooze(reading, minutes: minutes) != nil
            } else {
                accepted = cycle.snooze(reading)
            }
        }
        guard accepted else { return false }
        presenter.dismiss()
        record(.snoozed, at: time.reading().date)
        return true
    }

    func setWorkMinutes(_ minutes: Int) {
        let clamped = SettingsValidation.clampWorkMinutes(minutes)
        guard clamped != settings.workMinutes else { return }
        settings.workMinutes = clamped
        store.saveSettings(settings)

        var copy = cycle
        let effects = copy.updateConfiguration(settings.cycleConfiguration)
        cycle = copy
        handle(effects)
        presentPendingResumeIfNeeded()
        tick()
    }

    func setRestMinutes(_ minutes: Int) {
        let clamped = SettingsValidation.clampRestMinutes(minutes)
        guard clamped != settings.restMinutes else { return }
        settings.restMinutes = clamped
        store.saveSettings(settings)

        var copy = cycle
        let effects = copy.updateConfiguration(settings.cycleConfiguration)
        cycle = copy
        handle(effects)
        presentPendingResumeIfNeeded()
        tick()
    }

    func setRandomReminderScenes(_ enabled: Bool) {
        guard enabled != settings.randomReminderScenes else { return }
        settings.randomReminderScenes = enabled
        store.saveSettings(settings)
    }

    func setReminderStyle(_ style: ReminderStyle) {
        guard style != settings.reminderStyle else { return }
        settings.reminderStyle = style
        reminderStyleRevision += 1
        let revision = reminderStyleRevision
        store.saveSettings(settings)
        reminderChannelWarning = nil
        if case .claimed(let id) = resumePromptGate.state {
            resumePromptGate.close(id)
            if resumePanelVisible { presenter.dismiss() }
            resumePanelVisible = false
        }
        guard style == .systemNotification else { return }

        Task { [weak self] in
            guard let self else { return }
            let status = await self.notifications.authorizationStatus()
            guard self.reminderStyleRevision == revision else { return }
            switch status {
            case .notDetermined:
                let granted = await self.notifications.requestAuthorization()
                guard self.reminderStyleRevision == revision else { return }
                if !granted {
                    self.reminderChannelWarning = "系统通知未授权。可在系统设置中开启，或切回迷你弹窗。"
                }
            case .denied:
                self.reminderChannelWarning = "系统通知已关闭。可在系统设置中开启，或切回迷你弹窗。"
            default:
                break
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settingsError = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            settingsError = error.localizedDescription
        }

        let actual = Self.launchAtLoginIsEnabled
        settings.launchAtLogin = actual
        store.saveSettings(settings)
        if settingsError == nil, actual != enabled {
            settingsError = enabled
                ? "系统尚未批准登录启动。请到“系统设置 > 通用 > 登录项”中允许 SpineSaver。"
                : "未能取消登录启动，请在系统设置中检查。"
        }
    }

    private static var launchAtLoginIsEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func syncLaunchAtLoginState() {
        let actual = Self.launchAtLoginIsEnabled
        guard settings.launchAtLogin != actual else { return }
        settings.launchAtLogin = actual
        store.saveSettings(settings)
    }

    private static func matchesCurrentCycle(
        _ token: ReminderPresenter.WorkPromptToken,
        sessionID: String,
        cycle: BreakCycle
    ) -> Bool {
        CycleToken.matches(
            sessionID: token.sessionID,
            generation: token.generation,
            currentSessionID: sessionID,
            currentGeneration: cycle.generation
        )
    }

    private func mutateCycle(_ body: (inout BreakCycle, ClockReading) -> Void) {
        let reading = time.reading()
        var copy = cycle
        // Defer work reminders until the action has either changed the settled
        // generation or been rejected. Every accepted cycle mutation advances
        // generation; a rejected stale action must not consume a due reminder.
        let settleEffects = copy.tick(reading, available: activity.isAvailable)
        let settledGeneration = copy.generation
        handleSettleEffects(settleEffects)
        body(&copy, reading)
        cycle = copy
        if copy.generation == settledGeneration, settleEffects.contains(.reminderDue) {
            handle([.reminderDue])
        }
        if settleEffects.contains(.restAutoCompleted) {
            persistUsage(force: true)
        }
        presentPendingResumeIfNeeded()
        tick()
    }

    private func tick() {
        let reading = time.reading()
        var copy = cycle
        let effects = copy.tick(reading, available: activity.isAvailable)
        cycle = copy
        handle(effects)
        presentPendingResumeIfNeeded()
        recordScreenTime(screenTimeLedger.tick(reading, available: activity.isAvailable, isCounting: copy.isCounting))
        persistUsage(force: effects.contains(.restAutoCompleted))
        scheduleNext()
    }

    private func handle(_ effects: [BreakEffect]) {
        for effect in effects {
            switch effect {
            case .reminderDue:
                presentReminder()
            case .dismissReminder:
                presenter.dismiss()
            case .restAutoCompleted:
                store.clearRestSnapshot()
                record(.restAutoCompleted, restSeconds: cycle.restDuration, at: time.reading().date)
                resumePromptGate.recordCompletion()
            }
        }
    }

    private func handleSettleEffects(_ effects: [BreakEffect]) {
        for effect in effects {
            switch effect {
            case .dismissReminder:
                presenter.dismiss()
            case .restAutoCompleted:
                store.clearRestSnapshot()
                record(.restAutoCompleted, restSeconds: cycle.restDuration, at: time.reading().date)
                resumePromptGate.recordCompletion()
            case .reminderDue:
                break
            }
        }
    }

    private func resumeFromPrompt(sessionID: String, generation: Int, opportunityID: Int) {
        mutateCycle { cycle, reading in
            guard isCurrentResumePrompt(
                sessionID: sessionID, generation: generation, opportunityID: opportunityID, cycle: cycle
            ) else { return }
            clearResumePrompt()
            cycle.resume(reading)
        }
    }

    private func closeResumePrompt(sessionID: String, generation: Int, opportunityID: Int) {
        mutateCycle { cycle, _ in
            guard isCurrentResumePrompt(
                sessionID: sessionID, generation: generation, opportunityID: opportunityID, cycle: cycle
            ) else { return }
            resumePromptGate.close(opportunityID)
            presenter.dismiss()
            resumePanelVisible = false
        }
    }

    private func isCurrentResumePrompt(
        sessionID: String, generation: Int, opportunityID: Int, cycle: BreakCycle
    ) -> Bool {
        CycleToken.matches(
            sessionID: sessionID, generation: generation,
            currentSessionID: self.sessionID, currentGeneration: cycle.generation
        ) && cycle.isPaused && cycle.awaitingNextCycle && resumePromptGate.isClaimed(opportunityID)
    }

    private func clearResumePrompt() {
        if resumePanelVisible { presenter.dismiss() }
        resumePromptGate.clear()
        resumePanelVisible = false
        resumeNotificationAuthorizationID = nil
        resumeNotificationDelivered = false
    }

    private func presentPendingResumeIfNeeded() {
        guard cycle.isPaused, cycle.awaitingNextCycle else {
            clearResumePrompt()
            return
        }
        guard activity.isAvailable else {
            if resumePanelVisible {
                presenter.dismiss()
                resumePanelVisible = false
            }
            return
        }
        let opportunityID: Int
        if let claimed = resumePromptGate.claim(
            available: activity.isAvailable, awaitingNextCycle: cycle.awaitingNextCycle
        ) {
            opportunityID = claimed
        } else if case .claimed(let id) = resumePromptGate.state {
            opportunityID = id
        } else {
            return
        }

        switch settings.reminderStyle {
        case .miniPanel:
            let token = ReminderPresenter.ResumePromptToken(
                sessionID: sessionID, generation: cycle.generation, opportunityID: opportunityID
            )
            if resumePanelVisible {
                presenter.updateResumeToken(token)
            } else {
                presenter.showResume(token: token)
                resumePanelVisible = true
            }
        case .systemNotification:
            guard resumeNotificationAuthorizationID == nil, !resumeNotificationDelivered else { return }
            resumeNotificationAuthorizationID = opportunityID
            Task { [weak self] in
                guard let self else { return }
                let status = await self.notifications.authorizationStatus()
                guard self.resumeNotificationAuthorizationID == opportunityID,
                      self.resumePromptGate.isClaimed(opportunityID),
                      self.settings.reminderStyle == .systemNotification else { return }
                let authorized: Bool
                switch status {
                case .authorized, .provisional, .ephemeral:
                    authorized = true
                case .notDetermined:
                    authorized = await self.notifications.requestAuthorization()
                default:
                    authorized = false
                }
                guard self.resumeNotificationAuthorizationID == opportunityID else { return }
                self.resumeNotificationAuthorizationID = nil
                guard self.resumePromptGate.isClaimed(opportunityID),
                      self.cycle.isPaused, self.cycle.awaitingNextCycle,
                      self.settings.reminderStyle == .systemNotification else { return }
                guard authorized else {
                    self.resumePromptGate.close(opportunityID)
                    self.reminderChannelWarning = "系统通知未授权或已关闭。请在设置中开启，或从菜单栏开始新一轮。"
                    return
                }
                guard self.activity.isAvailable else { return }
                self.resumeNotificationDelivered = true
                self.notifications.deliverResume(
                    sessionID: self.sessionID,
                    generation: self.cycle.generation,
                    opportunityID: String(opportunityID)
                )
            }
        }
    }

    private func nextReminderScene() -> ReminderScene {
        if let forced = QAEnvironment.reminderScene {
            scenePicker.remember(forced)
            return ReminderSceneCatalog.scene(for: forced)
        }
        guard settings.randomReminderScenes else {
            scenePicker.remember(ReminderSceneCatalog.fallback.id)
            store.saveLastReminderSceneID(ReminderSceneCatalog.fallback.id)
            return ReminderSceneCatalog.fallback
        }
        var generator = SystemRandomNumberGenerator()
        let scene = scenePicker.next(using: &generator)
        store.saveLastReminderSceneID(scene.id)
        return scene
    }

    private func presentReminder() {
        record(.reminderPresented, at: time.reading().date)
        let scene = nextReminderScene()
        switch settings.reminderStyle {
        case .miniPanel:
            presenter.show(
                scene: scene,
                token: .init(sessionID: sessionID, generation: cycle.generation)
            )
        case .systemNotification:
            let sessionID = self.sessionID
            let generation = self.cycle.generation
            Task { [weak self] in
                guard let self else { return }
                let status = await self.notifications.authorizationStatus()
                guard self.sessionID == sessionID,
                      self.cycle.generation == generation, self.cycle.isDue,
                      self.activity.isAvailable,
                      self.settings.reminderStyle == .systemNotification else { return }
                switch status {
                case .authorized, .provisional, .ephemeral:
                    self.notifications.deliver(sessionID: sessionID, generation: generation, body: "\(scene.title)。\(scene.detail)")
                case .notDetermined:
                    let granted = await self.notifications.requestAuthorization()
                    guard self.cycle.generation == generation, self.cycle.isDue,
                          self.activity.isAvailable,
                          self.settings.reminderStyle == .systemNotification else { return }
                    if granted {
                        self.notifications.deliver(sessionID: sessionID, generation: generation, body: "\(scene.title)。\(scene.detail)")
                    } else {
                        self.reminderChannelWarning = "系统通知未授权。请在设置中开启，或切回迷你弹窗。"
                    }
                default:
                    self.reminderChannelWarning = "系统通知已关闭。请在设置中开启，或切回迷你弹窗。"
                }
            }
        }
    }

    private func recordScreenTime(_ slices: [ScreenTimeSlice]) {
        for slice in slices {
            record(.screenTime, screenSeconds: slice.seconds, at: slice.startDate)
        }
    }

    private func record(
        _ kind: HistoryEventKind,
        screenSeconds: Double? = nil,
        restSeconds: Double? = nil,
        reason: String? = nil,
        at date: Date
    ) {
        let event = HistoryEvent(
            occurredAt: date,
            timeZoneIdentifier: TimeZone.current.identifier,
            kind: kind,
            screenSeconds: screenSeconds,
            restSeconds: restSeconds,
            reason: reason,
            appVersion: Self.appVersion
        )
        do {
            try historyStore.append(event)
        } catch {
            historyWarning = error.localizedDescription
        }
    }

    private static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    private func persistUsage(force: Bool = false) {
        let minute = Int(cycle.used / 60)
        guard force || minute != lastPersistedMinute else { return }
        store.saveUsage(cycle.used)
        lastPersistedMinute = minute
    }

    private func scheduleNext() {
        timer?.invalidate()
        timer = nil
        guard activity.isAvailable,
              let delay = cycle.nextWake(after: time.reading()) else {
            return
        }
        let generation = cycle.generation
        let timer = Timer(timeInterval: max(0.5, delay), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.cycle.generation == generation else { return }
                self.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private static func formatted(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        return "\(minutes) 分钟"
    }

    private static func formattedCountdown(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// QA-only overrides. Normal launches ignore every key.
enum QAEnvironment {
    private static var env: [String: String] { ProcessInfo.processInfo.environment }
    static var suiteName: String? { env["SPINESAVER_QA_SUITE"] }
    static var reset: Bool { env["SPINESAVER_QA_RESET"] == "1" }
    static var startCounting: Bool { env["SPINESAVER_QA_START_COUNTING"] == "1" }
    static var intervalSeconds: TimeInterval? { seconds("SPINESAVER_QA_INTERVAL_SECONDS") }
    static var snoozeSeconds: TimeInterval? { seconds("SPINESAVER_QA_SNOOZE_SECONDS") }
    static var offscreenSeconds: TimeInterval? { seconds("SPINESAVER_QA_OFFSCREEN_SECONDS") }
    static var restSeconds: TimeInterval? { seconds("SPINESAVER_QA_REST_SECONDS") }
    static var historyPath: URL? { env["SPINESAVER_QA_HISTORY_PATH"].map { URL(fileURLWithPath: $0) } }
    static var openSettings: Bool { env["SPINESAVER_QA_OPEN_SETTINGS"] == "1" }
    static var openHistory: Bool { env["SPINESAVER_QA_OPEN_HISTORY"] == "1" }
    static var showReminder: Bool { env["SPINESAVER_QA_SHOW_REMINDER"] == "1" }
    static var historyRange: HistoryRange? {
        guard let raw = env["SPINESAVER_QA_HISTORY_RANGE"] else { return nil }
        return HistoryRange(rawValue: raw)
    }
    static var reminderScene: SceneID? {
        guard let raw = env["SPINESAVER_QA_REMINDER_SCENE"] else { return nil }
        return SceneID(rawValue: raw) ?? .walk
    }

    private static func seconds(_ key: String) -> TimeInterval? {
        guard let raw = env[key], let value = TimeInterval(raw), value > 0 else { return nil }
        return value
    }
}
