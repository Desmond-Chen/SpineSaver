import AppKit
import Charts
import Combine
import SwiftUI
import UniformTypeIdentifiers
import SpineSaverCore

enum HistoryRange: String, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: return "按日"
        case .weekly: return "按周"
        }
    }
}

enum HistoryExportKind {
    case csv
    case json
}

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var events: [HistoryEvent] = []
    @Published var range: HistoryRange = .daily
    @Published var errorMessage: String?
    @Published var showDeleteConfirmation = false

    let store: HistoryStore
    private let calendar: Calendar

    init(store: HistoryStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    var buckets: [HistoryBucket] {
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end
        switch range {
        case .daily:
            return HistoryAggregator.daily(events: events, from: start, to: end, calendar: calendar)
        case .weekly:
            return HistoryAggregator.weekly(events: events, from: start, to: end, calendar: calendar)
        }
    }

    var rangeText: String {
        guard let range = try? store.dateRange() else { return "无" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: range.lowerBound)) – \(formatter.string(from: range.upperBound))"
    }

    func reload() {
        do {
            events = try store.load().events
            errorMessage = nil
        } catch {
            events = []
            errorMessage = error.localizedDescription
        }
    }

    func deleteAll() {
        do {
            try store.deleteAll()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func export(_ kind: HistoryExportKind) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [kind == .csv ? .commaSeparatedText : .json]
        panel.nameFieldStringValue = "SpineSaver-history-\(Self.dateString(Date())).\(kind == .csv ? "csv" : "json")"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data: Data
        switch kind {
        case .csv:
            data = HistoryExporter.csv(events: events, timeZone: .current)
        case .json:
            data = HistoryExporter.json(events: events, timeZone: .current)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct HistoryView: View {
    @ObservedObject var model: HistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("本地使用习惯")
                    .font(.title2.bold())
                Spacer()
                Picker("范围", selection: $model.range) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            if model.events.isEmpty {
                Text("暂无记录。完成一次计时或休息后，这里会出现本机记录。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Chart(model.buckets) { bucket in
                    BarMark(
                        x: .value("日期", bucket.startDate, unit: model.range == .daily ? .day : .weekOfYear),
                        y: .value("分钟", bucket.screenSeconds / 60)
                    )
                    .foregroundStyle(.tint)
                }
                .frame(height: 220)
            }

            HStack(spacing: 16) {
                Text("记录范围：\(model.rangeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(model.events.count) 条事件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            HStack(spacing: 12) {
                Button("导出 CSV…") { model.export(.csv) }
                Button("导出 JSON…") { model.export(.json) }
                Spacer()
                Button("删除全部历史…", role: .destructive) {
                    model.showDeleteConfirmation = true
                }
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
        .onAppear(perform: model.reload)
        .alert("删除全部历史？", isPresented: $model.showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                model.deleteAll()
            }
        } message: {
            Text("这会删除本机全部使用习惯记录，无法撤销。设置和本轮进度不会被删除。")
        }
    }
}
