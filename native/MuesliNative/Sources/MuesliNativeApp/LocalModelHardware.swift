import Darwin
import Foundation

/// Ephemeral local facts for the model picker. No serial number, machine UUID,
/// account data, persistence, or telemetry is involved.
struct LocalModelHardwareSnapshot: Sendable, Equatable {
    let chipName: String
    let physicalMemoryBytes: UInt64
    let availableDiskBytes: UInt64?
    let macOSMajorVersion: Int
    let isAppleSilicon: Bool?

    static func current(
        modelCacheURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> LocalModelHardwareSnapshot {
        let chip = sysctlString("machdep.cpu.brand_string") ?? "Mac chip unavailable"
        let available = try? modelCacheURL.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            .volumeAvailableCapacity
        return LocalModelHardwareSnapshot(
            chipName: chip,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            availableDiskBytes: available.flatMap { $0 >= 0 ? UInt64($0) : nil },
            macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            // Unlike the executable's architecture, this also detects Apple
            // silicon when a process happens to be running under Rosetta.
            isAppleSilicon: sysctlInteger("hw.optional.arm64").map { $0 == 1 }
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var count = 0
        guard sysctlbyname(name, nil, &count, nil, 0) == 0, count > 1 else { return nil }
        var buffer = [CChar](repeating: 0, count: count)
        guard sysctlbyname(name, &buffer, &count, nil, 0) == 0 else { return nil }
        return String(validatingCString: buffer)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sysctlInteger(_ name: String) -> Int32? {
        var value: Int32 = 0
        var count = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &count, nil, 0) == 0 ? value : nil
    }
}

struct LocalModelHardwareAssessment: Sendable, Equatable {
    enum Level: Sendable, Equatable {
        case recommended
        case limited
        case notRecommended
        case insufficientStorage
    }

    let level: Level
    let label: String
    let detail: String
}

struct LocalModelHardwareRecommendation: Sendable, Equatable {
    let modelID: String
    let modelLabel: String
    let purpose: String
    let detail: String
}

struct LocalModelHardwareGuidance: Sendable, Equatable {
    /// Approximate artifact bytes (decimal MB/GB), not the memory requirement.
    /// Nil means assets are managed by macOS and their size varies by language.
    let downloadBytes: UInt64?
    let isBundled: Bool
    /// Total physical Mac memory, conventionally labeled GB by macOS (2^30 bytes).
    /// These are Mimo planning estimates including room for macOS and other apps,
    /// not manufacturer hardware minima or promises about live memory pressure.
    let minimumMemoryGB: Int
    let recommendedMemoryGB: Int
    /// Estimated model + inference working memory at Mimo's bounded settings.
    /// This is separate from the total Mac memory recommendations above.
    let estimatedWorkingMemoryGB: ClosedRange<Double>
    /// Free disk before a new download: model, temporary copy/compilation, headroom.
    let minimumFreeDiskBytes: UInt64
    let minimumFreeDiskBytesWhenDownloaded: UInt64
    let minimumMacOSMajorVersion: Int
    let requiresAppleSilicon: Bool
    let strengths: String
    let limitations: String

    var minimumMacOSVersionLabel: String {
        minimumMacOSMajorVersion == 14 ? "14.2" : String(minimumMacOSMajorVersion)
    }

    func suitability(
        on hardware: LocalModelHardwareSnapshot,
        isDownloaded: Bool
    ) -> LocalModelHardwareAssessment {
        if hardware.macOSMajorVersion < minimumMacOSMajorVersion {
            return .init(level: .notRecommended, label: "Needs macOS \(minimumMacOSVersionLabel)",
                         detail: "This runtime needs macOS \(minimumMacOSVersionLabel) or later.")
        }
        if requiresAppleSilicon, hardware.isAppleSilicon == false {
            return .init(level: .notRecommended, label: "Needs Apple silicon",
                         detail: "This Mimo runtime requires an Apple silicon Mac (M1 or later).")
        }
        if hardware.physicalMemoryBytes > 0,
           hardware.physicalMemoryBytes < UInt64(minimumMemoryGB) * LocalModelHardware.bytesPerMemoryGB {
            return .init(level: .notRecommended, label: "Not recommended on this Mac",
                         detail: "Mimo suggests at least \(minimumMemoryGB) GB total Mac memory for this model. This is planning guidance, not a manufacturer limit.")
        }
        let diskNeeded = isDownloaded || isBundled
            ? minimumFreeDiskBytesWhenDownloaded : minimumFreeDiskBytes
        if let available = hardware.availableDiskBytes, available < diskNeeded {
            return .init(level: .insufficientStorage, label: "Low free storage",
                         detail: isDownloaded || isBundled
                            ? "The model is present, but leave free storage for runtime caches and recordings."
                            : "Allow space for the model, its temporary download or compilation files, and recordings.")
        }
        if hardware.physicalMemoryBytes == 0 || (requiresAppleSilicon && hardware.isAppleSilicon == nil) {
            return .init(level: .limited, label: "Check Mac specifications",
                         detail: "Mimo could not read all hardware details. Compare your Mac with the suggested chip and memory below.")
        }
        let storageNote = hardware.availableDiskBytes == nil ? " Free storage could not be checked." : ""
        if hardware.physicalMemoryBytes < UInt64(recommendedMemoryGB) * LocalModelHardware.bytesPerMemoryGB {
            return .init(level: .limited, label: "Less room for other apps",
                         detail: "Meets Mimo's suggested minimum; \(recommendedMemoryGB) GB total Mac memory gives more room for meetings and other apps.\(storageNote)")
        }
        return .init(level: .recommended, label: "Good hardware fit",
                     detail: "Meets Mimo's memory guidance. Speed still depends on the chip, recording length, and other running apps.\(storageNote)")
    }
}

enum LocalModelHardware {
    static let bytesPerMemoryGB: UInt64 = 1_073_741_824
    static let estimateExplanation = "Mimo estimates; includes room for macOS and other apps. Download size is separate from memory used while running."

    /// IDs are existing persisted model IDs. Retired options keep their guidance
    /// so an already-downloaded model is still understandable and usable.
    static func guidance(forModelID id: String) -> LocalModelHardwareGuidance? {
        profiles[id]
    }

    /// Stable, role-specific starting points, offered only when the snapshot
    /// meets their hardware guidance. This never selects, loads, or downloads a
    /// model, and does not replace a user's existing choices.
    static func recommendations(
        on hardware: LocalModelHardwareSnapshot,
        downloadedModelIDs: Set<String> = []
    ) -> [LocalModelHardwareRecommendation] {
        let candidates: [LocalModelHardwareRecommendation] = [
            .init(modelID: "FluidInference/sensevoice-small-coreml", modelLabel: "SenseVoice Small",
                  purpose: "Fast Chinese + English meetings", detail: "Fast local transcription as speakers switch languages."),
            .init(modelID: "large-v3", modelLabel: "Whisper Large v3",
                  purpose: "After-meeting transcription", detail: "A larger model for the complete recording, after SenseVoice supplies live text."),
            .init(modelID: "FluidInference/parakeet-unified-en-0.6b-coreml", modelLabel: "Parakeet Unified",
                  purpose: "English dictation", detail: "Fast English-only speech recognition."),
            .init(modelID: "mimo-tiny-cleanup-v1", modelLabel: "Mimo Tiny Cleanup",
                  purpose: "Included English cleanup", detail: "Simple punctuation and filler cleanup with no extra download."),
            .init(modelID: "qwen35-0.8b", modelLabel: "Qwen 3.5 0.8B",
                  purpose: "Local text editing", detail: "General multilingual editing and Quill instructions."),
        ]
        return candidates.filter { candidate in
            guard let guidance = guidance(forModelID: candidate.modelID),
                  hardware.availableDiskBytes != nil else { return false }
            return guidance.suitability(
                on: hardware, isDownloaded: downloadedModelIDs.contains(candidate.modelID)
            ).level == .recommended
        }
    }

    private static func profile(
        downloadMB: Double?, minimum: Int = 8, recommended: Int = 8,
        working: ClosedRange<Double>, diskGB: Double,
        downloadedDiskGB: Double = 1,
        macOS: Int = 14, bundled: Bool = false,
        strengths: String, limitations: String
    ) -> LocalModelHardwareGuidance {
        .init(
            downloadBytes: downloadMB.map { UInt64($0 * 1_000_000) },
            isBundled: bundled,
            minimumMemoryGB: minimum, recommendedMemoryGB: recommended,
            estimatedWorkingMemoryGB: working,
            minimumFreeDiskBytes: UInt64(diskGB * 1_000_000_000),
            minimumFreeDiskBytesWhenDownloaded: UInt64(downloadedDiskGB * 1_000_000_000),
            minimumMacOSMajorVersion: macOS, requiresAppleSilicon: true,
            strengths: strengths, limitations: limitations
        )
    }

    // Sizes come from the selected artifacts/runtime catalogue, checked 2026-09-10.
    // Working-memory ranges are deliberately conservative Mimo estimates, not
    // benchmark results. They include the inference runtime but do not add every
    // concurrently loaded ASR/cleanup/diarization model together.
    // Primary cards: huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct,
    // huggingface.co/Qwen/Qwen3.5-0.8B, huggingface.co/superwhisper/s1-mini-GGUF,
    // huggingface.co/FluidInference/sensevoice-small-coreml, ai.google.dev/gemma/docs/core.
    // Current app limits: GGUF cleanup 1,024 context tokens; Quill 4,096;
    // Gemma LiteRT 4,096. Vendor maximum context is not the context exposed here.
    private static let profiles: [String: LocalModelHardwareGuidance] = {
        var result: [String: LocalModelHardwareGuidance] = [:]
        func add(_ ids: [String], _ guidance: LocalModelHardwareGuidance) {
            for id in ids { result[id] = guidance }
        }
        add(["mimo-tiny-cleanup-v1"], profile(
            downloadMB: 234.686560, working: 0.5...1.0, diskGB: 1, macOS: 15, bundled: true,
            strengths: "Included, fast English punctuation and simple cleanup.",
            limitations: "English-first baseline. Not a Chinese cleanup or meeting-summary model; Mimo limits cleanup to a short 1,024-token context."))
        add(["qwen35-postproc-v3"], profile(
            downloadMB: 505, working: 1.0...2.0, diskGB: 2, macOS: 15,
            strengths: "Dictation cleanup, correction cues, and spoken lists.",
            limitations: "Specialized cleanup, not general chat or meeting summaries. Mixed-language quality needs review; 1,024-token cleanup context."))
        add(["qwen35-0.8b"], profile(
            downloadMB: 533, working: 1.0...2.0, diskGB: 2, macOS: 15,
            strengths: "Compact multilingual text editing and Quill instructions.",
            limitations: "Small general model; may miss complex corrections. Mimo uses 1,024 context tokens for cleanup and 4,096 for Quill, not the model card's full context."))
        add(["superwhisper-s1-mini"], profile(
            downloadMB: 484, working: 0.8...1.6, diskGB: 2, macOS: 15,
            strengths: "English dictation normalization, written numbers, and correction cues.",
            limitations: "English only. Fixed normalization format; not general instructions, Chinese cleanup, or meeting summaries."))
        add(["qwen3-postproc-v2"], profile(
            downloadMB: 390, working: 0.8...1.6, diskGB: 2, macOS: 15,
            strengths: "Keeps an existing local cleanup installation usable.",
            limitations: "Retired model; use a current cleanup option for new downloads."))
        add(["FluidInference/sensevoice-small-coreml"], profile(
            downloadMB: 240, working: 0.4...1.2, diskGB: 2,
            strengths: "Fast Mandarin Chinese and English speech, including language switches.",
            limitations: "Also supports Cantonese, Japanese, and Korean. Accuracy varies with accents and short chunk boundaries."))
        add(["large-v3-v20240930_626MB"], profile(
            downloadMB: 626, recommended: 16, working: 2.0...4.0, diskGB: 4,
            strengths: "Multilingual accuracy, mixed Chinese-English speech, and difficult audio.",
            limitations: "More processing time and memory than SenseVoice. Choose SenseVoice when live update speed matters most."))
        // Exact full Core ML conversion is approximately 3.09 GB:
        // https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3
        add(["large-v3"], profile(
            downloadMB: 3090, minimum: 16, recommended: 24, working: 5.0...10.0,
            diskGB: 9, downloadedDiskGB: 2,
            strengths: "Accuracy-focused full-recording transcription after live SenseVoice captions.",
            limitations: "Slower and larger than Turbo. Accuracy still varies with accents, noise, and language switches; disputed details need review."))
        add(["FluidInference/parakeet-unified-en-0.6b-coreml"], profile(
            downloadMB: 565, working: 1.0...2.0, diskGB: 3,
            strengths: "Fast English dictation.", limitations: "English only; does not support Chinese."))
        add(["FluidInference/parakeet-realtime-eou-120m-coreml/320ms"], profile(
            downloadMB: 430, working: 0.8...1.6, diskGB: 3,
            strengths: "Fast interim English meeting captions.", limitations: "English only. Interim captions are separate from the selected final meeting transcription model."))
        add(["FluidInference/parakeet-tdt-0.6b-v3-coreml"], profile(
            downloadMB: 450, working: 1.0...2.0, diskGB: 3,
            strengths: "Fast speech recognition in 25 European languages.", limitations: "Includes English, but does not support Chinese."))
        add(["FluidInference/parakeet-tdt-0.6b-v2-coreml"], profile(
            downloadMB: 450, working: 1.0...2.0, diskGB: 3,
            strengths: "Older English dictation option for existing installations.", limitations: "English only; newer Parakeet options are preferred for new downloads."))
        add(["FluidInference/Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML"], profile(
            downloadMB: 665, recommended: 16, working: 1.5...3.0, diskGB: 4, macOS: 15,
            strengths: "Streaming speech recognition, including Mandarin Chinese and English.", limitations: "Live words append without revising earlier text; test your language and accent."))
        add(["tiny", "tiny.en"], profile(
            downloadMB: 77, working: 0.3...1.0, diskGB: 2,
            strengths: "Small download and lightweight speech recognition.", limitations: "Lower accuracy for noise and accents. The .en variant supports English only."))
        add(["small", "small.en"], profile(
            downloadMB: 487, working: 1.0...2.0, diskGB: 3,
            strengths: "Moderate-size Whisper speech recognition.", limitations: "Less accurate than Large Turbo on difficult audio. The .en variant supports English only."))
        add(["medium.en"], profile(
            downloadMB: 1500, recommended: 16, working: 2.5...4.5, diskGB: 5,
            strengths: "Older, larger English Whisper option.", limitations: "English only. Large Turbo is the preferred current Whisper option for new downloads."))
        add(["FluidInference/qwen3-asr-0.6b-coreml"], profile(
            downloadMB: 1300, recommended: 16, working: 2.0...4.0, diskGB: 5, macOS: 15,
            strengths: "Experimental multilingual recognition and Chinese dialect support.", limitations: "Slower preparation and inference; accented-English results can vary."))
        add(["phequals/indic-conformer-600m-multilingual-coreml-rnnt"], profile(
            downloadMB: 618, recommended: 16, working: 1.5...3.0, diskGB: 3, macOS: 15,
            strengths: "Experimental recognition for supported Indian languages.", limitations: "Requires choosing a supported language; not a Chinese-English meeting option."))
        add(["phequals/cohere-transcribe-coreml-mixed-precision"], profile(
            downloadMB: 3800, minimum: 16, recommended: 24, working: 6.0...10.0, diskGB: 10, macOS: 15,
            strengths: "Large transcription option for difficult speech in supported languages.", limitations: "High download and memory cost; results arrive after recording rather than as live text."))
        add(["litert-community/gemma-4-E2B-it-litert-lm"], profile(
            downloadMB: 2588.147712, recommended: 16, working: 3.0...5.0, diskGB: 7, macOS: 15,
            strengths: "Experimental local generative text and audio model.", limitations: "Research preview in Mimo; may answer instead of transcribing. Current runtime context is 4,096 tokens."))
        add(["litert-community/gemma-4-E4B-it-litert-lm"], profile(
            downloadMB: 3659.530240, minimum: 16, recommended: 24, working: 5.0...8.0, diskGB: 10, macOS: 15,
            strengths: "Larger experimental local generative model.", limitations: "More memory and preparation time; not a dependable live dictation default. Current runtime context is 4,096 tokens."))
        add(["apple-speech-transcriber"], profile(
            downloadMB: nil, working: 1.0...3.0, diskGB: 3, macOS: 26,
            strengths: "On-device speech with language assets maintained by macOS.", limitations: "Requires a supported system language. Download and working memory vary with Apple's selected assets."))
        return result
    }()
}
