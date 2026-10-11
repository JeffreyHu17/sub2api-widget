import AppIntents
import SwiftUI
import WidgetKit
#if os(macOS)
import AppKit
#endif

struct Sub2APIEntry: TimelineEntry {
    let date: Date
    let displayConfig: WidgetDisplayConfig
    let snapshot: MonitorSnapshot
    let instance: InstanceConfig
}

protocol Sub2APIDisplayConfigurationIntent: WidgetConfigurationIntent {
    var displayConfig: WidgetDisplayConfig { get }
}

extension PlatformActivityWidgetIntent: Sub2APIDisplayConfigurationIntent {}
extension ServerHealthWidgetIntent: Sub2APIDisplayConfigurationIntent {}
extension AccountMonitorWidgetIntent: Sub2APIDisplayConfigurationIntent {}

struct Sub2APIProvider<Intent: Sub2APIDisplayConfigurationIntent>: AppIntentTimelineProvider {
    var forcedPlatform: PlatformID?

    init(forcedPlatform: PlatformID? = nil) {
        self.forcedPlatform = forcedPlatform
    }

    func placeholder(in context: Context) -> Sub2APIEntry {
        // Gallery preview only — fabricated sample data is acceptable here and
        // nowhere else. Real timelines use `entry(for:)` which returns `unavailable`.
        Sub2APIEntry(
            date: Date(),
            displayConfig: WidgetDisplayConfig.defaultActivity,
            snapshot: .placeholder(),
            instance: .production
        )
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Sub2APIEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Sub2APIEntry> {
        let entry = entry(for: configuration)
        let interval = TimeInterval(max(entry.displayConfig.refreshIntervalSec, 5))
        let now = Date()
        let entryCount = timelineEntryCount(for: interval)
        let entries = (0..<entryCount).map { index in
            Sub2APIEntry(
                date: now.addingTimeInterval(TimeInterval(index) * interval),
                displayConfig: entry.displayConfig,
                snapshot: entry.snapshot,
                instance: entry.instance
            )
        }
        let plannedRefresh = now.addingTimeInterval(TimeInterval(entryCount) * interval)
        let refreshAfter = min(plannedRefresh, max(entry.snapshot.expiresAt, now.addingTimeInterval(15)))
        return Timeline(entries: entries, policy: .after(refreshAfter))
    }

    private func entry(for configuration: Intent) -> Sub2APIEntry {
        let instances = SnapshotStore.shared.loadInstances()
        // loadInstances() guarantees a non-empty result, but indexing without a
        // guard would trap the widget extension process if that ever changed.
        let instanceID = configuration.displayConfig.instanceID
        let resolved: InstanceConfig
        if let match = instances.first(where: { $0.id == instanceID }) {
            resolved = match
        } else {
            resolved = instances.first ?? .production
        }
        let snapshot = SnapshotStore.shared.loadSnapshot(instanceID: resolved.id)
            ?? .unavailable(instanceID: resolved.id)
        var displayConfig = configuration.displayConfig
        displayConfig.instanceID = resolved.id
        displayConfig.platformFilter = forcedPlatform
        displayConfig.id = "\(displayConfig.instanceID)-\(forcedPlatform?.rawValue ?? displayConfig.kind.rawValue)"
        return Sub2APIEntry(date: Date(), displayConfig: displayConfig, snapshot: snapshot, instance: resolved)
    }

    private func timelineEntryCount(for interval: TimeInterval) -> Int {
        switch interval {
        case ..<10:
            return 12
        case ..<20:
            return 8
        default:
            return 6
        }
    }
}

struct PlatformActivityStatusWidget: Widget {
    var platform: PlatformID? = nil

    private var kind: String {
        "Sub2APIPlatformActivityWidget-\(platform?.rawValue ?? "all")"
    }

    private var displayName: String {
        if let platform {
            return "Sub2API \(platform.shortName)"
        }
        return "Sub2API 全部平台"
    }

    private var description: String {
        if let platform {
            return "显示 \(platform.shortName) 的并发、排队和活跃账号。"
        }
        return "显示全部平台的并发、排队和活跃账号。"
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: PlatformActivityWidgetIntent.self, provider: Sub2APIProvider<PlatformActivityWidgetIntent>(forcedPlatform: platform)) { entry in
            PlatformActivityEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetTheme.background
                }
        }
        .configurationDisplayName(displayName)
        .description(description)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}

struct ServerHealthStatusWidget: Widget {
    let kind = "Sub2APIServerHealthWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ServerHealthWidgetIntent.self, provider: Sub2APIProvider<ServerHealthWidgetIntent>()) { entry in
            ServerHealthEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetTheme.background
                }
        }
        .configurationDisplayName("Sub2API 服务器状态")
        .description("显示服务器健康、请求、错误率和基础资源。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}

struct AccountMonitorStatusWidget: Widget {
    let kind = "Sub2APIAccountMonitorWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: AccountMonitorWidgetIntent.self, provider: Sub2APIProvider<AccountMonitorWidgetIntent>()) { entry in
            AccountMonitorEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetTheme.background
                }
        }
        .configurationDisplayName("Sub2API 账号监控")
        .description("显示指定账号的连接、排队、额度与可用状态。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
        .containerBackgroundRemovable(true)
    }
}

struct PlatformActivityEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Sub2APIEntry

    var body: some View {
        PlatformActivityWidgetView(entry: entry, config: entry.displayConfig, family: family)
            .widgetURL(entry.instance.dashboardURL(platform: entry.displayConfig.platformFilter, timeRange: entry.displayConfig.timeRange))
    }
}

struct ServerHealthEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Sub2APIEntry

    var body: some View {
        ServerHealthWidgetView(entry: entry, config: entry.displayConfig, family: family)
            .widgetURL(entry.instance.dashboardURL(platform: nil, timeRange: entry.displayConfig.timeRange))
    }
}

struct AccountMonitorEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: Sub2APIEntry

    var body: some View {
        AccountMonitorWidgetView(entry: entry, config: entry.displayConfig, family: family)
            .widgetURL(entry.instance.accountsURL)
    }
}

enum WidgetTheme {
    @MainActor
    static var background: some View {
        WidgetContainerBackground()
    }
    static let panel = Color.primary.opacity(0.10)
    static let panelSoft = Color.primary.opacity(0.055)
    static let border = Color.primary.opacity(0.16)
    static let text = Color.primary
    static let secondary = Color.secondary
    static let muted = Color.secondary.opacity(0.74)
    static let blue = Color.blue
    static let green = Color.green
    static let orange = Color.orange
    static let red = Color.red
}

private struct WidgetContainerBackground: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsWidgetContainerBackground

    var body: some View {
        if showsWidgetContainerBackground {
            platformBackground
                .overlay {
                    LinearGradient(
                        colors: [
                            WidgetTheme.blue.opacity(renderingMode == .fullColor ? 0.13 : 0.04),
                            WidgetTheme.green.opacity(renderingMode == .fullColor ? 0.08 : 0.03),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        } else {
            Color.clear
        }
    }

    private var platformBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(.systemBackground)
        #endif
    }
}
