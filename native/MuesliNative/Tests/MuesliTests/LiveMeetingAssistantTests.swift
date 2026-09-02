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

    @Test("Live Meeting always uses ChatGPT subscription with GPT-5.4 Mini")
    func subscriptionModelPolicy() {
        var configured = AppConfig()
        configured.meetingSummaryBackend = MeetingSummaryBackendOption.ollama.backend
        configured.chatGPTModel = "gpt-5.4"

        let live = MeetingSummaryClient.liveMeetingConfiguration(from: configured)

        #expect(live.meetingSummaryBackend == MeetingSummaryBackendOption.chatGPT.backend)
        #expect(live.chatGPTModel == "gpt-5.4-mini")
        #expect(MeetingSummaryClient.liveMeetingBackend == "chatgpt")
        #expect(MeetingSummaryClient.liveMeetingModel == "gpt-5.4-mini")
    }

    @Test("Live Meeting prefers configured local Parakeet or Apple Speech")
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
            ) == .parakeetUnified
        )
        #expect(
            BackendOption.resolvedLiveMeetingTranscriptionBackend(
                configured: .whisperSmall,
                availableOptions: [.whisperSmall]
            ) == nil
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
}
