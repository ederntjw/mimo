import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("Spoken snippet matching")
struct SpokenSnippetMatcherTests {
    @Test("matches the whole phrase despite case, whitespace and sentence punctuation")
    func normalizedWholePhrase() {
        let expansion = "Best,\nEdern\n  engineer@example.com  "
        let snippets = [SpokenSnippet(trigger: "my email signature", expansion: expansion)]
        #expect(SpokenSnippetMatcher.expansion(for: "  MY\tEMAIL\nSIGNATURE...！  ", snippets: snippets) == expansion)
    }

    @Test("does not expand substrings, extra instructions or similar phrases")
    func noAccidentalExpansion() {
        let snippets = [SpokenSnippet(trigger: "my signature", expansion: "Saved text")]
        for utterance in ["please add my signature", "my signature please", "my signatures", "my signatur", "my, signature", "my-signature"] {
            #expect(SpokenSnippetMatcher.expansion(for: utterance, snippets: snippets) == nil)
        }
    }

    @Test("supports Chinese and mixed-language triggers without translating")
    func bilingualTriggers() {
        let snippets = [SpokenSnippet(trigger: "我的 email 签名", expansion: "谢谢，Edern\nProduct Engineering")]
        #expect(SpokenSnippetMatcher.expansion(for: "我的 EMAIL 签名。", snippets: snippets) == snippets[0].expansion)
        #expect(SpokenSnippetMatcher.expansion(for: "我的email签名", snippets: snippets) == nil)
    }

    @Test("preserves meaningful symbols, internal punctuation and diacritics")
    func distinctPhrasesStayDistinct() {
        let snippets = [SpokenSnippet(trigger: "c# example", expansion: "Code"), SpokenSnippet(trigger: "café reply", expansion: "Reply")]
        #expect(SpokenSnippetMatcher.expansion(for: "c example", snippets: snippets) == nil)
        #expect(SpokenSnippetMatcher.expansion(for: "cafe reply", snippets: snippets) == nil)
        #expect(SpokenSnippetMatcher.expansion(for: "cafe\u{301} reply!", snippets: snippets) == "Reply")
    }

    @Test("ambiguous or empty matches never expand")
    func invalidMatchesFailClosed() {
        let snippets = [SpokenSnippet(trigger: "reply", expansion: "First"), SpokenSnippet(trigger: "REPLY!", expansion: "Second")]
        #expect(SpokenSnippetMatcher.expansion(for: "reply", snippets: snippets) == nil)
        #expect(SpokenSnippetMatcher.expansion(for: "...", snippets: [SpokenSnippet(trigger: "", expansion: "Hidden")]) == nil)
        #expect(SpokenSnippetMatcher.expansion(for: "reply", snippets: [SpokenSnippet(trigger: "reply", expansion: " \n")]) == nil)
    }
}

@Suite("Spoken snippet persistence")
@MainActor
struct SpokenSnippetStoreTests {
    @Test("CRUD survives reload and retains stable identifiers and literal text")
    func persistenceRoundTrip() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpokenSnippetStore(supportDirectory: directory)
        #expect(store.snippets.isEmpty)
        #expect(store.loadError == nil)
        let snippet = SpokenSnippet(trigger: "  my signature  ", expansion: "Regards,\nEdern  ")
        try store.save(snippet)
        let reopened = SpokenSnippetStore(supportDirectory: directory)
        #expect(reopened.snippets.first?.id == snippet.id)
        #expect(reopened.snippets.first?.trigger == "my signature")
        #expect(reopened.expansion(for: "MY SIGNATURE.") == snippet.expansion)
        try reopened.save(SpokenSnippet(id: snippet.id, trigger: "work signature", expansion: "新的签名\nNew signature"))
        #expect(reopened.snippets.count == 1)
        #expect(reopened.expansion(for: "my signature") == nil)
        try store.reload()
        #expect(store.expansion(for: "work signature") == "新的签名\nNew signature")
        try store.delete(id: snippet.id)
        #expect(SpokenSnippetStore(supportDirectory: directory).snippets.isEmpty)
    }

    @Test("rejects duplicate normalized phrases without changing stored content")
    func duplicateTriggersAreRejected() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpokenSnippetStore(supportDirectory: directory)
        try store.save(SpokenSnippet(trigger: "my signature", expansion: "Original"))
        let before = try Data(contentsOf: store.fileURL)
        #expect(throws: SpokenSnippetError.duplicateTrigger) {
            try store.save(SpokenSnippet(trigger: "MY   SIGNATURE!", expansion: "Replacement"))
        }
        #expect(try Data(contentsOf: store.fileURL) == before)
        #expect(store.snippets.count == 1)
    }

    @Test("rejects phrases without words and blank expansions")
    func validatesInput() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpokenSnippetStore(supportDirectory: directory)
        #expect(throws: SpokenSnippetError.emptyTrigger) {
            try store.save(SpokenSnippet(trigger: " 。!? ", expansion: "Text"))
        }
        #expect(throws: SpokenSnippetError.emptyExpansion) {
            try store.save(SpokenSnippet(trigger: "my reply", expansion: " \n\t"))
        }
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
    }

    @Test("a damaged library cannot be silently overwritten")
    func preservesUnreadableLibrary() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("spoken-snippets.json")
        let damagedData = Data("not valid JSON".utf8)
        try damagedData.write(to: file)
        let store = SpokenSnippetStore(supportDirectory: directory)
        #expect(store.loadError != nil)
        #expect(throws: SpokenSnippetError.unreadableLibrary) {
            try store.save(SpokenSnippet(trigger: "my reply", expansion: "Text"))
        }
        #expect(try Data(contentsOf: file) == damagedData)

        try Data(#"{"version":1,"snippets":[]}"#.utf8).write(to: file)
        try store.reload()
        #expect(store.loadError == nil)
        try store.save(SpokenSnippet(trigger: "my reply", expansion: "Recovered"))
        #expect(store.expansion(for: "my reply") == "Recovered")
    }

    @Test("a future schema fails closed rather than discarding new data")
    func preservesFutureSchema() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("spoken-snippets.json")
        let futureData = Data(#"{"version":2,"snippets":[],"newField":"keep"}"#.utf8)
        try futureData.write(to: file)
        let store = SpokenSnippetStore(supportDirectory: directory)
        #expect(store.loadError != nil)
        #expect(throws: SpokenSnippetError.unsupportedVersion) { try store.reload() }
        #expect(try Data(contentsOf: file) == futureData)
    }

    @Test("failed disk writes preserve the in-memory library")
    func writeFailureIsTransactional() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpokenSnippetStore(supportDirectory: directory)
        try store.save(SpokenSnippet(trigger: "my reply", expansion: "Original"))
        let before = store.snippets
        try FileManager.default.removeItem(at: store.fileURL)
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: false)
        #expect(throws: (any Error).self) {
            try store.save(SpokenSnippet(trigger: "another reply", expansion: "Unsaved"))
        }
        #expect(store.snippets == before)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mimo-snippets-\(UUID().uuidString)", isDirectory: true)
    }
}
