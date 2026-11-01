import AppKit
import SwiftUI
import SpineSaverCore

@MainActor
final class ReminderPresenter {
    /// Identity a resume action carries back to AppModel: validated against
    /// the live session, current cycle generation and completion opportunity
    /// before any state change. Refreshed via updateResumeToken, which must
    /// never re-present the panel.
    struct ResumePromptToken: Equatable {
        let sessionID: String
        let generation: Int
        let opportunityID: Int
    }

    var onStartRest: (() -> Void)?
    var onSnooze: (() -> Void)?
    var onResumeStart: ((ResumePromptToken) -> Void)?
    var onResumeLater: ((ResumePromptToken) -> Void)?

    private enum ContentKind: Equatable {
        case workReminder(ReminderScene)
        case resume(ResumePromptToken)
    }

    private var panel: NSPanel?
    private var displayedContent: ContentKind?

    func show(scene: ReminderScene) {
        present(.workReminder(scene))
    }

    /// Presents the resume panel bound to `token`. Replaces any work reminder
    /// currently on screen; the two contents are mutually exclusive.
    func showResume(token: ResumePromptToken) {
        present(.resume(token))
    }

    /// Rebinds the displayed resume content and its action identity to
    /// `token`. Never orders the panel front or repositions it: an update
    /// while hidden stays hidden.
    func updateResumeToken(_ token: ResumePromptToken) {
        guard let panel, case let .resume(current)? = displayedContent, current != token else { return }
        panel.contentView = makeContentView(for: .resume(token))
        displayedContent = .resume(token)
    }

    /// Hides only the currently displayed content; the content binding is
    /// kept, so a later token update still applies without showing anything.
    func dismiss() {
        panel?.orderOut(nil)
    }

    private func present(_ content: ContentKind) {
        if panel == nil {
            buildPanel()
        }
        if displayedContent != content {
            panel?.contentView = makeContentView(for: content)
            displayedContent = content
        }
        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func buildPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: ReminderLayout.width, height: ReminderLayout.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false

        self.panel = panel
    }

    private func makeContentView(for content: ContentKind) -> NSView? {
        switch content {
        case .workReminder(let scene):
            let view = ReminderView(
                scene: scene,
                onRest: { [weak self] in self?.onStartRest?() },
                onSnooze: { [weak self] in self?.onSnooze?() },
                onClose: { [weak self] in self?.dismiss() }
            )
            return NSHostingView(rootView: view)
        case .resume(let token):
            let view = ResumePromptView(
                token: token,
                onStart: { [weak self] in self?.onResumeStart?($0) },
                onLater: { [weak self] in self?.onResumeLater?($0) }
            )
            return NSHostingView(rootView: view)
        }
    }

    private func positionPanel() {
        guard let panel else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: max(visible.minX + ReminderLayout.screenMargin, visible.maxX - size.width - ReminderLayout.screenMargin),
            y: max(visible.minY + ReminderLayout.screenMargin, visible.maxY - size.height - ReminderLayout.screenMargin)
        )
        panel.setFrameOrigin(origin)
    }
}

struct ReminderView: View {
    let scene: ReminderScene
    let onRest: () -> Void
    let onSnooze: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 26) {
                illustration
                VStack(alignment: .leading, spacing: 12) {
                    Text(scene.title)
                        .font(.system(size: 34, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(scene.detail)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("建议离开屏幕休息一会儿")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary.opacity(0.5), in: Capsule())
                }
                Spacer(minLength: 0)
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("开始休息", action: onRest)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                Button("10 分钟后提醒", action: onSnooze)
                    .controlSize(.large)
                Spacer(minLength: 0)
                Button("关闭", action: onClose)
                    .buttonStyle(.borderless)
                    .controlSize(.large)
            }
        }
        .padding(ReminderLayout.padding)
        .frame(width: ReminderLayout.width, height: ReminderLayout.height, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ReminderLayout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReminderLayout.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(scene.accessibilityLabel)
    }

    private var illustration: some View {
        let symbol = SceneSymbolResolver.resolvedSymbol(
            for: scene,
            isAvailable: { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
        )
        return ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.30), Color.accentColor.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.18), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: 66, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
        }
        .frame(width: 150, height: 150)
        .accessibilityHidden(true)
    }
}

struct ResumePromptView: View {
    let token: ReminderPresenter.ResumePromptToken
    let onStart: (ReminderPresenter.ResumePromptToken) -> Void
    let onLater: (ReminderPresenter.ResumePromptToken) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                Text("休息倒计时已结束")
                    .font(.largeTitle.bold())
            }

            Text("本轮工作进度已停止累计。")
                .font(.title3)
                .foregroundStyle(.secondary)

            Text("点击“开始新一轮”恢复计时；暂时不想开始就选“稍后开始”，之后可随时从菜单栏开始新一轮。")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button("开始新一轮", action: { onStart(token) })
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                Button("稍后开始", action: { onLater(token) })
                    .controlSize(.large)
                Spacer(minLength: 0)
            }
        }
        .padding(ReminderLayout.padding)
        .frame(width: ReminderLayout.width, height: ReminderLayout.height, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: ReminderLayout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ReminderLayout.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SpineSaver 恢复提示")
    }
}
