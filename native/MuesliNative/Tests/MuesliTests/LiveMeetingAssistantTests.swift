import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Live meeting assistant")
struct LiveMeetingAssistantTests {
    @Test("live summary becomes visible during a short meeting")
    func responsiveCheckpointTiming() {
        #expect(LiveMeetingSummaryPolicy.initialDelay <= 15)
        #expect(LiveMeetingSummaryPolicy.refreshDelay <= 30)
        #expect(LiveMeetingSummaryPolicy.minimumTranscriptCharacters <= 160)
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
