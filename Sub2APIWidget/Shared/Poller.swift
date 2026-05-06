import Foundation
import WidgetKit

@MainActor
final class MonitorPoller: ObservableObject {
    @Published private(set) var latestSnapshot: MonitorSnapshot?
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var nextFetchAt: Date?

    private var task: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    private let snapshotStore: SnapshotStore

    init(snapshotStore: SnapshotStore = .shared) {
        self.snapshotStore = snapshotStore
        self.latestSnapshot = snapshotStore.loadSnapshot(instanceID: AppConstants.defaultInstanceID)
    }

    func start(instance: InstanceConfig, config: WidgetDisplayConfig) {
        stop()
        isRunning = true
        lastError = nil
        nextFetchAt = Date()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Keep Sub2API monitoring snapshots fresh for widgets"
        )
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOnce(instance: instance, config: config)
                let delay = UInt64(max(config.refreshIntervalSec, 5)) * 1_000_000_000
                self.nextFetchAt = Date().addingTimeInterval(TimeInterval(max(config.refreshIntervalSec, 5)))
                self.persistNextFetchAt(instanceID: instance.id)
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        isRunning = false
        nextFetchAt = nil
    }

    func pollOnce(instance: InstanceConfig, config: WidgetDisplayConfig) async {
        let client = Sub2APIClient(instance: instance)
        do {
            guard let tokens = try KeychainStore.loadTokens(instanceID: instance.id) else {
                lastError = Sub2APIError.missingToken.localizedDescription
                latestSnapshot = snapshotWithError(instanceID: instance.id, config: config, message: lastError)
                if let latestSnapshot {
                    try? snapshotStore.saveSnapshot(latestSnapshot)
                }
                return
            }

            var snapshot = try await client.fetchSnapshot(tokens: tokens, config: config)
            snapshot.diagnostics.lastSnapshotWriteAt = Date()
            snapshot.diagnostics.nextFetchAt = Date().addingTimeInterval(TimeInterval(max(config.refreshIntervalSec, 5)))
            try snapshotStore.saveSnapshot(snapshot)
            snapshot.diagnostics.lastWidgetReloadRequestAt = Date()
            try snapshotStore.saveSnapshot(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
            latestSnapshot = snapshot
            lastError = nil
            nextFetchAt = snapshot.diagnostics.nextFetchAt
        } catch {
            lastError = error.localizedDescription
            latestSnapshot = snapshotWithError(instanceID: instance.id, config: config, message: lastError)
            if let latestSnapshot {
                try? snapshotStore.saveSnapshot(latestSnapshot)
            }
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func snapshotWithError(instanceID: String, config: WidgetDisplayConfig, message: String?) -> MonitorSnapshot {
        var snapshot = snapshotStore.loadSnapshot(instanceID: instanceID) ?? .placeholder(instanceID: instanceID)
        snapshot.expiresAt = Date()
        snapshot.staleReason = message ?? "Refresh failed"
        snapshot.diagnostics.lastError = message
        snapshot.diagnostics.nextFetchAt = Date().addingTimeInterval(TimeInterval(max(config.refreshIntervalSec, 5)))
        return snapshot
    }

    private func persistNextFetchAt(instanceID: String) {
        guard var snapshot = snapshotStore.loadSnapshot(instanceID: instanceID) else {
            return
        }
        snapshot.diagnostics.nextFetchAt = nextFetchAt
        try? snapshotStore.saveSnapshot(snapshot)
    }
}
