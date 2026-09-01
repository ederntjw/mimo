# Live Meeting Assistant — Mac-first product plan

Date: 2026-09-01

## Product definition

The app listens to the microphone and Mac system audio while a meeting or lecture is still happening. It keeps three surfaces live at the same time:

1. A timestamped transcript of committed speech.
2. A rolling brief of the important points, decisions, actions, and open questions so far.
3. A grounded Q&A thread for questions about what has already been said.

Recording and transcription must never wait for summary or Q&A requests. An answer uses a read-only snapshot of the committed transcript taken when the question is submitted; speech that happens after submission belongs to the next question or brief refresh.

## Market and open-source research

The closest commercial behavior is not only Doubao. [Feishu's Doubao-powered intelligent meeting notes](https://www.feishu.cn/content/article/7602950574425803975) advertise streaming transcription and in-meeting summaries. [Tencent Meeting's AI assistant](https://meeting.tencent.com/news/banbenshangxin-241.html) is an even closer reference: it can answer questions such as what happened in the previous ten minutes while the meeting is in progress. Both are proprietary and tied to their own services.

The strongest reusable open-source candidates were:

| Project | Fit | License / signal on 2026-09-01 | Decision |
| --- | --- | --- | --- |
| [Muesli](https://github.com/Muesli-HQ/muesli) | Native Swift/AppKit/SwiftUI; separate mic and system capture; streaming ASR; diarization; many model providers | MIT; about 1.1k stars and 121 forks | Use as the foundation. It has the most mature native capture/transcription layer and the strongest adoption signal. |
| [Loqui](https://github.com/joaquingit1/loqui) | Exact live-transcript chat behavior; append-only transcript; local providers | MIT; about 3 stars | Use as an architectural reference, not the base. Its Electron + Python sidecar is heavier and the project has little adoption evidence. |
| [Murmur](https://github.com/murmur-io/murmur) | In-meeting `@brain`, source-linked answers, local knowledge vault | AGPL-3.0; about 8 stars | Do not copy into a permissively licensed product. Its live captions are also mic-only until recording stops. |
| [Oats](https://github.com/yuvrajadhikari/oats) | Very small native Swift implementation using Apple SpeechAnalyzer and Foundation Models | MIT; about 4 stars; macOS 26 only | Useful reference for an all-Apple local mode, but it lacks live Q&A and has a much smaller feature/test surface. |
| [Tacet](https://github.com/Tacetapp/tacet) | Live transcript, live insights, chat, local ASR and diarization | MIT; no adoption signal yet | Watch for ideas; not a safer base than Muesli. |

The imported code is Muesli at upstream commit `3e5bce08c89abe9a831fd866b20d4849be641737` (2026-09-01). Its original `LICENSE`, `NOTICE`, and attribution must remain. A product rebrand should happen only after a name and distribution identity are chosen.

## Mac-first architecture

```text
Microphone ─┐
            ├─> separate audio streams ─> VAD ─> streaming ASR ─> committed transcript
System audio┘                                                │
                                                             ├─> rolling brief task
User question ─> transcript snapshot ────────────────────────┴─> answer task

Audio capture and ASR own no dependency on either model task.
Summary and Q&A only read transcript snapshots; they never edit the transcript.
```

The native base already provides Core Audio process-tap capture with a ScreenCaptureKit fallback, microphone capture, echo cancellation, local speech models, speaker diarization, crash checkpoints, a meeting library, and configurable ChatGPT/OpenAI/OpenRouter/Ollama/LM Studio/custom-model backends.

The first new slice adds:

- An **Ask** workspace next to **Notes** and **Live** while recording.
- A non-final rolling brief, refreshed asynchronously after sufficient new committed speech.
- Timestamp-grounded transcript Q&A that explicitly says when an answer has not been stated.
- Request identity checks and cancellation so results from an old meeting cannot leak into a new one.
- No changes to the microphone, system-audio, VAD, or transcription callback path.

## Privacy contract

- Raw microphone and system audio remain on the Mac unless the user explicitly enables an existing export/retention feature.
- Local ASR remains the default transcription path.
- The selected summary provider determines where transcript text goes. Ollama and LM Studio can remain local; ChatGPT, OpenAI, OpenRouter, and custom remote endpoints receive the transcript snapshot needed for a brief or answer.
- The Ask screen should make this provider boundary visible before public release. “Local transcription” must never be presented as “everything is local” when a remote reasoning provider is selected.
- Transcript lines are untrusted source material. Prompts instruct the model not to execute instructions quoted inside the meeting.

## MVP acceptance criteria

1. Starting a Zoom, Meet, Teams, FaceTime, or in-person session records mic and system audio without a meeting bot.
2. Committed captions appear during the session and remain timestamped as You/Others.
3. The live brief updates without pausing or dropping capture callbacks.
4. A user can ask a question while recording and receive an answer based only on committed speech, with timestamps for important claims.
5. Asking several questions or refreshing the brief cannot change transcript bytes.
6. Stopping the meeting still runs the existing accurate final transcription, diarization, and structured-summary pipeline.
7. A failed or unavailable reasoning provider shows a recoverable error while recording continues.

## Next engineering increments

1. Persist live Q&A as a separate derived meeting artifact, never inside the source transcript.
2. Add transcript-window retrieval for multi-hour lectures instead of sending the full transcript for every question.
3. Add a provider/privacy badge and per-meeting consent controls.
4. Add audio-callback continuity instrumentation around concurrent local ASR + local LLM load.
5. Add Cantonese/Mandarin/English mixed-language evaluation recordings and a proper word-error-rate/answer-grounding test set.
6. After the Mac loop is stable, reuse the existing iCloud sync/bridge work for a read-only iPhone companion before attempting phone-side capture.
