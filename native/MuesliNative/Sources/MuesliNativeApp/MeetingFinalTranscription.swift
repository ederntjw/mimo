import AVFoundation
import Foundation

/// Temporary source recordings are never user recordings. One private directory
/// owns both files and is removed on completion, cancellation, or abandonment.
final class MeetingFinalAudioCapture {
    private let directory: URL
    private var microphone: PCMChunkRecorder?
    private var system: PCMChunkRecorder?

    init() throws {
        let name = "mimo-final-pass-\(UUID().uuidString)"
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        do {
            for folder in [directory, directory.appendingPathComponent("microphone"), directory.appendingPathComponent("system")] {
                try FileManager.default.createDirectory(
                    at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
                )
            }
            microphone = try PCMChunkRecorder(directoryName: "\(name)/microphone")
            system = try PCMChunkRecorder(directoryName: "\(name)/system")
            for folder in ["microphone", "system"] {
                for file in try FileManager.default.contentsOfDirectory(
                    at: directory.appendingPathComponent(folder), includingPropertiesForKeys: nil
                ) {
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                }
            }
        } catch {
            microphone?.cancel()
            system?.cancel()
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func appendMicrophone(_ samples: [Int16]) { microphone?.append(samples) }
    func appendSystem(_ samples: [Int16]) { system?.append(samples) }

    func stop() -> (microphone: URL?, system: URL?) {
        let urls = (microphone?.stop(), system?.stop())
        microphone = nil
        system = nil
        return urls
    }

    func cancel() {
        microphone?.cancel()
        system?.cancel()
        microphone = nil
        system = nil
        try? FileManager.default.removeItem(at: directory)
    }

    deinit { cancel() }
}

/// A second, independent decode of complete source recordings. The live draft
/// remains the fallback for each source; another model agreeing is not proof.
enum MeetingFinalTranscription {
    struct Input {
        let url: URL?
        let duration: TimeInterval
        let liveSegments: [SpeechSegment]
    }

    struct Outcome {
        let micSegments: [SpeechSegment]
        let systemSegments: [SpeechSegment]
        let completed: Bool
        let warnings: [String]
    }

    private struct TrackOutcome {
        let segments: [SpeechSegment]
        let completed: Bool
        let warning: String?
    }

    static func run(
        microphone: Input,
        system: Input,
        transcribe: (URL) async throws -> SpeechTranscriptionResult
    ) async throws -> Outcome {
        // Never run these in parallel: they share one mutable ASR runtime.
        let mic = try await transcribeTrack(microphone, name: "microphone", transcribe: transcribe)
        let others = try await transcribeTrack(system, name: "system audio", transcribe: transcribe)
        try Task.checkCancellation()
        var warnings = [mic.warning, others.warning].compactMap { $0 }
        let hasText = !(mic.segments + others.segments).allSatisfy { visibleLength($0.text) == 0 }
        if !hasText && warnings.isEmpty {
            warnings.append("The final pass returned no speech. The live draft was kept and needs review.")
        }
        return Outcome(
            micSegments: mic.segments,
            systemSegments: others.segments,
            completed: mic.completed && others.completed && hasText,
            warnings: warnings
        )
    }

    private static func transcribeTrack(
        _ input: Input,
        name: String,
        transcribe: (URL) async throws -> SpeechTranscriptionResult
    ) async throws -> TrackOutcome {
        try Task.checkCancellation()
        func fallback(_ reason: String) -> TrackOutcome {
            TrackOutcome(
                segments: input.liveSegments,
                completed: false,
                warning: "The final \(name) pass \(reason). Its live draft was kept and needs review."
            )
        }
        guard let url = input.url else {
            if input.duration == 0 && input.liveSegments.isEmpty {
                return TrackOutcome(segments: [], completed: true, warning: nil)
            }
            return fallback("could not access the complete recording")
        }

        do {
            let recording = try inspectRecording(at: url)
            if recording.duration == 0, input.duration == 0, input.liveSegments.isEmpty {
                return TrackOutcome(segments: [], completed: true, warning: nil)
            }
            guard input.duration.isFinite, input.duration > 0,
                  abs(recording.duration - input.duration) <= 0.25 else {
                return fallback("found an incomplete recording")
            }
            // Digital silence is a valid unused source (for example, a room
            // meeting with no system playback). Never decode it into invented speech.
            if !recording.hasSignal && input.liveSegments.isEmpty {
                return TrackOutcome(segments: [], completed: true, warning: nil)
            }
            let result = try await transcribe(url)
            try Task.checkCancellation()
            // The coordinator cleans the aggregate text. Repeat its same
            // deterministic cleanup per segment so timed output cannot leak
            // annotations or fillers that aggregate-only cleanup removed.
            let cleanedText = cleanText(result.text)
            guard visibleLength(cleanedText) > 0 else { return fallback("returned no speech") }
            let nonempty = result.segments.map {
                SpeechSegment(start: $0.start, end: $0.end, text: cleanText($0.text))
            }.filter { visibleLength($0.text) > 0 }
            guard !nonempty.isEmpty,
                  Double(nonempty.reduce(0) { $0 + visibleLength($1.text) }) >= Double(visibleLength(cleanedText)) * 0.9,
                  nonempty.allSatisfy({
                      $0.start.isFinite && $0.end.isFinite && $0.start >= 0
                          && $0.end > $0.start && $0.start < recording.duration
                          && $0.end <= recording.duration + 2
                  }) else {
                return fallback("did not return usable speech timestamps")
            }
            let segments = nonempty.map {
                SpeechSegment(
                    start: $0.start,
                    end: min($0.end, recording.duration),
                    text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }.sorted { $0.start < $1.start }
            if let concern = coverageConcern(live: input.liveSegments, final: segments) {
                return fallback(concern)
            }
            return TrackOutcome(segments: segments, completed: true, warning: nil)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return fallback("could not finish")
        }
    }

    /// Checks physical coverage separately from transcript coverage, including
    /// route-change loss and truncated files, without loading a whole meeting.
    private static func inspectRecording(at url: URL) throws -> (duration: TimeInterval, hasSignal: Bool) {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) where abs(channels[channel][frame]) > 0.00001 {
                    return (duration, true)
                }
            }
        }
        return (duration, false)
    }

    /// Conservative loss checks, not an accuracy score. Keep the source draft
    /// when the second model omits substantial content or a known speech region.
    static func coverageConcern(live: [SpeechSegment], final: [SpeechSegment]) -> String? {
        let liveTextLength = live.reduce(0) { $0 + visibleLength($1.text) }
        let finalTextLength = final.reduce(0) { $0 + visibleLength($1.text) }
        if liveTextLength >= 40 && Double(finalTextLength) < Double(liveTextLength) * 0.45 {
            return "returned substantially less speech than the live draft"
        }
        let knownSpeech = live.filter {
            visibleLength($0.text) > 0 && $0.start.isFinite && $0.end.isFinite && $0.end > $0.start
        }
        let finalWindows = final.map { (max(0, $0.start - 1.5), $0.end + 1.5) }
            .sorted { $0.0 < $1.0 }
        for segment in knownSpeech {
            var cursor = segment.start
            var largestGap: TimeInterval = 0
            for window in finalWindows where window.1 > segment.start && window.0 < segment.end {
                largestGap = max(largestGap, window.0 - cursor)
                cursor = max(cursor, window.1)
            }
            largestGap = max(largestGap, segment.end - cursor)
            if largestGap >= 2.5 {
                return "may have missed speech present in the live draft"
            }
        }
        return nil
    }

    private static func visibleLength(_ text: String) -> Int {
        text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.count
    }

    private static func cleanText(_ text: String) -> String {
        FillerWordFilter.apply(TranscriptionEngineArtifactsFilter.apply(text))
    }
}
