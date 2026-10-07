import Foundation
import Testing
import MuesliCore
@testable import MuesliNativeApp

@Suite("Meeting transcription plan")
struct MeetingTranscriptionPlanTests {
    @Test("subscription cleanup retains bilingual facts at both strengths", .enabled(if: ProcessInfo.processInfo.environment["MIMO_FLOW_CLEANUP_SMOKE"] == "1"))
    func subscriptionCleanupSmoke() async throws {
        let data = try Data(contentsOf: AppIdentity.supportDirectoryURL.appendingPathComponent("config.json"))
        var config = try JSONDecoder().decode(AppConfig.self, from: data)
        config.usesSimpleBilingualSetup = true
        config.applySimpleBilingualSetupIfNeeded()
        let input = "嗯，我们周五发布，预算是5000美元。Please ask Alex to finish testing by Thursday."
        var outputs: [String: String] = [:]
        for strength in [DictationCleanupStrength.light, .medium] {
            config.setDictationCleanupStrength(strength)
            let result = try await TranscriptCleanupClient.clean(
                text: input,
                systemPrompt: config.dictationCleanupSystemPrompt(configuredPrompt: ""),
                appContext: nil,
                backend: .hosted(.chatGPT),
                config: config
            )
            #expect(result.cleanedOutput.contains("Alex"))
            #expect(result.cleanedOutput.lowercased().contains("thursday"))
            #expect(result.cleanedOutput.contains("发布"))
            #expect(result.cleanedOutput.replacingOccurrences(of: ",", with: "").contains("5000"))
            outputs[strength.rawValue] = result.cleanedOutput
        }
        if let path = ProcessInfo.processInfo.environment["MIMO_FLOW_CLEANUP_SMOKE_OUTPUT"] {
            try JSONEncoder().encode(outputs).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }

    @Test("simple bilingual setup pins the full model in both passes and never requires SenseVoice")
    func simpleBilingualPlan() {
        var config = AppConfig()
        config.usesSimpleBilingualSetup = true
        config.applySimpleBilingualSetupIfNeeded()
        let plan = MeetingTranscriptionPlan(config: config, singlePassBackend: .senseVoiceSmall)
        #expect(plan.liveBackend == .whisperLargeV3)
        #expect(plan.finalBackend == .whisperLargeV3)
        #expect(plan.missingModels(from: [.senseVoiceSmall, .whisperLargeTurbo]) == [.whisperLargeV3])
        #expect(plan.missingModels(from: [.whisperLargeV3]).isEmpty)
        #expect(!config.meetingLiveStreamingPartialsEnabled)
    }

    @Test("simple setup normalizes conflicting saved engines and languages without changing personal settings")
    func simpleBilingualPersistence() throws {
        let json = #"{"uses_simple_bilingual_setup":true,"stt_backend":"parakeet-unified","stt_model":"obsolete","whisper_language":"en","meeting_transcription_backend":"sensevoice","meeting_final_transcription_model":"tiny","enable_live_streaming_partials":true,"meeting_summary_backend":"ollama","post_processor_backend":"local","enable_post_processor":false,"user_name":"Test User","dark_mode":false}"#
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(json.utf8))
        #expect(config.sttBackend == "whisper")
        #expect(config.sttModel == BackendOption.whisperLargeV3.model)
        #expect(config.meetingTranscriptionModel == config.sttModel)
        #expect(config.meetingFinalTranscriptionModel == config.sttModel)
        #expect(config.resolvedWhisperLanguage == .auto)
        #expect(config.resolvedMeetingWhisperLanguage == .auto)
        #expect(config.meetingChineseEnglishBilingual)
        #expect(config.meetingSummaryBackend == "chatgpt")
        #expect(config.chatGPTModel == SimpleBilingualSetup.writingModel)
        #expect(config.postProcessorChatGPTModel == config.chatGPTModel)
        #expect(config.quilModel == config.chatGPTModel)
        #expect(!config.enablePostProcessor)
        #expect(config.userName == "Test User")
        #expect(!config.darkMode)
        let restored = try JSONDecoder().decode(AppConfig.self, from: JSONEncoder().encode(config))
        #expect(restored.usesSimpleBilingualSetup)
        #expect(restored.sttModel == config.sttModel)
        #expect(restored.meetingFinalTranscriptionModel == config.meetingFinalTranscriptionModel)
    }

    @Test("legacy setups retain explicit provider choices until simple setup is enabled")
    func legacySetupIsUnchanged() {
        var config = AppConfig()
        config.sttBackend = BackendOption.senseVoiceSmall.backend
        config.sttModel = BackendOption.senseVoiceSmall.model
        config.whisperLanguage = "zh"
        config.meetingSummaryBackend = "ollama"
        config.applySimpleBilingualSetupIfNeeded()
        #expect(!config.usesSimpleBilingualSetup)
        #expect(config.sttModel == BackendOption.senseVoiceSmall.model)
        #expect(config.whisperLanguage == "zh")
        #expect(config.meetingSummaryBackend == "ollama")
    }

    @Test("new meetings use exactly SenseVoice live and full Whisper Large V3 after stopping")
    func defaults() {
        let config = AppConfig()
        let plan = MeetingTranscriptionPlan(config: config, singlePassBackend: .parakeetUnified)
        #expect(config.meetingFinalPassEnabled)
        #expect(plan.liveBackend == .senseVoiceSmall)
        #expect(plan.finalBackend == .whisperLargeV3)
        #expect(plan.finalBackend?.model != BackendOption.whisperLargeTurbo.model)
        #expect(MeetingTranscriptionPlan.finalModels == [.whisperLargeV3, .whisperLargeTurbo])
    }

    @Test("selecting Turbo changes the actual final role while retaining SenseVoice live")
    func turboRole() {
        var config = AppConfig()
        config.meetingFinalTranscriptionModel = BackendOption.whisperLargeTurbo.model
        let plan = MeetingTranscriptionPlan(config: config, singlePassBackend: .whisperTinyEnglish)
        #expect(plan.liveBackend == .senseVoiceSmall)
        #expect(plan.finalBackend == .whisperLargeTurbo)
        #expect(config.resolvedMeetingFinalBackend == .whisperLargeTurbo)
    }

    @Test("missing final model is reported and never replaced by an installed model")
    func missingFinalModel() {
        let plan = MeetingTranscriptionPlan(config: AppConfig(), singlePassBackend: .whisperLargeTurbo)
        #expect(plan.missingModels(from: [.senseVoiceSmall, .whisperLargeTurbo, .parakeetUnified]) == [.whisperLargeV3])
        #expect(plan.finalBackend == .whisperLargeV3)
        #expect(plan.missingModels(from: [.senseVoiceSmall, .whisperLargeV3]).isEmpty)
    }

    @Test("missing SenseVoice is reported instead of substituting an English live model")
    func missingLiveModel() {
        let plan = MeetingTranscriptionPlan(config: AppConfig(), singlePassBackend: .parakeetUnified)
        #expect(plan.missingModels(from: [.parakeetUnified, .whisperLargeV3]) == [.senseVoiceSmall])
        #expect(plan.missingModels(from: []) == [.senseVoiceSmall, .whisperLargeV3])
        #expect(plan.liveBackend == .senseVoiceSmall)
    }

    @Test("disabling the workflow retains the selected single-pass backend and streaming preference")
    func disabledWorkflow() {
        var config = AppConfig()
        config.meetingFinalPassEnabled = false
        config.enableLiveStreamingPartials = true
        config.whisperLanguage = "zh"
        let plan = MeetingTranscriptionPlan(config: config, singlePassBackend: .whisperLargeTurbo)
        #expect(plan.liveBackend == .whisperLargeTurbo)
        #expect(plan.finalBackend == nil)
        #expect(plan.missingModels(from: [.whisperLargeTurbo]).isEmpty)
        #expect(config.enableLiveStreamingPartials)
        #expect(config.meetingLiveStreamingPartialsEnabled)
        #expect(config.resolvedMeetingWhisperLanguage == .chinese)
        config.enableLiveStreamingPartials = false
        #expect(!config.meetingLiveStreamingPartialsEnabled)
    }

    @Test("the two-pass workflow suspends optional previews without erasing their saved setting")
    func streamingPreferencePreserved() {
        var config = AppConfig()
        config.enableLiveStreamingPartials = true
        config.meetingFinalPassEnabled = true
        config.meetingLiveCaptionBackend = MeetingLiveCaptionBackend.parakeetRealtimeEOU.rawValue
        #expect(!config.meetingLiveStreamingPartialsEnabled)
        #expect(config.enableLiveStreamingPartials)
        config.meetingFinalPassEnabled = false
        #expect(config.meetingLiveStreamingPartialsEnabled)
        #expect(config.resolvedMeetingLiveCaptionBackend == .parakeetRealtimeEOU)
    }

    @Test("workflow settings encode and decode without changing model identifiers or dictation language")
    func configRoundTrip() throws {
        var config = AppConfig()
        config.meetingFinalPassEnabled = false
        config.meetingFinalTranscriptionModel = BackendOption.whisperLargeTurbo.model
        config.whisperLanguage = "en"
        let encoded = try JSONEncoder().encode(config)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["meeting_final_pass_enabled"] as? Bool == false)
        #expect(json["meeting_final_transcription_model"] as? String == BackendOption.whisperLargeTurbo.model)
        let restored = try JSONDecoder().decode(AppConfig.self, from: encoded)
        #expect(!restored.meetingFinalPassEnabled)
        #expect(restored.meetingFinalTranscriptionModel == BackendOption.whisperLargeTurbo.model)
        #expect(restored.resolvedMeetingFinalBackend == .whisperLargeTurbo)
        #expect(restored.resolvedWhisperLanguage == .english)
    }

    @Test("older configurations receive the new workflow defaults while explicit opt-out persists")
    func decodedDefaults() throws {
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"whisper_language":"zh","enable_live_streaming_partials":true}"#.utf8))
        #expect(config.meetingFinalPassEnabled)
        #expect(config.resolvedMeetingFinalBackend == .whisperLargeV3)
        #expect(config.resolvedWhisperLanguage == .chinese)
        #expect(config.resolvedMeetingWhisperLanguage == .auto)
        let optedOut = try JSONDecoder().decode(AppConfig.self, from: Data(#"{"meeting_final_pass_enabled":false,"whisper_language":"zh"}"#.utf8))
        #expect(!optedOut.meetingFinalPassEnabled)
        #expect(optedOut.resolvedMeetingWhisperLanguage == .chinese)
    }

    @Test("final pass keeps automatic bilingual detection independent of dictation language")
    func resolvedLanguage() {
        var config = AppConfig()
        config.whisperLanguage = "en"
        config.meetingChineseEnglishBilingual = false
        config.meetingFinalPassEnabled = true
        #expect(config.resolvedMeetingWhisperLanguage == .auto)
        #expect(config.resolvedWhisperLanguage == .english)
        config.meetingFinalPassEnabled = false
        #expect(config.resolvedMeetingWhisperLanguage == .english)
        config.meetingChineseEnglishBilingual = true
        #expect(config.resolvedMeetingWhisperLanguage == .auto)
    }

    @Test("an obsolete or invalid final model identifier resolves to the documented full V3 default")
    func invalidFinalSelection() {
        var config = AppConfig()
        config.meetingFinalTranscriptionModel = BackendOption.whisperTinyEnglish.model
        let plan = MeetingTranscriptionPlan(config: config, singlePassBackend: .parakeetUnified)
        #expect(plan.finalBackend == .whisperLargeV3)
        #expect(plan.missingModels(from: [.senseVoiceSmall, .whisperTinyEnglish]) == [.whisperLargeV3])
    }
}
