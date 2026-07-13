import SwiftUI
import WidgetKit

struct AccountMonitorWidgetView: View {
    let entry: Sub2APIEntry
    let config: WidgetDisplayConfig
    let family: WidgetFamily

    private var accounts: [AccountMonitor] {
        let selectedIDs = config.accountIDs ?? config.accountID.map { [$0] } ?? []
        if !selectedIDs.isEmpty {
            let selectedSet = Set(selectedIDs)
            return entry.snapshot.monitoredAccounts.filter { selectedSet.contains($0.id) }
        }
        return entry.snapshot.monitoredAccounts.filter(\.eligibleForAutomaticMonitoring)
    }

    private var account: AccountMonitor? { accounts.first }

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
        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(title: "账号 · \(accounts.count)", systemImage: "person.crop.circle", snapshot: entry.snapshot)
            if let account {
                accountIdentity(account, nameLines: 2)
                connectionGauge(account)
                if let quota = account.quotas.first {
                    QuotaGauge(quota: quota)
                } else {
                    Text("未配置本地额度")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetTheme.secondary)
                }
            } else {
                EmptyState(text: "暂无启用调度的账号，可手动选择")
            }
            Spacer(minLength: 0)
        }
        .padding(13)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 7) {
            WidgetHeader(title: "账号监控 · \(accounts.count)", systemImage: "person.crop.circle", snapshot: entry.snapshot)
            if accounts.isEmpty {
                EmptyState(text: "暂无启用调度的账号，可编辑 Widget 手动选择")
            } else {
                ForEach(accounts.prefix(2)) { account in
                    AccountMonitorRow(account: account, compact: true)
                }
            }
            Spacer(minLength: 0)
        }
        .compactWidgetPadding()
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeader(title: "账号监控 · \(accounts.count)", systemImage: "person.crop.circle", snapshot: entry.snapshot)
            if accounts.isEmpty {
                EmptyState(text: "暂无启用调度的账号，可编辑 Widget 手动选择")
            } else {
                ForEach(accounts.prefix(6)) { account in
                    AccountMonitorRow(account: account, compact: false)
                }
                if accounts.count > 6 {
                    Text("另有 \(accounts.count - 6) 个账号")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(WidgetTheme.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
    }

    @ViewBuilder
    private func accountIdentity(_ account: AccountMonitor, nameLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(account.platformDisplayName)
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(WidgetTheme.blue)
                    .lineLimit(1)
                AccountStatusBadge(status: account.status)
                Spacer(minLength: 0)
            }
            Text(account.name)
                .font(.system(size: family == .systemLarge ? 17 : 14, weight: .heavy, design: .rounded))
                .foregroundStyle(WidgetTheme.text)
                .lineLimit(nameLines)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.leading)
            if let message = account.statusMessage {
                Text(message)
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetTheme.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    @ViewBuilder
    private func connectionGauge(_ account: AccountMonitor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("连接 / 并发")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetTheme.secondary)
                Spacer(minLength: 4)
                Text("\(account.currentInUse)/\(account.maxConcurrency)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(account.currentInUse > 0 ? WidgetTheme.green : WidgetTheme.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.13))
                    Capsule()
                        .fill(account.loadPercent >= 90 ? WidgetTheme.orange : WidgetTheme.green)
                        .frame(width: max(2, proxy.size.width * CGFloat(account.loadPercent / 100)))
                }
            }
            .frame(height: 5)
        }
    }

}

private struct AccountMonitorRow: View {
    let account: AccountMonitor
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.system(size: compact ? 10.5 : 11.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(WidgetTheme.text)
                        .lineLimit(2)
                        .minimumScaleFactor(0.5)
                    HStack(spacing: 5) {
                        Text(account.platformDisplayName)
                            .foregroundStyle(WidgetTheme.blue)
                        Text(account.status.displayName)
                            .foregroundStyle(healthColor(account.status))
                    }
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                RowMetric(label: "并发", value: "\(account.currentInUse)/\(account.maxConcurrency)", tint: account.currentInUse > 0 ? WidgetTheme.green : WidgetTheme.secondary)
                RowMetric(label: "队列", value: "\(account.waitingInQueue)", tint: account.waitingInQueue > 0 ? WidgetTheme.orange : WidgetTheme.secondary)
                if let quota = account.quotas.first {
                    RowMetric(label: quota.label, value: "\(Int(quota.usedPercent.rounded()))%", tint: quotaTint(quota))
                } else {
                    RowMetric(label: "额度", value: "--", tint: WidgetTheme.secondary)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(account.loadPercent >= 90 ? WidgetTheme.orange : WidgetTheme.green)
                        .frame(width: max(2, proxy.size.width * CGFloat(account.loadPercent / 100)))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, compact ? 7 : 9)
        .padding(.vertical, compact ? 5 : 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetSurface(tint: healthColor(account.status), opacity: 0.07, cornerRadius: 7)
    }

    private func quotaTint(_ quota: AccountQuotaWindow) -> Color {
        if quota.usedPercent >= 90 { return WidgetTheme.red }
        if quota.usedPercent >= 70 { return WidgetTheme.orange }
        return WidgetTheme.green
    }
}

private struct RowMetric: View {
    let label: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(label)
                .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetTheme.secondary)
            Text(value)
                .font(.system(size: 10, weight: .heavy, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
        }
        .frame(minWidth: 34, alignment: .trailing)
    }
}

private struct AccountStatusBadge: View {
    let status: AccountHealthStatus

    var body: some View {
        Text(status.displayName)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(healthColor(status))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .widgetSurface(tint: healthColor(status), opacity: 0.14, cornerRadius: 6)
    }
}

private struct QuotaGauge: View {
    let quota: AccountQuotaWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(quota.label)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetTheme.secondary)
                Spacer(minLength: 4)
                Text("\(Int(quota.usedPercent.rounded()))%")
                    .font(.system(size: 9.5, weight: .heavy, design: .rounded).monospacedDigit())
                    .foregroundStyle(quotaColor)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.13))
                    Capsule()
                        .fill(quotaColor)
                        .frame(width: max(2, proxy.size.width * CGFloat(quota.usedPercent / 100)))
                }
            }
            .frame(height: 4)
        }
    }

    private var quotaColor: Color {
        if quota.usedPercent >= 90 { return WidgetTheme.red }
        if quota.usedPercent >= 70 { return WidgetTheme.orange }
        return WidgetTheme.green
    }
}

private func healthColor(_ status: AccountHealthStatus) -> Color {
    switch status {
    case .healthy: WidgetTheme.green
    case .busy: WidgetTheme.blue
    case .rateLimited, .overloaded: WidgetTheme.orange
    case .error: WidgetTheme.red
    case .unavailable, .disabled: WidgetTheme.secondary
    }
}
