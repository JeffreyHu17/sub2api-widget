import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @State private var instanceName = AppConstants.defaultInstanceName
    @State private var baseURLText = AppConstants.defaultBaseURL.absoluteString

    private var snapshot: MonitorSnapshot {
        appState.poller.latestSnapshot
            ?? SnapshotStore.shared.loadSnapshot(instanceID: appState.instance.id)
            ?? .unavailable(instanceID: appState.instance.id)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            dashboard
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $appState.showingLogin) {
            LoginSheet(instance: appState.instance)
                .environmentObject(appState)
                .frame(minWidth: 900, minHeight: 680)
        }
        .onAppear {
            instanceName = appState.instance.name
            baseURLText = appState.instance.baseURL.absoluteString
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sub2API Widget")
                    .font(.system(size: 24, weight: .bold))
                Text("本地轮询与桌面小组件控制台")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SidebarSection(title: "实例") {
                TextField("名称", text: $instanceName)
                TextField("Base URL", text: $baseURLText)
                Button("保存实例") {
                    appState.saveInstance(name: instanceName, baseURLText: baseURLText)
                }
                .buttonStyle(.borderedProminent)
            }

            SidebarSection(title: "登录") {
                StatusPill(text: appState.tokens == nil ? "未登录" : "已登录", status: appState.tokens == nil ? .warning : .ok)
                Button("打开登录页") {
                    appState.showingLogin = true
                }
                Button("清除本地凭据", role: .destructive) {
                    Task { await appState.signOut() }
                }
                .disabled(appState.tokens == nil)
            }

            SidebarSection(title: "轮询") {
                Picker("刷新", selection: $appState.selectedRefresh) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Button(appState.poller.isRunning ? "停止" : "启动") {
                        appState.poller.isRunning ? appState.stopPolling() : appState.startPolling()
                    }
                    Button("立即刷新") {
                        Task { await appState.pollNow() }
                    }
                }
            }

            Spacer()

            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(24)
        .frame(minWidth: 276)
        .background(AppTheme.sidebar)
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                healthStrip
                widgetCatalog
                platformOverview
                accountOverview
                diagnosticsPanel
            }
            .padding(28)
        }
        .background(AppTheme.background)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("监控控制台")
                    .font(.system(size: 32, weight: .bold))
                Text(appState.instance.baseURL.absoluteString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                StatusPill(text: snapshot.isStale ? "数据过期" : "数据新鲜", status: snapshot.isStale ? .warning : .ok)
                Link("打开运维页", destination: appState.instance.dashboardURL(platform: nil, timeRange: .fiveMinutes))
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var healthStrip: some View {
        HStack(spacing: 12) {
            MetricTile(title: "健康", value: "\(snapshot.server.healthScore)", suffix: "/100", tint: healthColor)
            MetricTile(title: "请求", value: MetricFormatters.compactNumber(snapshot.server.requestCount), suffix: "", tint: .blue)
            MetricTile(title: "SLA", value: MetricFormatters.percent(snapshot.server.slaPercent, digits: 2), suffix: "", tint: .green)
            MetricTile(title: "错误率", value: MetricFormatters.percent(snapshot.server.errorRate), suffix: "", tint: snapshot.server.errorRate > 0 ? .red : .green)
            MetricTile(title: "TTFT P99", value: MetricFormatters.compactMS(snapshot.server.ttftP99), suffix: "", tint: .red)
        }
    }

    private var widgetCatalog: some View {
        Panel(title: "可添加的小组件") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 130), spacing: 10), count: 3), spacing: 10) {
                WidgetCatalogItem(title: "全部平台", subtitle: "并发/排队/活跃账号")
                ForEach(PlatformID.allCases) { platform in
                    WidgetCatalogItem(title: platform.shortName, subtitle: platform.displayName)
                }
                WidgetCatalogItem(title: "服务器状态", subtitle: "健康/请求/资源")
                WidgetCatalogItem(title: "账号监控", subtitle: "连接/排队/额度")
            }
        }
    }

    private var platformOverview: some View {
        Panel(title: "平台活动") {
            VStack(spacing: 10) {
                ForEach(snapshot.platforms.sorted(by: sortPlatforms)) { platform in
                    PlatformDashboardRow(platform: platform)
                }
            }
        }
    }

    private var accountOverview: some View {
        Panel(title: "账号监控 · \(snapshot.monitoredAccounts.count)") {
            if snapshot.monitoredAccounts.isEmpty {
                Text("暂无账号数据，请完成登录并刷新。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(snapshot.monitoredAccounts.prefix(10)) { account in
                        AccountDashboardRow(account: account)
                    }
                }
            }
        }
    }

    private var diagnosticsPanel: some View {
        Panel(title: "刷新诊断") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 140), spacing: 12), count: 3), spacing: 12) {
                DiagnosticItem(title: "最近拉取", value: MetricFormatters.clockTime(snapshot.diagnostics.lastFetchAt))
                DiagnosticItem(title: "下次拉取", value: appState.poller.nextFetchAt.map { MetricFormatters.clockTime($0) } ?? MetricFormatters.clockTime(snapshot.diagnostics.nextFetchAt))
                DiagnosticItem(title: "快照写入", value: MetricFormatters.clockTime(snapshot.diagnostics.lastSnapshotWriteAt))
                DiagnosticItem(title: "Widget 请求", value: MetricFormatters.clockTime(snapshot.diagnostics.lastWidgetReloadRequestAt))
                DiagnosticItem(title: "轮询状态", value: appState.poller.isRunning ? "运行中 \(appState.selectedRefresh.displayName)" : "已停止")
            }
            if let error = snapshot.diagnostics.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private var healthColor: Color {
        if snapshot.server.healthScore >= 90 { return .green }
        if snapshot.server.healthScore >= 70 { return .orange }
        return .red
    }

    private func sortPlatforms(_ lhs: PlatformActivity, _ rhs: PlatformActivity) -> Bool {
        if lhs.hasActivity != rhs.hasActivity { return lhs.hasActivity }
        if lhs.currentInUse != rhs.currentInUse { return lhs.currentInUse > rhs.currentInUse }
        return lhs.platform.rawValue < rhs.platform.rawValue
    }
}

private enum AppTheme {
    static let background = Color(red: 0.07, green: 0.10, blue: 0.15)
    static let sidebar = Color(red: 0.045, green: 0.065, blue: 0.10)
    static let panel = Color(red: 0.10, green: 0.14, blue: 0.20)
    static let panelSoft = Color.white.opacity(0.055)
    static let border = Color.white.opacity(0.09)
}

private enum PillStatus {
    case ok
    case warning
    case error
}

private struct SidebarSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(.bottom, 2)
    }
}

private struct LoginSheet: View {
    @EnvironmentObject private var appState: AppState
    var instance: InstanceConfig

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("登录 Sub2API")
                        .font(.title2.bold())
                    Text("完成 Cloudflare/TOTP 后会自动保存本地 Token")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") {
                    appState.showingLogin = false
                }
            }
            .padding()
            Divider()
            LoginWebView(instance: instance) { tokens in
                appState.handleLoginTokens(tokens)
            } onStatus: { status in
                appState.statusMessage = status
            }
        }
    }
}

private struct Panel<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(18)
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.border)
        )
    }
}

private struct MetricTile: View {
    var title: String
    var value: String
    var suffix: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                Text(suffix)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppTheme.panelSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct PlatformDashboardRow: View {
    var platform: PlatformActivity

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(platform.platform.displayName)
                    .font(.headline)
                Text("\(platform.availableCount)/\(platform.totalAccounts) 可用 · \(platform.activeAccounts.count) 活跃账号")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 180, alignment: .leading)
            ProgressView(value: min(max(platform.loadPercent, 0), 100), total: 100)
                .tint(platform.loadPercent >= 80 ? .red : platform.loadPercent >= 50 ? .orange : .green)
            Text("\(platform.currentInUse)/\(platform.maxCapacity)")
                .font(.headline.monospacedDigit())
                .frame(width: 84, alignment: .trailing)
            StatusPill(text: platform.waitingInQueue > 0 ? "队列 \(platform.waitingInQueue)" : "队列 0", status: platform.waitingInQueue > 0 ? .warning : .ok)
        }
        .padding(12)
        .background(AppTheme.panelSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AccountDashboardRow: View {
    var account: AccountMonitor

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text("\(account.platformDisplayName) · \(account.type.uppercased()) · #\(account.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text("连接 \(account.currentInUse)/\(account.maxConcurrency) · 队列 \(account.waitingInQueue)")
                    .font(.callout.weight(.semibold).monospacedDigit())
                ProgressView(value: account.loadPercent, total: 100)
                    .tint(account.loadPercent >= 90 ? .orange : .green)
            }
            .frame(width: 210, alignment: .leading)

            if let quota = account.quotas.first {
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(quota.label) \(Int(quota.usedPercent.rounded()))%")
                        .font(.callout.weight(.bold).monospacedDigit())
                    Text("\(MetricFormatters.decimal(quota.used))/\(MetricFormatters.decimal(quota.limit))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(width: 110, alignment: .trailing)
            } else {
                Text("额度 --")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 110, alignment: .trailing)
            }

            StatusPill(text: account.status.displayName, status: pillStatus(account.status))
        }
        .padding(12)
        .background(AppTheme.panelSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func pillStatus(_ status: AccountHealthStatus) -> PillStatus {
        switch status {
        case .healthy, .busy: .ok
        case .rateLimited, .overloaded, .unavailable, .disabled: .warning
        case .error: .error
        }
    }
}

private struct WidgetCatalogItem: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AppTheme.panelSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DiagnosticItem: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppTheme.panelSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct StatusPill: View {
    var text: String
    var status: PillStatus

    var body: some View {
        let tint = color
        Text(text)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.16))
            .foregroundStyle(tint)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch status {
        case .ok: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
