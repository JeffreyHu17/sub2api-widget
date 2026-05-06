import SwiftUI
import WidgetKit

struct PlatformActivityWidgetView: View {
    let entry: Sub2APIEntry
    let config: WidgetDisplayConfig
    let family: WidgetFamily

    private var platforms: [PlatformActivity] {
        let filtered = entry.snapshot.platforms.filter { platform in
            config.platformFilter == nil || config.platformFilter == platform.platform
        }
        return filtered.sorted {
            if $0.hasActivity != $1.hasActivity {
                return $0.hasActivity
            }
            if $0.currentInUse != $1.currentInUse {
                return $0.currentInUse > $1.currentInUse
            }
            return $0.platform.rawValue < $1.platform.rawValue
        }
    }

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
        let platform = platforms.first ?? entry.snapshot.platforms.first
        return VStack(alignment: .leading, spacing: 10) {
            WidgetHeader(title: "活动", systemImage: "bolt.fill", snapshot: entry.snapshot)
            if let platform {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(platform.platform.displayName)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(WidgetTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.58)
                        Spacer(minLength: 2)
                        Text("\(platform.currentInUse)/\(platform.maxCapacity)")
                            .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(platform.hasActivity ? WidgetTheme.green : WidgetTheme.secondary)
                    }
                    LoadLine(platform: platform, height: 5)
                }
                HStack(spacing: 6) {
                    SmallStatPill(text: "队列 \(platform.waitingInQueue)", tint: platform.waitingInQueue > 0 ? WidgetTheme.orange : WidgetTheme.secondary)
                    SmallStatPill(text: "账号 \(platform.availableCount)/\(platform.totalAccounts)", tint: WidgetTheme.green)
                }
                if let account = platform.activeAccounts.first {
                    Text(account.accountName)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.56)
                } else {
                    Text("暂无活跃账号")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetTheme.secondary)
                }
            } else {
                EmptyState(text: "暂无数据")
            }
            Spacer(minLength: 0)
        }
        .widgetPadding()
    }

    @ViewBuilder
    private var medium: some View {
        if config.platformFilter == nil {
            mediumAllPlatforms
        } else {
            mediumSinglePlatform
        }
    }

    private var mediumAllPlatforms: some View {
        GeometryReader { proxy in
            let outerPadding: CGFloat = 14
            let headerHeight: CGFloat = 17
            let bodySpacing: CGFloat = 7
            let availableHeight = max(88, proxy.size.height - outerPadding * 2 - headerHeight - bodySpacing)
            let gridColumns = Array(repeating: GridItem(.flexible(minimum: 0), spacing: 7), count: 2)
            let cardHeight = floor((availableHeight - 7) / 2)

            VStack(alignment: .leading, spacing: bodySpacing) {
                CompactWidgetHeader(title: "全部平台", systemImage: "bolt.fill", snapshot: entry.snapshot)
                    .frame(height: headerHeight)
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 7) {
                    ForEach(Array(platforms.prefix(4))) { platform in
                        PlatformMediumTile(platform: platform)
                            .frame(height: cardHeight)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: availableHeight, alignment: .topLeading)
            }
            .padding(outerPadding)
        }
    }

    private var mediumSinglePlatform: some View {
        let platform = platforms.first ?? entry.snapshot.platforms.first
        return GeometryReader { proxy in
            let padding: CGFloat = 16
            let accountLimit = proxy.size.width > 310 ? 3 : 2
            VStack(alignment: .leading, spacing: 12) {
                WidgetHeader(title: "平台活动", systemImage: "bolt.fill", snapshot: entry.snapshot)
                if let platform {
                    HStack(alignment: .firstTextBaseline) {
                        Text(platform.platform.displayName)
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(WidgetTheme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Spacer()
                        Text("\(platform.currentInUse)/\(platform.maxCapacity)")
                            .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(platform.hasActivity ? WidgetTheme.green : WidgetTheme.secondary)
                    }
                    LoadLine(platform: platform, height: 6)
                    HStack(spacing: 8) {
                        MediumBadge(text: "队列 \(platform.waitingInQueue)", tint: platform.waitingInQueue > 0 ? WidgetTheme.orange : WidgetTheme.secondary)
                        MediumBadge(text: "账号 \(platform.availableCount)/\(platform.totalAccounts)", tint: WidgetTheme.green)
                        if platform.rateLimitedCount > 0 {
                            MediumBadge(text: "限流 \(platform.rateLimitedCount)", tint: WidgetTheme.orange)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(platform.activeAccounts.prefix(accountLimit))) { account in
                            Text(account.accountName)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(WidgetTheme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                        }
                        if platform.activeAccounts.isEmpty {
                            MediumEmptyState(text: "暂无活跃账号")
                        }
                    }
                } else {
                    EmptyState(text: "暂无数据")
                }
                Spacer(minLength: 0)
            }
            .padding(padding)
        }
    }

    private var large: some View {
        GeometryReader { _ in
            let isSingle = config.platformFilter != nil
            VStack(alignment: .leading, spacing: 12) {
                WidgetHeader(title: isSingle ? "平台活动" : "全部平台", systemImage: "bolt.fill", snapshot: entry.snapshot)
                if isSingle, let platform = platforms.first {
                    PlatformLargeDetail(platform: platform)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10), count: 2), spacing: 10) {
                        ForEach(Array(platforms.prefix(4))) { platform in
                            PlatformLargeSummaryCard(platform: platform)
                        }
                    }
                    let accounts = activeAccounts(limit: 3)
                    if !accounts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("活跃账号")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(WidgetTheme.secondary)
                            ForEach(accounts) { account in
                                Text("\(account.platform.shortName) · \(account.accountName)")
                                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(WidgetTheme.text)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.55)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }

    private func activeAccounts(limit: Int) -> [ActiveAccount] {
        Array(platforms.flatMap(\.activeAccounts).prefix(limit))
    }

    private func accountBlock(accounts: [ActiveAccount], limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if accounts.isEmpty {
                Text("暂无活跃账号")
                    .font(.caption2)
                    .foregroundStyle(WidgetTheme.secondary)
            } else {
                ForEach(Array(accounts.prefix(limit))) { account in
                    Text(account.accountName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(WidgetTheme.text)
                        .lineLimit(family == .systemSmall ? 2 : 3)
                        .minimumScaleFactor(0.48)
                }
            }
        }
    }
}

private struct PlatformCompactRow: View {
    let platform: PlatformActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(platform.platform.displayName)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Spacer()
                Text("\(platform.currentInUse)/\(platform.maxCapacity)")
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(platform.hasActivity ? WidgetTheme.green : WidgetTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            LoadLine(platform: platform)
            HStack(spacing: 4) {
                Text("队\(platform.waitingInQueue)")
                Text("可\(platform.availableCount)/\(platform.totalAccounts)")
                if platform.rateLimitedCount > 0 {
                    Text("限\(platform.rateLimitedCount)")
                        .foregroundStyle(WidgetTheme.orange)
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(WidgetTheme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 37, maxHeight: 37, alignment: .leading)
        .widgetSurface(tint: WidgetTheme.panel, opacity: 0.92)
    }
}

private struct PlatformMediumRow: View {
    let platform: PlatformActivity
    let rowHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(platform.platform.displayName)
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                Spacer(minLength: 4)
                Text("\(platform.currentInUse)/\(platform.maxCapacity)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(platform.hasActivity ? WidgetTheme.green : WidgetTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            LoadLine(platform: platform, height: 4)
            HStack(spacing: 4) {
                Text("队\(platform.waitingInQueue)")
                Text("可\(platform.availableCount)/\(platform.totalAccounts)")
                if platform.rateLimitedCount > 0 {
                    Text("限\(platform.rateLimitedCount)")
                        .foregroundStyle(WidgetTheme.orange)
                }
            }
            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
            .foregroundStyle(WidgetTheme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.62)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: rowHeight, maxHeight: rowHeight, alignment: .leading)
        .widgetSurface(tint: WidgetTheme.panel, opacity: 0.92, cornerRadius: 8)
    }
}

private struct PlatformMediumTile: View {
    let platform: PlatformActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(platform.platform.displayName)
                    .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.56)
                Spacer(minLength: 3)
                Text("\(platform.currentInUse)/\(platform.maxCapacity)")
                    .font(.system(size: 10.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(platform.hasActivity ? WidgetTheme.green : WidgetTheme.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
            }
            LoadLine(platform: platform, height: 4)
            HStack(spacing: 5) {
                Text("队\(platform.waitingInQueue)")
                Text("可\(platform.availableCount)/\(platform.totalAccounts)")
                if platform.rateLimitedCount > 0 {
                    Text("限\(platform.rateLimitedCount)")
                        .foregroundStyle(WidgetTheme.orange)
                }
            }
            .font(.system(size: 8.6, weight: .semibold, design: .rounded))
            .foregroundStyle(WidgetTheme.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.58)
            if let account = platform.activeAccounts.first {
                Text(account.accountName)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.48)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetSurface(tint: WidgetTheme.panel, opacity: 0.92, cornerRadius: 8)
    }
}

private struct SmallStatPill: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .widgetSurface(tint: tint, opacity: 0.12, cornerRadius: 999)
    }
}

private struct AccountCompactRow: View {
    let account: ActiveAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(account.platform.shortName)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(platformColor(account.platform))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text("\(account.currentInUse)/\(account.maxCapacity)")
                    .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(WidgetTheme.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if account.waitingInQueue > 0 {
                    Text("队\(account.waitingInQueue)")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(WidgetTheme.orange)
                        .lineLimit(1)
                }
            }
            Text(account.accountName)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 45, alignment: .leading)
        .widgetSurface(tint: WidgetTheme.panelSoft, opacity: 1)
    }
}

private struct AccountMediumRow: View {
    let account: ActiveAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(account.platform.shortName)
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(platformColor(account.platform))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 2)
                Text("\(account.currentInUse)/\(account.maxCapacity)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(WidgetTheme.secondary)
                    .lineLimit(1)
            }
            Text(account.accountName)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(WidgetTheme.text)
                .lineLimit(2)
                .minimumScaleFactor(0.52)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, minHeight: 43, alignment: .leading)
        .widgetSurface(tint: WidgetTheme.panelSoft, opacity: 1, cornerRadius: 8)
    }
}

private struct MediumBadge: View {
    var text: String
    var tint: Color

    var body: some View {
        Text(text)
            .font(.system(size: 8.5, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .widgetSurface(tint: tint, opacity: 0.14, cornerRadius: 999)
    }
}

private struct MediumEmptyState: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(WidgetTheme.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

private struct PlatformLargeSummaryCard: View {
    let platform: PlatformActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(platform.platform.displayName)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.58)
                Spacer()
                Text("\(platform.currentInUse)/\(platform.maxCapacity)")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(platform.hasActivity ? WidgetTheme.green : WidgetTheme.secondary)
            }
            LoadLine(platform: platform, height: 5)
            HStack(spacing: 5) {
                MediumBadge(text: "队\(platform.waitingInQueue)", tint: platform.waitingInQueue > 0 ? WidgetTheme.orange : WidgetTheme.secondary)
                MediumBadge(text: "可\(platform.availableCount)/\(platform.totalAccounts)", tint: WidgetTheme.green)
                if platform.rateLimitedCount > 0 {
                    MediumBadge(text: "限\(platform.rateLimitedCount)", tint: WidgetTheme.orange)
                }
            }
            HStack(spacing: 8) {
                if platform.errorCount > 0 {
                    Text("异常 \(platform.errorCount)")
                        .foregroundStyle(WidgetTheme.red)
                } else {
                    Text("活跃 \(platform.activeAccounts.count)")
                        .foregroundStyle(platform.hasActivity ? WidgetTheme.green : WidgetTheme.secondary)
                }
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .padding(10)
        .widgetSurface(tint: WidgetTheme.panel, opacity: 0.92, cornerRadius: 8)
    }
}

private struct PlatformLargeDetail: View {
    let platform: PlatformActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(platform.platform.displayName)
                    .font(.system(size: 25, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                Spacer()
                Text("\(platform.currentInUse)/\(platform.maxCapacity)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(platform.hasActivity ? WidgetTheme.green : WidgetTheme.secondary)
            }
            LoadLine(platform: platform, height: 7)
            HStack(spacing: 8) {
                Badge(text: "队列 \(platform.waitingInQueue)", tint: platform.waitingInQueue > 0 ? WidgetTheme.orange : WidgetTheme.secondary)
                Badge(text: "账号 \(platform.availableCount)/\(platform.totalAccounts)", tint: WidgetTheme.green)
                if platform.rateLimitedCount > 0 {
                    Badge(text: "限流 \(platform.rateLimitedCount)", tint: WidgetTheme.orange)
                }
                if platform.errorCount > 0 {
                    Badge(text: "异常 \(platform.errorCount)", tint: WidgetTheme.red)
                }
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("活跃账号")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.secondary)
                if platform.activeAccounts.isEmpty {
                    MediumEmptyState(text: "暂无活跃账号")
                } else {
                    ForEach(Array(platform.activeAccounts.prefix(5))) { account in
                        HStack(spacing: 8) {
                            Text("\(account.currentInUse)/\(account.maxCapacity)")
                                .font(.system(size: 10, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(WidgetTheme.secondary)
                                .frame(width: 44, alignment: .leading)
                            Text(account.accountName)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(WidgetTheme.text)
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                        }
                    }
                }
            }
        }
    }
}

private func platformColor(_ platform: PlatformID) -> Color {
    switch platform {
    case .anthropic: WidgetTheme.orange
    case .openai: WidgetTheme.green
    case .gemini: WidgetTheme.blue
    case .antigravity: WidgetTheme.red
    }
}

private struct LoadLine: View {
    let platform: PlatformActivity
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14))
                Capsule()
                    .fill(platform.loadPercent >= 80 ? WidgetTheme.red : (platform.loadPercent >= 50 ? WidgetTheme.orange : WidgetTheme.green))
                    .frame(width: max(2, proxy.size.width * min(max(platform.loadPercent, 0), 100) / 100))
            }
        }
        .frame(height: height)
    }
}
