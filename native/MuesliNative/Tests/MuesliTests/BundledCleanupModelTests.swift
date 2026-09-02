import CryptoKit
import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Bundled transcript cleanup model", .serialized)
struct BundledCleanupModelTests {
    @Test("tiny cleanup is included, integrity checked, and selected for new local installs")
    func bundledModelIntegrity() throws {
        let option = PostProcessorOption.mimoTiny

        #expect(option.isBundled)
        #expect(!option.isDownloadable)
        #expect(option.filename == "mimo-smollm2-360m-instruct-q3_k_m.gguf")
        #expect(PostProcessorOption.defaultOption == option)
        #expect(AppConfig().activePostProcessorId == option.id)

        // Source checkouts fetch this checksum-pinned release asset during
        // packaging. When present locally, validate the exact distributable.
        guard option.isDownloaded else { return }
        let data = try Data(contentsOf: option.modelURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(data.count == 234_686_560)
        #expect(digest == "eb31394ff392eaca725fd9582eade3352adce2143704273846f0d194123fccf3")
    }

    @Test("tiny cleanup model loads and completes one safe local rewrite")
    func bundledModelInferenceSmokeTest() async throws {
        guard #available(macOS 15, *) else { return }
        let option = PostProcessorOption.mimoTiny
        guard option.isDownloaded else { return }
        let prompt = option.effectiveSystemPrompt(
            configuredSystemPrompt: PostProcessorOption.defaultSystemPrompt
        )
        let processor = Qwen3PostProcessor(
            modelURL: option.modelURL,
            systemPrompt: prompt,
            inputFormat: option.inputFormat
        )

        let output = try await processor.process(
            "Uh, we should send the update tomorrow",
            configuration: Qwen3PostProcessor.Configuration(
                modelURL: option.modelURL,
                systemPrompt: prompt,
                inputFormat: option.inputFormat,
                maxTokenCount: 256
            )
        )

        #expect(!output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(output.localizedCaseInsensitiveContains("send the update tomorrow"))
        #expect(!output.localizedCaseInsensitiveContains("uh"))
        await processor.shutdown()
    }
}
