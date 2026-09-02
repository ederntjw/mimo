import Foundation
import MuesliCore
import Testing
@testable import MuesliNativeApp

private actor TestMimoAccountAPI: MimoAccountAPIProtocol {
    let accountSession: MimoAccountSession
    private(set) var pushedRecords: [MimoPushRecord] = []
    private var nextChangeSequence: Int64 = 1
    var pullRecords: [MimoRemoteRecord] = []

    init(userID: UUID = UUID(), email: String = "person@example.com") {
        accountSession = MimoAccountSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3_600),
            user: MimoAccountUser(id: userID, email: email)
        )
    }

    var isConfigured: Bool { true }

    func storedSession() throws -> MimoAccountSession? { accountSession }

    func signUp(email: String, password: String, displayName: String?) async throws -> MimoAccountSignUpResult {
        MimoAccountSignUpResult(user: accountSession.user, session: accountSession)
    }

    func signIn(email: String, password: String) async throws -> MimoAccountSession { accountSession }

    func signOut() async {}

    func deleteAccount() async throws {}

    func authenticatedSession() async throws -> MimoAccountSession { accountSession }

    func push(records: [MimoPushRecord]) async throws -> [MimoRemoteRecord] {
        pushedRecords.append(contentsOf: records)
        return records.map { record in
            defer { nextChangeSequence += 1 }
            return MimoRemoteRecord(
                userID: accountSession.user.id,
                recordID: record.recordID,
                kind: record.kind,
                schemaVersion: record.schemaVersion,
                payload: record.payload,
                clientUpdatedAt: record.clientUpdatedAt,
                deviceID: record.deviceID,
                deletedAt: record.deletedAt,
                changeSeq: nextChangeSequence,
                serverUpdatedAt: Date()
            )
        }
    }

    func pull(after cursor: Int64, limit: Int) async throws -> [MimoRemoteRecord] {
        Array(pullRecords.filter { $0.changeSeq > cursor }.prefix(limit))
    }

    func setPullRecords(_ records: [MimoRemoteRecord]) {
        pullRecords = records
    }
}

@Suite("Mimo account sync", .serialized)
struct MimoAccountSyncTests {
    private func makeStore() throws -> DictationStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-account-sync-\(UUID().uuidString).db")
        let store = DictationStore(databaseURL: url)
        try store.migrateIfNeeded()
        return store
    }

    @Test("configuration requires a complete HTTPS project configuration")
    func configurationGate() {
        let valid = MimoAccountConfiguration.resolve(
            bundle: .main,
            environment: [
                "MIMO_SUPABASE_URL": "https://example.supabase.co",
                "MIMO_SUPABASE_PUBLISHABLE_KEY": "publishable-key",
            ]
        )
        #expect(valid?.baseURL.absoluteString == "https://example.supabase.co")
        #expect(valid?.publishableKey == "publishable-key")

        #expect(MimoAccountConfiguration.resolve(
            bundle: .main,
            environment: [
                "MIMO_SUPABASE_URL": "http://example.supabase.co",
                "MIMO_SUPABASE_PUBLISHABLE_KEY": "publishable-key",
            ]
        ) == nil)
        #expect(MimoAccountConfiguration.resolve(
            bundle: .main,
            environment: ["MIMO_SUPABASE_URL": "https://example.supabase.co"]
        ) == nil)
    }

    @Test("Mac meeting fields use the canonical account envelope")
    func canonicalMeetingEnvelope() throws {
        let updatedAt = Date(timeIntervalSince1970: 1_800_000_000.25)
        let notesUpdatedAt = updatedAt.addingTimeInterval(-2)
        let record = SyncTextRecord(
            id: "meeting-stable-name",
            kind: .meeting,
            title: "Planning",
            text: "Raw transcript",
            speakerTranscript: "[00:00:01] Speaker: Raw transcript",
            summaryText: "## Notes",
            manualNotes: "Remember this",
            source: "macos",
            localSource: "lecture",
            meetingStatus: .completed,
            engineIdentifier: "parakeet-tdt-0.6b-v3",
            createdAt: updatedAt.addingTimeInterval(-60),
            updatedAt: updatedAt,
            manualNotesUpdatedAt: notesUpdatedAt,
            startedAt: updatedAt.addingTimeInterval(-60),
            endedAt: updatedAt,
            durationSeconds: 60,
            wordCount: 2,
            followUpToRecordName: "meeting-parent-name"
        )
        let push = MimoPushRecord(
            record: record,
            deviceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        )
        let data = try MimoJSON.encoder().encode(push)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try #require(object["payload"] as? [String: Any])

        #expect(object["record_id"] as? String == "meeting-stable-name")
        #expect(object["schema_version"] as? Int == 1)
        #expect(payload["local_source"] as? String == "lecture")
        #expect(payload["meeting_status"] as? String == "completed")
        #expect(payload["follow_up_to_record_name"] as? String == "meeting-parent-name")
        #expect(payload["manual_notes_updated_at"] is String)
        #expect(object["cloud_change_tag"] == nil)
        #expect(object["cloud_system_fields"] == nil)
        #expect(payload["cloud_change_tag"] == nil)
        #expect(payload["cloud_system_fields"] == nil)
    }

    @Test("remote records decode additive fields and ignore unknown payload keys")
    func remoteEnvelopeCompatibility() throws {
        let userID = UUID()
        let deviceID = UUID()
        let json = """
        {
          "user_id": "\(userID.uuidString)",
          "record_id": "dictation-one",
          "kind": "dictation",
          "schema_version": 1,
          "payload": {
            "text": "Hello Mimo",
            "source": "ios",
            "local_source": "dictation",
            "created_at": "2026-09-02T02:00:00Z",
            "duration_seconds": 1.5,
            "word_count": 2,
            "future_additive_field": {"safe": true}
          },
          "client_updated_at": "2026-09-02T02:00:01Z",
          "device_id": "\(deviceID.uuidString)",
          "deleted_at": null,
          "change_seq": 7,
          "server_updated_at": "2026-09-02T02:00:02Z"
        }
        """
        let remote = try MimoJSON.decoder().decode(MimoRemoteRecord.self, from: Data(json.utf8))
        let textRecord = try remote.textRecord()

        #expect(textRecord.id == "dictation-one")
        #expect(textRecord.text == "Hello Mimo")
        #expect(textRecord.source == "ios")
        #expect(textRecord.cloudChangeTag == "7")
        #expect(textRecord.cloudSystemFields == nil)
    }

    @Test("future schema versions fail safely before changing local data")
    func futureSchemaGate() throws {
        let base = SyncTextRecord(
            id: "future-record",
            kind: .dictation,
            text: "Future",
            createdAt: Date(),
            updatedAt: Date(),
            durationSeconds: 0,
            wordCount: 1
        )
        let remote = MimoRemoteRecord(
            userID: UUID(),
            recordID: base.id,
            kind: base.kind.rawValue,
            schemaVersion: 2,
            payload: MimoSyncPayload(record: base),
            clientUpdatedAt: base.updatedAt,
            deviceID: UUID(),
            deletedAt: nil,
            changeSeq: 1,
            serverUpdatedAt: Date()
        )

        #expect(throws: MimoAccountError.invalidResponse) {
            try remote.textRecord()
        }
    }

    @Test("dirty local records upload and become clean without changing their stable names")
    func dirtyOutboxRoundTrip() async throws {
        let store = try makeStore()
        let now = Date()
        _ = try store.insertDictation(
            text: "Offline first text",
            durationSeconds: 2,
            startedAt: now.addingTimeInterval(-2),
            endedAt: now
        )
        let dirtyBefore = try store.textRecordsNeedingSync(limit: 10)
        let stableName = try #require(dirtyBefore.first?.id)
        let api = TestMimoAccountAPI()
        let engine = MimoAccountSyncEngine(store: store, api: api, deviceID: UUID())

        let result = try await engine.sync()

        #expect(result.uploaded == 1)
        #expect(result.downloaded == 0)
        #expect(try store.textRecordsNeedingSync(limit: 10).isEmpty)
        #expect(await api.pushedRecords.first?.recordID == stableName)
        #expect(try store.textRecordForSync(recordName: stableName)?.id == stableName)
    }

    @Test("a library already claimed by another account is never uploaded")
    func accountScopeGuard() async throws {
        let store = try makeStore()
        #expect(try store.claimCloudSyncAccountScope(UUID().uuidString, forKey: MimoAccountSyncEngine.accountScopeKey))
        let api = TestMimoAccountAPI()
        let engine = MimoAccountSyncEngine(store: store, api: api, deviceID: UUID())

        await #expect(throws: MimoAccountError.accountMismatch) {
            try await engine.sync()
        }
        #expect(await api.pushedRecords.isEmpty)
    }

    @Test("a pull page applies with its cursor and never partially imports")
    func pullPageAndCursorAreAtomic() async throws {
        let store = try makeStore()
        let api = TestMimoAccountAPI()
        let deviceID = UUID()
        let now = Date()
        let valid = SyncTextRecord(
            id: "dictation-remote-valid",
            kind: .dictation,
            text: "Arrived from the phone",
            source: "ios",
            localSource: "dictation",
            createdAt: now,
            updatedAt: now,
            durationSeconds: 1,
            wordCount: 4
        )
        let validRemote = MimoRemoteRecord(
            userID: api.accountSession.user.id,
            recordID: valid.id,
            kind: valid.kind.rawValue,
            schemaVersion: 1,
            payload: MimoSyncPayload(record: valid),
            clientUpdatedAt: valid.updatedAt,
            deviceID: deviceID,
            deletedAt: nil,
            changeSeq: 7,
            serverUpdatedAt: now
        )
        let invalidRemote = MimoRemoteRecord(
            userID: api.accountSession.user.id,
            recordID: "unsupported-kind",
            kind: "future_kind",
            schemaVersion: 1,
            payload: MimoSyncPayload(record: valid),
            clientUpdatedAt: now,
            deviceID: deviceID,
            deletedAt: nil,
            changeSeq: 8,
            serverUpdatedAt: now
        )
        await api.setPullRecords([validRemote, invalidRemote])
        let engine = MimoAccountSyncEngine(store: store, api: api, deviceID: UUID())

        await #expect(throws: MimoAccountError.invalidResponse) {
            try await engine.pullOnly()
        }

        #expect(try store.textRecordForSync(recordName: valid.id) == nil)
        let cursorKey = "mimo.account-sync.cursor.v1.\(api.accountSession.user.id.uuidString.lowercased())"
        #expect(try store.cloudSyncStateData(forKey: cursorKey) == nil)

        await api.setPullRecords([validRemote])
        let result = try await engine.pullOnly()
        #expect(result.downloaded == 1)
        #expect(try store.textRecordForSync(recordName: valid.id)?.text == valid.text)
        #expect(try store.cloudSyncStateData(forKey: cursorKey) == Data("7".utf8))
    }
}
