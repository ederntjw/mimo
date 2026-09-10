import Foundation

/// The API catalog and the models available to a ChatGPT subscription are
/// different. Discover the latter using Mimo's own signed-in account.
struct ChatGPTAvailableModel: Decodable, Sendable, Equatable {
    struct ReasoningLevel: Decodable, Sendable, Equatable {
        let effort: String
    }

    let slug: String
    let displayName: String?
    let visibility: String?
    let priority: Int?
    let defaultReasoningLevel: String?
    let supportedReasoningLevels: [ReasoningLevel]?

    enum CodingKeys: String, CodingKey {
        case slug, visibility, priority
        case displayName = "display_name"
        case defaultReasoningLevel = "default_reasoning_level"
        case supportedReasoningLevels = "supported_reasoning_levels"
    }

    var fastReasoningEffort: String? {
        let supported = supportedReasoningLevels?.map(\.effort) ?? []
        if supported.contains("low") { return "low" }
        if let level = defaultReasoningLevel, supported.isEmpty || supported.contains(level) { return level }
        return supported.first
    }
}

enum ChatGPTModelSelection {
    static let automatic = "auto"
    static let fastModelIDs = ["gpt-5.6-luna", "gpt-5.6-terra", "gpt-5.6-sol", "gpt-5.5"]

    static func candidates(requested: String, available: [ChatGPTAvailableModel]?) -> [String] {
        let requested = SummaryModelPreset.supportedChatGPTModel(requested)
        var ids: [String] = []
        if !requested.isEmpty, requested != automatic { ids.append(requested) }
        if let available, !available.isEmpty {
            let offered = Set(available.map(\.slug))
            // An explicit custom choice is attempted even if it is unlisted;
            // fallback only occurs after a model-specific rejection.
            ids += fastModelIDs.filter { offered.contains($0) }
            ids += available.sorted { ($0.priority ?? Int.max) < ($1.priority ?? Int.max) }.map(\.slug)
        } else {
            ids += fastModelIDs
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    static func isUnavailableModelError(_ error: Error) -> Bool {
        guard case let ChatGPTResponsesError.backendFailed(statusCode, message) = error,
              [200, 400, 403, 404, 422].contains(statusCode) else { return false }
        let text = message.lowercased()
        if text.contains("model_not_found") || text.contains("unsupported_model") { return true }
        guard text.contains("model") else { return false }
        guard !text.contains("parameter") && !text.contains("reasoning effort") else { return false }
        return ["not supported", "unsupported model", "does not exist", "not found",
                "not available", "unavailable for", "do not have access to", "don't have access to"]
            .contains { text.contains($0) }
    }

    /// Retry only model selection failures. Authentication, quota, connectivity,
    /// and ordinary generation errors keep their original meaning.
    static func perform(
        candidates: [String],
        operation: (String) async throws -> String,
        rejected: (String) async -> Void = { _ in }
    ) async throws -> String {
        var lastError: Error?
        for model in candidates.prefix(3) {
            try Task.checkCancellation()
            do { return try await operation(model) }
            catch {
                guard isUnavailableModelError(error) else { throw error }
                lastError = error
                await rejected(model)
            }
        }
        throw lastError ?? ChatGPTResponsesError.backendFailed(
            statusCode: 404,
            message: "No supported text model is available for this ChatGPT account. Refresh the model list in Settings → Meetings."
        )
    }
}

actor ChatGPTModelCatalog {
    static let shared = ChatGPTModelCatalog()
    private struct Entry {
        let models: [ChatGPTAvailableModel]
        let expires: Date
    }
    private var cache: [String: Entry] = [:]
    private var rejectedByAccount: [String: [String: Date]] = [:]

    static func decode(_ data: Data) throws -> [ChatGPTAvailableModel] {
        struct Catalog: Decodable { let models: [ChatGPTAvailableModel] }
        return try JSONDecoder().decode(Catalog.self, from: data).models.filter {
            !$0.slug.isEmpty && ($0.visibility == nil || $0.visibility == "list")
        }
    }

    func models(token: String, accountID: String, forceRefresh: Bool = false) async throws -> [ChatGPTAvailableModel] {
        if !forceRefresh, !accountID.isEmpty, let entry = cache[accountID], entry.expires > Date() {
            return entry.models
        }
        let request = ChatGPTResponsesTransport.makeModelsRequest(token: token, accountId: accountID)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ChatGPTResponsesError.backendFailed(statusCode: status, message: "Could not refresh this account's ChatGPT models.")
        }
        let models = try Self.decode(data)
        guard !models.isEmpty else {
            throw ChatGPTResponsesError.backendFailed(statusCode: 404, message: "ChatGPT returned no available text models.")
        }
        if !accountID.isEmpty {
            cache[accountID] = Entry(models: models, expires: Date().addingTimeInterval(600))
            if forceRefresh { rejectedByAccount[accountID] = nil }
        }
        return models
    }

    func candidates(
        requested: String,
        available: [ChatGPTAvailableModel]?,
        accountID: String,
        now: Date = Date()
    ) -> [String] {
        let rejected = (rejectedByAccount[accountID] ?? [:]).filter { $0.value > now }
        rejectedByAccount[accountID] = rejected
        let explicitChoice = SummaryModelPreset.supportedChatGPTModel(requested)
        return ChatGPTModelSelection.candidates(requested: requested, available: available)
            .filter { $0 == explicitChoice || rejected[$0] == nil }
    }

    func markUnavailable(_ model: String, accountID: String, now: Date = Date()) {
        guard !accountID.isEmpty else { return }
        rejectedByAccount[accountID, default: [:]][model] = now.addingTimeInterval(600)
        // Refresh on the next request so a changed server catalog is picked up.
        cache[accountID] = nil
    }
}
