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
