import AVFoundation
import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("MeetingFinalTranscription")
struct MeetingFinalTranscriptionTests {
    private actor Calls {
        var sources: [String] = []
        var firstCallWaiters: [CheckedContinuation<Void, Never>] = []

        func record(_ url: URL) {
            sources.append(url.deletingLastPathComponent().lastPathComponent)
            firstCallWaiters.forEach { $0.resume() }
            firstCallWaiters.removeAll()
        }

        func waitForFirstCall() async {
            if !sources.isEmpty { return }
            await withCheckedContinuation { firstCallWaiters.append($0) }
        }
    }

    private func fixture(seconds: Int, systemSilent: Bool = false) throws -> (MeetingFinalAudioCapture, URL, URL) {
        let capture = try MeetingFinalAudioCapture()
        // Independent source streams; no app, microphone, model, or saved data.
        let second = [Int16](repeating: 500, count: 16_000)
        let systemSecond = [Int16](repeating: systemSilent ? 0 : -700, count: 16_000)
        for _ in 0..<seconds {
            capture.appendMicrophone(second)
            capture.appendSystem(systemSecond)
        }
        let urls = capture.stop()
        return (capture, try #require(urls.microphone), try #require(urls.system))
    }

    private func result(_ text: String, duration: Double) -> SpeechTranscriptionResult {
        .init(text: text, segments: [.init(start: 0, end: duration, text: text)])
    }

    @Test("complete recordings longer than 108 seconds are decoded independently and serially")
    func fullTrackCoverageAndSourceOrder() async throws {
        let (capture, mic, system) = try fixture(seconds: 120)
        defer { capture.cancel() }
        let calls = Calls()
        let live = [
            SpeechSegment(start: 0, end: 5, text: "我们先确认预算。Please confirm the project budget."),
            SpeechSegment(start: 115, end: 120, text: "尾部决定保留。Keep the final decision at the end.")
        ]
        let outcome = try await MeetingFinalTranscription.run(
            microphone: .init(url: mic, duration: 120, liveSegments: live),
            system: .init(url: system, duration: 120, liveSegments: live)
        ) { url in
            await calls.record(url)
            let file = try AVAudioFile(forReading: url)
            #expect(file.length == 120 * 16_000)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1))
            try file.read(into: buffer, frameCount: 1)
            let channels = try #require(buffer.floatChannelData)
            #expect(url == mic ? channels[0][0] > 0 : channels[0][0] < 0)
            return .init(text: live.map(\.text).joined(separator: " "), segments: live)
        }
        #expect(await calls.sources == ["microphone", "system"])
        #expect(outcome.completed)
        #expect(outcome.warnings.isEmpty)
        #expect(outcome.micSegments.last?.start == 115)
        #expect(outcome.systemSegments.last?.end == 120)
    }

    @Test("empty final source retains its live draft while a successful other source is kept")
    func emptySourceFallsBackIndependently() async throws {
        let (capture, mic, system) = try fixture(seconds: 5)
        defer { capture.cancel() }
        let live = [SpeechSegment(start: 0, end: 5, text: "Keep this microphone draft.")]
        let outcome = try await MeetingFinalTranscription.run(
            microphone: .init(url: mic, duration: 5, liveSegments: live),
            system: .init(url: system, duration: 5, liveSegments: [])
        ) { url in
            url == mic ? .init(text: "", segments: []) : result("Accurate other speaker.", duration: 5)
        }
        #expect(!outcome.completed)
        #expect(outcome.micSegments.map(\.text) == live.map(\.text))
        #expect(outcome.systemSegments.first?.text == "Accurate other speaker.")
        #expect(outcome.warnings.contains { $0.contains("microphone") && $0.contains("returned no speech") })
    }

    @Test("missing and physically truncated recordings never count as a completed final pass")
    func incompleteCaptureFallsBackBeforeInference() async throws {
        let (capture, mic, _) = try fixture(seconds: 5)
        defer { capture.cancel() }
        let calls = Calls()
        let live = [SpeechSegment(start: 0, end: 10, text: "Preserve the whole live draft.")]
        let outcome = try await MeetingFinalTranscription.run(
            microphone: .init(url: mic, duration: 10, liveSegments: live),
            system: .init(url: nil, duration: 10, liveSegments: live)
        ) { url in
            await calls.record(url)
            return result("Should never run", duration: 5)
        }
        #expect(await calls.sources.isEmpty)
        #expect(!outcome.completed)
        #expect(outcome.warnings.count == 2)
        #expect(outcome.micSegments.first?.text == live.first?.text)
        #expect(outcome.systemSegments.first?.text == live.first?.text)
    }

    @Test("a decoder failure retains that source and still attempts the other source")
    func decoderFailure() async throws {
        let (capture, mic, system) = try fixture(seconds: 5)
        defer { capture.cancel() }
        let calls = Calls()
        let live = [SpeechSegment(start: 0, end: 5, text: "Retained draft")]
        let outcome = try await MeetingFinalTranscription.run(
            microphone: .init(url: mic, duration: 5, liveSegments: live),
            system: .init(url: system, duration: 5, liveSegments: [])
        ) { url in
            await calls.record(url)
            if url == mic { throw CocoaError(.fileReadUnknown) }
            return result("Other source completed", duration: 5)
        }
        #expect(await calls.sources == ["microphone", "system"])
        #expect(!outcome.completed)
        #expect(outcome.micSegments.first?.text == "Retained draft")
        #expect(outcome.systemSegments.first?.text == "Other source completed")
        #expect(outcome.warnings.first?.contains("could not finish") == true)
    }

    @Test("missing middle or tail speech and large content loss are flagged")
    func suspiciousCoverage() {
        let live = [
            SpeechSegment(start: 0, end: 5, text: "Opening point"),
            SpeechSegment(start: 40, end: 45, text: "Important middle decision"),
            SpeechSegment(start: 115, end: 120, text: "Final action and owner")
        ]
        #expect(MeetingFinalTranscription.coverageConcern(live: live, final: [live[0], live[2]]) != nil)
        #expect(MeetingFinalTranscription.coverageConcern(live: live, final: [live[0], live[1]]) != nil)
        #expect(MeetingFinalTranscription.coverageConcern(live: live, final: live) == nil)
        #expect(MeetingFinalTranscription.coverageConcern(
            live: [SpeechSegment(start: 0, end: 10, text: String(repeating: "决定", count: 40))],
            final: [SpeechSegment(start: 0, end: 10, text: "决定")]
        ) != nil)
    }

    @Test("invalid timestamps retain the draft instead of fabricating whole-meeting timings")
    func invalidTimestamps() async throws {
        let (capture, mic, system) = try fixture(seconds: 5, systemSilent: true)
        defer { capture.cancel() }
        let live = [SpeechSegment(start: 0, end: 5, text: "Keep the timed draft.")]
        let outcome = try await MeetingFinalTranscription.run(
            microphone: .init(url: mic, duration: 5, liveSegments: live),
            system: .init(url: system, duration: 5, liveSegments: [])
        ) { _ in
            .init(text: "New words", segments: [.init(start: .nan, end: 5, text: "New words")])
        }
        #expect(!outcome.completed)
        #expect(outcome.micSegments.first?.text == "Keep the timed draft.")
        #expect(outcome.warnings.first?.contains("timestamps") == true)
    }

    @Test("digital silence is skipped without running a second source model call")
    func unusedSilentSource() async throws {
        let (capture, mic, system) = try fixture(seconds: 5, systemSilent: true)
        defer { capture.cancel() }
        let calls = Calls()
        let outcome = try await MeetingFinalTranscription.run(
            microphone: .init(url: mic, duration: 5, liveSegments: []),
            system: .init(url: system, duration: 5, liveSegments: [])
        ) { url in
            await calls.record(url)
            return result("In-person meeting speech", duration: 5)
        }
        #expect(outcome.completed)
        #expect(await calls.sources == ["microphone"])
        #expect(outcome.systemSegments.isEmpty)
    }

    @Test("segment cleanup preserves real timestamps and drops non-speech artifacts")
    func segmentCleanupPreservesTiming() async throws {
        let (capture, mic, system) = try fixture(seconds: 5, systemSilent: true)
        defer { capture.cancel() }
        let outcome = try await MeetingFinalTranscription.run(
            microphone: .init(url: mic, duration: 5, liveSegments: []),
            system: .init(url: system, duration: 5, liveSegments: [])
        ) { _ in
            .init(text: "um 确认预算。 [music] uh Keep the date.", segments: [
                .init(start: 0.5, end: 1.5, text: "um 确认预算。"),
                .init(start: 2, end: 3, text: "[music]"),
                .init(start: 3.5, end: 4.5, text: "uh Keep the date.")
            ])
        }
        #expect(outcome.completed)
        #expect(outcome.micSegments.map(\.text) == ["确认预算。", "Keep the date."])
        #expect(outcome.micSegments.map(\.start) == [0.5, 3.5])
        #expect(outcome.micSegments.map(\.end) == [1.5, 4.5])
    }

    @Test("a zero-frame unused source is valid, but missing expected audio or live speech is not")
    func zeroFrameSource() async throws {
        let (capture, mic, system) = try fixture(seconds: 5)
        defer { capture.cancel() }
        try WavWriter.header(dataSize: 0).write(to: system)
        for (expectedDuration, liveSpeech, shouldComplete) in [(0.0, false, true), (5.0, false, false), (0.0, true, false)] {
            let calls = Calls()
            let outcome = try await MeetingFinalTranscription.run(
                microphone: .init(url: mic, duration: 5, liveSegments: []),
                system: .init(
                    url: system, duration: expectedDuration,
                    liveSegments: liveSpeech ? [.init(start: 0, end: 1, text: "Existing system speech")] : []
                )
            ) { url in
                await calls.record(url)
                return result("Microphone speech", duration: 5)
            }
            #expect(await calls.sources == ["microphone"])
            #expect(outcome.completed == shouldComplete)
            #expect(outcome.warnings.isEmpty == shouldComplete)
            if liveSpeech { #expect(outcome.systemSegments.first?.text == "Existing system speech") }
        }
    }

    @Test("result overrides preserve final-pass review for resumed summary generation")
    func resultOverridePreservesReview() {
        let review = MeetingTranscriptReview.compare(
            liveTranscript: "[00:00:01] You: Keep the draft.",
            finalTranscript: "[00:00:01] You: Keep the draft.",
            finalPassCompleted: false,
            additionalWarnings: ["The final model was unavailable."]
        )
        let date = Date(timeIntervalSince1970: 1_000)
        let result = MeetingSessionResult(
            title: "Meeting", originalTitle: "Meeting", calendarEventID: nil,
            startTime: date, endTime: date.addingTimeInterval(5), durationSeconds: 5,
            rawTranscript: "Draft", formattedNotes: "Notes", retainedRecordingURL: nil,
            retainedRecordingError: nil, systemRecordingURL: nil,
            templateSnapshot: MeetingTemplates.auto.snapshot, transcriptionReview: review
        )
        let merged = result.overriding(rawTranscript: "Merged draft", formattedNotes: "Merged notes")
        #expect(merged.transcriptionReview?.summaryContext == review.summaryContext)
        #expect(merged.transcriptionReview?.finalPassCompleted == false)
    }

    @Test("cancellation stops before the other source and leaves owned files until cleanup")
    func cancellation() async throws {
        let (capture, mic, system) = try fixture(seconds: 5)
        defer { capture.cancel() }
        let calls = Calls()
        let task = Task {
            try await MeetingFinalTranscription.run(
                microphone: .init(url: mic, duration: 5, liveSegments: []),
                system: .init(url: system, duration: 5, liveSegments: [])
            ) { url in
                await calls.record(url)
                try await Task.sleep(for: .seconds(10))
                return result("Cancelled", duration: 5)
            }
        }
        await calls.waitForFirstCall()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancellation must propagate")
        } catch is CancellationError {
            #expect(await calls.sources == ["microphone"])
            #expect(FileManager.default.fileExists(atPath: mic.path))
            #expect(FileManager.default.fileExists(atPath: system.path))
        }
    }

    @Test("temporary source files are private and removed when capture ownership ends")
    func privateCaptureLifetime() throws {
        var capture: MeetingFinalAudioCapture? = try MeetingFinalAudioCapture()
        capture?.appendMicrophone([100, 200])
        let mic = try #require(capture?.stop().microphone)
        let fm = FileManager.default
        let attrs = try fm.attributesOfItem(atPath: mic.path)
        let parentAttrs = try fm.attributesOfItem(atPath: mic.deletingLastPathComponent().path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((parentAttrs[.posixPermissions] as? NSNumber)?.intValue == 0o700)
        capture = nil
        #expect(!fm.fileExists(atPath: mic.path))
        #expect(!fm.fileExists(atPath: mic.deletingLastPathComponent().deletingLastPathComponent().path))
    }
}
