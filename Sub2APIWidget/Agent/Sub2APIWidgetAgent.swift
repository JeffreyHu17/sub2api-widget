import AppKit
import Foundation

@main
@MainActor
final class Sub2APIWidgetAgent: NSObject, NSApplicationDelegate {
    private let controller = BackgroundPollingController()

    static func main() {
        let application = NSApplication.shared
        let delegate = Sub2APIWidgetAgent()
        application.delegate = delegate
        application.setActivationPolicy(.prohibited)
        application.run()
        withExtendedLifetime(delegate) {}
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

@MainActor
private final class BackgroundPollingController {
    private let poller = MonitorPoller()
    private var loopTask: Task<Void, Never>?
    private var activity: NSObjectProtocol?

    func start() {
        guard loopTask == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: .background,
            reason: "Keep Sub2API widget snapshots current"
        )
        loopTask = Task { [weak self] in
            var nextPollAt = Date()

            while !Task.isCancelled {
                guard let self else { return }

                if self.isMainApplicationRunning || !BackgroundPreferences.monitoringEnabled {
                    nextPollAt = Date()
                } else if Date() >= nextPollAt {
                    let instance = SnapshotStore.shared.loadInstances().first ?? .production
                    if (try? KeychainStore.loadTokens(for: instance)) != nil {
                        let config = BackgroundPreferences.displayConfig(for: instance)
                        await self.poller.pollOnce(instance: instance, config: config)
                        nextPollAt = Date().addingTimeInterval(
                            TimeInterval(BackgroundPreferences.refreshInterval.rawValue)
                        )
                    } else {
                        nextPollAt = Date().addingTimeInterval(5)
                    }
                }

                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        poller.stop()
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    private var isMainApplicationRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: AppConstants.bundleID
        ).isEmpty
    }
}
