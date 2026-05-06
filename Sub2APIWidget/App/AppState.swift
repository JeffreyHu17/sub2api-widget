import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class AppState: ObservableObject {
    @Published var instance: InstanceConfig = .production
    @Published var tokens: AuthTokenBundle?
    @Published var statusMessage = "未连接"
    @Published var showingLogin = false

    @Published var selectedRefresh: RefreshInterval = .five {
        didSet { schedulePollingRestartIfNeeded() }
    }

    let poller = MonitorPoller()
    private let snapshotStore = SnapshotStore.shared
    private var pollingRestartTask: Task<Void, Never>?

    init() {
        load()
    }

    func load() {
        instance = snapshotStore.loadInstances().first ?? .production
        tokens = try? KeychainStore.loadTokens(instanceID: instance.id)
        statusMessage = tokens == nil ? "请先登录 Sub2API" : "已读取本地登录凭据"
        if snapshotStore.loadSnapshot(instanceID: instance.id) == nil {
            try? snapshotStore.saveSnapshot(.placeholder(instanceID: instance.id))
        }
        startPollingIfAuthenticated(reason: "自动轮询已启动")
    }

    func saveInstance(name: String, baseURLText: String) {
        guard let url = URL(string: baseURLText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme,
              ["https", "http"].contains(scheme)
        else {
            statusMessage = "实例地址无效"
            return
        }

        instance.name = name.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? AppConstants.defaultInstanceName
        instance.baseURL = url
        do {
            try snapshotStore.saveInstances([instance])
            statusMessage = "实例已保存"
            schedulePollingRestartIfNeeded()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func handleLoginTokens(_ tokenBundle: AuthTokenBundle) {
        do {
            try KeychainStore.saveTokens(tokenBundle, instanceID: instance.id)
            tokens = tokenBundle
            statusMessage = "登录已保存"
            showingLogin = false
            startPollingIfAuthenticated(reason: "登录成功，自动轮询已启动")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func signOut() {
        KeychainStore.deleteTokens(instanceID: instance.id)
        tokens = nil
        poller.stop()
        statusMessage = "已清除本地登录凭据"
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
        if let error = poller.lastError {
            statusMessage = error
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
}
