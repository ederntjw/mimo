import Foundation

/// A spoken phrase and the literal text to insert when that whole phrase is dictated.
struct SpokenSnippet: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var trigger: String
    var expansion: String

    init(id: UUID = UUID(), trigger: String, expansion: String) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
    }
}

enum SpokenSnippetMatcher {
    // Ignore sentence punctuation supplied by transcription. Keep meaningful symbols,
    // apostrophes, hyphens and internal punctuation so distinct phrases stay distinct.
    private static let sentenceEndings = CharacterSet(charactersIn: ".!?。！？…，,;；:：")

    static func normalizedTrigger(_ text: String) -> String {
        var result = text.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = result.unicodeScalars.last,
              sentenceEndings.contains(last) || CharacterSet.whitespacesAndNewlines.contains(last) {
            result.unicodeScalars.removeLast()
        }
        return result.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    /// Full-utterance matching only. An ambiguous library fails closed instead of
    /// choosing an arbitrary expansion. The replacement is returned without edits.
    static func expansion(for utterance: String, snippets: [SpokenSnippet]) -> String? {
        let trigger = normalizedTrigger(utterance)
        guard !trigger.isEmpty else { return nil }
        let matches = snippets.filter { normalizedTrigger($0.trigger) == trigger }
        guard matches.count == 1,
              let match = matches.first,
              !match.expansion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return match.expansion
    }
}
