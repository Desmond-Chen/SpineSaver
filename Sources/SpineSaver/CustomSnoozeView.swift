import Combine
import SwiftUI
import SpineSaverCore

/// View-local state for the single-use custom snooze editor. Lives outside
/// SwiftUI `@State` because this project's build toolchain has no SwiftUI
/// property-wrapper macro support; the reminder panel and menu bar each own
/// one instance for the lifetime of their surface.
@MainActor
final class SnoozeEditorModel: ObservableObject {
    @Published var isShown = false
    @Published var draft = ""
    @Published var invalidMessage: String?
    @Published var staleHint: String?
    private(set) var sourceToken: ReminderPresenter.WorkPromptToken?

    func open(sourceToken: ReminderPresenter.WorkPromptToken) {
        self.sourceToken = sourceToken
        open()
    }

    func invalidate(unless currentToken: ReminderPresenter.WorkPromptToken) {
        guard let sourceToken, sourceToken != currentToken else { return }
        resetForPresentation()
        staleHint = "本轮提醒已变化，未推迟。"
    }

    func open() {
        draft = ""
        invalidMessage = nil
        staleHint = nil
        isShown = true
    }

    func close() {
        sourceToken = nil
        isShown = false
        invalidMessage = nil
    }

    func resetForPresentation() {
        sourceToken = nil
        isShown = false
        draft = ""
        invalidMessage = nil
        staleHint = nil
    }
}

/// Shared single-use custom snooze editor used by the reminder panel and the
/// menu bar status view. Submits only whole minutes parsed into 1...20 and
/// reports acceptance so the caller can explain a stale rejection. Return
/// submits the draft; Escape and the cancel button close the draft only,
/// never the reminder itself.
struct CustomSnoozeView: View {
    @ObservedObject var editor: SnoozeEditorModel
    /// Runs the snooze submit for the parsed minutes. Returns whether it was
    /// accepted; false means the current cycle no longer accepts it.
    let submit: (Int) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                TextField("1–20", text: $editor.draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .onSubmit(submitDraft)
                Text("分钟")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("取消", action: editor.close)
                    .keyboardShortcut(.cancelAction)
                Button("确定", action: submitDraft)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            if let invalidMessage = editor.invalidMessage {
                Text(invalidMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func submitDraft() {
        guard let minutes = SettingsValidation.parseSnoozeMinutes(editor.draft) else {
            editor.invalidMessage = "请输入 1 到 20 的整数分钟。"
            return
        }
        _ = submit(minutes)
        editor.close()
    }
}
