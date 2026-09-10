# Choosing models in Mimo

Reviewed September 10, 2026. The app separates language coverage from language
mixing: knowing several languages does not establish that a model can follow
switches within one sentence. Transcription keeps the spoken language. Meeting
summaries and generated notes are in English.

## Reviewed meetings

By default, **Review recording after meeting** separates speed from the final
transcript. SenseVoice Small supplies live Mandarin–English text in short batches.
After Stop, the selected Whisper model transcribes the complete recording, held
temporarily for review. The user’s separate recording-save preference still applies.
Mimo compares that transcript with the live draft before producing English minutes;
unresolved differences in names, numbers, dates, or decisions need confirmation.
Neither model's output is treated as proof that a disputed detail is correct.

**Whisper Large v3** is the default accuracy-focused final model. Choose **Whisper
Large Turbo** for a faster, smaller final pass. Full Large v3 retains 32 decoder layers;
Turbo has four and trades a little quality for speed in the publisher's general
comparison. The gain on a particular Mandarin–English meeting is not guaranteed.
Live captions and the final transcript keep the original spoken languages.

Both SenseVoice and the selected final model must be downloaded before recording.
The app shows missing downloads in Settings → Meetings, with a link to the model
library. It does not silently replace the chosen final model. Choose the workflow
and final model before starting; the meeting keeps those choices through completion.
Turning this workflow off restores the separate one-pass meeting controls.

The final pass processes microphone and system audio separately and retains their
timing. The comparison checks timestamp windows and adds a compact **Transcript
review** section to the notes, including any omitted-issue count. It is a text
comparison, not a second listen by the summary model or proof of correctness.
If the final pass fails, returns unusable timing, or appears to omit substantial
speech, the affected live draft is kept with a confirmation-needed notice.

## Speech models

| Model | Best use | Language behavior in Mimo |
| --- | --- | --- |
| SenseVoice Small | Fast Mandarin–English meetings | Supports Mandarin, Cantonese, English, Japanese, and Korean. Mandarin–English mixing passed Mimo's audio check; other mixed pairs are unverified. Live meeting text arrives in short batches, about every three seconds or at pauses. |
| Whisper Large v3 | Accuracy-focused transcription after Stop | 100 model languages, including Mandarin and English. Automatic detection supports multilingual recordings; mixed-language results still need review. Larger and slower than Turbo. |
| Whisper Large Turbo | Faster, smaller after-meeting pass | 100 model languages. Mandarin–English mixing passed Mimo's audio check with automatic detection. Other mixed pairs are unverified. Uses more memory than SenseVoice but less than full Large v3. |
| Parakeet Unified | Fast English dictation | English only. |
| Parakeet v3 | Fast European-language transcription | 25 European languages, including English; no Chinese. Automatic detection is available, but mixing within a recording is unverified in Mimo. |
| Nemotron 3.5 | Early live text | 28 languages across 32 usable locales, including Mandarin and English. Auto-detection is not a guarantee of sentence-level switching. Bilingual meetings use a separate model for completed segments. |
| Apple Speech | System-managed speech recognition | One selected language per session. Available languages depend on macOS and its language assets. Requires macOS 26. |

When the reviewed workflow is off, “Use transcript model” keeps live meeting text
enabled without an additional preview model. Parakeet Realtime previews are English
only. Preview and meeting language choices must be made before recording because
those engines keep their starting settings. The one-pass meeting transcript model
can still be changed after recording has started.

Older Whisper variants, Parakeet v2, and experimental speech models are excluded
from new recommendations. Current selections and previously downloaded models
remain manageable; no existing model files or settings are deleted automatically.

## Local AI

| Model | Role | Suggested total Mac RAM |
| --- | --- | --- |
| Mimo Tiny Cleanup | Included English-first punctuation and simple cleanup | 8 GB |
| Mimo Cleanup | Correction cues and spoken-list formatting | 8 GB |
| S1-mini | English-only normalization, numbers, and correction cues | 8 GB |
| Qwen 3.5 0.8B | General multilingual text editing and Quill instructions | 8 GB |

These are short-text tools, not local meeting-summary models. Previously
downloaded experimental Gemma models retain their requirements and management
controls; the app does not promote them as dependable speech models.

The model details distinguish download size, estimated working memory, total Mac
RAM, free disk for a download, and runtime disk headroom. RAM figures are Mimo
planning estimates, not manufacturer limits or measured guarantees. Other open
apps and concurrently loaded speech models affect actual memory pressure.
Whisper Turbo and Nemotron have 16 GB recommended total RAM; larger experimental
models carry higher guidance. Full Whisper Large v3 is about a 3.1 GB download;
Mimo suggests at least 16 GB total Mac RAM, preferably 24 GB, and 9 GB free disk
before the first download and preparation. Its estimated working memory is 5–10 GB.
These remain conservative planning estimates, not a measured performance promise.
The app reads chip, RAM, OS, and free disk locally to suggest suitable choices.
This recommendation check does not collect a serial number, send hardware
details, or change model selections automatically.

## Primary references

- [SenseVoice Small](https://huggingface.co/FunAudioLLM/SenseVoiceSmall)
- [Whisper Turbo](https://huggingface.co/openai/whisper-large-v3-turbo)
- [Whisper Large v3](https://huggingface.co/openai/whisper-large-v3)
- [Full Large v3 Core ML artifact](https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-large-v3)
- [Parakeet Unified conversion](https://huggingface.co/FluidInference/parakeet-unified-en-0.6b-coreml)
- [Parakeet v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- [Nemotron 3.5](https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b)
- [Apple Speech locale selection](https://developer.apple.com/documentation/speech/speechtranscriber/init(locale:preset:))
- [SmolLM2 360M](https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct)
- [Qwen 3.5 0.8B](https://huggingface.co/Qwen/Qwen3.5-0.8B)
- [S1-mini](https://huggingface.co/superwhisper/s1-mini-GGUF)

The app-specific language-mixing check and RAM estimates are distinct from the
capabilities documented by these publishers.
