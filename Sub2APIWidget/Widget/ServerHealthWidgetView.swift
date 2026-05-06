import SwiftUI
import WidgetKit

struct ServerHealthWidgetView: View {
    let entry: Sub2APIEntry
    let config: WidgetDisplayConfig
    let family: WidgetFamily

    private var server: ServerHealth { entry.snapshot.server }

    var body: some View {
        switch family {
        case .systemSmall:
            small
        case .systemMedium:
            medium
        default:
            large
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "服务器", systemImage: "chart.line.uptrend.xyaxis", snapshot: entry.snapshot)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(server.healthScore)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundStyle(scoreColor)
                    .minimumScaleFactor(0.6)
                Text("/100")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WidgetTheme.secondary)
            }
            HStack(spacing: 6) {
                MiniMetric(label: "QPS", value: MetricFormatters.decimal(server.qps.avg), tint: WidgetTheme.blue)
                MiniMetric(label: "TPS", value: MetricFormatters.decimal(server.tps.avg), tint: WidgetTheme.blue)
            }
            VStack(alignment: .leading, spacing: 3) {
                StatusLine(label: "DB", status: server.dbStatus)
                StatusLine(label: "Redis", status: server.redisStatus)
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(title: "服务器基础信息", systemImage: "chart.line.uptrend.xyaxis", snapshot: entry.snapshot)
            MetricGrid(columns: 4, rows: [
                .init(title: "健康", value: "\(server.healthScore)", tint: scoreColor),
                .init(title: "SLA", value: MetricFormatters.percent(server.slaPercent, digits: 2), tint: WidgetTheme.green),
                .init(title: "错误", value: MetricFormatters.percent(server.errorRate), tint: server.errorRate > 0 ? WidgetTheme.red : WidgetTheme.green),
                .init(title: "上游", value: MetricFormatters.percent(server.upstreamErrorRate), tint: server.upstreamErrorRate > 0 ? WidgetTheme.red : WidgetTheme.green),
                .init(title: "QPS", value: MetricFormatters.decimal(server.qps.avg), tint: WidgetTheme.blue),
                .init(title: "TPS", value: MetricFormatters.decimal(server.tps.avg), tint: WidgetTheme.blue),
                .init(title: "TTFT", value: MetricFormatters.compactMS(server.ttftP99), tint: WidgetTheme.red),
                .init(title: "P99", value: MetricFormatters.compactMS(server.durationP99), tint: WidgetTheme.orange),
                .init(title: "CPU", value: server.cpuPercent.map { MetricFormatters.percent($0) } ?? "--", tint: WidgetTheme.green),
                .init(title: "内存", value: server.memoryPercent.map { MetricFormatters.percent($0) } ?? "--", tint: WidgetTheme.green),
                .init(title: "DB", value: server.dbStatus.displayName, tint: statusColor(server.dbStatus)),
                .init(title: "Redis", value: server.redisStatus.displayName, tint: statusColor(server.redisStatus))
            ])
        }
        .compactWidgetPadding()
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeader(title: "服务器基础信息", systemImage: "chart.line.uptrend.xyaxis", snapshot: entry.snapshot)
            HStack(alignment: .top, spacing: 10) {
                ServerScoreCard(score: server.healthScore, tint: scoreColor)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 7) {
                    StatusLine(label: "数据库", status: server.dbStatus)
                    StatusLine(label: "Redis", status: server.redisStatus)
                    StatusLine(label: "后台任务", status: server.jobStatus)
                }
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .widgetSurface(tint: WidgetTheme.panel, opacity: 0.92, cornerRadius: 8)
            }
            MetricGrid(columns: 4, rows: [
                .init(title: "请求", value: MetricFormatters.compactNumber(server.requestCount), tint: WidgetTheme.blue),
                .init(title: "Token", value: MetricFormatters.compactNumber(server.tokenConsumed), tint: WidgetTheme.blue),
                .init(title: "SLA", value: MetricFormatters.percent(server.slaPercent, digits: 2), tint: WidgetTheme.green),
                .init(title: "错误", value: MetricFormatters.percent(server.errorRate), tint: server.errorRate > 0 ? WidgetTheme.red : WidgetTheme.green),
                .init(title: "QPS", value: MetricFormatters.decimal(server.qps.avg), tint: WidgetTheme.blue),
                .init(title: "TPS", value: MetricFormatters.decimal(server.tps.avg), tint: WidgetTheme.blue),
                .init(title: "P99", value: MetricFormatters.compactMS(server.durationP99), tint: WidgetTheme.orange),
                .init(title: "TTFT", value: MetricFormatters.compactMS(server.ttftP99), tint: WidgetTheme.red),
                .init(title: "CPU", value: server.cpuPercent.map { MetricFormatters.percent($0) } ?? "--", tint: WidgetTheme.green),
                .init(title: "内存", value: server.memoryPercent.map { MetricFormatters.percent($0) } ?? "--", tint: WidgetTheme.green),
                .init(title: "协程", value: server.goroutines.map(String.init) ?? "--", tint: WidgetTheme.green),
                .init(title: "队列", value: server.queueDepth.map(String.init) ?? "--", tint: WidgetTheme.orange)
            ])
            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private var scoreColor: Color {
        if server.healthScore >= 90 { return WidgetTheme.green }
        if server.healthScore >= 70 { return WidgetTheme.orange }
        return WidgetTheme.red
    }
}

private struct ServerScoreCard: View {
    var score: Int
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("健康评分")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(score)")
                    .font(.system(size: 36, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Text("/100")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.14))
                    Capsule()
                        .fill(tint)
                        .frame(width: max(2, proxy.size.width * CGFloat(min(max(score, 0), 100)) / 100))
                }
            }
            .frame(height: 6)
        }
        .padding(10)
        .widgetSurface(tint: tint, opacity: 0.12, cornerRadius: 8)
    }
}

private struct MetricCell: Identifiable {
    let id = UUID()
    var title: String
    var value: String
    var tint: Color
}

private struct MetricGrid: View {
    var columns: Int
    var rows: [MetricCell]

    var body: some View {
        let gridColumns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 6), count: columns)
        LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 6) {
            ForEach(rows) { row in
                HealthMetric(title: row.title, value: row.value, tint: row.tint)
            }
        }
    }
}

private struct HealthMetric: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.42)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .widgetSurface(tint: WidgetTheme.panel, opacity: 0.92)
    }
}

private struct MiniMetric: View {
    var label: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.secondary)
            Text(value)
                .font(.caption.weight(.heavy).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .widgetSurface(tint: WidgetTheme.panel, opacity: 0.92)
    }
}
