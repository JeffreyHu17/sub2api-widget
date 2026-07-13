import Foundation
import Testing
@testable import Sub2APIWidgetCore

struct SnapshotBuilderTests {
    @Test
    func mergesAccountListWithRealtimeOpsAndQuota() throws {
        let concurrency: ConcurrencyResponseDTO = try decodeData("""
        {
          "enabled": true,
          "platform": {},
          "account": {
            "42": {
              "account_id": 42,
              "account_name": "OpenAI Main",
              "platform": "openai",
              "group_id": 1,
              "group_name": "default",
              "current_in_use": 3,
              "max_capacity": 8,
              "load_percentage": 37.5,
              "waiting_in_queue": 2
            }
          },
          "timestamp": null
        }
        """)
        let availability: AvailabilityResponseDTO = try decodeData("""
        {
          "enabled": true,
          "platform": {},
          "account": {
            "42": {
              "account_id": 42,
              "account_name": "OpenAI Main",
              "platform": "openai",
              "group_name": "default",
              "status": "active",
              "is_available": false,
              "is_rate_limited": true,
              "is_overloaded": false,
              "has_error": false,
              "error_message": null
            }
          },
          "timestamp": null
        }
        """)
        let accounts: AccountsPageDTO = try decodeData("""
        {
          "items": [{
            "id": 42,
            "name": "OpenAI Main",
            "platform": "openai",
            "type": "apikey",
            "concurrency": 4,
            "current_concurrency": 1,
            "status": "active",
            "error_message": "",
            "schedulable": true,
            "last_used_at": null,
            "rate_limit_reset_at": null,
            "overload_until": null,
            "temp_unschedulable_until": null,
            "quota_daily_limit": 100,
            "quota_daily_used": 75,
            "quota_daily_reset_at": "2026-07-14T00:00:00Z",
            "active_sessions": 2,
            "max_sessions": 5,
            "current_rpm": 7,
            "base_rpm": 20
          }],
          "total": 1,
          "page": 1,
          "page_size": 1000,
          "pages": 1
        }
        """)
        let dashboard: DashboardSnapshotDTO = try decodeData("""
        {"generated_at": null, "overview": {"health_score": 95}}
        """)

        let snapshot = SnapshotBuilder.build(
            instanceID: "test",
            concurrency: concurrency,
            availability: availability,
            dashboard: dashboard,
            accounts: accounts,
            authState: .sample,
            refreshInterval: 15,
            diagnostics: .empty,
            staleReason: nil
        )

        let account = try #require(snapshot.monitoredAccounts.first)
        #expect(snapshot.dataState == .available)
        #expect(account.currentInUse == 3)
        #expect(account.maxConcurrency == 8)
        #expect(account.waitingInQueue == 2)
        #expect(account.status == .rateLimited)
        #expect(account.activeSessions == 2)
        #expect(account.quotas.first?.kind == "daily")
        #expect(account.quotas.first?.usedPercent == 75)
    }

    @Test
    func oldSnapshotWithoutNewOptionalFieldsStillDecodes() throws {
        let encoded = try JSONEncoder.sub2api.encode(MonitorSnapshot.placeholder(instanceID: "legacy"))
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "accounts")
        object.removeValue(forKey: "dataState")
        object.removeValue(forKey: "data_state")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder.sub2api.decode(MonitorSnapshot.self, from: legacyData)
        #expect(decoded.instanceID == "legacy")
        #expect(decoded.monitoredAccounts.isEmpty)
        #expect(decoded.dataState == nil)
    }

    @Test
    func rejectsCredentialTransportOverRemoteHTTP() {
        #expect(URL(string: "https://example.com")!.isAllowedSub2APIBaseURL)
        #expect(URL(string: "http://localhost:8080")!.isAllowedSub2APIBaseURL)
        #expect(!URL(string: "http://example.com")!.isAllowedSub2APIBaseURL)
        #expect(!URL(string: "https://user:pass@example.com")!.isAllowedSub2APIBaseURL)
    }

    private func decodeData<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder.sub2api.decode(T.self, from: Data(json.utf8))
    }
}
