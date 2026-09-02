import Foundation
import MuesliCore
import Security

struct MimoAccountConfiguration: Sendable, Equatable {
    let baseURL: URL
    let publishableKey: String

    static var current: MimoAccountConfiguration? {
        resolve(bundle: .main, environment: ProcessInfo.processInfo.environment)
    }

    static func resolve(
        bundle: Bundle,
        environment: [String: String]
    ) -> MimoAccountConfiguration? {
        let rawURL = configuredValue(
            environmentKey: "MIMO_SUPABASE_URL",
            infoKey: "MimoSupabaseURL",
            bundle: bundle,
            environment: environment
        )
        let publishableKey = configuredValue(
            environmentKey: "MIMO_SUPABASE_PUBLISHABLE_KEY",
            infoKey: "MimoSupabasePublishableKey",
            bundle: bundle,
            environment: environment
        )
        guard let rawURL,
              let baseURL = URL(string: rawURL),
              baseURL.scheme?.lowercased() == "https",
              let publishableKey else {
            return nil
        }
        return MimoAccountConfiguration(baseURL: baseURL, publishableKey: publishableKey)
    }

    private static func configuredValue(
        environmentKey: String,
        infoKey: String,
        bundle: Bundle,
        environment: [String: String]
    ) -> String? {
        let candidates = [
            environment[environmentKey],
            bundle.object(forInfoDictionaryKey: infoKey) as? String,
        ]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty, !trimmed.hasPrefix("$(") {
                return trimmed
            }
        }
        return nil
    }
}

enum MimoAccountError: Error, LocalizedError, Equatable {
    case notConfigured
    case signedOut
    case invalidResponse
    case accountConfirmationRequired
    case accountMismatch
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Mimo account sync is not configured in this build yet."
        case .signedOut:
            return "Sign in to your Mimo account to sync."
        case .invalidResponse:
            return "Mimo received an unexpected response from the sync service."
        case .accountConfirmationRequired:
            return "Check your email to confirm your Mimo account, then sign in."
        case .accountMismatch:
            return "This local library belongs to another Mimo account. Clear the local library before switching accounts."
        case .server(let message):
            return message
        }
    }
}

struct MimoAccountUser: Codable, Sendable, Equatable, Identifiable {
    let id: UUID
    let email: String?
}

struct MimoAccountSession: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: MimoAccountUser

    var needsRefresh: Bool {
        expiresAt.timeIntervalSinceNow < 60
    }
}

struct MimoAccountSignUpResult: Sendable, Equatable {
    let user: MimoAccountUser
    let session: MimoAccountSession?
}

enum MimoJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(render(date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = parse(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid RFC3339 date"
                )
            }
            return date
        }
        return decoder
    }

    private static func render(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }
}

struct MimoSyncPayload: Codable, Sendable, Equatable {
    let title: String?
    let text: String
    let speakerTranscript: String?
    let summaryText: String?
    let manualNotes: String?
    let manualNotesUpdatedAt: Date?
    let source: String?
    let localSource: String?
    let meetingStatus: String?
    let engineIdentifier: String?
    let createdAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let durationSeconds: Double
    let wordCount: Int
    let followUpToRecordName: String?

    init(record: SyncTextRecord) {
        title = record.title
        text = record.text
        speakerTranscript = record.speakerTranscript
        summaryText = record.summaryText
        manualNotes = record.manualNotes
        manualNotesUpdatedAt = record.manualNotesUpdatedAt
        source = record.source
        localSource = record.localSource
        meetingStatus = record.meetingStatus?.rawValue
        engineIdentifier = record.engineIdentifier
        createdAt = record.createdAt
        startedAt = record.startedAt
        endedAt = record.endedAt
        durationSeconds = record.durationSeconds
        wordCount = record.wordCount
        followUpToRecordName = record.followUpToRecordName
    }
}

struct MimoPushRecord: Encodable, Sendable, Equatable {
    let recordID: String
    let kind: String
    let schemaVersion: Int
    let clientUpdatedAt: Date
    let deviceID: UUID
    let deletedAt: Date?
    let payload: MimoSyncPayload

    init(record: SyncTextRecord, deviceID: UUID) {
        recordID = record.id
        kind = record.kind.rawValue
        schemaVersion = 1
        clientUpdatedAt = record.updatedAt
        self.deviceID = deviceID
        deletedAt = record.isDeleted ? record.updatedAt : nil
        payload = MimoSyncPayload(record: record)
    }
}

struct MimoRemoteRecord: Decodable, Sendable, Equatable {
    let userID: UUID
    let recordID: String
    let kind: String
    let schemaVersion: Int
    let payload: MimoSyncPayload
    let clientUpdatedAt: Date
    let deviceID: UUID
    let deletedAt: Date?
    let changeSeq: Int64
    let serverUpdatedAt: Date

    private enum CodingKeys: String, CodingKey {
        // MimoJSON.decoder applies convertFromSnakeCase before consulting
        // CodingKeys. Acronyms therefore arrive as `userId`/`recordId` rather
        // than Swift's `userID`/`recordID` spelling.
        case userID = "userId"
        case recordID = "recordId"
        case kind
        case schemaVersion
        case payload
        case clientUpdatedAt
        case deviceID = "deviceId"
        case deletedAt
        case changeSeq
        case serverUpdatedAt
    }

    func textRecord() throws -> SyncTextRecord {
        guard schemaVersion <= 1,
              let resolvedKind = SyncTextRecordKind(rawValue: kind) else {
            throw MimoAccountError.invalidResponse
        }
        return SyncTextRecord(
            id: recordID,
            kind: resolvedKind,
            title: payload.title,
            text: payload.text,
            speakerTranscript: payload.speakerTranscript,
            summaryText: payload.summaryText,
            manualNotes: payload.manualNotes,
            source: payload.source,
            localSource: payload.localSource,
            meetingStatus: payload.meetingStatus.flatMap(MeetingStatus.init(rawValue:)),
            engineIdentifier: payload.engineIdentifier,
            createdAt: payload.createdAt,
            updatedAt: clientUpdatedAt,
            manualNotesUpdatedAt: payload.manualNotesUpdatedAt,
            startedAt: payload.startedAt,
            endedAt: payload.endedAt,
            durationSeconds: payload.durationSeconds,
            wordCount: payload.wordCount,
            isDeleted: deletedAt != nil,
            cloudChangeTag: String(changeSeq),
            cloudSystemFields: nil,
            followUpToRecordName: payload.followUpToRecordName
        )
    }
}

private struct MimoAuthResponse: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
    let expiresAt: Int?
    let user: MimoAccountUser?
}

private struct MimoAuthErrorResponse: Decodable, Sendable {
    let message: String?
    let msg: String?
    let errorDescription: String?
    let error: String?

    var bestMessage: String? {
        errorDescription ?? message ?? msg ?? error
    }
}

protocol MimoAccountSessionVault: Sendable {
    func load() throws -> MimoAccountSession?
    func save(_ session: MimoAccountSession) throws
    func clear() throws
}

final class MimoKeychainSessionVault: MimoAccountSessionVault, @unchecked Sendable {
    private let service: String
    private let account = "session.v1"

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.muesli.app") {
        service = "\(bundleIdentifier).mimo-account"
    }

    func load() throws -> MimoAccountSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw MimoAccountError.server("Mimo could not read its saved account session.")
        }
        return try MimoJSON.decoder().decode(MimoAccountSession.self, from: data)
    }

    func save(_ session: MimoAccountSession) throws {
        let data = try MimoJSON.encoder().encode(session)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw MimoAccountError.server("Mimo could not save its account session.")
        }
        var insert = baseQuery
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
            throw MimoAccountError.server("Mimo could not save its account session.")
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw MimoAccountError.server("Mimo could not clear its saved account session.")
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

protocol MimoAccountAPIProtocol: Sendable {
    var isConfigured: Bool { get async }
    func storedSession() async throws -> MimoAccountSession?
    func signUp(email: String, password: String, displayName: String?) async throws -> MimoAccountSignUpResult
    func signIn(email: String, password: String) async throws -> MimoAccountSession
    func signOut() async
    func deleteAccount() async throws
    func authenticatedSession() async throws -> MimoAccountSession
    func push(records: [MimoPushRecord]) async throws -> [MimoRemoteRecord]
    func pull(after cursor: Int64, limit: Int) async throws -> [MimoRemoteRecord]
}

actor MimoAccountAPI: MimoAccountAPIProtocol {
    static let shared = MimoAccountAPI()

    private let configuration: MimoAccountConfiguration?
    private let vault: any MimoAccountSessionVault
    private let session: URLSession
    private var cachedSession: MimoAccountSession?
    private var loadedSession = false

    init(
        configuration: MimoAccountConfiguration? = .current,
        vault: any MimoAccountSessionVault = MimoKeychainSessionVault(),
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.vault = vault
        self.session = session
    }

    var isConfigured: Bool { configuration != nil }

    func storedSession() throws -> MimoAccountSession? {
        try loadSessionIfNeeded()
        return cachedSession
    }

    func signUp(email: String, password: String, displayName: String?) async throws -> MimoAccountSignUpResult {
        let body = [
            "email": email,
            "password": password,
            "data": ["display_name": displayName ?? ""],
        ] as [String: Any]
        let response: MimoAuthResponse = try await sendDecoded(
            path: "auth/v1/signup",
            method: "POST",
            body: try JSONSerialization.data(withJSONObject: body),
            accessToken: nil
        )
        guard let user = response.user else { throw MimoAccountError.invalidResponse }
        let resolvedSession = try makeSession(from: response)
        if let resolvedSession { try save(resolvedSession) }
        return MimoAccountSignUpResult(user: user, session: resolvedSession)
    }

    func signIn(email: String, password: String) async throws -> MimoAccountSession {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let response: MimoAuthResponse = try await sendDecoded(
            path: "auth/v1/token",
            queryItems: [URLQueryItem(name: "grant_type", value: "password")],
            method: "POST",
            body: body,
            accessToken: nil
        )
        guard let resolvedSession = try makeSession(from: response) else {
            throw MimoAccountError.accountConfirmationRequired
        }
        try save(resolvedSession)
        return resolvedSession
    }

    func signOut() async {
        if let current = try? storedSession() {
            _ = try? await send(
                path: "auth/v1/logout",
                method: "POST",
                body: nil,
                accessToken: current.accessToken
            )
        }
        try? clearSession()
    }

    func deleteAccount() async throws {
        let current = try await authenticatedSession()
        _ = try await send(
            path: "functions/v1/delete-account",
            method: "DELETE",
            body: nil,
            accessToken: current.accessToken
        )
        try clearSession()
    }

    func authenticatedSession() async throws -> MimoAccountSession {
        try loadSessionIfNeeded()
        guard let current = cachedSession else { throw MimoAccountError.signedOut }
        guard current.needsRefresh else { return current }
        return try await refresh(current)
    }

    func push(records: [MimoPushRecord]) async throws -> [MimoRemoteRecord] {
        guard !records.isEmpty else { return [] }
        struct Body: Encodable { let records: [MimoPushRecord] }
        return try await sendAuthenticatedDecoded(
            path: "rest/v1/rpc/mimo_push_sync_records",
            body: MimoJSON.encoder().encode(Body(records: records))
        )
    }

    func pull(after cursor: Int64, limit: Int = 200) async throws -> [MimoRemoteRecord] {
        let body = try JSONSerialization.data(withJSONObject: [
            "after_change_seq": cursor,
            "max_count": min(max(limit, 1), 200),
        ])
        return try await sendAuthenticatedDecoded(
            path: "rest/v1/rpc/mimo_pull_sync_records",
            body: body
        )
    }

    private func refresh(_ current: MimoAccountSession) async throws -> MimoAccountSession {
        do {
            let body = try JSONSerialization.data(withJSONObject: ["refresh_token": current.refreshToken])
            let response: MimoAuthResponse = try await sendDecoded(
                path: "auth/v1/token",
                queryItems: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                method: "POST",
                body: body,
                accessToken: nil
            )
            guard let refreshed = try makeSession(from: response, fallbackUser: current.user) else {
                throw MimoAccountError.signedOut
            }
            try save(refreshed)
            return refreshed
        } catch {
            try? clearSession()
            throw MimoAccountError.signedOut
        }
    }

    private func sendAuthenticatedDecoded<Response: Decodable & Sendable>(
        path: String,
        body: Data
    ) async throws -> Response {
        var current = try await authenticatedSession()
        do {
            return try await sendDecoded(
                path: path,
                method: "POST",
                body: body,
                accessToken: current.accessToken
            )
        } catch MimoAccountError.signedOut {
            current = try await refresh(current)
            return try await sendDecoded(
                path: path,
                method: "POST",
                body: body,
                accessToken: current.accessToken
            )
        }
    }

    private func sendDecoded<Response: Decodable & Sendable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Data?,
        accessToken: String?
    ) async throws -> Response {
        let data = try await send(
            path: path,
            queryItems: queryItems,
            method: method,
            body: body,
            accessToken: accessToken
        )
        do {
            return try MimoJSON.decoder().decode(Response.self, from: data)
        } catch {
            throw MimoAccountError.invalidResponse
        }
    }

    private func send(
        path: String,
        queryItems: [URLQueryItem] = [],
        method: String,
        body: Data?,
        accessToken: String?
    ) async throws -> Data {
        guard let configuration else { throw MimoAccountError.notConfigured }
        var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components?.url else { throw MimoAccountError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MimoAccountError.invalidResponse
        }
        if http.statusCode == 401, accessToken != nil {
            throw MimoAccountError.signedOut
        }
        guard (200..<300).contains(http.statusCode) else {
            let serverError = try? MimoJSON.decoder().decode(MimoAuthErrorResponse.self, from: data)
            let message = serverError?.bestMessage
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw MimoAccountError.server(message)
        }
        return data
    }

    private func makeSession(
        from response: MimoAuthResponse,
        fallbackUser: MimoAccountUser? = nil
    ) throws -> MimoAccountSession? {
        guard let accessToken = response.accessToken,
              let refreshToken = response.refreshToken,
              let user = response.user ?? fallbackUser else { return nil }
        let expiresAt = response.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
            ?? Date().addingTimeInterval(TimeInterval(response.expiresIn ?? 3600))
        return MimoAccountSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            user: user
        )
    }

    private func loadSessionIfNeeded() throws {
        guard !loadedSession else { return }
        cachedSession = try vault.load()
        loadedSession = true
    }

    private func save(_ session: MimoAccountSession) throws {
        try vault.save(session)
        cachedSession = session
        loadedSession = true
    }

    private func clearSession() throws {
        try vault.clear()
        cachedSession = nil
        loadedSession = true
    }
}

struct MimoAccountSyncResult: Sendable, Equatable {
    var uploaded = 0
    var downloaded = 0
}

actor MimoAccountSyncEngine {
    static let accountScopeKey = "mimo.account-sync.owner.v1"
    private static let cursorKeyPrefix = "mimo.account-sync.cursor.v1."
    private static let batchLimit = 200
    private static let maximumPushBatches = 50

    private let store: DictationStore
    private let api: any MimoAccountAPIProtocol
    private let deviceID: UUID

    init(
        store: DictationStore,
        api: any MimoAccountAPIProtocol,
        deviceID: UUID
    ) {
        self.store = store
        self.api = api
        self.deviceID = deviceID
    }

    func sync() async throws -> MimoAccountSyncResult {
        let account = try await prepareAccount()
        var result = MimoAccountSyncResult()
        result.uploaded = try await pushAll(account: account)
        result.downloaded = try await pullAll(account: account)
        return result
    }

    func pushOnly() async throws -> MimoAccountSyncResult {
        let account = try await prepareAccount()
        return MimoAccountSyncResult(uploaded: try await pushAll(account: account), downloaded: 0)
    }

    func pullOnly() async throws -> MimoAccountSyncResult {
        let account = try await prepareAccount()
        return MimoAccountSyncResult(uploaded: 0, downloaded: try await pullAll(account: account))
    }

    private func prepareAccount() async throws -> MimoAccountSession {
        let account = try await api.authenticatedSession()
        guard try store.claimCloudSyncAccountScope(
            account.user.id.uuidString.lowercased(),
            forKey: Self.accountScopeKey
        ) else {
            throw MimoAccountError.accountMismatch
        }
        return account
    }

    private func pushAll(account: MimoAccountSession) async throws -> Int {
        var uploaded = 0
        for _ in 0..<Self.maximumPushBatches {
            let localRecords = try store.textRecordsNeedingSync(limit: Self.batchLimit)
            guard !localRecords.isEmpty else { break }
            let remoteRecords = try await api.push(
                records: localRecords.map { MimoPushRecord(record: $0, deviceID: deviceID) }
            )
            let remoteByID = Dictionary(uniqueKeysWithValues: remoteRecords.map { ($0.recordID, $0) })
            var madeProgress = false

            for local in localRecords {
                guard let remote = remoteByID[local.id], remote.userID == account.user.id else { continue }
                let sameAcceptedWrite = remote.deviceID == deviceID
                    && datesEqual(remote.clientUpdatedAt, local.updatedAt)
                if sameAcceptedWrite {
                    if try store.markTextRecordSynced(
                        kind: local.kind,
                        recordName: local.id,
                        changeTag: String(remote.changeSeq),
                        recordUpdatedAt: local.updatedAt
                    ) {
                        uploaded += 1
                        madeProgress = true
                    }
                    continue
                }

                if conflictTuple(remote.clientUpdatedAt, remote.deviceID)
                    > conflictTuple(local.updatedAt, deviceID),
                   remote.schemaVersion <= 1 {
                    let applied = try store.upsertAuthoritativeSyncedTextRecord(
                        remote.textRecord(),
                        replacingLocalUpdatedAt: local.updatedAt
                    )
                    madeProgress = madeProgress || applied
                }
            }

            if !madeProgress { break }
        }
        return uploaded
    }

    private func pullAll(account: MimoAccountSession) async throws -> Int {
        let cursorKey = Self.cursorKeyPrefix + account.user.id.uuidString.lowercased()
        var cursor = try loadCursor(forKey: cursorKey)
        var downloaded = 0
        while true {
            let page = try await api.pull(after: cursor, limit: Self.batchLimit)
            guard !page.isEmpty else { break }
            let supported = page.filter {
                $0.userID == account.user.id && $0.schemaVersion <= 1
            }
            let localByID = try store.textRecordsForSync(
                recordNames: supported.map(\.recordID)
            )
            var pageItems: [SyncTextRecordPageItem] = []
            var metadataUpdates: [SyncTextRecordMetadataUpdate] = []
            for remote in supported {
                let incoming = try remote.textRecord()
                if let local = localByID[incoming.id] {
                    let remoteWins = conflictTuple(remote.clientUpdatedAt, remote.deviceID)
                        > conflictTuple(local.updatedAt, deviceID)
                    if remoteWins {
                        pageItems.append(SyncTextRecordPageItem(
                            record: incoming,
                            replacingLocalUpdatedAt: local.updatedAt
                        ))
                    } else if !local.isDeleted,
                              datesEqual(remote.clientUpdatedAt, local.updatedAt),
                              remote.deviceID == deviceID {
                        metadataUpdates.append(SyncTextRecordMetadataUpdate(
                            kind: local.kind,
                            recordName: local.id,
                            changeTag: String(remote.changeSeq)
                        ))
                    }
                } else {
                    pageItems.append(SyncTextRecordPageItem(record: incoming))
                }
            }
            guard let highest = page.map(\.changeSeq).max() else { break }
            let nextCursor = max(cursor, highest)
            let applied = try store.applySyncedTextRecordPage(
                pageItems,
                metadataUpdates: metadataUpdates,
                cursorData: Data(String(nextCursor).utf8),
                cursorKey: cursorKey
            )
            downloaded += applied.count
            cursor = nextCursor
            if page.count < Self.batchLimit { break }
        }
        return downloaded
    }

    private func loadCursor(forKey key: String) throws -> Int64 {
        guard let data = try store.cloudSyncStateData(forKey: key),
              let raw = String(data: data, encoding: .utf8),
              let cursor = Int64(raw) else { return 0 }
        return max(cursor, 0)
    }

    private func conflictTuple(_ date: Date, _ deviceID: UUID) -> (Double, String) {
        (date.timeIntervalSince1970, deviceID.uuidString.lowercased())
    }

    private func datesEqual(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 0.000_5
    }
}
