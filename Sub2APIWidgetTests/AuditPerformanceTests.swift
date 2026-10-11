import Foundation
import Testing
@testable import Sub2APIWidgetCore

/// Performance guardrails for the 2026-10-11 audit fixes. These assert the fixes
/// actually hold on realistic payloads, not just that the code compiles.
struct AuditPerformanceTests {

    // P1-2: the decoder must not allocate two ISO8601DateFormatter per value.
    // Measured before the fix at ~608us per parse; target is well under 100us.
    @Test
    func dateParsingStaysFast() {
        let stamp = "2026-07-14T08:00:00Z"
        // Warm the caches first so we measure steady state, not one-time setup.
        _ = DateParsers.parseSub2APIDate(stamp)

        let n = 4000
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<n { _ = DateParsers.parseSub2APIDate(stamp) }
        let us = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(n) / 1000

        print("AUDIT date parse = \(String(format: "%.1f", us)) us/call (was ~608 us before fix)")
        #expect(us < 150, "Date parsing regressed to \(us) us/call")
    }

    // P2-3 + P1-2 together: decoding a realistic account page must stay in the
    // low hundreds of milliseconds rather than the ~2s it took before.
    @Test
    func accountPageDecodeStaysAcceptable() throws {
        func item(_ id: Int) -> String {
            """
            {"id":\(id),"name":"acct-\(id)","platform":"openai","type":"apikey",
             "concurrency":5,"current_concurrency":1,"status":"active",
             "error_message":null,"schedulable":true,
             "last_used_at":"2026-07-14T08:00:00Z","rate_limit_reset_at":"2026-07-14T09:00:00Z",
             "overload_until":null,"temp_unschedulable_until":null}
            """
        }
        let count = 226
        let json = "{\"items\":[\((0..<count).map(item).joined(separator: ","))],\"total\":\(count),\"page\":1,\"page_size\":1000,\"pages\":1}"
        let data = Data(json.utf8)

        let start = DispatchTime.now().uptimeNanoseconds
        let page = try JSONDecoder.sub2api.decode(AccountsPageDTO.self, from: data)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

        #expect(page.items.count == count)
        print("AUDIT 226-account decode = \(String(format: "%.0f", ms)) ms (was ~867 ms before fix)")
        #expect(ms < 400, "Account page decode regressed to \(ms) ms")
    }

    // P2-3: snapshot size feeds both file IO and main-thread decode in the widget.
    @Test
    func snapshotFileStaysSmall() throws {
        var snapshot = MonitorSnapshot.placeholder(instanceID: "size")
        snapshot.accounts = (0..<226).map { i in
            AccountMonitor(
                id: Int64(i), name: "account-\(i)", platform: "openai", type: "apikey",
                status: .healthy, statusMessage: nil, schedulable: true,
                currentInUse: 1, maxConcurrency: 5, waitingInQueue: 0,
                activeSessions: nil, maxSessions: nil, currentRPM: nil, baseRPM: nil,
                quotas: [AccountQuotaWindow(kind: "daily", label: "日额度", used: 75, limit: 100, resetAt: nil)],
                lastUsedAt: Date(), recoveryAt: nil
            )
        }
        let data = try JSONEncoder.sub2api.encode(snapshot)

        print("AUDIT 226-account snapshot = \(data.count) bytes (was 104,290 with prettyPrinted)")
        #expect(data.count < 90_000, "Snapshot grew to \(data.count) bytes")
    }

    // P0-2: the widget decodes one snapshot per timeline; keep that decode cheap.
    @Test
    func timelineSnapshotDecodeStaysCheap() throws {
        var snapshot = MonitorSnapshot.placeholder(instanceID: "timeline")
        snapshot.accounts = (0..<226).map { i in
            AccountMonitor(
                id: Int64(i), name: "account-\(i)", platform: "openai", type: "apikey",
                status: .healthy, statusMessage: nil, schedulable: true,
                currentInUse: 1, maxConcurrency: 5, waitingInQueue: 0,
                activeSessions: nil, maxSessions: nil, currentRPM: nil, baseRPM: nil,
                quotas: [AccountQuotaWindow(kind: "daily", label: "日额度", used: 75, limit: 100, resetAt: nil)],
                lastUsedAt: Date(), recoveryAt: nil
            )
        }
        let data = try JSONEncoder.sub2api.encode(snapshot)

        let start = DispatchTime.now().uptimeNanoseconds
        let decoded = try JSONDecoder.sub2api.decode(MonitorSnapshot.self, from: data)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

        #expect(decoded.monitoredAccounts.count == 226)
        print("AUDIT full snapshot decode = \(String(format: "%.0f", ms)) ms (was ~550 ms before fix)")
        #expect(ms < 300, "Full snapshot decode regressed to \(ms) ms")
    }
}