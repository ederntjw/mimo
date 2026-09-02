import Foundation
import MuesliCore
import Testing
@testable import MuesliNativeApp

@Suite("Live meeting and lecture modes", .serialized)
struct LiveSessionKindTests {
    @Test("lecture has a distinct persisted source and note structure")
    func lectureTemplateAndPersistence() throws {
        #expect(MeetingSource.lecture.rawValue == "lecture")
        #expect(MeetingTemplates.lecture.id == "lecture")
        #expect(MeetingTemplates.lecture.promptBody.contains("## Core Concepts"))
        #expect(MeetingTemplates.lecture.promptBody.contains("## Study Checklist"))
        #expect(MeetingSummaryClient.liveDigestTemplate(for: .lecture).id == "live-lecture-digest")
        #expect(MeetingSummaryClient.liveDigestTemplate(for: .meeting).id == "live-meeting-digest")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimo-live-lecture-\(UUID().uuidString).db")
        let store = DictationStore(databaseURL: url)
        try store.migrateIfNeeded()
        let id = try store.createLiveMeeting(
            title: "Live Lecture",
            calendarEventID: nil,
            startTime: Date(),
            selectedTemplateID: MeetingTemplates.lecture.id,
            selectedTemplateName: MeetingTemplates.lecture.title,
            selectedTemplateKind: MeetingTemplates.lecture.kind,
            selectedTemplatePrompt: MeetingTemplates.lecture.promptBody,
            source: .lecture
        )
        let loadedRecord = try store.meeting(id: id)
        let record = try #require(loadedRecord)

        #expect(record.source == .lecture)
        #expect(record.selectedTemplateID == MeetingTemplates.lecture.id)
        #expect(record.status == .recording)
    }

    @Test("lecture Q&A tells the model which transcript it is answering")
    func lectureQuestionPrompt() {
        let meeting = MeetingSummaryClient.liveQuestionTemplate(
            question: "What should I review?",
            sessionKind: .meeting
        )
        let lecture = MeetingSummaryClient.liveQuestionTemplate(
            question: "What should I review?",
            sessionKind: .lecture
        )

        #expect(meeting.prompt.contains("meeting transcript"))
        #expect(lecture.prompt.contains("lecture transcript"))
        #expect(meeting.prompt != lecture.prompt)
    }
}
