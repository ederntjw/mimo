import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Meeting transcription plan")
struct MeetingTranscriptionPlanTests {
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
