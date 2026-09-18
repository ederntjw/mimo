import Foundation
import MuesliCore
import Testing
@testable import MuesliNativeApp

@Suite("Live meeting assistant")
struct LiveMeetingAssistantTests {
    @Test("live summary becomes visible during a short meeting")
    func responsiveCheckpointTiming() {
        #expect(LiveMeetingSummaryPolicy.initialDelay == 12)
        #expect(LiveMeetingSummaryPolicy.refreshDelay == 30)
        #expect(LiveMeetingSummaryPolicy.minimumTranscriptCharacters <= 160)
    }

    @Test("recording meetings open directly on Live Summary")
    func liveSummaryIsDefaultWorkspace() {
        #expect(LiveMeetingWorkspacePolicy.opensLiveSummary(for: .recording))
        #expect(!LiveMeetingWorkspacePolicy.opensLiveSummary(for: .processing))
        #expect(!LiveMeetingWorkspacePolicy.opensLiveSummary(for: .completed))
    }

    @Test("Live Meeting honors the selected ChatGPT model")
    func subscriptionModelPolicy() {
        var configured = AppConfig()
        configured.meetingSummaryBackend = MeetingSummaryBackendOption.ollama.backend
        configured.chatGPTModel = "gpt-5.4"

        let live = MeetingSummaryClient.liveMeetingConfiguration(from: configured)

        #expect(live.meetingSummaryBackend == MeetingSummaryBackendOption.chatGPT.backend)
        #expect(live.chatGPTModel == "gpt-5.4")
        #expect(MeetingSummaryClient.liveMeetingBackend == "chatgpt")
        #expect(MeetingSummaryClient.liveMeetingModel == "auto")
        configured.chatGPTModel = "gpt-5.4-mini"
        #expect(MeetingSummaryClient.liveMeetingConfiguration(from: configured).chatGPTModel == "auto")
        configured.chatGPTModel = "gpt-5.6-luna"
        #expect(MeetingSummaryClient.liveMeetingConfiguration(from: configured).chatGPTModel == "gpt-5.6-luna")
    }

    @Test("Live Meeting keeps the configured supported local transcriber")
    func localTranscriptionPolicy() {
        let available: [BackendOption] = [
            .whisperSmall,
            .appleSpeechAnalyzer,
            .parakeetMultilingual,
            .parakeetUnified,
        ]

        #expect(
            BackendOption.resolvedLiveMeetingTranscriptionBackend(
                configured: .appleSpeechAnalyzer,
                availableOptions: available
            ) == .appleSpeechAnalyzer
        )
        #expect(
            BackendOption.resolvedLiveMeetingTranscriptionBackend(
                configured: .whisperSmall,
                availableOptions: available
            ) == .whisperSmall
        )
        #expect(
            BackendOption.resolvedLiveMeetingTranscriptionBackend(
                configured: .whisperSmall,
                availableOptions: [.whisperSmall]
            ) == .whisperSmall
        )
    }

    @Test("rolling summary waits for enough committed transcript")
    func summaryMinimum() {
        #expect(!LiveMeetingSummaryPolicy.shouldGenerate(
            transcriptCharacterCount: LiveMeetingSummaryPolicy.minimumTranscriptCharacters - 1,
            lastSummarizedCharacterCount: 0,
            isGenerating: false
        ))
        #expect(LiveMeetingSummaryPolicy.shouldGenerate(
            transcriptCharacterCount: LiveMeetingSummaryPolicy.minimumTranscriptCharacters,
            lastSummarizedCharacterCount: 0,
            isGenerating: false
        ))
    }

    @Test("rolling summary requires meaningful new speech")
    func summaryDelta() {
        let previous = 1_000
        #expect(!LiveMeetingSummaryPolicy.shouldGenerate(
            transcriptCharacterCount: previous + LiveMeetingSummaryPolicy.minimumNewCharacters - 1,
            lastSummarizedCharacterCount: previous,
            isGenerating: false
        ))
        #expect(LiveMeetingSummaryPolicy.shouldGenerate(
            transcriptCharacterCount: previous + LiveMeetingSummaryPolicy.minimumNewCharacters,
            lastSummarizedCharacterCount: previous,
            isGenerating: false
        ))
        #expect(!LiveMeetingSummaryPolicy.shouldGenerate(
            transcriptCharacterCount: previous + LiveMeetingSummaryPolicy.minimumNewCharacters,
            lastSummarizedCharacterCount: previous,
            isGenerating: true
        ))
    }

    @Test("live digest is explicitly non-final")
    func digestPrompt() {
        let prompt = MeetingSummaryClient.liveDigestTemplate.prompt
        #expect(prompt.contains("meeting is still happening"))
        #expect(prompt.contains("Never imply the meeting has ended"))
        #expect(prompt.contains("## Decisions"))
        #expect(prompt.contains("## Open questions"))
    }

    @Test("question prompt demands grounded timestamped answers")
    func questionPrompt() {
        let template = MeetingSummaryClient.liveQuestionTemplate(
            question: "  What deadline did Alex promise?  "
        )
        #expect(template.prompt.contains("User question: What deadline did Alex promise?"))
        #expect(template.prompt.contains("[HH:MM:SS]"))
        #expect(template.prompt.contains("If the answer has not been stated"))
        #expect(template.prompt.contains("Do not guess"))
    }

    @Test("question text is bounded before entering the model prompt")
    func questionLimit() {
        let oversized = String(repeating: "x", count: 2_500)
        let template = MeetingSummaryClient.liveQuestionTemplate(question: oversized)
        #expect(template.prompt.contains(String(repeating: "x", count: 2_000)))
        #expect(!template.prompt.contains(String(repeating: "x", count: 2_001)))
    }

    @Test("saved meeting questions cannot include another meeting's live captions")
    func savedTranscriptIsolation() {
        #expect(MeetingAssistantTranscriptPolicy.transcript(
            meetingID: 10,
            savedTranscript: "[00:01:00] Alex: Ship on Friday.",
            liveOwnerID: 20,
            liveTranscript: "Private discussion from another meeting."
        ) == "[00:01:00] Alex: Ship on Friday.")
        #expect(MeetingAssistantTranscriptPolicy.transcript(
            meetingID: 10, savedTranscript: "Final transcript", liveOwnerID: nil, liveTranscript: "Stale captions"
        ) == "Final transcript")
    }

    @Test("a resumed meeting can answer from both saved and current speech")
    func resumedTranscriptContext() {
        let transcript = MeetingAssistantTranscriptPolicy.transcript(
            meetingID: 10, savedTranscript: "Prior discussion", liveOwnerID: 10, liveTranscript: "New discussion"
        )
        #expect(transcript.contains("Prior discussion"))
        #expect(transcript.contains("New discussion"))
    }

    @Test("completed meeting prompts include follow-up context without claiming to record")
    func completedFollowUpPrompt() {
        let prompt = MeetingSummaryClient.liveQuestionTemplate(
            question: "Who owns that?",
            history: [
                LiveMeetingAssistantMessage(role: .user, text: "What is the next step?"),
                LiveMeetingAssistantMessage(role: .assistant, text: "Prepare the launch checklist.")
            ],
            isOngoing: false
        ).prompt
        #expect(prompt.contains("The session has ended"))
        #expect(!prompt.contains("The session is ongoing"))
        #expect(prompt.contains("User: What is the next step?"))
        #expect(prompt.contains("Assistant: Prepare the launch checklist."))
        #expect(prompt.contains("User question: Who owns that?"))
        #expect(prompt.contains("previous answers are not evidence"))
    }

    @Test("follow-up context is bounded to recent turns and message length")
    func boundedHistory() {
        let history = [LiveMeetingAssistantMessage(role: .user, text: "OLD QUESTION")]
            + (0..<12).map { LiveMeetingAssistantMessage(role: .assistant, text: "Turn \($0) " + String(repeating: "z", count: 3_000)) }
        let prompt = MeetingSummaryClient.liveQuestionTemplate(question: "Continue", history: history).prompt
        #expect(!prompt.contains("OLD QUESTION"))
        #expect(prompt.contains("Turn 11"))
        #expect(!prompt.contains(String(repeating: "z", count: 2_001)))
        #expect(prompt.count < 26_000)
    }

    @MainActor
    @Test("completed meetings accept questions independently of the active recording")
    func completedMeetingAcceptsQuestions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-assistant-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DictationStore(databaseURL: directory.appendingPathComponent("test.db"))
        try store.migrateIfNeeded()
        let meetingID = try store.insertMeeting(
            title: "Finished meeting", calendarEventID: nil, startTime: Date(), endTime: Date(),
            rawTranscript: "", formattedNotes: "", micAudioPath: nil, systemAudioPath: nil
        )
        let controller = MuesliController(
            runtime: RuntimePaths(repoRoot: directory, menuIcon: nil, appIcon: nil, bundlePath: nil),
            dictationStore: store, configStore: ConfigStore(supportDirectory: directory)
        )
        let otherMeetingID = meetingID + 1
        let existingQuestion = LiveMeetingAssistantMessage(role: .user, text: "Live question")
        controller.appState.liveMeetingTranscriptOwnerID = otherMeetingID
        controller.appState.liveMeetingTranscript = "Another meeting is still recording."
        controller.appState.isMeetingRecording = true
        controller.appState.meetingAssistantConversations[otherMeetingID] = MeetingAssistantConversation(
            messages: [existingQuestion], requestID: UUID()
        )

        controller.askLiveMeetingAssistant(question: "What was decided?", meetingID: meetingID)

        let conversation = try #require(controller.appState.meetingAssistantConversations[meetingID])
        #expect(conversation.messages.count == 2)
        #expect(conversation.messages.first?.text == "What was decided?")
        #expect(conversation.messages.last?.text.contains("does not have a saved transcript") == true)
        #expect(!conversation.isAnswering)
        #expect(controller.appState.meetingAssistantConversations[otherMeetingID]?.messages == [existingQuestion])
        #expect(controller.appState.meetingAssistantConversations[otherMeetingID]?.isAnswering == true)
        #expect(controller.appState.isMeetingRecording)
        #expect(controller.appState.liveMeetingTranscriptOwnerID == otherMeetingID)
        #expect(controller.appState.liveMeetingTranscript == "Another meeting is still recording.")
    }

}
