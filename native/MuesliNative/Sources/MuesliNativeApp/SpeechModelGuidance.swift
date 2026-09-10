import Foundation

/// Language coverage describes the shipped model, not a promise that arbitrary
/// language pairs can be mixed. `switching` describes Mimo's actual route/evidence.
/// Primary model cards and runtime language selection were reviewed 2026-09-10.
struct SpeechModelGuidance: Equatable, Sendable {
    enum Switching: Equatable, Sendable {
        case englishOnly
        case chooseOneLanguage
        case automaticDetection
        case chineseEnglishTested
        case notVerified
    }

    /// Full model language list where stable; empty for system-dependent or
    /// unverified coverage. Model coverage can exceed the manual language picker.
    let languages: [String]
    let languageSummary: String
    let switching: Switching
    let switchingSummary: String
    let bestFor: String
    let limitation: String
    let recommendedForDiscovery: Bool
}

extension BackendOption {
    var speechGuidance: SpeechModelGuidance {
        let details: (languages: [String], summary: String, switching: SpeechModelGuidance.Switching, mixing: String, best: String, limit: String)
        switch backend {
        case "parakeet-unified":
            // https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml
            details = (["English"], "English only", .englishOnly,
                       "English only. Cannot transcribe Chinese or switch between languages.",
                       "Fast English dictation and meeting transcripts.",
                       "Choose SenseVoice Small for Mandarin Chinese and English together.")
        case "fluidaudio" where model == Self.parakeetMultilingual.model:
            // https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
            details = (SpeechLanguageLists.parakeetV3, "25 European languages; Chinese is not supported", .automaticDetection,
                       "Automatically detects supported languages. Switching languages within one recording has not been verified in Mimo.",
                       "Fast English and European-language transcription.",
                       "Automatic detection does not establish reliable mixed-language transcription.")
        case "fluidaudio":
            details = (["English"], "English only", .englishOnly,
                       "English only. Cannot transcribe Chinese or switch between languages.",
                       "Existing Parakeet v2 setups.",
                       "An older model; Parakeet Unified is recommended for new English setups.")
        case "sensevoice":
            // Small has five languages. Do not inherit the family's 50+ claim.
            // https://huggingface.co/FunAudioLLM/SenseVoiceSmall
            details = (["Mandarin Chinese", "Cantonese", "English", "Japanese", "Korean"],
                       "Mandarin Chinese, Cantonese, English, Japanese and Korean", .chineseEnglishTested,
                       "Mandarin Chinese and English can be mixed in the same meeting; this pair passed Mimo's audio check. Other mixed pairs are unverified.",
                       "Fast Mandarin Chinese and English meeting updates in short batches.",
                       "Accuracy varies with accents, noise and rapid switches. This is not word-by-word streaming.")
        case "whisper" where !supportsWhisperLanguageSelection:
            details = (["English"], "English only", .englishOnly,
                       "English only. The .en model cannot transcribe Chinese or switch languages.",
                       "Existing English Whisper setups.",
                       "An older model; Parakeet Unified is recommended for fast English transcription.")
        case "whisper":
            // Full Large v3 favors post-meeting context over live latency.
            // https://huggingface.co/openai/whisper-large-v3
            // https://huggingface.co/openai/whisper-large-v3-turbo
            // https://github.com/openai/whisper/blob/main/whisper/tokenizer.py
            let isTurbo = model == Self.whisperLargeTurbo.model
            let isFullV3 = model == Self.whisperLargeV3.model
            let languages = SpeechLanguageLists.whisper + (isTurbo || isFullV3 ? ["Cantonese"] : [])
            details = (languages, "\(languages.count) model languages, including Mandarin Chinese and English",
                       isTurbo ? .chineseEnglishTested : .automaticDetection,
                       isTurbo
                           ? "Mandarin Chinese and English mixing passed Mimo's audio check. Use Auto-detect for mixed meetings; other mixed pairs are unverified."
                           : isFullV3
                               ? "Recognizes Mandarin Chinese and English with automatic language detection. Mixed-language accuracy varies; compare the final transcript with the live draft."
                               : "Automatically detects language. This older variant is not the tested recommendation for mixed Mandarin Chinese and English meetings.",
                       isFullV3 ? "Accuracy-focused transcription of the full recording after a meeting."
                           : isTurbo ? "A faster, smaller final pass with broad language coverage." : "Existing multilingual Whisper setups.",
                       isTurbo
                           ? "Trades some accuracy for speed compared with full Large v3. SenseVoice Small supplies live text in reviewed meetings."
                           : isFullV3
                               ? "A larger download and slower final pass than Turbo. A larger model does not guarantee every disputed word is correct."
                               : "Retained for compatibility. Choose SenseVoice Small or a current Whisper Large model for new mixed-language setups.")
        case "nemotron35":
            // 32 usable locales = 28 languages; exclude eight adaptation-only locales.
            // https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b
            details = (SpeechLanguageLists.nemotron35,
                       "28 languages across 32 locales, including Mandarin Chinese and English", .automaticDetection,
                       "Auto-detection identifies utterance languages. Reliable switching within a sentence has not been verified in Mimo.",
                       "Live text for hold-to-talk or hands-free dictation, with automatic language detection.",
                       "Includes native punctuation, but streaming does not go back to correct earlier words. Mandarin belongs to the model's lower-accuracy coverage tier. Reviewed meetings use SenseVoice for mixed-language live text.")
        case "cohere":
            // Publisher explicitly documents inconsistent code-switched audio.
            // https://huggingface.co/CohereLabs/cohere-transcribe-03-2026
            details = (SpeechLanguageLists.cohere, "14 languages; choose one before recording", .chooseOneLanguage,
                       "One chosen language per recording. No automatic language detection; mixed-language results are inconsistent.",
                       "Existing setups for recordings in one language.",
                       "Large download and delayed results; not recommended for fast mixed-language meetings.")
        case "indicasr":
            // Upstream has 22; the shipped conversion has only these seven heads.
            // https://huggingface.co/phequals/indic-conformer-600m-multilingual-coreml-rnnt
            details = (["Hindi", "Bengali", "Marathi", "Telugu", "Tamil", "Malayalam", "Kannada"],
                       "7 Indian languages in Mimo; choose one before recording", .chooseOneLanguage,
                       "One chosen language per recording. Mimo selects one language-specific recognizer; automatic switching is unavailable.",
                       "Existing experimental setups for these seven Indian languages.",
                       "English and Chinese are not supported by this packaged model.")
        case "qwen":
            // https://huggingface.co/Qwen/Qwen3-ASR-0.6B
            // Upstream vLLM streaming is not the local runtime shipped by Mimo.
            details = (SpeechLanguageLists.qwen3,
                       "30 languages and 22 Chinese dialects in the model", .automaticDetection,
                       "Automatic language detection is available. Same-session language mixing has not been verified in Mimo.",
                       "Existing experimental setups needing broader Chinese dialect coverage.",
                       "Preparation and transcription can be slow. The publisher's streaming benchmark does not describe Mimo's local route.")
        case "apple-speech":
            // https://developer.apple.com/documentation/speech/speechtranscriber/init(locale:preset:)
            details = ([], "Languages supplied by macOS; choose one available on this Mac", .chooseOneLanguage,
                       "One selected language per session in Mimo. Automatic switching between languages is unavailable.",
                       "System-managed on-device dictation and meetings on macOS 26.",
                       "Language availability depends on macOS and downloaded speech assets.")
        default:
            details = ([], "Speech language coverage is not verified in Mimo", .notVerified,
                       "Reliable transcription and language switching have not been verified in Mimo.",
                       "Existing experimental setups only.",
                       "Not recommended for meetings. May answer or rewrite instead of transcribing speech faithfully.")
        }
        return SpeechModelGuidance(
            languages: details.languages,
            languageSummary: details.summary,
            switching: details.switching,
            switchingSummary: details.mixing,
            bestFor: details.best,
            limitation: details.limit,
            recommendedForDiscovery: isCurated
        )
    }
}

private enum SpeechLanguageLists {
    static let parakeetV3 = [
        "Bulgarian", "Croatian", "Czech", "Danish", "Dutch", "English", "Estonian",
        "Finnish", "French", "German", "Greek", "Hungarian", "Italian", "Latvian",
        "Lithuanian", "Maltese", "Polish", "Portuguese", "Romanian", "Russian",
        "Slovak", "Slovenian", "Spanish", "Swedish", "Ukrainian",
    ]

    static let nemotron35 = [
        "English (US, UK)", "Spanish (US, Spain)", "French (France, Canada)",
        "Italian", "Portuguese (Brazil, Portugal)", "Dutch", "German", "Turkish",
        "Russian", "Arabic", "Hindi", "Japanese", "Korean", "Vietnamese", "Ukrainian",
        "Polish", "Swedish", "Czech", "Norwegian Bokmål", "Danish", "Bulgarian",
        "Finnish", "Croatian", "Slovak", "Mandarin Chinese", "Hungarian", "Romanian", "Estonian",
    ]

    static let cohere = [
        "English", "French", "German", "Spanish", "Italian", "Portuguese", "Dutch",
        "Polish", "Greek", "Arabic", "Japanese", "Mandarin Chinese", "Vietnamese", "Korean",
    ]

    static let qwen3 = [
        "Mandarin Chinese", "English", "Cantonese", "Arabic", "German", "French",
        "Spanish", "Portuguese", "Indonesian", "Italian", "Korean", "Russian", "Thai",
        "Vietnamese", "Japanese", "Turkish", "Hindi", "Malay", "Dutch", "Swedish",
        "Danish", "Finnish", "Polish", "Czech", "Filipino", "Persian", "Greek",
        "Hungarian", "Macedonian", "Romanian",
    ]

    // Small/Tiny's 99-language vocabulary; v3 adds a separate Cantonese token.
    static let whisper = [
        "English", "Mandarin Chinese", "German", "Spanish", "Russian", "Korean", "French",
        "Japanese", "Portuguese", "Turkish", "Polish", "Catalan", "Dutch", "Arabic",
        "Swedish", "Italian", "Indonesian", "Hindi", "Finnish", "Vietnamese", "Hebrew",
        "Ukrainian", "Greek", "Malay", "Czech", "Romanian", "Danish", "Hungarian", "Tamil",
        "Norwegian", "Thai", "Urdu", "Croatian", "Bulgarian", "Lithuanian", "Latin", "Māori",
        "Malayalam", "Welsh", "Slovak", "Telugu", "Persian", "Latvian", "Bengali", "Serbian",
        "Azerbaijani", "Slovenian", "Kannada", "Estonian", "Macedonian", "Breton", "Basque",
        "Icelandic", "Armenian", "Nepali", "Mongolian", "Bosnian", "Kazakh", "Albanian",
        "Swahili", "Galician", "Marathi", "Punjabi", "Sinhala", "Khmer", "Shona", "Yoruba",
        "Somali", "Afrikaans", "Occitan", "Georgian", "Belarusian", "Tajik", "Sindhi",
        "Gujarati", "Amharic", "Yiddish", "Lao", "Uzbek", "Faroese", "Haitian Creole",
        "Pashto", "Turkmen", "Norwegian Nynorsk", "Maltese", "Sanskrit", "Luxembourgish",
        "Burmese", "Tibetan", "Tagalog", "Malagasy", "Assamese", "Tatar", "Hawaiian",
        "Lingala", "Hausa", "Bashkir", "Javanese", "Sundanese",
    ]
}
