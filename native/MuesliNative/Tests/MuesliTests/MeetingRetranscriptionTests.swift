import Foundation
import MuesliCore
import Testing
@testable import MuesliNativeApp

@Suite("Meeting re-transcription model choice")
struct MeetingRetranscriptionTests {
    @Test("an explicit higher-quality model overrides the configured model")
    func explicitModel() {
        #expect(MeetingRetranscriptionPolicy.resolveModel(
            requested: .whisperLargeV3, configured: .whisperLargeTurbo,
            downloaded: [.whisperLargeTurbo, .whisperLargeV3]
        ) == .whisperLargeV3)
        #expect(MeetingRetranscriptionPolicy.resolveModel(
            requested: nil, configured: .whisperLargeTurbo,
            downloaded: [.whisperLargeTurbo, .whisperLargeV3]
        ) == .whisperLargeTurbo)
    }

    @Test("a missing selected model never silently falls back")
    func missingModel() {
        #expect(MeetingRetranscriptionPolicy.resolveModel(
            requested: .whisperLargeV3, configured: .whisperLargeTurbo,
            downloaded: [.whisperLargeTurbo]
        ) == nil)
    }

    @Test("streaming-only models cannot be used for saved recordings")
    func streamingModel() {
        #expect(MeetingRetranscriptionPolicy.resolveModel(
            requested: .nemotron35Multilingual, configured: .whisperLargeV3,
            downloaded: [.nemotron35Multilingual, .whisperLargeV3]
        ) == nil)
    }

    @Test("chooser offers full-recording models and compatible installed alternatives once")
    func choices() {
        let choices = MeetingRetranscriptionPolicy.modelChoices(downloaded: [
            .whisperLargeV3, .senseVoiceSmall, .nemotron35Multilingual, .whisperSmallEnglish
        ])
        #expect(choices == [.whisperLargeV3, .whisperLargeTurbo, .senseVoiceSmall, .whisperSmallEnglish])
        #expect(MeetingRetranscriptionPolicy.modelChoices(downloaded: []) == [.whisperLargeV3, .whisperLargeTurbo])
    }

    @MainActor
    @Test("re-transcription refuses to disturb recording, processing, or another re-transcription",
          arguments: ["recording", "starting", "processing", "retranscribing", "dictation"])
    func activeWorkIsProtected(activity: String) async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = fixture.controller
        switch activity {
        case "recording": controller.appState.isMeetingRecording = true
        case "starting": controller.appState.isMeetingStarting = true
        case "processing": controller.appState.isMeetingProcessing = true
        case "retranscribing": controller.appState.retranscribingMeetingID = fixture.meeting.id + 1
        default: controller.appState.dictationState = .recording
        }
        let originalModel = controller.appState.config.meetingFinalTranscriptionModel
        let result = await withCheckedContinuation { continuation in
            controller.retranscribe(meeting: fixture.meeting, using: .whisperLargeV3) {
                continuation.resume(returning: $0)
            }
        }
        guard case .failure(let error) = result,
              case .transcriptionBusy = error as? MeetingRetranscriptionError else {
            Issue.record("Expected re-transcription to be blocked before touching audio or models")
            return
        }
        let saved = try #require(try fixture.store.meeting(id: fixture.meeting.id))
        #expect(saved.status == .completed)
        #expect(saved.rawTranscript == "Original transcript")
        #expect(saved.formattedNotes == "Original notes")
        #expect(controller.appState.config.meetingFinalTranscriptionModel == originalModel)
        if activity == "retranscribing" {
            #expect(controller.appState.retranscribingMeetingID == fixture.meeting.id + 1)
        }
    }

    @MainActor
    @Test("recording cannot start while a selected model is re-transcribing")
    func recordingAdmission() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.controller.appState.retranscribingMeetingID = fixture.meeting.id
        #expect(!fixture.controller.startMeetingRecording(title: "Should not start"))
    }

    @MainActor
    @Test("a stale completed meeting cannot be re-transcribed after processing starts")
    func staleMeeting() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        fixture.controller.appState.meetingRows = [fixture.meeting]
        try fixture.store.updateMeetingStatus(id: fixture.meeting.id, status: .processing)
        let result = await withCheckedContinuation { continuation in
            fixture.controller.retranscribe(meeting: fixture.meeting, using: .whisperLargeV3) {
                continuation.resume(returning: $0)
            }
        }
        guard case .failure(let error) = result,
              case .transcriptionBusy = error as? MeetingRetranscriptionError else {
            Issue.record("Expected the fresh meeting status to prevent a second transcription")
            return
        }
        #expect(try fixture.store.meeting(id: fixture.meeting.id)?.status == .processing)
    }

    @MainActor
    private func makeFixture() throws -> (
        directory: URL, store: DictationStore, meeting: MeetingRecord, controller: MuesliController
    ) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("mimo-retranscription-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = DictationStore(databaseURL: directory.appendingPathComponent("test.db"))
        try store.migrateIfNeeded()
        let meetingID = try store.insertMeeting(
            title: "Saved meeting", calendarEventID: nil, startTime: Date(), endTime: Date(),
            rawTranscript: "Original transcript", formattedNotes: "Original notes",
            micAudioPath: nil, systemAudioPath: nil,
            savedRecordingPath: directory.appendingPathComponent("recording.wav").path
        )
        let meeting = try #require(try store.meeting(id: meetingID))
        let controller = MuesliController(
            runtime: RuntimePaths(repoRoot: directory, menuIcon: nil, appIcon: nil, bundlePath: nil),
            dictationStore: store, configStore: ConfigStore(supportDirectory: directory)
        )
        return (directory, store, meeting, controller)
    }
}
