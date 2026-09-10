import AppIntents

@available(macOS 13.0, *)
enum MuesliShortcutsError: Swift.Error, CustomLocalizedStringResourceConvertible {
    case noDictations
    case noMeetings
    case notRunning

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noDictations: return "Mimo has no dictations yet."
        case .noMeetings: return "Mimo has no meetings yet."
        case .notRunning: return "Mimo isn't running. Open Mimo and try again."
        }
    }
}
