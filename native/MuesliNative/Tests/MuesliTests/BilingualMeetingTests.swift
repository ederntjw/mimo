import Foundation
import AVFoundation
import Testing
import WhisperKit
@testable import MuesliNativeApp

@Suite("Chinese and English meetings")
struct BilingualMeetingTests {
    @Test("bilingual meeting setting persists independently from pinned dictation languages")
    func configRoundTrip() throws {
        var config = AppConfig()
        config.meetingChineseEnglishBilingual = true
        config.whisperLanguage = WhisperKitLanguage.english.rawValue
        config.nemotron35Language = Nemotron35Language.chinese.rawValue
        config.meetingLiveCaptionBackend = MeetingLiveCaptionBackend.parakeetRealtimeEOU.rawValue

        let encoded = try JSONEncoder().encode(config)
        let restored = try JSONDecoder().decode(AppConfig.self, from: encoded)
        #expect(restored.meetingChineseEnglishBilingual)
        #expect(restored.resolvedMeetingWhisperLanguage == .auto)
        #expect(restored.resolvedMeetingNemotron35Language == .auto)
        #expect(restored.resolvedMeetingLiveCaptionBackend == .nemotron35)
        #expect(restored.resolvedWhisperLanguage == .english)
        #expect(restored.resolvedNemotron35Language == .chinese)
    }

    @Test("older configurations keep their explicit language choices")
    func legacyConfig() throws {
        let data = Data(#"{"whisper_language":"zh","nemotron35_language":"en","meeting_final_pass_enabled":false}"#.utf8)
        let config = try JSONDecoder().decode(AppConfig.self, from: data)
        #expect(!config.meetingChineseEnglishBilingual)
        #expect(config.resolvedMeetingWhisperLanguage == .chinese)
        #expect(config.resolvedMeetingNemotron35Language == config.resolvedNemotron35Language)
        #expect(config.resolvedMeetingLiveCaptionBackend == .parakeetRealtimeEOU)
    }

    @Test("bilingual mode cannot select English-only or unsupported multilingual engines")
    func supportedModels() {
        for model in [BackendOption.parakeetUnified, .parakeetMultilingual, .parakeetEnglish,
                      .appleSpeechAnalyzer, .nemotron35Multilingual, .whisperTinyEnglish, .whisperSmallEnglish, .whisperMediumEnglish] {
            #expect(!model.supportsChineseEnglishMeetingTranscription)
            #expect(BackendOption.resolvedChineseEnglishMeetingBackend(
                configured: model, availableOptions: [model]
            ) == nil)
        }
        for model in [BackendOption.senseVoiceSmall, .whisperLargeTurbo, .whisperSmall, .whisperTiny] {
            #expect(model.supportsChineseEnglishMeetingTranscription)
            #expect(model.supportsMeetingTranscription)
            #expect(model.supportsLiveMeetingTranscription)
        }
    }

    @Test("availability fallback selects Chinese-capable models and preserves an explicit safe choice")
    func availabilityFallback() {
        #expect(BackendOption.resolvedChineseEnglishMeetingBackend(
            configured: .parakeetUnified, availableOptions: [.senseVoiceSmall, .whisperLargeTurbo]
        ) == .senseVoiceSmall)
        #expect(BackendOption.resolvedChineseEnglishMeetingBackend(
            configured: .whisperLargeTurbo, availableOptions: [.senseVoiceSmall, .whisperLargeTurbo]
        ) == .whisperLargeTurbo)
        let available: [BackendOption] = [.parakeetUnified, .whisperLargeTurbo, .nemotron35Multilingual]
        #expect(BackendOption.resolvedChineseEnglishMeetingBackend(
            configured: .parakeetUnified, availableOptions: available
        ) == .whisperLargeTurbo)
        #expect(BackendOption.resolvedChineseEnglishMeetingBackend(
            configured: .whisperLargeTurbo, availableOptions: available
        ) == .whisperLargeTurbo)
        #expect(BackendOption.resolvedChineseEnglishMeetingBackend(
            configured: .nemotron35Multilingual, availableOptions: [.parakeetUnified, .whisperLargeTurbo]
        ) == .whisperLargeTurbo)
        #expect(BackendOption.resolvedChineseEnglishMeetingBackend(
            configured: .nemotron35Multilingual, availableOptions: [.parakeetUnified, .nemotron35Multilingual]
        ) == nil)
    }

    @Test("Live Meeting uses the same bilingual safety policy as recorded meetings")
    func liveMeetingRouting() {
        #expect(BackendOption.resolvedLiveMeetingTranscriptionBackend(
            configured: .parakeetUnified,
            availableOptions: [.parakeetUnified, .whisperLargeTurbo],
            chineseEnglishBilingual: true
        ) == .whisperLargeTurbo)
        #expect(BackendOption.resolvedLiveMeetingTranscriptionBackend(
            configured: .parakeetUnified,
            availableOptions: [.parakeetUnified, .appleSpeechAnalyzer],
            chineseEnglishBilingual: true
        ) == nil)
    }

    @Test("Whisper bilingual chunks detect language and transcribe rather than translate")
    func whisperDecoding() {
        var config = AppConfig()
        config.meetingChineseEnglishBilingual = true
        config.whisperLanguage = "en"
        let options = WhisperKitTranscriber.makeDecodeOptions(
            language: config.resolvedMeetingWhisperLanguage,
            modelName: BackendOption.whisperLargeTurbo.model
        )
        #expect(options.detectLanguage)
        #expect(options.language == nil)
        #expect(options.task == .transcribe)
    }

    @Test("fast live decoding keeps code-switching enabled without retrying the same chunk")
    func fastWhisperDecoding() {
        for model in [BackendOption.whisperLargeTurbo, .whisperSmall, .whisperTiny] {
            let live = WhisperKitTranscriber.makeDecodeOptions(
                language: .auto, modelName: model.model, preferLowLatency: true
            )
            #expect(live.detectLanguage)
            #expect(live.language == nil)
            #expect(live.task == .transcribe)
            #expect(live.temperatureFallbackCount == 0)
            #expect(live.withoutTimestamps)
            let full = WhisperKitTranscriber.makeDecodeOptions(language: .auto, modelName: model.model)
            #expect(full.temperatureFallbackCount > live.temperatureFallbackCount)
        }
        #expect(StreamingVadController.ChunkTiming.fastBilingual.maximum == 5)
        #expect(StreamingVadController.ChunkTiming.fastBilingual.minimum == 1.5)
    }

    @Test("native meeting engines preserve the bilingual audio fixture", .enabled(if: ProcessInfo.processInfo.environment["MIMO_BILINGUAL_AUDIO_SMOKE_PATH"] != nil))
    func nativeEngineAudioSmoke() async throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["MIMO_BILINGUAL_AUDIO_SMOKE_PATH"])
        let backend: BackendOption
        switch environment["MIMO_BILINGUAL_AUDIO_SMOKE_MODEL"] {
        case "sensevoice": backend = .senseVoiceSmall
        case "nemotron35": backend = .nemotron35Multilingual
        case "whisper-tiny": backend = .whisperTiny
        case "whisper-small": backend = .whisperSmall
        default: backend = .whisperLargeTurbo
        }
        #expect(backend.isDownloaded)
        let coordinator = TranscriptionCoordinator()
        var config = AppConfig()
        config.meetingChineseEnglishBilingual = true
        config.whisperLanguage = "en"
        config.nemotron35Language = "en"
        await coordinator.setNemotron35PromptId(config.resolvedNemotron35Language.promptId)
        // Exercise switching to SenseVoice before its background preload starts.
        if backend != .senseVoiceSmall {
            try await coordinator.preloadRequired(backend: backend, includeMeetingHelpers: false)
        }
        let url = URL(fileURLWithPath: path)
        let chunk = try await coordinator.transcribeMeetingChunk(
            at: url,
            backend: backend,
            whisperLanguage: config.resolvedMeetingWhisperLanguage,
            nemotron35Language: config.resolvedMeetingNemotron35Language
        )
        let full = try await coordinator.transcribeMeeting(
            at: url,
            backend: backend,
            whisperLanguage: config.resolvedMeetingWhisperLanguage,
            nemotron35Language: config.resolvedMeetingNemotron35Language
        )
        if let outputPath = environment["MIMO_BILINGUAL_AUDIO_SMOKE_OUTPUT"] {
            try "Chunk: \(chunk.text)\n\nFull: \(full.text)\n".write(
                toFile: outputPath, atomically: true, encoding: .utf8
            )
        }
        for text in [chunk.text, full.text] {
            let lower = text.lowercased()
            #expect(lower.contains("friday"))
            #expect(lower.contains("thursday"))
            #expect(lower.contains("feedback"))
            #expect(text.contains("发布"))
            #expect(text.contains("测试"))
            #expect(lower.replacingOccurrences(of: ",", with: "").contains("5000") || text.contains("五千"))
        }
    }

    @Test("SenseVoice live chunks feed a separate full-recording Whisper pass and review", .enabled(if: ProcessInfo.processInfo.environment["MIMO_REVIEWED_MEETING_SMOKE_PATH"] != nil))
    func reviewedMeetingAudioSmoke() async throws {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["MIMO_REVIEWED_MEETING_SMOKE_PATH"])
        let directory = try #require(environment["MIMO_BILINGUAL_LIVE_CHUNKS_DIR"])
        let finalBackend: BackendOption = environment["MIMO_REVIEWED_MEETING_SMOKE_MODEL"] == "large-v3" ? .whisperLargeV3 : .whisperLargeTurbo
        #expect(BackendOption.senseVoiceSmall.isDownloaded)
        #expect(finalBackend.isDownloaded)
        let coordinator = TranscriptionCoordinator()
        try await coordinator.preloadRequired(backend: .senseVoiceSmall, includeMeetingHelpers: false)
        let chunks = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: directory), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!chunks.isEmpty)
        var live: [SpeechSegment] = []
        var offset: Double = 0
        var chunkSeconds: [Double] = []
        for chunk in chunks {
            let audio = try AVAudioFile(forReading: chunk)
            let duration = Double(audio.length) / audio.processingFormat.sampleRate
            let started = Date()
            let result = try await coordinator.transcribeMeetingChunk(at: chunk, backend: .senseVoiceSmall, whisperLanguage: .auto)
            chunkSeconds.append(Date().timeIntervalSince(started))
            if !result.text.isEmpty { live.append(.init(start: offset, end: offset + duration, text: result.text)) }
            offset += duration
        }
        let url = URL(fileURLWithPath: path)
        let audio = try AVAudioFile(forReading: url)
        let duration = Double(audio.length) / audio.processingFormat.sampleRate
        let finalStarted = Date()
        let outcome = try await MeetingFinalTranscription.run(
            microphone: .init(url: url, duration: duration, liveSegments: live),
            system: .init(url: nil, duration: 0, liveSegments: [])
        ) { url in
            try await coordinator.transcribeMeeting(at: url, backend: finalBackend, whisperLanguage: .auto)
        }
        let finalSeconds = Date().timeIntervalSince(finalStarted)
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let finalText = outcome.micSegments.map(\.text).joined(separator: " ")
        let review = MeetingTranscriptReview.compare(
            liveTranscript: MeetingTranscriptReview.timestampedTranscript(microphone: live, system: [], meetingStart: startedAt),
            finalTranscript: MeetingTranscriptReview.timestampedTranscript(microphone: outcome.micSegments, system: [], meetingStart: startedAt),
            finalPassCompleted: outcome.completed, additionalWarnings: outcome.warnings
        )
        if let output = environment["MIMO_REVIEWED_MEETING_SMOKE_OUTPUT"] {
            let data = try JSONSerialization.data(withJSONObject: [
                "liveModel": "sensevoice-small", "finalModel": finalBackend.model,
                "liveChunkSeconds": chunkSeconds, "finalSeconds": finalSeconds,
                "liveText": live.map(\.text).joined(separator: " "), "finalText": finalText,
                "completed": outcome.completed, "warnings": outcome.warnings, "review": review.notesMarkdown,
                "finalSegments": outcome.micSegments.map { ["start": $0.start, "end": $0.end, "text": $0.text] as [String: Any] }
            ], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: output))
        }
        #expect(outcome.completed)
        #expect(outcome.warnings.isEmpty)
        #expect(finalText.contains("发布") || finalText.contains("發布"))
        #expect(finalText.lowercased().contains("friday"))
        #expect(finalText.lowercased().contains("thursday"))
        #expect(finalText.lowercased().contains("feedback"))
        #expect(finalText.replacingOccurrences(of: ",", with: "").contains("5000") || finalText.contains("五千"))
        #expect(review.finalPassCompleted)
        #expect(!finalText.contains("<|"))
        #expect(!review.notesMarkdown.contains("<|"))
    }

    @Test("short live chunks preserve Chinese and English", .enabled(if: ProcessInfo.processInfo.environment["MIMO_BILINGUAL_LIVE_CHUNKS_DIR"] != nil))
    func fastLiveChunkSmoke() async throws {
        let environment = ProcessInfo.processInfo.environment
        let directory = try #require(environment["MIMO_BILINGUAL_LIVE_CHUNKS_DIR"])
        let backend: BackendOption
        switch environment["MIMO_BILINGUAL_AUDIO_SMOKE_MODEL"] {
        case "sensevoice": backend = .senseVoiceSmall
        case "whisper-tiny": backend = .whisperTiny
        default: backend = .whisperLargeTurbo
        }
        let coordinator = TranscriptionCoordinator()
        try await coordinator.preloadRequired(backend: backend, includeMeetingHelpers: false)
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: directory), includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "wav" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(!urls.isEmpty)
        var text = ""
        var measurements: [[String: Any]] = []
        for url in urls {
            let start = ContinuousClock.now
            let result = try await coordinator.transcribeMeetingChunk(
                at: url, backend: backend, whisperLanguage: .auto
            )
            let elapsed = start.duration(to: .now)
            let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            measurements.append(["file": url.lastPathComponent, "seconds": seconds, "text": result.text])
            text += " " + result.text
        }
        if let outputPath = environment["MIMO_BILINGUAL_AUDIO_SMOKE_OUTPUT"] {
            let data = try JSONSerialization.data(withJSONObject: measurements, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: outputPath))
        }
        #expect(text.contains("发布") || text.contains("發布"))
        #expect(text.lowercased().contains("friday"))
        #expect(text.lowercased().contains("thursday"))
    }

}
