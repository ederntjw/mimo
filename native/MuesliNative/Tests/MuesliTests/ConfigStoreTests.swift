import Testing
import Foundation
import MuesliCore
@testable import MuesliNativeApp

@Suite("ConfigStore", .serialized)
struct ConfigStoreTests {

    @Test("load returns a valid config")
    func loadReturnsConfig() {
        let supportDirectory = makeSupportDirectory(label: "load")
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let store = ConfigStore(supportDirectory: supportDirectory)
        let config = store.load()
        #expect(HotkeyConfig.label(for: config.dictationHotkey.keyCode) != nil)
        #expect(!config.sttBackend.isEmpty)
    }

    @Test("a fresh profile uses the single bilingual speech setup")
    func freshProfileUsesSimpleBilingualSetup() {
        let supportDirectory = makeSupportDirectory(label: "fresh-bilingual")
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let store = ConfigStore(supportDirectory: supportDirectory)

        let config = store.load()

        #expect(config.usesSimpleBilingualSetup)
        #expect(!config.darkMode)
        #expect(!config.enableScreenContext)
        #expect(!config.enableDictationOCRContext)
        #expect(config.sttBackend == BackendOption.whisperLargeV3.backend)
        #expect(config.sttModel == BackendOption.whisperLargeV3.model)
        #expect(config.meetingTranscriptionModel == BackendOption.whisperLargeV3.model)
        #expect(config.dictationProvider == DictationProvider.local.rawValue)
        #expect(config.meetingSummaryBackend == MeetingSummaryBackendOption.chatGPT.backend)
        #expect(config.whisperLanguage == WhisperKitLanguage.auto.rawValue)
        store.save(config)
        #expect(store.load().usesSimpleBilingualSetup)
    }

    @Test("an existing profile without the new flag retains its provider choices")
    func legacyProfileDoesNotOptIntoCloudWriting() throws {
        let supportDirectory = makeSupportDirectory(label: "legacy-bilingual")
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let store = ConfigStore(supportDirectory: supportDirectory)
        let legacyJSON = #"{"stt_backend":"parakeet-unified","meeting_summary_backend":"ollama","post_processor_backend":"local","enable_post_processor":false}"#
        try Data(legacyJSON.utf8).write(to: store.configPath())

        let config = store.load()

        #expect(!config.usesSimpleBilingualSetup)
        #expect(config.sttBackend == "parakeet-unified")
        #expect(config.meetingSummaryBackend == "ollama")
        #expect(config.postProcessorBackend == "local")
        #expect(!config.enablePostProcessor)
    }

    @Test("an unreadable existing profile is not treated as a new simple profile")
    func existingCorruptProfileDoesNotOptIn() throws {
        let supportDirectory = makeSupportDirectory(label: "corrupt-bilingual")
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let store = ConfigStore(supportDirectory: supportDirectory)
        try Data("invalid json".utf8).write(to: store.configPath())
        #expect(!store.load().usesSimpleBilingualSetup)
    }

    @Test("save and load round-trip")
    func saveLoadRoundTrip() throws {
        let supportDirectory = makeSupportDirectory(label: "roundtrip")
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let store = ConfigStore(supportDirectory: supportDirectory)

        var config = AppConfig()
        config.openAIAPIKey = "sk-test-roundtrip"
        config.openAIModel = "gpt-5.4-pro"
        config.openRouterAPIKey = "sk-or-test-roundtrip"
        config.openRouterModel = "nvidia/nemotron-3-super-120b-a12b:free"
        config.cohereLanguage = CohereTranscribeLanguage.german.rawValue
        config.whisperLanguage = WhisperKitLanguage.german.rawValue
        config.appleSpeechLanguage = "en-US"
        config.meetingSummaryBackend = "openrouter"
        store.save(config)

        let loaded = store.load()
        #expect(loaded.openAIAPIKey == "sk-test-roundtrip")
        #expect(loaded.openAIModel == "gpt-5.4-pro")
        #expect(loaded.openRouterAPIKey.isEmpty)
        #expect(
            try OpenRouterCredentialStore(supportDirectory: supportDirectory).load()?.apiKey ==
                "sk-or-test-roundtrip"
        )
        #expect(loaded.openRouterModel == "nvidia/nemotron-3-super-120b-a12b:free")
        #expect(loaded.cohereLanguage == CohereTranscribeLanguage.german.rawValue)
        #expect(loaded.whisperLanguage == WhisperKitLanguage.german.rawValue)
        #expect(loaded.appleSpeechLanguage == "en-US")
        #expect(loaded.meetingSummaryBackend == "openrouter")
    }

    @Test("config path honors the isolated support directory")
    func configPath() {
        let supportDirectory = makeSupportDirectory(label: "path")
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let store = ConfigStore(supportDirectory: supportDirectory)
        let path = store.configPath().path
        #expect(path.hasPrefix(supportDirectory.path))
        #expect(path.hasSuffix("config.json"))
    }

    @Test("saved config uses owner-only file permissions")
    func configPermissions() throws {
        let supportDirectory = makeSupportDirectory(label: "permissions")
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let store = ConfigStore(supportDirectory: supportDirectory)

        store.save(AppConfig())

        let attributes = try FileManager.default.attributesOfItem(atPath: store.configPath().path)
        let permissions = attributes[.posixPermissions] as? NSNumber

        #expect(permissions?.intValue == 0o600)
    }

    @Test("legacy migration preserves an existing dedicated credential")
    func legacyMigrationPreservesExistingCredential() throws {
        let supportDirectory = makeSupportDirectory(label: "migration-existing")
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        try FileManager.default.createDirectory(
            at: supportDirectory,
            withIntermediateDirectories: true
        )

        let credentialStore = OpenRouterCredentialStore(supportDirectory: supportDirectory)
        let existingCredential = OpenRouterCredential(
            apiKey: "sk-or-new-oauth",
            userID: "user-new"
        )
        try credentialStore.save(existingCredential)

        var staleConfig = AppConfig()
        staleConfig.openRouterAPIKey = "sk-or-stale-legacy"
        let configURL = supportDirectory.appendingPathComponent("config.json")
        try JSONEncoder().encode(staleConfig).write(to: configURL, options: .atomic)

        let loaded = ConfigStore(supportDirectory: supportDirectory).load()

        #expect(loaded.openRouterAPIKey.isEmpty)
        #expect(try credentialStore.load() == existingCredential)
        let persistedConfig = try JSONDecoder().decode(
            AppConfig.self,
            from: Data(contentsOf: configURL)
        )
        #expect(persistedConfig.openRouterAPIKey.isEmpty)
    }

    private func makeSupportDirectory(label: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "muesli-config-\(label)-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
