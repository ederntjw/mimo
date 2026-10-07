import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Dictation cleanup strength")
struct DictationCleanupStrengthTests {
    @Test("legacy cleanup toggle migrates without opting a user into cleanup", arguments: [false, true])
    func migratesLegacyToggle(enabled: Bool) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "uses_simple_bilingual_setup": true,
            "enable_post_processor": enabled,
        ])
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(config.resolvedDictationCleanupStrength == (enabled ? .light : .none))
        #expect(config.enablePostProcessor == enabled)
    }

    @Test("simple strength survives save and controls cleanup", arguments: DictationCleanupStrength.allCases)
    func roundTrips(strength: DictationCleanupStrength) throws {
        var config = AppConfig()
        config.usesSimpleBilingualSetup = true
        config.setDictationCleanupStrength(strength)
        config.applySimpleBilingualSetupIfNeeded()
        let restored = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(restored.resolvedDictationCleanupStrength == strength)
        #expect(restored.enablePostProcessor == (strength != .none))
        #expect(restored.postProcessorChatGPTModel == SimpleBilingualSetup.writingModel)
    }

    @Test("strength overrides simple cleanup prompts but preserves advanced custom prompts")
    func promptSelection() {
        var config = AppConfig()
        let custom = "Custom legacy cleanup instructions"
        config.dictationCleanupStrength = "medium"
        #expect(config.dictationCleanupSystemPrompt(configuredPrompt: custom) == custom)
        config.applySimpleBilingualSetupIfNeeded()
        #expect(!config.enablePostProcessor)
        config.usesSimpleBilingualSetup = true
        config.applySimpleBilingualSetupIfNeeded()
        #expect(config.dictationCleanupSystemPrompt(configuredPrompt: custom) == DictationCleanupStrength.medium.systemPrompt)
        config.setDictationCleanupStrength(.light)
        #expect(config.dictationCleanupSystemPrompt(configuredPrompt: custom) == DictationCleanupStrength.light.systemPrompt)
    }

    @Test("None returns the exact bilingual input even when a hosted caller asks for cleanup")
    func noneBypassesHostedRequest() async throws {
        var config = AppConfig()
        config.usesSimpleBilingualSetup = true
        config.setDictationCleanupStrength(.none)
        let input = "Um, 预算是五千美元。 I kind of agree — maybe Friday?"
        let result = try await TranscriptCleanupClient.clean(
            text: input, systemPrompt: "Translate everything", appContext: nil,
            backend: .hosted(.customLLM), config: config
        )
        #expect(result.rawOutput == input)
        #expect(result.cleanedOutput == input)
    }
}
