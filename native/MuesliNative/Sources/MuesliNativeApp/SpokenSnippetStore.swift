import Combine
import Foundation

enum SpokenSnippetError: LocalizedError, Equatable {
    case emptyTrigger
    case emptyExpansion
    case duplicateTrigger
    case duplicateIdentifier
    case missingSnippet
    case unsupportedVersion
    case unreadableLibrary

    var errorDescription: String? {
        switch self {
        case .emptyTrigger: "Enter a phrase containing a word or number."
        case .emptyExpansion: "Enter the text this phrase should insert."
        case .duplicateTrigger: "That spoken phrase already belongs to another snippet."
        case .duplicateIdentifier: "The snippets file contains duplicate entries."
        case .missingSnippet: "This snippet no longer exists."
        case .unsupportedVersion: "This snippets file needs a newer version of Mimo."
        case .unreadableLibrary: "Your snippets could not be loaded. Retry loading them before making changes."
        }
    }
}

/// The app should share one instance between the snippets page and dictation.
/// Failed reads never turn into an empty library that silently overwrites user data.
@MainActor
final class SpokenSnippetStore: ObservableObject {
    @Published private(set) var snippets: [SpokenSnippet] = []
    @Published private(set) var loadError: String?

    let fileURL: URL

    private struct Document: Codable {
        var version = 1
        var snippets: [SpokenSnippet]
    }

    init(supportDirectory: URL = AppIdentity.supportDirectoryURL) {
        fileURL = supportDirectory.appendingPathComponent("spoken-snippets.json")
        try? reload()
    }

    func reload() throws {
        do {
            let loaded: [SpokenSnippet]
            do {
                let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: fileURL))
                guard document.version == 1 else { throw SpokenSnippetError.unsupportedVersion }
                try Self.validate(document.snippets)
                loaded = document.snippets
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                loaded = []
            }
            snippets = loaded
            loadError = nil
        } catch {
            loadError = error.localizedDescription
            throw error
        }
    }

    func expansion(for utterance: String) -> String? {
        guard loadError == nil else { return nil }
        return SpokenSnippetMatcher.expansion(for: utterance, snippets: snippets)
    }

    /// Adds a new snippet or updates the entry with the same stable identifier.
    func save(_ snippet: SpokenSnippet) throws {
        var candidate = snippets
        var cleaned = snippet
        cleaned.trigger = cleaned.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = candidate.firstIndex(where: { $0.id == cleaned.id }) {
            candidate[index] = cleaned
        } else {
            candidate.append(cleaned)
        }
        try persist(candidate)
    }

    func delete(id: UUID) throws {
        guard snippets.contains(where: { $0.id == id }) else { throw SpokenSnippetError.missingSnippet }
        try persist(snippets.filter { $0.id != id })
    }

    private func persist(_ candidate: [SpokenSnippet]) throws {
        guard loadError == nil else { throw SpokenSnippetError.unreadableLibrary }
        try Self.validate(candidate)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Document(snippets: candidate))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        snippets = candidate
    }

    private static func validate(_ snippets: [SpokenSnippet]) throws {
        var triggers = Set<String>()
        var identifiers = Set<UUID>()
        for snippet in snippets {
            let trigger = SpokenSnippetMatcher.normalizedTrigger(snippet.trigger)
            guard trigger.rangeOfCharacter(from: .alphanumerics) != nil else {
                throw SpokenSnippetError.emptyTrigger
            }
            guard !snippet.expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw SpokenSnippetError.emptyExpansion
            }
            guard triggers.insert(trigger).inserted else { throw SpokenSnippetError.duplicateTrigger }
            guard identifiers.insert(snippet.id).inserted else { throw SpokenSnippetError.duplicateIdentifier }
        }
    }
}
