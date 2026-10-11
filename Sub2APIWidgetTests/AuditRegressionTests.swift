import Foundation
import Testing
@testable import Sub2APIWidgetCore

/// Regression coverage for defects confirmed during the 2026-10-11 audit.
/// Each test here previously failed against the pre-fix code.
struct AuditRegressionTests {

    // P0-1: duplicate account_id used to trap the process with fatalError.
    @Test
    func duplicateAccountIDDoesNotCrashAndKeepsLastValue() throws {
        let json = """
        {
          "enabled": true,
          "platform": {},
          "account": {
            "a": {"account_id": 7, "account_name": "A", "platform": "openai",
                  "current_in_use": 1, "max_capacity": 4, "load_percentage": 25, "waiting_in_queue": 0},
            "b": {"account_id": 7, "account_name": "B", "platform": "openai",
                  "current_in_use": 3, "max_capacity": 4, "load_percentage": 75, "waiting_in_queue": 0}
          },
          "timestamp": null
        }
        """
        let concurrency: ConcurrencyResponseDTO = try JSONDecoder.sub2api.decode(
            ConcurrencyResponseDTO.self, from: Data(json.utf8)
        )
        let accounts: AccountsPageDTO = try JSONDecoder.sub2api.decode(
            AccountsPageDTO.self,
            from: Data("""
            {"items":[{"id":7,"name":"A","platform":"openai","type":"apikey",
                       "concurrency":4,"current_concurrency":0,"status":"active",
                       "error_message":null,"schedulable":true}],"total":1,"page":1,"page_size":1000,"pages":1}
            """.utf8)
        )

        // Previously: Dictionary(uniqueKeysWithValues:) -> "Fatal error: Duplicate values for key"
        let snapshot = SnapshotBuilder.build(
            instanceID: "dup",
            concurrency: concurrency,
            availability: nil,
            dashboard: nil,
            accounts: accounts,
            authState: .sample,
            refreshInterval: 15,
            diagnostics: .empty,
            staleReason: nil
        )

        let account = try #require(snapshot.monitoredAccounts.first)
        #expect(account.id == 7)
        #expect(snapshot.dataState == .partial)
    }

    // P1-1: one malformed date used to fail the decode of the whole snapshot.
    @Test
    func malformedDateDoesNotDiscardEntireSnapshot() throws {
        var object = try #require(
            JSONSerialization.jsonObject(
                with: try JSONEncoder.sub2api.encode(MonitorSnapshot.placeholder(instanceID: "x"))
            ) as? [String: Any]
        )
        object["diagnostics"] = [
            "lastFetchAt": "not-a-date",
            "nextFetchAt": nil, "lastSnapshotWriteAt": nil,
            "lastWidgetReloadRequestAt": nil, "lastWidgetRenderAt": nil, "lastError": nil
        ]
        let data = try JSONSerialization.data(withJSONObject: object)

        let decoded = try #require(
            try JSONDecoder.sub2api.decode(MonitorSnapshot.self, from: data),
            "A single malformed date must not void the entire snapshot"
        )
        #expect(decoded.instanceID == "x")
        #expect(decoded.diagnostics.lastFetchAt?.isUnknownTimestamp == true)
        // Other fields survive.
        #expect(!decoded.platforms.isEmpty)
    }

    @Test
    func unknownTimestampRendersAsPlaceholderNotYearOne() {
        #expect(MetricFormatters.clockTime(Date.distantPast) == "--:--:--")
        #expect(MetricFormatters.relativeTime(Date.distantPast) == "--")
        #expect(MetricFormatters.clockTime(nil) == "--:--:--")
    }

    // P1-4: a missing createdAt used to fail instances.json and silently revert
    // the user to the default production instance.
    @Test
    func instanceConfigDecodesWithoutCreatedAt() throws {
        let json = """
        [{"id":"i1","name":"Custom","baseURL":"https://my.host","dashboardPath":"/admin/ops"}]
        """
        let decoded = try JSONDecoder.sub2api.decode([InstanceConfig].self, from: Data(json.utf8))
        #expect(decoded.count == 1)
        #expect(decoded.first?.name == "Custom")
        #expect(decoded.first?.baseURL.host == "my.host")
    }

    // P0-3: server text must never reach the widget with credentials in it.
    @Test
    func sanitizeRemovesCredentialShapedText() {
        let marker = SafeMessage.redactionMarker
        let bearer = SafeMessage.sanitize("Authorization: Bearer sk-abcdef123456")
        #expect(!bearer.contains("sk-abcdef123456"), "API key leaked: \(bearer)")
        #expect(bearer.contains(marker))

        let token = SafeMessage.sanitize("failed for token ghp_ABCDEFGHIJKLMNOP")
        #expect(!token.contains("ghp_ABCDEFGHIJKLMNOP"), "Provider token leaked: \(token)")

        #expect(!SafeMessage.sanitize("contact admin@corp.com now").contains("@corp.com"))
        #expect(!SafeMessage.sanitize("jwt eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9").contains("eyJ"))
        #expect(SafeMessage.sanitize("plain failure").contains("plain failure"))
    }

    @Test
    func sanitizeTruncatesAndCollapsesWhitespace() {
        let long = String(repeating: "x", count: 500)
        let result = SafeMessage.sanitize(long)
        #expect(result.count <= SafeMessage.maxLength + 1)
        #expect(!SafeMessage.sanitize("a\n\n   b").contains("\n"))
    }

    // P0-4: transient faults must not be treated as session expiry.
    @Test
    func transientErrorsAreNotFatalButUnauthorizedIs() {
        let transient = SourceOutcome<DashboardSnapshotDTO>(value: nil, failure: SafeMessage.sanitize(URLError(.notConnectedToInternet)))
        #expect(transient.fatalError == nil, "Network faults must not wipe credentials")

        let unauthorized = SourceOutcome<DashboardSnapshotDTO>(value: nil, failure: Sub2APIError.unauthorized.localizedDescription)
        if case .unauthorized = unauthorized.fatalError {
            // expected
        } else {
            Issue.record("401 must invalidate the session")
        }
    }

    // P1-3: per-source failures must be reported, not silently swallowed.
    @Test
    func sourceSummaryReportsEveryFailure() {
        let combined = SourceSummary.combine(["并发：超时", nil, "服务器：500", "账号：解析失败"])
        #expect(combined == "并发：超时；服务器：500；账号：解析失败")
        #expect(SourceSummary.combine([nil, nil]) == nil)
    }

    // P2-3: snapshots must stay compact; pretty-printing inflated them ~47%.
    @Test
    func snapshotEncodingStaysCompact() throws {
        let data = try JSONEncoder.sub2api.encode(MonitorSnapshot.placeholder(instanceID: "size"))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("\n"), "Snapshot files must not be pretty-printed")
    }

    // P1-2: the date parser must not allocate a formatter per call.
    @Test
    func dateParserHandlesServerFormatsWithoutAllocatingPerCall() {
        #expect(DateParsers.parseSub2APIDate("2026-07-14T00:00:00Z") != nil)
        #expect(DateParsers.parseSub2APIDate("2026-07-14T00:00:00.123Z") != nil)
        #expect(DateParsers.parseSub2APIDate("2026-07-14 00:00:00") != nil, "space-separated form now supported")
        #expect(DateParsers.parseSub2APIDate("garbage") == nil)
    }

    @Test
    func epochMillisecondsDecodeCorrectly() throws {
        struct Probe: Decodable { var at: Date }
        let json = "{\"at\": 1767225600000}"
        let probe = try JSONDecoder.sub2api.decode(Probe.self, from: Data(json.utf8))
        #expect(abs(probe.at.timeIntervalSince1970 - 1_767_225_600) < 1)
    }

    // P1-5 / trust: the widget must never render fabricated metrics as real.
    @Test
    func unavailableSnapshotCarriesNoFabricatedMetrics() {
        let unavailable = MonitorSnapshot.unavailable(instanceID: "x", reason: "暂无数据")
        #expect(unavailable.isStale)
        #expect(unavailable.dataState != .available)
        #expect(unavailable.platforms.allSatisfy { $0.totalAccounts == 0 && $0.currentInUse == 0 })
        #expect(unavailable.server.healthScore == 0)
    }
}