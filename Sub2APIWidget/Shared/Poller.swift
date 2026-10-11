import Foundation
import WidgetKit

@MainActor
final class MonitorPoller: ObservableObject {
    @Published private(set) var latestSnapshot: MonitorSnapshot?
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?
    @Published private(set) var nextFetchAt: Date?

    var onAuthenticationRequired: (() -> Void)?

    private var loopTask: Task<Void, Never>?
    private var activePollTask: Task<Void, Never>?
    private var activeRequestID: UUID?
    private var generation: UInt64 = 0
    private var lastWidgetReloadAt: Date?
    private var consecutiveFailures = 0
    private let snapshotStore: SnapshotStore

    init(snapshotStore: SnapshotStore = .shared) {
        self.snapshotStore = snapshotStore
        latestSnapshot = snapshotStore.loadSnapshot(instanceID: AppConstants.defaultInstanceID)
    }

    func start(instance: InstanceConfig, config: WidgetDisplayConfig) {
        stop()
        isRunning = true
        lastError = nil
        nextFetchAt = Date()
        consecutiveFailures = 0
        let loopGeneration = generation

        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.generation == loopGeneration else { return }
                await self.pollOnce(instance: instance, config: config)
                guard !Task.isCancelled, self.generation == loopGeneration, self.isRunning else { return }

                let interval = self.currentInterval(for: config)
                self.nextFetchAt = Date().addingTimeInterval(interval)
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        generation &+= 1
        loopTask?.cancel()
        loopTask = nil
        activePollTask?.cancel()
        activePollTask = nil
        activeRequestID = nil
        isRunning = false
        nextFetchAt = nil
    }

    func pollOnce(instance: InstanceConfig, config: WidgetDisplayConfig) async {
        activePollTask?.cancel()
        let requestID = UUID()
        let requestGeneration = generation
        activeRequestID = requestID

        let task = Task { [weak self] () -> Void in
            guard let self else { return }
            await self.performPoll(
                instance: instance,
                config: config,
                requestID: requestID,
                requestGeneration: requestGeneration
            )
        }
        activePollTask = task
        await task.value

        if activeRequestID == requestID {
            activePollTask = nil
            activeRequestID = nil
        }
    }

    private func performPoll(
        instance: InstanceConfig,
        config: WidgetDisplayConfig,
        requestID: UUID,
        requestGeneration: UInt64
    ) async {
        let client = Sub2APIClient(instance: instance)
        do {
            guard let tokens = try KeychainStore.loadTokens(for: instance) else {
                handleSessionExpired(instance: instance, reason: Sub2APIError.missingToken.localizedDescription)
                return
            }

            var snapshot = try await client.fetchSnapshot(tokens: tokens, config: config)
            try Task.checkCancellation()
            guard isCurrent(requestID: requestID, generation: requestGeneration) else { return }

            let now = Date()
            snapshot.diagnostics.lastSnapshotWriteAt = now
            snapshot.diagnostics.nextFetchAt = now.addingTimeInterval(TimeInterval(max(config.refreshIntervalSec, 5)))

            let shouldReloadWidget = lastWidgetReloadAt.map { now.timeIntervalSince($0) >= 15 } ?? true
            if shouldReloadWidget {
                snapshot.diagnostics.lastWidgetReloadRequestAt = now
                lastWidgetReloadAt = now
            }

            try snapshotStore.saveSnapshot(snapshot)
            guard isCurrent(requestID: requestID, generation: requestGeneration) else { return }

            latestSnapshot = snapshot
            lastError = snapshot.staleReason
            nextFetchAt = snapshot.diagnostics.nextFetchAt
            consecutiveFailures = 0
            if shouldReloadWidget {
                WidgetCenter.shared.reloadAllTimelines()
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch let error as Sub2APIError {
            guard isCurrent(requestID: requestID, generation: requestGeneration) else { return }
            switch error {
            case .unauthorized, .sessionExpired:
                // The refresh path inside the client already failed, so the session
                // is genuinely dead. Stop and ask for a fresh login.
                handleSessionExpired(instance: instance, reason: error.errorDescription)
            default:
                // Transport / server faults are treated as transient: record them and
                // let the loop retry with backoff instead of destroying credentials.
                recordFailure(snapshotStore: snapshotStore, instance: instance, config: config, error: error)
            }
        } catch {
            guard isCurrent(requestID: requestID, generation: requestGeneration) else { return }
            recordFailure(snapshotStore: snapshotStore, instance: instance, config: config, error: error)
        }
    }

    private func recordFailure(
        snapshotStore: SnapshotStore,
        instance: InstanceConfig,
        config: WidgetDisplayConfig,
        error: Error
    ) {
        consecutiveFailures += 1
        let message = SafeMessage.sanitize(error)
        lastError = message

        let snapshot = snapshotWithError(
            instanceID: instance.id,
            config: config,
            message: message
        )
        latestSnapshot = snapshot
        try? snapshotStore.saveSnapshot(snapshot)

        let now = Date()
        if lastWidgetReloadAt.map({ now.timeIntervalSince($0) >= 15 }) ?? true {
            lastWidgetReloadAt = now
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Backoff for transient failures so a down server is not hammered every 5s.
    func currentInterval(for config: WidgetDisplayConfig) -> TimeInterval {
        let base = TimeInterval(max(config.refreshIntervalSec, 5))
        guard consecutiveFailures > 0 else { return base }
        let multiplier = min(pow(2.0, Double(min(consecutiveFailures - 1, 5))), 16.0)
        return min(base * multiplier, 300)
    }

    private func isCurrent(requestID: UUID, generation requestGeneration: UInt64) -> Bool {
        !Task.isCancelled && activeRequestID == requestID && generation == requestGeneration
    }

    private func handleSessionExpired(instance: InstanceConfig, reason: String?) {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
        nextFetchAt = nil
        lastError = reason
        KeychainStore.deleteTokens(instanceID: instance.id)

        let snapshot = MonitorSnapshot.unavailable(
            instanceID: instance.id,
            reason: SafeMessage.sanitize(reason ?? "登录已失效")
        )
        latestSnapshot = snapshot
        try? snapshotStore.saveSnapshot(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        onAuthenticationRequired?()
    }

    private func snapshotWithError(
        instanceID: String,
        config: WidgetDisplayConfig,
        message: String
    ) -> MonitorSnapshot {
        var snapshot = snapshotStore.loadSnapshot(instanceID: instanceID)
            ?? .unavailable(
                instanceID: instanceID,
                reason: message,
                authState: AuthState(isAuthenticated: true, userEmail: nil, tokenExpiresAt: nil)
            )
        snapshot.expiresAt = Date()
        snapshot.staleReason = message
        snapshot.dataState = .unavailable
        snapshot.diagnostics.lastError = message
        snapshot.diagnostics.nextFetchAt = Date().addingTimeInterval(TimeInterval(max(config.refreshIntervalSec, 5)))
        return snapshot
    }
}
