import Foundation

enum ChatGPTResponsesError: LocalizedError {
    case backendFailed(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case let .backendFailed(statusCode, message):
            return "ChatGPT failed with status \(statusCode). \(message)"
        }
    }
}

/// Shared request construction for ChatGPT-authenticated Responses calls.
///
/// Mimo routes its existing ChatGPT OAuth credentials to the Codex inference
/// lane. That direct third-party contract is compatibility-sensitive, so keep
/// request metadata centralized and the client identity honest: these headers
/// describe Mimo and never impersonate an official Codex client. WHAM remains
/// available only as an explicit, process-level emergency rollback.
enum ChatGPTResponsesTransport {
    enum Backend: Equatable {
        case codex
        case wham

        var responsesURL: URL {
            switch self {
            case .codex:
                return URL(string: "https://chatgpt.com/backend-api/codex/responses")!
            case .wham:
                return URL(string: "https://chatgpt.com/backend-api/wham/responses")!
            }
        }
    }

    static let environmentKey = "MUESLI_CHATGPT_TRANSPORT"
    static let requestTimeout: TimeInterval = 120
    static let originator = "mimo"
    /// Compatibility revision of the Codex catalog consumed by this adapter,
    /// independent of Mimo's marketing version. The server compares this query
    /// value with its model metadata's `minimal_client_version`; sending 0.8.6
    /// returns an empty catalog despite successful text inference. Revision
    /// 0.153.0 covers the schema and text/reasoning options we consume, including
    /// Astra, and is pinned rather than inferred from a different installed app.
    /// Reference: openai/codex, codex-rs/models-manager/models.json.
    /// Request identity remains Mimo/<actual app version>, originator mimo.
    static let catalogCompatibilityVersion = "0.153.0"

    static func selectedBackend(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Backend {
        let requested = environment[environmentKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return requested == "wham" ? .wham : .codex
    }

    static func makeRequest(
        body: [String: Any],
        token: String,
        accountId: String,
        appVersion: String = AppIdentity.marketingVersion,
        sessionID: UUID = UUID(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URLRequest {
        let backend = selectedBackend(environment: environment)
        var request = URLRequest(url: backend.responsesURL)
        request.timeoutInterval = requestTimeout
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        if backend == .codex {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.setValue(originator, forHTTPHeaderField: "originator")
            request.setValue("Mimo/\(appVersion)", forHTTPHeaderField: "User-Agent")
            request.setValue(sessionID.uuidString.lowercased(), forHTTPHeaderField: "session_id")
        }
        var backendBody = body
        if backend == .codex {
            // The ChatGPT Codex endpoint rejects this public Responses API
            // parameter with HTTP 400. Quill still validates output size locally.
            backendBody.removeValue(forKey: "max_output_tokens")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: backendBody)
        return request
    }

    static func makeModelsRequest(
        token: String,
        accountId: String,
        appVersion: String = AppIdentity.marketingVersion
    ) -> URLRequest {
        var components = URLComponents(string: "https://chatgpt.com/backend-api/codex/models")!
        components.queryItems = [URLQueryItem(name: "client_version", value: catalogCompatibilityVersion)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !accountId.isEmpty { request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id") }
        request.setValue(originator, forHTTPHeaderField: "originator")
        request.setValue("Mimo/\(appVersion)", forHTTPHeaderField: "User-Agent")
        return request
    }
}

enum ChatGPTResponsesClient {
    static func respond(
        systemPrompt: String,
        userPrompt: String,
        model: String,
        maxOutputTokens: Int? = nil,
        logCategory: String,
        credentials: (() async throws -> (token: String, accountId: String))? = nil
    ) async throws -> String {
        let (token, accountId): (String, String)
        if let credentials {
            (token, accountId) = try await credentials()
        } else {
            (token, accountId) = try await ChatGPTAuthManager.shared.validAccessToken()
        }
        let usesCodex = ChatGPTResponsesTransport.selectedBackend() == .codex
        let catalog = ChatGPTModelCatalog.shared
        // Catalog refresh failure must not prevent a known working model from
        // running. Actual response errors still propagate, including auth/quota.
        let available = usesCodex ? try? await catalog.models(token: token, accountID: accountId) : nil
        try Task.checkCancellation()
        let candidates = usesCodex
            ? await catalog.candidates(requested: model, available: available, accountID: accountId)
            : [model == ChatGPTModelSelection.automatic || model.isEmpty ? ChatGPTModelSelection.fastModelIDs[0] : model]
        return try await ChatGPTModelSelection.perform(candidates: candidates) { selectedModel in
            let effort = available?.first(where: { $0.slug == selectedModel })?.fastReasoningEffort
                ?? (ChatGPTModelSelection.fastModelIDs.contains(selectedModel) ? "low" : nil)
            return try await performRequest(
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                model: selectedModel,
                reasoningEffort: effort,
                maxOutputTokens: maxOutputTokens,
                logCategory: logCategory,
                token: token,
                accountId: accountId
            )
        } rejected: { rejectedModel in
            await catalog.markUnavailable(rejectedModel, accountID: accountId)
            fputs("[\(logCategory)] ChatGPT model \(rejectedModel) unavailable; trying an account-supported alternative.\n", stderr)
        }
    }

    private static func performRequest(
        systemPrompt: String,
        userPrompt: String,
        model: String,
        reasoningEffort: String?,
        maxOutputTokens: Int?,
        logCategory: String,
        token: String,
        accountId: String
    ) async throws -> String {
        fputs("[\(logCategory)] ChatGPT Responses: using \(model)\n", stderr)
        let body = requestBody(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            model: model,
            maxOutputTokens: maxOutputTokens,
            reasoningEffort: reasoningEffort
        )

        let request = try ChatGPTResponsesTransport.makeRequest(
            body: body,
            token: token,
            accountId: accountId
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard httpStatus == 200 else {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let message = extractErrorMessage(from: errorData)
                ?? String(data: errorData, encoding: .utf8)
                ?? "(unknown)"
            fputs("[\(logCategory)] ChatGPT Responses: HTTP \(httpStatus): \(String(message.prefix(500)))\n", stderr)
            throw ChatGPTResponsesError.backendFailed(statusCode: httpStatus, message: message)
        }

        var deltaText = ""
        var finalText = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonString = String(line.dropFirst(6))
            if jsonString == "[DONE]" { break }
            guard let json = try decodeStreamPayload(jsonString, httpStatus: httpStatus) else { continue }

            applyStreamPayload(json, deltaText: &deltaText, finalText: &finalText)
        }

        let fullText = accumulatedOutputText(deltaText: deltaText, finalText: finalText)
        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        fputs("[\(logCategory)] ChatGPT Responses: collected \(trimmed.count) chars\n", stderr)
        return trimmed
    }

    static func requestBody(
        systemPrompt: String,
        userPrompt: String,
        model: String,
        maxOutputTokens: Int? = nil,
        reasoningEffort: String? = nil
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": model,
            "store": false,
            "stream": true,
            "instructions": systemPrompt,
            "input": [[
                "role": "user",
                "content": [["type": "input_text", "text": userPrompt]],
            ] as [String: Any]],
        ]
        if let effort = reasoningEffort ?? SummaryModelPreset.reasoningEffort(for: model) {
            body["reasoning"] = ["effort": effort]
        }
        if let maxOutputTokens, maxOutputTokens > 0 {
            body["max_output_tokens"] = maxOutputTokens
        }
        return body
    }

    static func applyStreamPayload(_ payload: [String: Any], deltaText: inout String, finalText: inout String) {
        if let delta = extractOutputTextDelta(from: payload) {
            deltaText += delta
            return
        }

        if let outputText = extractOutputText(from: payload), !outputText.isEmpty {
            finalText = outputText
        }
    }

    static func accumulatedOutputText(deltaText: String, finalText: String) -> String {
        finalText.isEmpty ? deltaText : finalText
    }

    static func decodeStreamPayload(_ jsonString: String, httpStatus: Int) throws -> [String: Any]? {
        let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if shouldIgnoreNonJSONStreamPayload(trimmed) { return nil }
        guard
            let data = trimmed.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ChatGPTResponsesError.backendFailed(
                statusCode: httpStatus,
                message: "Malformed ChatGPT stream payload."
            )
        }
        let eventType = json["type"] as? String
        if eventType == "error" || eventType == "response.failed" || json["error"] is [String: Any] {
            let failure = (json["response"] as? [String: Any]) ?? json
            let data = try JSONSerialization.data(withJSONObject: failure)
            throw ChatGPTResponsesError.backendFailed(
                statusCode: httpStatus,
                message: extractErrorMessage(from: data) ?? "ChatGPT could not complete this response."
            )
        }
        return json
    }

    private static func shouldIgnoreNonJSONStreamPayload(_ payload: String) -> Bool {
        switch payload.lowercased() {
        case "ping", "heartbeat", "keep-alive":
            return true
        default:
            return false
        }
    }

    static func extractOutputText(from payload: [String: Any]) -> String? {
        if let outputText = payload["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }
        if let response = payload["response"] as? [String: Any],
           let responseText = extractOutputText(from: response) {
            return responseText
        }
        if let outputText = extractText(fromOutput: payload["output"]) {
            return outputText
        }
        if let contentText = extractText(fromContent: payload["content"]) {
            return contentText
        }
        return nil
    }

    static func extractOutputTextDelta(from payload: [String: Any]) -> String? {
        guard
            (payload["type"] as? String) == "response.output_text.delta",
            let delta = payload["delta"] as? String,
            !delta.isEmpty
        else {
            return nil
        }
        return delta
    }

    private static func extractText(fromOutput output: Any?) -> String? {
        guard let output else { return nil }
        if let outputText = output as? String, !outputText.isEmpty {
            return outputText
        }
        if let item = output as? [String: Any] {
            return extractText(fromContent: item["content"]) ?? (item["text"] as? String)
        }
        if let items = output as? [[String: Any]] {
            let parts = items.compactMap { item -> String? in
                extractText(fromContent: item["content"]) ?? (item["text"] as? String)
            }
            let joined = parts.joined(separator: "")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func extractText(fromContent content: Any?) -> String? {
        guard let content else { return nil }
        if let text = content as? String, !text.isEmpty {
            return text
        }
        if let item = content as? [String: Any] {
            if let text = item["text"] as? String, !text.isEmpty { return text }
            if let text = item["content"] as? String, !text.isEmpty { return text }
            if let nested = item["text"] as? [String: Any],
               let value = nested["value"] as? String,
               !value.isEmpty {
                return value
            }
        }
        if let items = content as? [[String: Any]] {
            let parts = items.compactMap { item -> String? in
                if let text = item["text"] as? String, !text.isEmpty { return text }
                if let text = item["content"] as? String, !text.isEmpty { return text }
                if let nested = item["text"] as? [String: Any],
                   let value = nested["value"] as? String,
                   !value.isEmpty {
                    return value
                }
                return nil
            }
            let joined = parts.joined(separator: "")
            return joined.isEmpty ? nil : joined
        }
        return nil
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty {
                let code = error["code"] as? String
                return code.map { "\($0): \(message)" } ?? message
            }
            if let code = error["code"] as? String, !code.isEmpty { return code }
            return String(describing: error)
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return (json["code"] as? String).map { "\($0): \(message)" } ?? message
        }
        if let detail = json["detail"] as? String, !detail.isEmpty { return detail }
        return nil
    }
}
