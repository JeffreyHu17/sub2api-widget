import Foundation

final class SnapshotStore: @unchecked Sendable {
    static let shared = SnapshotStore()

    private let fileManager = FileManager.default

    private var containerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID)
    }

    private var instancesURL: URL? {
        containerURL?.appendingPathComponent("instances.json")
    }

    func loadInstances() -> [InstanceConfig] {
        guard let instancesURL,
              let data = try? Data(contentsOf: instancesURL),
              let instances = try? JSONDecoder.sub2api.decode([InstanceConfig].self, from: data),
              !instances.isEmpty
        else {
            return [.production]
        }
        return instances
    }

    func saveInstances(_ instances: [InstanceConfig]) throws {
        let containerURL = try requiredContainerURL()
        try ensureContainer(containerURL)
        let data = try JSONEncoder.sub2api.encode(instances)
        try data.write(to: containerURL.appendingPathComponent("instances.json"), options: [.atomic])
    }

    func snapshotURL(instanceID: String) -> URL? {
        containerURL?.appendingPathComponent("snapshot-\(instanceID).json")
    }

    func loadSnapshot(instanceID: String) -> MonitorSnapshot? {
        guard let url = snapshotURL(instanceID: instanceID) else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.sub2api.decode(MonitorSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: MonitorSnapshot) throws {
        let containerURL = try requiredContainerURL()
        try ensureContainer(containerURL)
        let data = try JSONEncoder.sub2api.encode(snapshot)
        let url = containerURL.appendingPathComponent("snapshot-\(snapshot.instanceID).json")
        try data.write(to: url, options: [.atomic])
    }

    func clearSnapshot(instanceID: String) throws {
        guard let url = snapshotURL(instanceID: instanceID), fileManager.fileExists(atPath: url.path) else {
            return
        }
        try fileManager.removeItem(at: url)
    }

    private func requiredContainerURL() throws -> URL {
        guard let containerURL else { throw SnapshotStoreError.appGroupUnavailable }
        return containerURL
    }

    private func ensureContainer(_ url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

enum SnapshotStoreError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        "App Group 不可用，请检查签名和 entitlement 配置"
    }
}
