import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("ChatGPT Responses transport")
struct ChatGPTResponsesTransportTests {
    @Test("Quill output budgets are omitted only on the Codex transport")
    func quillOutputBudgetCompatibility() throws {
        let body = ChatGPTResponsesClient.requestBody(
            systemPrompt: "Rewrite the text", userPrompt: "Hello", model: "gpt-5.6-luna",
            maxOutputTokens: QuilModelPolicy.remoteMaximumOutputTokens
        )
        for backend in ["codex", "wham"] {
            let request = try ChatGPTResponsesTransport.makeRequest(
                body: body, token: "test-token", accountId: "test-account",
                environment: [ChatGPTResponsesTransport.environmentKey: backend]
            )
            let data = try #require(request.httpBody)
            let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            if backend == "codex" {
                #expect(payload["max_output_tokens"] == nil)
            } else {
                #expect(payload["max_output_tokens"] as? Int == QuilModelPolicy.remoteMaximumOutputTokens)
            }
            #expect(payload["instructions"] as? String == "Rewrite the text")
            #expect(payload["stream"] as? Bool == true)
            #expect(payload["store"] as? Bool == false)
        }
    }

    @Test("catalog compatibility is independent of Mimo's honest client identity")
    func modelsRequest() {
        let request = ChatGPTResponsesTransport.makeModelsRequest(
            token: "test-token", accountId: "test-account", appVersion: "0.8.6"
        )
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/codex/models?client_version=0.153.0")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "test-account")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Mimo/0.8.6")
        #expect(request.value(forHTTPHeaderField: "originator") == "mimo")
        let upgraded = ChatGPTResponsesTransport.makeModelsRequest(
            token: "test-token", accountId: "test-account", appVersion: "1.2.3"
        )
        #expect(upgraded.url == request.url)
        #expect(upgraded.value(forHTTPHeaderField: "User-Agent") == "Mimo/1.2.3")
    }

    @Test("account catalog omits hidden models and retains subscription-only models")
    func modelCatalog() throws {
        let data = Data(#"{"models":[{"slug":"hidden","visibility":"hide"},{"slug":"gpt-5.6-luna","visibility":"list","supported_in_api":false,"default_reasoning_level":"medium","supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"}]}]}"#.utf8)
        let models = try ChatGPTModelCatalog.decode(data)
        #expect(models.map(\.slug) == ["gpt-5.6-luna"])
        #expect(models.first?.fastReasoningEffort == "low")
        let candidates = ChatGPTModelSelection.candidates(requested: "auto", available: models)
        #expect(candidates == ["gpt-5.6-luna"])
        #expect(ChatGPTModelSelection.candidates(requested: "gpt-5.4-mini", available: models) == candidates)
        #expect(ChatGPTModelSelection.candidates(requested: "my-selected-model", available: models).first == "my-selected-model")
    }

    @Test("retired Mini selection migrates without changing the API provider")
    func miniMigration() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"chatgpt_model":"gpt-5.4-mini","openai_model":"gpt-5.4-mini"}"#.utf8))
        #expect(config.chatGPTModel.isEmpty)
        #expect(config.openAIModel == "gpt-5.4-mini")
    }

    @Test("account picker does not offer model IDs the runtime migrates")
    func accountPickerHonorsRuntimePolicy() throws {
        let models = try ChatGPTModelCatalog.decode(Data(#"{"models":[{"slug":"gpt-5.4-mini"},{"slug":"gpt-5.4-nano"},{"slug":"chat-latest"},{"slug":"gpt-5.6-luna"},{"slug":"future-supported-model"}]}"#.utf8))
        #expect(SummaryModelPreset.accountChatGPTPresets(models).map(\.id)
                == ["auto", "gpt-5.6-luna", "future-supported-model"])
    }

    @Test("only model-unavailable failures try another model")
    func modelFallback() async throws {
        var attempted: [String] = []
        let text = try await ChatGPTModelSelection.perform(candidates: ["missing", "working"]) { model in
            attempted.append(model)
            if model == "missing" {
                throw ChatGPTResponsesError.backendFailed(statusCode: 400, message: "This model is not supported when using Codex with a ChatGPT account.")
            }
            return "English meeting summary"
        }
        #expect(attempted == ["missing", "working"])
        #expect(text == "English meeting summary")
    }

    @Test("auth quota network and request parameter failures never switch models")
    func permanentFailures() async {
        let failures: [Error] = [
            ChatGPTResponsesError.backendFailed(statusCode: 401, message: "Unauthorized"),
            ChatGPTResponsesError.backendFailed(statusCode: 429, message: "Model rate limit exceeded"),
            ChatGPTResponsesError.backendFailed(statusCode: 400, message: "Parameter temperature is not supported for this model"),
            URLError(.notConnectedToInternet), CancellationError()
        ]
        for failure in failures {
            var attempts = 0
            do {
                _ = try await ChatGPTModelSelection.perform(candidates: ["first", "second"]) { _ in
                    attempts += 1
                    throw failure
                }
                Issue.record("Expected failure")
            } catch {}
            #expect(attempts == 1)
        }
    }

    @Test("fallback is bounded and rejection is scoped to the signed-in account")
    func boundedAccountFallback() async throws {
        var attempts = 0
        do {
            _ = try await ChatGPTModelSelection.perform(candidates: ["a", "b", "c", "d"]) { _ in
                attempts += 1
                throw ChatGPTResponsesError.backendFailed(statusCode: 404, message: "model_not_found")
            }
            Issue.record("Expected failure")
        } catch {}
        #expect(attempts == 3)
        let catalog = ChatGPTModelCatalog()
        await catalog.markUnavailable("gpt-5.6-luna", accountID: "account-a")
        let first = await catalog.candidates(requested: "auto", available: nil, accountID: "account-a")
        let second = await catalog.candidates(requested: "auto", available: nil, accountID: "account-b")
        #expect(!first.contains("gpt-5.6-luna"))
        #expect(second.first == "gpt-5.6-luna")
    }

    @Test("explicit selections bypass old rejections and automatic rejections expire")
    func modelReselection() async {
        let catalog = ChatGPTModelCatalog()
        let rejectedAt = Date(timeIntervalSince1970: 1_000)
        await catalog.markUnavailable("gpt-5.6-luna", accountID: "account", now: rejectedAt)
        let explicit = await catalog.candidates(
            requested: "gpt-5.6-luna", available: nil, accountID: "account", now: rejectedAt
        )
        #expect(explicit.first == "gpt-5.6-luna")
        let automatic = await catalog.candidates(
            requested: "auto", available: nil, accountID: "account", now: rejectedAt.addingTimeInterval(599)
        )
        #expect(!automatic.contains("gpt-5.6-luna"))
        let recovered = await catalog.candidates(
            requested: "auto", available: nil, accountID: "account", now: rejectedAt.addingTimeInterval(600)
        )
        #expect(recovered.first == "gpt-5.6-luna")
    }

    @Test("streamed model failures trigger fallback instead of returning empty notes")
    func streamFailure() throws {
        do {
            _ = try ChatGPTResponsesClient.decodeStreamPayload(
                #"{"type":"response.failed","response":{"error":{"code":"model_not_found","message":"Unavailable"}}}"#,
                httpStatus: 200
            )
            Issue.record("Expected model failure")
        } catch {
            #expect(ChatGPTModelSelection.isUnavailableModelError(error))
        }
        let body = ChatGPTResponsesClient.requestBody(
            systemPrompt: "English summaries", userPrompt: "会议", model: "gpt-5.6-luna", reasoningEffort: "low"
        )
        #expect((body["reasoning"] as? [String: String])?["effort"] == "low")
    }

    @Test("builds Codex Responses requests with honest Muesli identity")
    func buildsCodexRequest() throws {
        let sessionID = UUID(uuidString: "8AF070D8-956D-4706-9FF8-8140CE7F6B2D")!
        let request = try ChatGPTResponsesTransport.makeRequest(
            body: ["model": "gpt-5.6-sol", "stream": true],
            token: "access-token",
            accountId: "account-123",
            appVersion: "1.2.3",
            sessionID: sessionID,
            environment: [:]
        )

        #expect(request.url == URL(string: "https://chatgpt.com/backend-api/codex/responses"))
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 120)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "account-123")
        #expect(request.value(forHTTPHeaderField: "originator") == "mimo")
        #expect(request.value(forHTTPHeaderField: "version") == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Mimo/1.2.3")
        #expect(request.value(forHTTPHeaderField: "session_id") == sessionID.uuidString.lowercased())
        #expect(request.value(forHTTPHeaderField: "OpenAI-Beta") == nil)

        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "gpt-5.6-sol")
        #expect(json["stream"] as? Bool == true)
    }

    @Test("omits empty account IDs without dropping Codex identity headers")
    func omitsEmptyAccountID() throws {
        let request = try ChatGPTResponsesTransport.makeRequest(
            body: ["stream": true],
            token: "access-token",
            accountId: "",
            appVersion: "2.0.0",
            sessionID: UUID(uuidString: "194AC4DC-E234-4153-BA13-A1D48323303F")!,
            environment: [:]
        )

        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
        #expect(request.value(forHTTPHeaderField: "originator") == "mimo")
        #expect(request.value(forHTTPHeaderField: "version") == nil)
    }

    @Test("creates a fresh session ID for every request")
    func createsFreshSessionIDs() throws {
        let first = try ChatGPTResponsesTransport.makeRequest(
            body: ["stream": true],
            token: "access-token",
            accountId: "account-123",
            appVersion: "1.0.0",
            environment: [:]
        )
        let second = try ChatGPTResponsesTransport.makeRequest(
            body: ["stream": true],
            token: "access-token",
            accountId: "account-123",
            appVersion: "1.0.0",
            environment: [:]
        )

        let firstSessionID = try #require(first.value(forHTTPHeaderField: "session_id"))
        let secondSessionID = try #require(second.value(forHTTPHeaderField: "session_id"))
        #expect(UUID(uuidString: firstSessionID) != nil)
        #expect(UUID(uuidString: secondSessionID) != nil)
        #expect(firstSessionID != secondSessionID)
    }

    @Test("uses Codex by default and only selects WHAM for the explicit override")
    func selectsBackendFromEnvironment() {
        #expect(ChatGPTResponsesTransport.selectedBackend(environment: [:]) == .codex)
        #expect(ChatGPTResponsesTransport.selectedBackend(environment: [
            ChatGPTResponsesTransport.environmentKey: "codex",
        ]) == .codex)
        #expect(ChatGPTResponsesTransport.selectedBackend(environment: [
            ChatGPTResponsesTransport.environmentKey: "unknown",
        ]) == .codex)
        #expect(ChatGPTResponsesTransport.selectedBackend(environment: [
            ChatGPTResponsesTransport.environmentKey: " WHAM ",
        ]) == .wham)
    }

    @Test("builds the legacy WHAM request only for the emergency override")
    func buildsWhamOverrideRequest() throws {
        let request = try ChatGPTResponsesTransport.makeRequest(
            body: ["model": "gpt-5.4", "stream": true],
            token: "access-token",
            accountId: "account-123",
            appVersion: "1.2.3",
            sessionID: UUID(uuidString: "6482D44E-BE26-4B98-B0B7-B5D5281C713B")!,
            environment: [ChatGPTResponsesTransport.environmentKey: "wham"]
        )

        #expect(request.url == URL(string: "https://chatgpt.com/backend-api/wham/responses"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "account-123")
        #expect(request.value(forHTTPHeaderField: "originator") == nil)
        #expect(request.value(forHTTPHeaderField: "version") == nil)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == nil)
        #expect(request.value(forHTTPHeaderField: "session_id") == nil)
    }
}
