import Foundation

final class SnapshotStore: @unchecked Sendable {
    static let shared = SnapshotStore()

    private let fileManager = FileManager.default

    /// Set when instances.json exists but could not be decoded. Callers surface this
    /// so a corrupted config never silently reverts the user to the default instance.
    private let degradationLock = NSLock()
    private var _degradationNotice: String?
    private let cacheLock = NSLock()
    var degradationNotice: String? {
        degradationLock.lock()
        defer { degradationLock.unlock() }
        return _degradationNotice
    }

    private func recordDegradation(_ notice: String) {
        degradationLock.lock()
        defer { degradationLock.unlock() }
        _degradationNotice = notice
    }

    private func clearDegradation() {
        degradationLock.lock()
        defer { degradationLock.unlock() }
        _degradationNotice = nil
    }

    private var containerURL: URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupID)
    }

    private var instancesURL: URL? {
        containerURL?.appendingPathComponent("instances.json")
    }

    func loadInstances() -> [InstanceConfig] {
        guard let instancesURL else {
            clearDegradation()
            return [.production]
        }
        guard let data = try? Data(contentsOf: instancesURL) else {
            // No file yet — first launch, nothing to report.
            clearDegradation()
            return [.production]
        }
        do {
            let instances = try JSONDecoder.sub2api.decode([InstanceConfig].self, from: data)
            clearDegradation()
            return instances.isEmpty ? [.production] : instances
        } catch {
            recordDegradation("本地实例配置无法解析，已回退到默认实例：\(error.localizedDescription)")
            return [.production]
        }
    }

    func saveInstances(_ instances: [InstanceConfig]) throws {
        let containerURL = try requiredContainerURL()
        try ensureContainer(containerURL)
        let data = try JSONEncoder.sub2api.encode(instances)
        try data.write(to: containerURL.appendingPathComponent("instances.json"), options: [.atomic])
        clearDegradation()
    }

    func snapshotURL(instanceID: String) -> URL? {
        containerURL?.appendingPathComponent("snapshot-\(instanceID).json")
    }

    /// Decoded snapshots are cached in memory because callers read them from SwiftUI
    /// view bodies: decoding a 226-account snapshot off disk measured ~550ms on the
    /// main thread, which froze the UI on every render.
    private var snapshotCache: [String: MonitorSnapshot] = [:]

    func loadSnapshot(instanceID: String) -> MonitorSnapshot? {
        cacheLock.lock()
        if let cached = snapshotCache[instanceID] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        guard let url = snapshotURL(instanceID: instanceID) else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let snapshot = try? JSONDecoder.sub2api.decode(MonitorSnapshot.self, from: data) else {
            return nil
        }

        cacheLock.lock()
        snapshotCache[instanceID] = snapshot
        cacheLock.unlock()
        return snapshot
    }

    func saveSnapshot(_ snapshot: MonitorSnapshot) throws {
        let containerURL = try requiredContainerURL()
        try ensureContainer(containerURL)
        let data = try JSONEncoder.sub2api.encode(snapshot)
        let url = containerURL.appendingPathComponent("snapshot-\(snapshot.instanceID).json")
        try data.write(to: url, options: [.atomic])

        cacheLock.lock()
        snapshotCache[snapshot.instanceID] = snapshot
        cacheLock.unlock()
    }

    func clearSnapshot(instanceID: String) throws {
        cacheLock.lock()
        snapshotCache.removeValue(forKey: instanceID)
        cacheLock.unlock()

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
