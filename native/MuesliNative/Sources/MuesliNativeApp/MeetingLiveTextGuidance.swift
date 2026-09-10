/// Describes the actual live-text route without making optional draft captions
/// look like a requirement for transcription during the meeting.
enum MeetingLiveTextGuidance {
    static let transcriptModelLabel = "Use transcript model"

    static let reviewedLiveModelLabel = "SenseVoice Small · fast live text"

    static func reviewedMeetingDescription(finalModel: BackendOption) -> String {
        "SenseVoice Small shows Mandarin Chinese and English as spoken, about every 3 seconds or at pauses. After Stop, \(finalModel.label) transcribes the complete recording. Mimo compares the two transcripts before writing English minutes and flags unresolved details."
    }

    static func previewLabel(_ backend: MeetingLiveCaptionBackend, chineseEnglishBilingual: Bool) -> String {
        switch backend {
        case .parakeetRealtimeEOU: "Parakeet · English preview"
        case .nemotron35: chineseEnglishBilingual
            ? "Nemotron 3.5 · Multilingual preview"
            : "Nemotron 3.5 · Live + saved"
        }
    }

    static func description(
        transcriptModel: BackendOption,
        preview: MeetingLiveCaptionBackend?,
        chineseEnglishBilingual: Bool
    ) -> String {
        switch preview {
        case .none:
            if chineseEnglishBilingual && transcriptModel == .senseVoiceSmall {
                return "SenseVoice Small shows Chinese and English as spoken, in short updates about every 3 seconds or at pauses. You can switch between Mandarin and English. No extra preview model is needed."
            }
            return "\(transcriptModel.label) shows live text as speech segments finish. No extra preview model is needed. Transcription keeps the spoken language; it does not translate the text."
        case .parakeetRealtimeEOU:
            return "English-only draft captions. Chinese and other languages are not supported by this preview. The meeting transcript model supplies completed segments."
        case .nemotron35:
            if chineseEnglishBilingual {
                return "Draft captions support Mandarin and English with automatic language detection. Words may be missed when switching mid-sentence; \(transcriptModel.label) supplies completed segments. Speech is transcribed in its original language."
            }
            return "Live text and the saved transcript use Nemotron 3.5. It supports 32 language locales, including Mandarin and English. Automatic detection does not guarantee reliable mixing within a sentence. Enable Chinese + English meetings for a separate model to confirm mixed-language speech."
        }
    }
}
