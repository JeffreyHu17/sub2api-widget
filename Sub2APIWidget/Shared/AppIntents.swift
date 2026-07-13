import AppIntents
import Foundation

struct InstanceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sub2API 实例")
    static let defaultQuery = InstanceQuery()

    var id: String
    var name: String
    var baseURL: URL

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(baseURL.absoluteString)")
    }
}

struct InstanceQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [InstanceEntity] {
        SnapshotStore.shared.loadInstances()
            .filter { identifiers.contains($0.id) }
            .map { InstanceEntity(id: $0.id, name: $0.name, baseURL: $0.baseURL) }
    }

    func suggestedEntities() async throws -> [InstanceEntity] {
        SnapshotStore.shared.loadInstances()
            .map { InstanceEntity(id: $0.id, name: $0.name, baseURL: $0.baseURL) }
    }

    func defaultResult() async -> InstanceEntity? {
        let instance = SnapshotStore.shared.loadInstances().first ?? .production
        return InstanceEntity(id: instance.id, name: instance.name, baseURL: instance.baseURL)
    }
}

struct AccountEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Sub2API 账号")
    static let defaultQuery = AccountQuery()

    var id: String
    var accountID: Int64
    var instanceID: String
    var name: String
    var platform: String
    var isSchedulable: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(platform.uppercased()) · \(isSchedulable ? "启用调度" : "未调度") · #\(accountID)")
    }
}

struct AccountQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [AccountEntity] {
        allEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [AccountEntity] {
        allEntities()
    }

    func defaultResult() async -> AccountEntity? {
        nil
    }

    private func allEntities() -> [AccountEntity] {
        SnapshotStore.shared.loadInstances().flatMap { instance in
            SnapshotStore.shared.loadSnapshot(instanceID: instance.id)?.monitoredAccounts.map { account in
                AccountEntity(
                    id: "\(instance.id):\(account.id)",
                    accountID: account.id,
                    instanceID: instance.id,
                    name: account.name,
                    platform: account.platform,
                    isSchedulable: account.eligibleForAutomaticMonitoring
                )
            } ?? []
        }
        .sorted {
            if $0.isSchedulable != $1.isSchedulable { return $0.isSchedulable }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

enum RefreshOption: Int, AppEnum {
    case five = 5
    case fifteen = 15
    case thirty = 30

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "刷新")
    static let caseDisplayRepresentations: [RefreshOption: DisplayRepresentation] = [
        .five: "5s",
        .fifteen: "15s",
        .thirty: "30s"
    ]
}

struct PlatformActivityWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Sub2API 平台活动"
    static let description = IntentDescription("选择实例和刷新频率。")

    @Parameter(title: "实例")
    var instance: InstanceEntity?

    @Parameter(title: "刷新", default: .five)
    var refresh: RefreshOption

    var displayConfig: WidgetDisplayConfig {
        let instanceID = instance?.id ?? AppConstants.defaultInstanceID
        return WidgetDisplayConfig(
            id: "\(instanceID)-platform-all",
            instanceID: instanceID,
            kind: .platformActivity,
            platformFilter: nil,
            refreshIntervalSec: refresh.rawValue,
            timeRange: .fiveMinutes,
            maxAccounts: 6
        )
    }
}

struct ServerHealthWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Sub2API 服务器状态"
    static let description = IntentDescription("选择实例和刷新频率。")

    @Parameter(title: "实例")
    var instance: InstanceEntity?

    @Parameter(title: "刷新", default: .fifteen)
    var refresh: RefreshOption

    var displayConfig: WidgetDisplayConfig {
        let instanceID = instance?.id ?? AppConstants.defaultInstanceID
        return WidgetDisplayConfig(
            id: "\(instanceID)-server",
            instanceID: instanceID,
            kind: .serverHealth,
            platformFilter: nil,
            refreshIntervalSec: refresh.rawValue,
            timeRange: .fiveMinutes,
            maxAccounts: 0
        )
    }
}

struct AccountMonitorWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Sub2API 账号监控"
    static let description = IntentDescription("不选账号时仅监控启用调度的账号；也可手动指定任意账号。")

    @Parameter(title: "实例")
    var instance: InstanceEntity?

    @Parameter(title: "账号")
    var accounts: [AccountEntity]?

    @Parameter(title: "刷新", default: .fifteen)
    var refresh: RefreshOption

    var displayConfig: WidgetDisplayConfig {
        let selectedInstanceID = accounts?.first?.instanceID
        let instanceID = selectedInstanceID ?? instance?.id ?? AppConstants.defaultInstanceID
        let selectedAccountIDs = accounts?
            .filter { $0.instanceID == instanceID }
            .map(\.accountID)
            .sorted()
        return WidgetDisplayConfig(
            id: "\(instanceID)-accounts-\(selectedAccountIDs?.map(String.init).joined(separator: "-") ?? "auto")",
            instanceID: instanceID,
            kind: .accountMonitor,
            platformFilter: nil,
            refreshIntervalSec: refresh.rawValue,
            timeRange: .fiveMinutes,
            maxAccounts: 6,
            accountID: selectedAccountIDs?.first,
            accountIDs: selectedAccountIDs
        )
    }
}
