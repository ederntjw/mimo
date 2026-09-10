import FluidAudio
import Foundation
import MuesliCore

protocol FluidAudioModelRuntime: Sendable {
    func transcribe(wavURL: URL, language: String?) async throws -> ASRResult
}

private struct LoadedFluidAudioRuntime: FluidAudioModelRuntime {
    let manager: AsrManager

    func transcribe(wavURL: URL, language: String?) async throws -> ASRResult {
        let languageHint = language.flatMap(Language.init(rawValue:))
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        return try await manager.transcribe(wavURL, decoderState: &decoderState, language: languageHint)
    }
}

/// Native Swift transcription backend using FluidAudio's Parakeet TDT model
/// running on Apple's Neural Engine (ANE) via CoreML.
actor FluidAudioTranscriber {
    typealias ModelLoader = @Sendable (AsrModelVersion, ((Double, String?) -> Void)?, ModelDownloadProgressHandler?) async throws -> any FluidAudioModelRuntime

    private var asrManager: (any FluidAudioModelRuntime)?
    private var loadedVersion: AsrModelVersion?
    private let operationGate: InferenceGate
    private let modelLoader: ModelLoader

    init(modelLoader: ModelLoader? = nil, operationGate: InferenceGate = InferenceGate()) {
        self.modelLoader = modelLoader ?? Self.loadRuntime
        self.operationGate = operationGate
    }

    enum TranscriberError: Error, LocalizedError {
        case notLoaded

        var errorDescription: String? {
            switch self {
            case .notLoaded:
                return "FluidAudio models not loaded. Call loadModels() first."
            }
        }
    }

    /// Downloads models (if needed) and initializes the ASR manager.
    /// - Parameter version: .v3 for multilingual (25 langs), .v2 for English-only
    func loadModels(
        version: AsrModelVersion = .v3,
        progress: ((Double, String?) -> Void)? = nil,
        progressSnapshot: ModelDownloadProgressHandler? = nil
    ) async throws {
        try await operationGate.acquire()
        do {
            try await loadSelectedModel(version: version, progress: progress, progressSnapshot: progressSnapshot)
            await operationGate.release()
        } catch {
            await operationGate.release()
            throw error
        }
    }

    private func loadSelectedModel(
        version: AsrModelVersion,
        progress: ((Double, String?) -> Void)? = nil,
        progressSnapshot: ModelDownloadProgressHandler? = nil
    ) async throws {
        try Task.checkCancellation()
        if loadedVersion == version, asrManager != nil { return }
        fputs("[fluidaudio] downloading/loading models (version: \(version))...\n", stderr)
        let runtime = try await modelLoader(version, progress, progressSnapshot)
        try Task.checkCancellation()
        asrManager = runtime
        loadedVersion = version
        fputs("[fluidaudio] models ready: \(version)\n", stderr)
    }

    private static func loadRuntime(
        version: AsrModelVersion,
        progress: ((Double, String?) -> Void)?,
        progressSnapshot: ModelDownloadProgressHandler?
    ) async throws -> any FluidAudioModelRuntime {
        let plan = version == .v2 ? ManagedASRModelPlans.parakeetV2() : ManagedASRModelPlans.parakeetV3()
        let manager = try await ManagedASRModelDownloader.loadValidated(
            plan,
            progress: progress,
            progressSnapshot: progressSnapshot
        ) { modelDirectory in
            let preparing = ModelDownloadProgress.preparing(
                modelID: plan.modelID,
                message: "Loading Parakeet into Core ML..."
            )
            progress?(0.95, preparing.message)
            progressSnapshot?(preparing)
            let models = try await AsrModels.load(from: modelDirectory, version: version)
            let manager = AsrManager(config: .default)
            try await manager.loadModels(models)
            return manager
        }
        let preparing = ModelDownloadProgress.preparing(
            modelID: plan.modelID,
            message: "Loading Parakeet into Core ML..."
        )
        progress?(1, nil)
        progressSnapshot?(preparing.replacing(phase: .ready, message: "Model ready"))
        return LoadedFluidAudioRuntime(manager: manager)
    }

    /// Transcribe a WAV file URL directly.
    /// `language` is an optional ISO code enabling FluidAudio's script-level
    /// token filter on the v3 joint decoder (v2 ignores the hint; nil = auto).
    func transcribe(wavURL: URL, version: AsrModelVersion, language: String? = nil) async throws -> ASRResult {
        try await operationGate.acquire()
        do {
            try await loadSelectedModel(version: version)
            guard let asrManager else { throw TranscriberError.notLoaded }
            let result = try await asrManager.transcribe(wavURL: wavURL, language: language)
            await operationGate.release()
            return result
        } catch {
            await operationGate.release()
            throw error
        }
    }

    func shutdown() async {
        guard (try? await operationGate.acquire()) != nil else { return }
        asrManager = nil
        loadedVersion = nil
        await operationGate.release()
    }

    func shutdown(ifLoadedVersion version: AsrModelVersion) async {
        guard (try? await operationGate.acquire()) != nil else { return }
        guard FluidAudioUnloadPolicy.shouldUnload(
            loadedVersion: loadedVersion,
            deletingVersion: version
        ) else {
            await operationGate.release()
            return
        }
        asrManager = nil
        loadedVersion = nil
        await operationGate.release()
    }
}

enum FluidAudioUnloadPolicy {
    static func shouldUnload(
        loadedVersion: AsrModelVersion?,
        deletingVersion: AsrModelVersion
    ) -> Bool {
        loadedVersion == deletingVersion
    }
}
