import Foundation

final class SnapshotStore: @unchecked Sendable {
    static let shared = SnapshotStore()

    private let fileManager = FileManager.default

    private var containerURL: URL {
        if let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID) {
            return url
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sub2APIWidget", isDirectory: true)
    }

    private var instancesURL: URL {
        containerURL.appendingPathComponent("instances.json")
    }

    private var diagnosticsURL: URL {
        containerURL.appendingPathComponent("refresh-diagnostics.json")
    }

    func loadInstances() -> [InstanceConfig] {
        guard let data = try? Data(contentsOf: instancesURL),
              let instances = try? JSONDecoder.sub2api.decode([InstanceConfig].self, from: data),
              !instances.isEmpty
        else {
            return [.production]
        }
        return instances
    }

    func saveInstances(_ instances: [InstanceConfig]) throws {
        try ensureContainer()
        let data = try JSONEncoder.sub2api.encode(instances)
        try data.write(to: instancesURL, options: [.atomic])
    }

    func snapshotURL(instanceID: String) -> URL {
        containerURL.appendingPathComponent("snapshot-\(instanceID).json")
    }

    func loadSnapshot(instanceID: String) -> MonitorSnapshot? {
        let url = snapshotURL(instanceID: instanceID)
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder.sub2api.decode(MonitorSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: MonitorSnapshot) throws {
        try ensureContainer()
        let data = try JSONEncoder.sub2api.encode(snapshot)
        try data.write(to: snapshotURL(instanceID: snapshot.instanceID), options: [.atomic])
    }

    func updateWidgetRenderTime(instanceID: String, date: Date = Date()) {
        guard var snapshot = loadSnapshot(instanceID: instanceID) else {
            return
        }
        snapshot.diagnostics.lastWidgetRenderAt = date
        try? saveSnapshot(snapshot)
    }

    private func ensureContainer() throws {
        try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)
    }
}
