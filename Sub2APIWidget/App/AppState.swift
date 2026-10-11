import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppState: ObservableObject {
    @Published var instance: InstanceConfig = .production
    @Published var tokens: AuthTokenBundle?
    @Published var statusMessage = "未连接"
    @Published var showingLogin = false

    /// Last snapshot read from disk. Held in `@Published` state so SwiftUI views can
    /// read it without performing file IO inside their `body`.
    @Published private(set) var cachedSnapshot: MonitorSnapshot?

    @Published var selectedRefresh: RefreshInterval = .five {
        didSet { schedulePollingRestartIfNeeded() }
    }

    let poller = MonitorPoller()
    private let snapshotStore = SnapshotStore.shared
    private var pollingRestartTask: Task<Void, Never>?

    init() {
        poller.onAuthenticationRequired = { [weak self] in
            self?.handleAuthenticationRequired()
        }
        load()
    }

    func load() {
        instance = snapshotStore.loadInstances().first ?? .production
        cachedSnapshot = snapshotStore.loadSnapshot(instanceID: instance.id)
        tokens = try? KeychainStore.loadTokens(for: instance)
        if let notice = snapshotStore.degradationNotice {
            statusMessage = notice
        } else {
            statusMessage = tokens == nil ? "请先登录 Sub2API" : "已读取本地登录凭据"
        }
        startPollingIfAuthenticated(reason: "自动轮询已启动")
    }

    func saveInstance(name: String, baseURLText: String) {
        guard let url = URL(string: baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.isAllowedSub2APIBaseURL
        else {
            statusMessage = "实例地址无效：仅允许 HTTPS，localhost 可使用 HTTP"
            return
        }

        let originChanged = instance.baseURL.normalizedOrigin != url.normalizedOrigin
        if originChanged {
            pollingRestartTask?.cancel()
            poller.stop()
            KeychainStore.deleteTokens(instanceID: instance.id)
            try? snapshotStore.clearSnapshot(instanceID: instance.id)
            cachedSnapshot = nil
            tokens = nil
        }

        instance.name = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? AppConstants.defaultInstanceName
        instance.baseURL = url
        do {
            try snapshotStore.saveInstances([instance])
            if originChanged {
                statusMessage = "实例地址已变更，请重新登录"
                WidgetCenter.shared.reloadAllTimelines()
            } else {
                cachedSnapshot = snapshotStore.loadSnapshot(instanceID: instance.id)
                statusMessage = "实例已保存"
                schedulePollingRestartIfNeeded()
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func handleLoginTokens(_ tokenBundle: AuthTokenBundle) {
        do {
            try KeychainStore.saveTokens(tokenBundle, for: instance)
            tokens = try KeychainStore.loadTokens(for: instance)
            statusMessage = "登录已保存"
            showingLogin = false
            startPollingIfAuthenticated(reason: "登录成功，自动轮询已启动")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func signOut() async {
        pollingRestartTask?.cancel()
        poller.stop()
        KeychainStore.deleteTokens(instanceID: instance.id)
        try? snapshotStore.clearSnapshot(instanceID: instance.id)
        let unavailable = MonitorSnapshot.unavailable(instanceID: instance.id, reason: "已退出登录")
        try? snapshotStore.saveSnapshot(unavailable)
        cachedSnapshot = unavailable
        tokens = nil
        await WebSessionStore.clearAllData()
        statusMessage = "已退出登录并清除本地会话"
        WidgetCenter.shared.reloadAllTimelines()
    }

    func startPolling() {
        guard tokens != nil else {
            statusMessage = "请先登录 Sub2API"
            showingLogin = true
            return
        }
        startPollingIfAuthenticated(reason: "轮询已启动：\(selectedRefresh.displayName)")
    }

    func stopPolling() {
        poller.stop()
        statusMessage = "轮询已停止"
    }

    func pollNow() async {
        await poller.pollOnce(instance: instance, config: displayConfig)
        cachedSnapshot = poller.latestSnapshot ?? cachedSnapshot
        if let error = poller.lastError {
            statusMessage = SafeMessage.sanitize(error)
        } else {
            statusMessage = "快照已更新"
        }
    }

    var displayConfig: WidgetDisplayConfig {
        WidgetDisplayConfig(
            id: "\(instance.id)-platform-all",
            instanceID: instance.id,
            kind: .platformActivity,
            platformFilter: nil,
            refreshIntervalSec: selectedRefresh.rawValue,
            timeRange: .fiveMinutes,
            maxAccounts: 6
        )
    }

    private func schedulePollingRestartIfNeeded() {
        guard poller.isRunning else { return }
        pollingRestartTask?.cancel()
        pollingRestartTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, self.poller.isRunning else { return }
            self.poller.start(instance: self.instance, config: self.displayConfig)
            self.statusMessage = "轮询已更新：\(self.selectedRefresh.displayName)"
        }
    }

    private func startPollingIfAuthenticated(reason: String) {
        guard tokens != nil else { return }
        poller.start(instance: instance, config: displayConfig)
        statusMessage = reason
    }

    private func handleAuthenticationRequired() {
        tokens = nil
        cachedSnapshot = nil
        statusMessage = "登录已失效，轮询已停止，请重新登录"
    }
}
