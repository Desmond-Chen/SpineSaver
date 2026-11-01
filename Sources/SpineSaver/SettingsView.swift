import SwiftUI
import SpineSaverCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var onOpenHistory: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            Form {
                Section("提醒节奏") {
                    MinuteControl(
                        title: "工作分钟数",
                        minutes: model.settings.workMinutes,
                        canDecrease: SettingsValidation.canDecreaseWorkMinutes(model.settings.workMinutes),
                        canIncrease: SettingsValidation.canIncreaseWorkMinutes(model.settings.workMinutes),
                        onDecrease: { model.setWorkMinutes(model.settings.workMinutes - SettingsValidation.workMinutesStep) },
                        onIncrease: { model.setWorkMinutes(model.settings.workMinutes + SettingsValidation.workMinutesStep) }
                    )
                    MinuteControl(
                        title: "休息分钟数",
                        minutes: model.settings.restMinutes,
                        canDecrease: SettingsValidation.canDecreaseRestMinutes(model.settings.restMinutes),
                        canIncrease: SettingsValidation.canIncreaseRestMinutes(model.settings.restMinutes),
                        onDecrease: { model.setRestMinutes(model.settings.restMinutes - SettingsValidation.restMinutesStep) },
                        onIncrease: { model.setRestMinutes(model.settings.restMinutes + SettingsValidation.restMinutesStep) }
                    )
                    Text("工作时长 15–120 分钟；休息时长 2–15 分钟。百分比表示本轮进度，不代表疲劳、坐姿或真实身体活动。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("提醒方式") {
                    Picker(
                        "方式",
                        selection: Binding(
                            get: { model.settings.reminderStyle },
                            set: { model.setReminderStyle($0) }
                        )
                    ) {
                        ForEach(ReminderStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Text(model.settings.reminderStyle.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("休息结束待开始时，菜单栏仍有“开始新一轮”入口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let warning = model.reminderChannelWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("启动") {
                    Toggle(
                        "登录时启动 SpineSaver",
                        isOn: Binding(
                            get: { model.settings.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                    if let error = model.settingsError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section("历史") {
                    Button("打开历史…") {
                        onOpenHistory?()
                    }
                    Text("查看按日/周图表、导出 CSV/JSON、删除历史。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let warning = model.historyWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("菜单栏") {
                    Text("使用 Bartender / Ice 等菜单栏管理器时，请把 SpineSaver 设为可见。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DisclosureGroup("完整说明") {
                        Text("较窄菜单栏可能截断文字；状态仍可通过无障碍标签读取。应用不会修改 Bartender 配置。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("隐私与限制") {
                    Text("只在本机保存设置、进度和使用习惯记录；不联网、不读键盘内容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DisclosureGroup("完整说明") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("只在本机保存设置、本轮进度和本地使用习惯记录（屏幕计时、提醒、推迟、休息操作）；可查看范围、导出 CSV/JSON、主动删除。不联网、不读取键盘内容、不申请辅助功能/输入监控、不保存健康、喝水或如厕记录；记录不能证明你已起身或实际休息。")
                            Text("系统睡眠、屏幕熄灭和会话切开会暂停累计；连续离屏 10 分钟会重新开始屏幕计时，但这不等于你已起身。锁屏而屏幕仍亮的场景没有已证实的完整公开信号，可能继续计入。")
                            Text("自绘迷你弹窗不受系统 Focus 自动管理，可能在专注时出现；希望严格遵循 Focus 时请选择系统通知或手动暂停。")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 520, height: 640)
        .padding(8)
    }
}

private struct MinuteControl: View {
    let title: String
    let minutes: Int
    let canDecrease: Bool
    let canIncrease: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("−", action: onDecrease)
                .disabled(!canDecrease)
                .accessibilityLabel("减少\(title)")
                .accessibilityValue("\(minutes) 分钟")
            Text("\(minutes) 分钟")
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .frame(minWidth: 76)
                .accessibilityLabel("\(title) \(minutes) 分钟")
            Button("+", action: onIncrease)
                .disabled(!canIncrease)
                .accessibilityLabel("增加\(title)")
                .accessibilityValue("\(minutes) 分钟")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}
