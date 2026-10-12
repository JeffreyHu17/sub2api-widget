import Foundation
import ServiceManagement
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

    @Published var selectedRefresh: RefreshInterval = BackgroundPreferences.refreshInterval {
        didSet {
            BackgroundPreferences.refreshInterval = selectedRefresh
            schedulePollingRestartIfNeeded()
        }
    }

    @Published private(set) var backgroundServiceDesired = BackgroundPreferences.backgroundServiceDesired
    @Published private(set) var backgroundServiceStatus = "正在检查"
    @Published private(set) var backgroundServiceNeedsApproval = false

    let poller = MonitorPoller()
    private let snapshotStore = SnapshotStore.shared
    private let backgroundService = SMAppService.loginItem(identifier: AppConstants.agentBundleID)
    private var pollingRestartTask: Task<Void, Never>?
    private var backgroundServiceTransitionTask: Task<Void, Never>?

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
        refreshBackgroundServiceStatus()
        reconcileBackgroundService()
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
            BackgroundPreferences.monitoringEnabled = true
            statusMessage = "登录已保存"
            showingLogin = false
            reconcileBackgroundService()
            startPollingIfAuthenticated(reason: "登录成功，自动轮询已启动")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func signOut() async {
        pollingRestartTask?.cancel()
        poller.stop()
        BackgroundPreferences.monitoringEnabled = false
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
        BackgroundPreferences.monitoringEnabled = false
        poller.stop()
        statusMessage = "轮询已停止"
    }

    func setBackgroundServiceEnabled(_ enabled: Bool) {
        backgroundServiceDesired = enabled
        BackgroundPreferences.backgroundServiceDesired = enabled

        if enabled {
            reconcileBackgroundService()
        } else {
            unregisterBackgroundService()
        }
    }

    func openBackgroundServiceSettings() {
        SMAppService.openSystemSettingsLoginItems()
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
        BackgroundPreferences.monitoringEnabled = true
        poller.start(instance: instance, config: displayConfig)
        statusMessage = reason
    }

    private func handleAuthenticationRequired() {
        BackgroundPreferences.monitoringEnabled = false
        tokens = nil
        cachedSnapshot = nil
        statusMessage = "登录已失效，轮询已停止，请重新登录"
    }

    // MARK: - Background login item

    /// Keeps the login item registered whenever the user wants background
    /// polling on. macOS drops the registration across app updates, so the
    /// fingerprint check re-registers when the embedded helper changes.
    private func reconcileBackgroundService() {
        guard backgroundServiceDesired else {
            unregisterBackgroundService()
            return
        }

        switch backgroundService.status {
        case .enabled:
            if BackgroundPreferences.registeredHelperFingerprint == currentHelperFingerprint {
                backgroundServiceStatus = "后台更新已启用"
                backgroundServiceNeedsApproval = false
            } else {
                refreshBackgroundServiceRegistration()
            }
        case .requiresApproval:
            backgroundServiceStatus = "需要系统批准"
            backgroundServiceNeedsApproval = true
        case .notRegistered, .notFound:
            do {
                try backgroundService.register()
                BackgroundPreferences.registeredHelperFingerprint = currentHelperFingerprint
                refreshBackgroundServiceStatus()
            } catch {
                backgroundServiceStatus = "启用失败：\(error.localizedDescription)"
                backgroundServiceNeedsApproval = backgroundService.status == .requiresApproval
            }
        @unknown default:
            backgroundServiceStatus = "后台状态未知"
            backgroundServiceNeedsApproval = false
        }
    }

    private func unregisterBackgroundService() {
        guard backgroundService.status != .notRegistered,
              backgroundService.status != .notFound
        else {
            BackgroundPreferences.registeredHelperFingerprint = nil
            refreshBackgroundServiceStatus()
            return
        }

        do {
            try backgroundService.unregister()
            BackgroundPreferences.registeredHelperFingerprint = nil
            refreshBackgroundServiceStatus()
        } catch {
            backgroundServiceStatus = "停用失败：\(error.localizedDescription)"
        }
    }

    private func refreshBackgroundServiceRegistration() {
        backgroundServiceTransitionTask?.cancel()
        backgroundServiceTransitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try self.backgroundService.unregister()
                try self.backgroundService.register()
                BackgroundPreferences.registeredHelperFingerprint = self.currentHelperFingerprint
            } catch {
                self.backgroundServiceStatus = "重新注册失败：\(error.localizedDescription)"
            }
            self.refreshBackgroundServiceStatus()
        }
    }

    private func refreshBackgroundServiceStatus() {
        switch backgroundService.status {
        case .enabled:
            backgroundServiceStatus = "后台更新已启用"
            backgroundServiceNeedsApproval = false
        case .requiresApproval:
            backgroundServiceStatus = "需要系统批准"
            backgroundServiceNeedsApproval = true
        case .notRegistered:
            backgroundServiceStatus = backgroundServiceDesired ? "后台更新未启用" : "后台更新已关闭"
            backgroundServiceNeedsApproval = false
        case .notFound:
            backgroundServiceStatus = "未找到后台组件"
            backgroundServiceNeedsApproval = false
        @unknown default:
            backgroundServiceStatus = "后台状态未知"
            backgroundServiceNeedsApproval = false
        }
    }

    /// Identity of the embedded helper. When this changes the old registration
    /// points at a stale binary, so the login item has to be re-registered.
    private var currentHelperFingerprint: String {
        let helperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/Sub2APIWidgetAgent.app")
        let attributes = try? FileManager.default.attributesOfItem(atPath: helperURL.path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(helperURL.standardizedFileURL.path)|\(size)|\(modifiedAt)"
    }
}
