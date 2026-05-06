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
            timeRange: .oneHour,
            maxAccounts: 0
        )
    }
}
