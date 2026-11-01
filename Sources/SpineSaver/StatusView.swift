import AppKit
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Text(model.menuLabel)
            .font(.system(size: 12, weight: .semibold, design: .monospaced))
            .accessibilityLabel(model.menuAccessibilityLabel)
    }
}

struct StatusView: View {
    @ObservedObject var model: AppModel
    let onOpenSettings: () -> Void
    let onOpenHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.statusTitle)
                    .font(.headline)
                Spacer()
                Text(model.menuLabel)
                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                    .accessibilityLabel(model.menuAccessibilityLabel)
            }

            ProgressView(value: Double(model.percent), total: 100)
                .tint(model.isDue ? .orange : .accentColor)

            Text(model.detailText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let warning = model.reminderChannelWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions

            Divider()

            HStack {
                Button("统计…", action: onOpenHistory)
                Button("设置…", action: onOpenSettings)
                Spacer()
                Button("退出 SpineSaver") {
                    NSApp.terminate(nil)
                }
            }
            .font(.caption)
        }
        .padding(14)
        .frame(width: 330, alignment: .leading)
    }

    @ViewBuilder
    private var actions: some View {
        if model.isResting {
            HStack(spacing: 8) {
                Button("已休息，继续") { model.finishRest() }
                    .buttonStyle(.borderedProminent)
                Button("取消休息") { model.cancelRest() }
            }
        } else if model.isPaused {
            if model.isAwaitingNextCycle {
                Button("开始新一轮") { model.resume() }
                    .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 8) {
                    Button("继续计时") { model.resume() }
                        .buttonStyle(.borderedProminent)
                    Button("现在开始休息") { model.startRest() }
                }
            }
        } else if model.isDue {
            HStack(spacing: 8) {
                Button("开始休息") { model.startRest() }
                    .buttonStyle(.borderedProminent)
                Button("10 分钟后提醒") { model.snooze() }
            }
            Button("暂停计时") { model.pause() }
                .buttonStyle(.borderless)
                .font(.caption)
        } else {
            HStack(spacing: 8) {
                Button("现在开始休息") { model.startRest() }
                Button("暂停计时") { model.pause() }
            }
        }
    }
}
