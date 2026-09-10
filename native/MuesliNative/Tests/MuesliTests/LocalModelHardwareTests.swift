import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Local model hardware guidance")
struct LocalModelHardwareTests {
    private let gib = LocalModelHardware.bytesPerMemoryGB

    private func hardware(
        memoryGB: UInt64 = 16,
        freeDisk: UInt64? = 50_000_000_000,
        macOS: Int = 26,
        appleSilicon: Bool? = true
    ) -> LocalModelHardwareSnapshot {
        .init(chipName: "Fixture Mac chip", physicalMemoryBytes: memoryGB * gib,
              availableDiskBytes: freeDisk, macOSMajorVersion: macOS,
              isAppleSilicon: appleSilicon)
    }

    @Test("Every selectable model has guidance without downloading or loading it")
    func catalogueCoverage() {
        let ids = BackendOption.catalog(appleSpeechAvailable: true).all.map(\.model)
            + PostProcessorOption.all.map(\.id)
            + [PostProcessorOption.legacyV2.id]
        for id in ids {
            #expect(LocalModelHardware.guidance(forModelID: id) != nil, "Missing guidance for \(id)")
        }
        #expect(LocalModelHardware.guidance(forModelID: "unknown-user-model") == nil)
        #expect(LocalModelHardware.guidance(forModelID: "FluidInference/parakeet-realtime-eou-120m-coreml/320ms") != nil)
    }

    @Test("Physical memory boundaries use exact bytes, without rounding up")
    func memoryBoundaries() throws {
        let model = try #require(LocalModelHardware.guidance(forModelID: "large-v3-v20240930_626MB"))
        #expect(model.suitability(on: hardware(memoryGB: 8), isDownloaded: false).level == .limited)
        #expect(model.suitability(on: hardware(memoryGB: 16), isDownloaded: false).level == .recommended)
        let justBelow = LocalModelHardwareSnapshot(
            chipName: "Fixture", physicalMemoryBytes: 8 * gib - 1,
            availableDiskBytes: 50_000_000_000, macOSMajorVersion: 26, isAppleSilicon: true
        )
        #expect(model.suitability(on: justBelow, isDownloaded: false).level == .notRecommended)
    }

    @Test("Full Large v3 final-pass guidance leaves room for the larger runtime")
    func fullWhisperFinalPass() throws {
        let model = try #require(LocalModelHardware.guidance(forModelID: "large-v3"))
        #expect(model.suitability(on: hardware(memoryGB: 8), isDownloaded: false).level == .notRecommended)
        #expect(model.suitability(on: hardware(memoryGB: 16), isDownloaded: false).level == .limited)
        #expect(model.suitability(on: hardware(memoryGB: 24), isDownloaded: false).level == .recommended)
        #expect(model.suitability(on: hardware(memoryGB: 24, freeDisk: 8_000_000_000), isDownloaded: false).level == .insufficientStorage)
        #expect(model.suitability(on: hardware(memoryGB: 24, freeDisk: 2_000_000_000), isDownloaded: true).level == .recommended)
        #expect(LocalModelHardware.recommendations(on: hardware(memoryGB: 24)).contains { $0.modelID == "large-v3" })
        #expect(!LocalModelHardware.recommendations(on: hardware(memoryGB: 16)).contains { $0.modelID == "large-v3" })
    }

    @Test("Download space is not required again for an installed model")
    func diskBoundaries() throws {
        let model = try #require(LocalModelHardware.guidance(forModelID: "large-v3-v20240930_626MB"))
        let betweenInstalledAndNew = hardware(freeDisk: 2_000_000_000)
        #expect(model.suitability(on: betweenInstalledAndNew, isDownloaded: false).level == .insufficientStorage)
        #expect(model.suitability(on: betweenInstalledAndNew, isDownloaded: true).level == .recommended)
        #expect(model.suitability(on: hardware(freeDisk: model.minimumFreeDiskBytes), isDownloaded: false).level == .recommended)
        #expect(model.suitability(on: hardware(freeDisk: model.minimumFreeDiskBytes - 1), isDownloaded: false).level == .insufficientStorage)
        #expect(model.suitability(on: hardware(freeDisk: 0), isDownloaded: true).level == .insufficientStorage)
    }

    @Test("Unknown disk capacity is not treated as zero or silently called sufficient")
    func unknownDisk() throws {
        let model = try #require(LocalModelHardware.guidance(forModelID: "qwen35-0.8b"))
        let assessment = model.suitability(on: hardware(freeDisk: nil), isDownloaded: false)
        #expect(assessment.level == .recommended)
        #expect(assessment.detail.contains("Free storage could not be checked"))
    }

    @Test("Runtime OS and chip requirements precede favorable memory ratings")
    func incompatibleRuntime() throws {
        let cleanup = try #require(LocalModelHardware.guidance(forModelID: "mimo-tiny-cleanup-v1"))
        let oldOS = cleanup.suitability(on: hardware(memoryGB: 64, macOS: 14), isDownloaded: true)
        #expect(oldOS.level == .notRecommended)
        #expect(oldOS.label == "Needs macOS 15")
        let intel = cleanup.suitability(on: hardware(memoryGB: 64, appleSilicon: false), isDownloaded: true)
        #expect(intel.label == "Needs Apple silicon")
        #expect(cleanup.suitability(on: hardware(appleSilicon: nil), isDownloaded: true).level == .limited)
        #expect(cleanup.suitability(on: hardware(memoryGB: 0), isDownloaded: true).level == .limited)
    }

    @Test("Bundled and system-managed assets are distinguished from download requirements")
    func bundledAndSystemManaged() throws {
        let bundled = try #require(LocalModelHardware.guidance(forModelID: "mimo-tiny-cleanup-v1"))
        #expect(bundled.isBundled)
        #expect(bundled.downloadBytes == 234_686_560)
        let apple = try #require(LocalModelHardware.guidance(forModelID: "apple-speech-transcriber"))
        #expect(apple.downloadBytes == nil)
        #expect(apple.minimumMacOSMajorVersion == 26)
        #expect(apple.suitability(on: hardware(macOS: 15), isDownloaded: true).level == .notRecommended)
    }

    @Test("Model bytes never masquerade as total Mac RAM recommendations")
    func dimensionsAndGuidance() throws {
        let models = ["mimo-tiny-cleanup-v1", "qwen35-postproc-v3", "qwen35-0.8b", "superwhisper-s1-mini",
                      "FluidInference/sensevoice-small-coreml", "large-v3-v20240930_626MB",
                      "litert-community/gemma-4-E4B-it-litert-lm"]
        for id in models {
            let model = try #require(LocalModelHardware.guidance(forModelID: id))
            #expect(model.minimumMemoryGB >= 8)
            #expect(model.recommendedMemoryGB >= model.minimumMemoryGB)
            #expect(model.estimatedWorkingMemoryGB.lowerBound > 0)
            #expect(model.minimumFreeDiskBytes >= model.minimumFreeDiskBytesWhenDownloaded)
            #expect(!model.strengths.isEmpty && !model.limitations.isEmpty)
        }
        let qwen = try #require(LocalModelHardware.guidance(forModelID: "qwen35-0.8b"))
        #expect(qwen.limitations.contains("4,096"))
        #expect(LocalModelHardware.estimateExplanation.contains("Mimo estimates"))
        let senseVoice = try #require(LocalModelHardware.guidance(forModelID: "FluidInference/sensevoice-small-coreml"))
        #expect(senseVoice.downloadBytes == 240_000_000)
        #expect(senseVoice.minimumMacOSVersionLabel == "14.2")
    }

    @Test("Recommendations depend on hardware and installed state, without selecting models")
    func recommendationsRespectHardware() {
        let normal = LocalModelHardware.recommendations(on: hardware(memoryGB: 8))
        #expect(normal.count == 4)
        #expect(normal.first?.modelID == "FluidInference/sensevoice-small-coreml")
        #expect(LocalModelHardware.recommendations(on: hardware(memoryGB: 4)).isEmpty)
        #expect(LocalModelHardware.recommendations(on: hardware(appleSilicon: false)).isEmpty)
        #expect(LocalModelHardware.recommendations(on: hardware(appleSilicon: nil)).isEmpty)
        #expect(LocalModelHardware.recommendations(on: hardware(freeDisk: nil)).isEmpty)
        let noRoomForDownloads = hardware(freeDisk: 1_500_000_000)
        #expect(LocalModelHardware.recommendations(on: noRoomForDownloads).map(\.modelID) == ["mimo-tiny-cleanup-v1"])
        let withSenseVoice = LocalModelHardware.recommendations(
            on: noRoomForDownloads,
            downloadedModelIDs: ["FluidInference/sensevoice-small-coreml"]
        )
        #expect(withSenseVoice.map(\.modelID) == ["FluidInference/sensevoice-small-coreml", "mimo-tiny-cleanup-v1"])
        #expect(LocalModelHardware.recommendations(on: hardware(macOS: 14)).count == 2)
    }
}
