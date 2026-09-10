import Foundation
import WhisperKit
import MuesliCore

protocol WhisperKitModelRuntime: Sendable {
    func transcribe(wavURL: URL, decodeOptions: DecodingOptions) async throws -> String
    func transcribeResult(wavURL: URL, decodeOptions: DecodingOptions) async throws -> SpeechTranscriptionResult
    func warmup() async throws
}

extension WhisperKitModelRuntime {
    func transcribeResult(wavURL: URL, decodeOptions: DecodingOptions) async throws -> SpeechTranscriptionResult {
        let text = try await transcribe(wavURL: wavURL, decodeOptions: decodeOptions)
        return SpeechTranscriptionResult(text: text, segments: [])
    }
}

// WhisperKit is mutable and does not declare Sendable. Its only owner is a
// transcriber whose operation gate serializes loading, warmup, and inference.
private struct LoadedWhisperKitRuntime: WhisperKitModelRuntime, @unchecked Sendable {
    let model: WhisperKit

    func transcribe(wavURL: URL, decodeOptions: DecodingOptions) async throws -> String {
        try await transcribeResult(wavURL: wavURL, decodeOptions: decodeOptions).text
    }

    func transcribeResult(wavURL: URL, decodeOptions: DecodingOptions) async throws -> SpeechTranscriptionResult {
        let results = try await model.transcribe(audioPath: wavURL.path, decodeOptions: decodeOptions)
        let text = results.map(\.text).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = results.flatMap(\.segments).compactMap { segment -> SpeechSegment? in
            let content = WhisperKitTranscriber.visibleSegmentText(segment.text)
            guard !content.isEmpty else { return nil }
            return SpeechSegment(start: TimeInterval(segment.start), end: TimeInterval(segment.end), text: content)
        }
        return SpeechTranscriptionResult(text: text, segments: segments)
    }

    func warmup() async throws {
        let silence = [Float](repeating: 0, count: 16000)
        let _: [TranscriptionResult] = try await model.transcribe(audioArray: silence)
    }
}

/// Native Swift transcription backend using WhisperKit (CoreML on ANE/GPU).
actor WhisperKitTranscriber {
    typealias ModelLoader = @Sendable (String, ((Double, String?) -> Void)?, ModelDownloadProgressHandler?) async throws -> any WhisperKitModelRuntime

    private var whisperKit: (any WhisperKitModelRuntime)?
    private var loadedModel: String?
    private let operationGate: InferenceGate
    private let modelLoader: ModelLoader

    init(modelLoader: ModelLoader? = nil, operationGate: InferenceGate = InferenceGate()) {
        self.modelLoader = modelLoader ?? Self.loadRuntime
        self.operationGate = operationGate
    }

    /// WhisperKit's timestamped segment text includes decoder control tokens,
    /// even when its aggregate transcript is clean. Never persist these as speech.
    nonisolated static func visibleSegmentText(_ text: String) -> String {
        text.replacingOccurrences(of: #"<\|[^|>]+\|>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum TranscriberError: Error, LocalizedError {
        case notLoaded
        case transcriptionFailed(String)

        var errorDescription: String? {
            switch self {
            case .notLoaded: return "WhisperKit model not loaded."
            case .transcriptionFailed(let msg): return "Transcription failed: \(msg)"
            }
        }
    }

    /// Load a WhisperKit CoreML model. Downloads from HuggingFace if not cached.
    func loadModel(
        modelName: String,
        progress: ((Double, String?) -> Void)? = nil,
        progressSnapshot: ModelDownloadProgressHandler? = nil
    ) async throws {
        try await operationGate.acquire()
        do {
            try await loadSelectedModel(modelName: modelName, progress: progress, progressSnapshot: progressSnapshot)
            await operationGate.release()
        } catch {
            await operationGate.release()
            throw error
        }
    }

    private func loadSelectedModel(
        modelName: String,
        progress: ((Double, String?) -> Void)? = nil,
        progressSnapshot: ModelDownloadProgressHandler? = nil
    ) async throws {
        try Task.checkCancellation()
        if loadedModel == modelName, whisperKit != nil { return }
        fputs("[whisperkit] loading model: \(modelName)...\n", stderr)
        let runtime = try await modelLoader(modelName, progress, progressSnapshot)
        try Task.checkCancellation()
        whisperKit = runtime
        loadedModel = modelName
        fputs("[whisperkit] model loaded: \(modelName)\n", stderr)
    }

    private static func loadRuntime(
        modelName: String,
        progress: ((Double, String?) -> Void)?,
        progressSnapshot: ModelDownloadProgressHandler?
    ) async throws -> any WhisperKitModelRuntime {
        let plan = ManagedASRModelPlans.whisperKit(modelName: modelName)
        let loadedWhisperKit = try await ManagedASRModelDownloader.loadValidated(
            plan,
            progress: progress,
            progressSnapshot: progressSnapshot
        ) { modelFolder in
            let preparing = ModelDownloadProgress.preparing(
                modelID: plan.modelID,
                message: "Loading WhisperKit into Core ML..."
            )
            progress?(0.95, preparing.message)
            progressSnapshot?(preparing)

            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                )
            )
            return try await WhisperKit(config)
        }

        return LoadedWhisperKitRuntime(model: loadedWhisperKit)
    }

    /// Transcribe a 16kHz mono WAV file.
    /// - Parameter language: `.auto` enables WhisperKit language detection; otherwise pins that ISO code.
    ///   Ignored for English-only `.en` models, which keep default English decoding.
    func transcribe(
        wavURL: URL,
        modelName: String,
        language: WhisperKitLanguage = .defaultLanguage,
        preferLowLatency: Bool = false
    ) async throws -> (text: String, segments: [SpeechSegment], processingTime: Double) {
        // Actor isolation alone permits preload to re-enter at each await.
        // Hold one operation across model selection and use of the mutable runtime.
        try await operationGate.acquire()
        do {
            try await loadSelectedModel(modelName: modelName)
            guard let whisperKit else { throw TranscriberError.notLoaded }
            let start = CFAbsoluteTimeGetCurrent()
            let decodeOptions = Self.makeDecodeOptions(
                language: language, modelName: modelName, preferLowLatency: preferLowLatency
            )
            let result = try await whisperKit.transcribeResult(wavURL: wavURL, decodeOptions: decodeOptions)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            await operationGate.release()
            return (text: result.text, segments: result.segments, processingTime: elapsed)
        } catch {
            await operationGate.release()
            throw error
        }
    }

    /// Build WhisperKit decode options for the loaded model.
    /// English-only checkpoints ignore language preference and keep default English decoding.
    static func makeDecodeOptions(
        language: WhisperKitLanguage,
        modelName: String,
        preferLowLatency: Bool = false
    ) -> DecodingOptions {
        let effective = WhisperKitLanguage.preferenceForLoadedModel(language, modelName: modelName)
        var options: DecodingOptions
        switch effective {
        case .auto?:
            // Default DecodingOptions leaves detectLanguage false when usePrefillPrompt is true,
            // which silently forces English. Request detection explicitly for multilingual models.
            options = DecodingOptions(detectLanguage: true)
        case let language?:
            options = DecodingOptions(language: language.rawValue)
        case nil:
            options = DecodingOptions()
        }
        if preferLowLatency {
            // Live chunks already carry their recording times. Avoid extra
            // timestamp tokens and repeated temperature retries before showing text.
            options.withoutTimestamps = true
            options.wordTimestamps = false
            options.temperatureFallbackCount = 0
        }
        return options
    }

    /// Run a short silent transcription to trigger CoreML compilation.
    /// First-run compilation takes 10-30s; subsequent loads are instant.
    func warmup(modelName: String) async throws {
        try await operationGate.acquire()
        do {
            try await loadSelectedModel(modelName: modelName)
            guard let whisperKit else { throw TranscriberError.notLoaded }
            let start = CFAbsoluteTimeGetCurrent()
            try await whisperKit.warmup()
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            fputs("[whisperkit] warmup transcription took \(String(format: "%.1f", elapsed))s\n", stderr)
            await operationGate.release()
        } catch {
            await operationGate.release()
            throw error
        }
    }

    func shutdown() async {
        // Cleanup must not free a model still being used by an awaited decode.
        // A cancelled caller leaves cleanup to the next explicit shutdown.
        guard (try? await operationGate.acquire()) != nil else { return }
        whisperKit = nil
        loadedModel = nil
        await operationGate.release()
    }

    // MARK: - Model Storage

    /// WhisperKit stores models under ~/Documents/huggingface/models/argmaxinc/whisperkit-coreml/.
    /// Each model variant is a direct subdirectory (e.g. openai_whisper-small/).
    static func isModelDownloaded(_ modelName: String) -> Bool {
        ManagedASRModelPlans.whisperKit(modelName: modelName).isAvailableLocally()
    }

    /// Delete cached model files for a WhisperKit model variant.
    static func deleteModel(_ modelName: String) {
        try? ManagedASRModelPlans.whisperKit(modelName: modelName).delete()
    }
}
