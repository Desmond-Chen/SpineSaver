import AppKit
import Charts
import Combine
import SwiftUI
import UniformTypeIdentifiers
import SpineSaverCore

enum HistoryRange: String, CaseIterable, Identifiable {
    case today
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今日"
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
    @Published private(set) var events: [HistoryEvent] = []
    @Published private(set) var skippedLines = 0
    @Published private(set) var lastLoadedAt: Date?
    @Published private(set) var isStale = false
    @Published private(set) var readErrorMessage: String?
    @Published private(set) var exportErrorMessage: String?
    @Published private(set) var deleteErrorMessage: String?
    @Published var writerWarning: String?
    @Published var range: HistoryRange = .today
    @Published var showDeleteConfirmation = false

    let store: HistoryStore
    let calendar: Calendar

    init(store: HistoryStore, calendar: Calendar = .current, initialRange: HistoryRange = .today) {
        self.store = store
        self.calendar = calendar
        self.range = initialRange
    }

    var todayStart: Date {
        calendar.startOfDay(for: Date())
    }

    var hasSnapshot: Bool {
        lastLoadedAt != nil
    }

    var displayState: HistoryDisplayState {
        HistoryDisplayStateResolver.resolve(
            hasSnapshot: hasSnapshot,
            eventCount: events.count,
            readErrorMessage: readErrorMessage
        )
    }

    var lastLoadedText: String? {
        guard let lastLoadedAt else { return nil }
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: lastLoadedAt)
    }

    var dailyBuckets: [HistoryBucket] {
        let end = todayStart
        let start = calendar.date(byAdding: .day, value: -13, to: end) ?? end
        return HistoryAggregator.daily(events: events, from: start, to: end, calendar: calendar)
    }

    var weeklyBuckets: [HistoryBucket] {
        var iso = calendar
        iso.firstWeekday = 2
        iso.minimumDaysInFirstWeek = 4
        let end = todayStart
        let currentWeekStart = iso.dateInterval(of: .weekOfYear, for: end)?.start
            ?? iso.startOfDay(for: end)
        let start = iso.date(byAdding: .weekOfYear, value: -7, to: currentWeekStart) ?? currentWeekStart
        return HistoryAggregator.weekly(events: events, from: start, to: end, calendar: iso)
    }

    var buckets: [HistoryBucket] {
        switch range {
        case .today: return []
        case .daily: return dailyBuckets
        case .weekly: return weeklyBuckets
        }
    }

    var detailBuckets: [HistoryBucket] {
        switch range {
        case .today: return []
        case .daily: return Array(dailyBuckets.suffix(7))
        case .weekly: return Array(weeklyBuckets.suffix(4))
        }
    }

    var xComponent: Calendar.Component {
        range == .weekly ? .weekOfYear : .day
    }

    var xStride: Int {
        2
    }

    var rangeText: String {
        let times = events.map(\.occurredAt)
        guard let first = times.min(), let last = times.max() else { return "无" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "\(formatter.string(from: first)) - \(formatter.string(from: last))"
    }

    func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let weekday = ["日", "一", "二", "三", "四", "五", "六"][max(0, min(6, calendar.component(.weekday, from: date) - 1))]
        return "\(formatter.string(from: date)) 周\(weekday)"
    }

    func weekLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return "\(formatter.string(from: date)) 起"
    }

    func label(for date: Date) -> String {
        range == .weekly ? weekLabel(date) : dayLabel(date)
    }

    func restCount(for bucket: HistoryBucket) -> Int {
        bucket.restAutoCompletedCount + bucket.restFinishedEarlyCount
    }

    func reload() {
        do {
            apply(try store.load())
        } catch {
            markReadFailed(error)
        }
    }

    func deleteAll() {
        deleteErrorMessage = nil
        do {
            try store.deleteAll()
        } catch {
            deleteErrorMessage = error.localizedDescription
        }
        reload()
    }

    private func apply(_ result: HistoryLoadResult) {
        events = result.events
        skippedLines = result.skippedLines
        lastLoadedAt = Date()
        isStale = false
        readErrorMessage = nil
    }

    private func markReadFailed(_ error: Error) {
        readErrorMessage = error.localizedDescription
        isStale = true
    }

    func export(_ kind: HistoryExportKind) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [kind == .csv ? .commaSeparatedText : .json]
        panel.nameFieldStringValue = "SpineSaver-history-\(Self.dateString(Date())).\(kind == .csv ? "csv" : "json")"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportErrorMessage = nil

        let fresh: HistoryLoadResult
        do {
            fresh = try store.load()
        } catch {
            markReadFailed(error)
            exportErrorMessage = "导出已取消：无法读取最新历史记录，未写入文件。"
            return
        }
        apply(fresh)
        if fresh.skippedLines > 0 {
            exportErrorMessage = "导出已取消：\(fresh.skippedLines) 行记录无法解析，已阻止导出不完整数据。"
            return
        }
        let data: Data
        switch kind {
        case .csv:
            data = HistoryExporter.csv(events: fresh.events, timeZone: .current)
        case .json:
            data = HistoryExporter.json(events: fresh.events, timeZone: .current)
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            exportErrorMessage = "写入导出文件失败：\(error.localizedDescription)"
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
                .frame(width: 240)
            }

            if let warning = model.writerWarning {
                Text(warning)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            switch model.displayState {
            case .readFailureNoSnapshot:
                Text("读取历史记录失败：\(model.readErrorMessage ?? "")")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 320)
            case .staleEmpty:
                Text("刷新失败，上次成功读取时没有记录：\(model.readErrorMessage ?? "")")
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, minHeight: 320)
            case .empty:
                Text("暂无记录。完成一次计时或休息后，这里会出现本机记录。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 320)
            case .content:
                content
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 16) {
                    Text("记录范围：\(model.rangeText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(model.events.count) 条事件")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.skippedLines > 0 {
                        Text("跳过 \(model.skippedLines) 行无法解析的记录")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let loadedText = model.lastLoadedText {
                    Text("上次读取：\(loadedText)\(model.isStale ? "（数据可能已过期）" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("导出 CSV…") { model.export(.csv) }
                Button("导出 JSON…") { model.export(.json) }
                Spacer()
                Button("删除全部历史…", role: .destructive) {
                    model.showDeleteConfirmation = true
                }
            }

            if case .content = model.displayState, let readError = model.readErrorMessage {
                Text("刷新失败，仍显示上次成功读取的数据：\(readError)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let exportError = model.exportErrorMessage {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let deleteError = model.deleteErrorMessage {
                Text("删除历史失败：\(deleteError)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(20)
        .frame(minWidth: 840, minHeight: 620)
        .alert("删除全部历史？", isPresented: $model.showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                model.deleteAll()
            }
        } message: {
            Text("这会删除本机全部使用习惯记录，无法撤销。设置和本轮进度不会被删除。")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.range {
        case .today:
            ScrollView {
                TodayTimelineView(events: model.events, day: Date(), calendar: model.calendar)
                    .padding(.vertical, 4)
            }
        case .daily, .weekly:
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    chartSection(
                        title: "计时时长",
                        subtitle: model.range == .weekly ? "最近 8 个自然周" : "最近 14 天"
                    ) {
                        durationChart
                    }
                    chartSection(title: "休息完成次数", subtitle: "每根柱是一次完成的休息") {
                        restChart
                    }
                    detailList
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func chartSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            content()
        }
    }

    private var durationChart: some View {
        Chart(model.buckets) { bucket in
            BarMark(
                x: .value("日期", bucket.startDate, unit: model.xComponent),
                y: .value("分钟", bucket.screenSeconds / 60)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: model.xComponent, count: model.xStride)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(model.label(for: date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(DurationText.axis(seconds: minutes * 60))
                    }
                }
            }
        }
        .chartYAxisLabel("分钟")
        .frame(height: 180)
    }

    private var restChart: some View {
        Chart(model.buckets) { bucket in
            BarMark(
                x: .value("日期", bucket.startDate, unit: model.xComponent),
                y: .value("次", model.restCount(for: bucket))
            )
            .foregroundStyle(Color.green)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: model.xComponent, count: model.xStride)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(model.label(for: date))
                    }
                }
            }
        }
        .chartYAxisLabel("次")
        .frame(height: 150)
    }

    private var detailList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("明细")
                .font(.headline)
            HStack {
                Text("日期").frame(width: 130, alignment: .leading)
                Text("计时").frame(width: 120, alignment: .leading)
                Text("休息")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(model.detailBuckets) { bucket in
                HStack {
                    Text(model.label(for: bucket.startDate))
                        .frame(width: 130, alignment: .leading)
                    Text(DurationText.compact(seconds: bucket.screenSeconds))
                        .frame(width: 120, alignment: .leading)
                        .monospacedDigit()
                    Text("\(model.restCount(for: bucket)) 次")
                        .monospacedDigit()
                    Spacer()
                }
                .font(.caption)
            }
        }
    }
}
