import Foundation

/// Keeps live and final model roles explicit instead of silently substituting a model.
struct MeetingTranscriptionPlan: Equatable {
    static let finalModels: [BackendOption] = [.whisperLargeV3, .whisperLargeTurbo]

    let liveBackend: BackendOption
    let finalBackend: BackendOption?

    init(config: AppConfig, singlePassBackend: BackendOption) {
        liveBackend = config.meetingFinalPassEnabled ? .senseVoiceSmall : singlePassBackend
        finalBackend = config.meetingFinalPassEnabled ? config.resolvedMeetingFinalBackend : nil
    }

    func missingModels(from available: [BackendOption]) -> [BackendOption] {
        ([liveBackend] + (finalBackend.map { [$0] } ?? [])).filter { !available.contains($0) }
    }
}

enum MeetingRetranscriptionPolicy {
    /// Keep the full-recording choices visible even when they need downloading.
    static func modelChoices(downloaded: [BackendOption]) -> [BackendOption] {
        (MeetingTranscriptionPlan.finalModels + downloaded.filter(\.supportsMeetingTranscription))
            .reduce(into: []) { choices, option in
                if !choices.contains(option) { choices.append(option) }
            }
    }

    static func resolveModel(
        requested: BackendOption?,
        configured: BackendOption,
        downloaded: [BackendOption]
    ) -> BackendOption? {
        let selected = requested ?? configured
        // An explicit choice must never silently fall back to another model.
        guard selected.supportsMeetingTranscription, downloaded.contains(selected) else { return nil }
        return selected
    }
}
