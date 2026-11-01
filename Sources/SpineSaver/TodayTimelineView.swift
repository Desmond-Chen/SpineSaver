import Charts
import SwiftUI
import SpineSaverCore

/// One calendar day rebuilt from the event log: four unit-bearing summary tiles,
/// a 24 hour three-lane strip, and an hourly work bar chart.
struct TodayTimelineView: View {
    let events: [HistoryEvent]
    let day: Date
    let calendar: Calendar

    var body: some View {
        let now = Date()
        let segments = DailyTimeline.segments(
            events: events,
            day: day,
            referenceDate: now,
            calendar: calendar
        )
        let hourly = DailyTimeline.hourlyTotals(
            events: events,
            day: day,
            referenceDate: now,
            calendar: calendar
        )
        let summary = DailyTimeline.summary(events: events, day: day, calendar: calendar)

        VStack(alignment: .leading, spacing: 16) {
            statTiles(summary)
            if segments.isEmpty {
                Text("今天还没有记录。开始计时或完成一次休息后，这里会出现当天的时段。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                timelineChart(segments, now: now)
                Divider()
                hourlyChart(hourly)
            }
        }
    }

    private func statTiles(_ summary: TodaySummary) -> some View {
        HStack(spacing: 12) {
            tile("计时", DurationText.compact(seconds: summary.workSeconds))
            tile("休息", "\(summary.restCount) 次 · \(DurationText.compact(seconds: summary.restSeconds))")
            tile("提醒", "\(summary.reminderCount) 次")
            tile("推迟", "\(summary.snoozeCount) 次")
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func timelineChart(_ segments: [TimelineSegment], now: Date) -> some View {
        Chart {
            ForEach(segments.indices, id: \.self) { index in
                let segment = segments[index]
                if segment.kind == .reminder {
                    PointMark(
                        x: .value("时间", segment.start),
                        y: .value("类型", laneTitle(.reminder))
                    )
                    .foregroundStyle(color(for: .reminder))
                    .symbolSize(40)
                } else {
                    RectangleMark(
                        xStart: .value("开始", segment.start),
                        xEnd: .value("结束", segment.end),
                        y: .value("类型", laneTitle(segment.kind))
                    )
                    .foregroundStyle(color(for: segment.kind))
                }
            }
            if calendar.isDate(now, inSameDayAs: day) {
                RuleMark(x: .value("现在", now))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: dayWindow.start...dayWindow.end)
        .chartYScale(domain: [laneTitle(.work), laneTitle(.rest), laneTitle(.reminder)])
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text("\(calendar.component(.hour, from: date))")
                    }
                }
            }
        }
        .chartXAxisLabel("时")
        .frame(height: 150)
    }

    private func hourlyChart(_ hourly: [HourlyTotal]) -> some View {
        Chart(hourly, id: \.hour) { item in
            BarMark(
                x: .value("小时", item.hour),
                y: .value("分钟", item.workSeconds / 60)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartXAxis {
            AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let hour = value.as(Int.self) {
                        Text("\(hour)")
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
        .frame(height: 130)
    }

    private var dayWindow: (start: Date, end: Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)
            ?? start.addingTimeInterval(24 * 3600)
        return (start, end)
    }

    private func laneTitle(_ kind: TimelineKind) -> String {
        switch kind {
        case .work: return "计时"
        case .rest, .restCancelled: return "休息"
        case .reminder: return "提醒"
        }
    }

    private func color(for kind: TimelineKind) -> Color {
        switch kind {
        case .work: return .accentColor
        case .rest: return .green
        case .restCancelled: return .green.opacity(0.35)
        case .reminder: return .orange
        }
    }
}
