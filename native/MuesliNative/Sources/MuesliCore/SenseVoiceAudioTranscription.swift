import Foundation

/// Keeps every sample within the shipped SenseVoice preprocessor's input limits.
/// Inputs are already resampled to 16 kHz, matching the app and CLI runtimes.
public enum SenseVoiceAudioTranscription {
    public static let minimumChunkSamples = 3_200
    public static let maximumChunkSamples = 30 * 16_000
    private static let boundarySearchSamples = 3 * 16_000
    private static let energyWindowSamples = 320 // 20 ms at 16 kHz.

    public static func chunkRanges(samples: [Float]) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = 0
        while start < samples.count {
            let limit = min(start + maximumChunkSamples, samples.count)
            let end = limit == samples.count
                ? limit
                : quietBoundary(samples: samples, start: start, limit: limit)
            ranges.append(start..<end)
            start = end
        }
        return ranges
    }

    public static func transcribe(
        samples: [Float],
        transcribeChunk: @Sendable ([Float]) async throws -> String
    ) async throws -> String {
        try Task.checkCancellation()
        var transcripts: [String] = []
        for range in chunkRanges(samples: samples) {
            try Task.checkCancellation()
            var chunk = Array(samples[range])
            // Core ML accepts 3,200...480,000 samples. Pad only the inference
            // buffer for short files/tails; the source ranges and duration stay
            // unchanged, and no final spoken samples are discarded.
            if chunk.count < minimumChunkSamples {
                chunk.append(contentsOf: repeatElement(0, count: minimumChunkSamples - chunk.count))
            }
            let text = try await transcribeChunk(chunk)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            if !text.isEmpty { transcripts.append(text) }
        }
        // Windows are contiguous, with no overlap: joining must not deduplicate
        // legitimate repeated words or assume that Chinese uses word spaces.
        return transcripts.joined(separator: " ")
    }

    private static func quietBoundary(samples: [Float], start: Int, limit: Int) -> Int {
        let searchStart = max(start + 1, limit - boundarySearchSamples)
        var bestEnd = limit
        var minimumEnergy = Double.infinity
        var windowStart = searchStart
        while windowStart < limit {
            let windowEnd = min(windowStart + energyWindowSamples, limit)
            var energy = 0.0
            for sample in samples[windowStart..<windowEnd] {
                let value = Double(sample)
                energy += value.isFinite ? value * value : .infinity
            }
            energy /= Double(windowEnd - windowStart)
            // Prefer the later boundary on ties, avoiding needless short chunks.
            if energy <= minimumEnergy {
                minimumEnergy = energy
                bestEnd = windowEnd
            }
            windowStart = windowEnd
        }
        return bestEnd
    }
}
