<p align="center">
  <img src="assets/repository-open-graph.png" alt="Mimo — Hear it. Keep it. Ask it." width="900" />
</p>

<p align="center">
  <a href="https://github.com/ederntjw/mimo/releases"><strong>Download Mimo for macOS</strong></a>
  &nbsp;·&nbsp;
  <a href="#live-meetings-that-stay-live">Live meetings</a>
  &nbsp;·&nbsp;
  <a href="#build-and-test">Build from source</a>
</p>

Mimo is a native Mac companion for conversations that keep moving. It transcribes
in-person and online meetings as they happen, maintains a rolling brief, and lets
you ask questions about what has already been said without stopping the recording.

It also handles everyday dictation, voice-directed text editing, and transcription
of existing audio or video files. Speech recognition can stay on your Mac; the
reasoning provider for summaries, questions, and cleanup is your choice.

Mimo runs on Apple silicon Macs. The macOS app is the current focus; companion
apps follow the desktop workflow.

## The short version

| You want to… | Mimo can… |
|---|---|
| Follow an in-person discussion | Listen through the Mac microphone and build a live transcript |
| Capture Zoom, Meet, Teams, or another call | Record microphone and system audio as separate sides of the conversation |
| Catch up without interrupting | Maintain a rolling brief of decisions, actions, key points, and open questions |
| Ask while people are still talking | Answer from a read-only snapshot of committed transcript while recording continues |
| Reuse an old recording | Import `.mp3`, `.mp4`, `.m4a`, or `.wav` and turn it into a transcript and notes |
| Rewrite text by voice | Highlight text, speak the change with Quill, and replace the selection in place |
| Type anywhere by speaking | Use the global dictation hotkey and paste the result at the cursor |

## Live meetings that stay live

Mimo is designed around one important constraint: asking a question or refreshing
notes must never pause capture.

1. In **Settings → Meetings**, choose the after-meeting model. Download SenseVoice
   Small and that model from **Models**, then choose **Start Live Meeting**.
2. Mimo records the room through your microphone. For an online call, it can also
   capture the other side through macOS system audio.
3. SenseVoice Small supplies live Mandarin–English text in short batches, including
   language switches.
4. The live brief refreshes as enough new context arrives.
5. Ask a question such as “What deadline did we agree on?” Mimo answers from the
   transcript collected up to that moment while recording keeps running.
6. Stop when the conversation ends. The selected Whisper model transcribes the
   complete recording, then Mimo compares it with the live draft before generating
   English minutes. A transcript-review section flags differences to confirm.

The reviewed workflow is enabled by default, with full Whisper Large v3 selected
for the final pass. Whisper Large Turbo is the faster, smaller alternative. Both
meeting models must be downloaded before recording; Mimo does not silently swap
the final model. Your recording-save preference controls whether audio is retained
after processing. See the [model guide](docs/model-guide.md) for requirements.

No meeting bot has to join the room. In-person meetings need only microphone access;
online capture additionally uses macOS System Audio Recording permission.

## A Mac app with ten moods

Classic remains the calm default. Strawberry Milk, Cherry Ribbon, Lavender Dream,
Peach Sorbet, Mint Macaron, and Rose Quartz bring softer palettes and rounded details;
Neon Grid, Aurora Glass, and Solar Flare add bolder futuristic color systems.
Switching themes is immediate and does not require a restart.

<p align="center">
  <img src="assets/mimo-strawberry-appearance.jpg" alt="Mimo settings showing the Strawberry Milk theme" width="860" />
</p>

Choose a palette from **Settings → Appearance → Theme**. Each styled theme initially
selects its matching accent; the accent remains independently customizable afterward.

## More than meeting notes

### Quill

Select text in another app, hold the Quill shortcut, and describe the edit you want.
Mimo captures the selection before recording, sends the original text and spoken
instruction to the configured cleanup model, then replaces the selection. With no
selection, Quill can create text at the cursor instead.

### Recorded files

Use **Import Audio** for lectures, interviews, voice memos, podcasts, or screen
recordings you already have. Imported media follows the same transcription,
diarization, note-generation, search, and export pipeline as a live meeting.

### Dictation

Hold the dictation hotkey, speak, and release. Mimo transcribes and pastes into the
active app. Hands-free double-tap mode, a personal dictionary, filler-word removal,
and optional cleanup are available when you need them.

### Meeting memory

Meetings can be organized in folders, searched, re-summarized with another template,
and exported as Markdown or PDF. The local database keeps the core workflow
available even when the Mac is offline.

## Models and privacy

Transcription and reasoning are separate choices in Mimo.

| Job | Recommended starting point | Other options |
|---|---|---|
| Live Mandarin–English meeting text | SenseVoice Small on-device | Reviewed meetings keep this live model separate from the final pass |
| Final meeting transcription | Full Whisper Large v3 on-device | Whisper Large Turbo for a faster, smaller final pass |
| English dictation | Parakeet Unified on-device | Other curated local models or a configured hosted dictation provider |
| Meeting summaries and live Q&A | ChatGPT subscription sign-in | OpenAI or OpenRouter with an API key, Ollama, LM Studio, or a compatible custom endpoint |
| Dictation transcript cleanup | Mimo Tiny Cleanup, bundled on-device | ChatGPT, hosted providers, or larger supported local models |
| Quill voice editing | ChatGPT subscription or a general-purpose local model | OpenAI, OpenRouter, Ollama, LM Studio, or a custom endpoint |

With an on-device transcription model, microphone audio is processed locally.
If you select a hosted transcription provider, audio is sent to that provider. If
you select ChatGPT or another hosted reasoning provider for summaries, questions,
or cleanup, the relevant transcript or text is sent only for that requested task.
Account sessions and provider credentials remain local, in macOS Keychain or
permission-restricted local files, and are never part of Mimo Account sync.

## Install

### Download the DMG

1. Open the [Mimo releases page](https://github.com/ederntjw/mimo/releases).
2. Download the newest `Mimo-*.dmg` asset.
3. Open the disk image and drag **Mimo** into **Applications**.
4. Launch Mimo and follow onboarding for the permissions and transcription model.

The public release workflow requires Developer ID signing and Apple notarization
before publication. A normal first-open confirmation may appear. If macOS says a
copy is damaged or cannot be verified, download a fresh copy from this repository's
release page and report the issue if it persists.

### Updates

Mimo checks for signed updates automatically once per day. You can also choose
**Check for Updates…** from its menu-bar menu at any time. When a release is
available, Mimo shows the release notes, downloads the DMG through Sparkle, verifies
it with Mimo's dedicated EdDSA public key, installs it, and relaunches. An existing
installation therefore does not need another manual drag to Applications.

Maintainers publish an update from a clean, CI-passing `main` branch with one tag:

```bash
./scripts/publish_mimo_update.sh 0.8.8
```

The tag-triggered GitHub workflow builds and signs the native Mac app with
Developer ID, notarizes and staples the app and DMG, then signs the final update
metadata using the protected `MIMO_SPARKLE_PRIVATE_KEY` repository secret. It
creates a draft release, downloads and verifies the uploaded files, and only then
publishes the release and moves the stable appcast feed to it. Signing and
notarization credentials are required. Mimo Account sync is optional: leave both
Supabase client settings absent for a library stored on this Mac, or configure
both to enable account sync. An incomplete pair or invalid project URL stops the
release. Private keys are never committed to this repository.

### Requirements

- Apple Silicon Mac
- macOS 14.2 or later
- Xcode 16 or later only when building from source
- Microphone permission for speech capture
- Accessibility and Input Monitoring for global hotkeys and text insertion
- System Audio Recording for online-meeting capture

The application includes the roughly 235 MB Mimo Tiny Cleanup text model. Speech
models download separately: SenseVoice Small is about 240 MB, full Whisper Large
v3 about 3.1 GB, and Turbo about 626 MB. The default reviewed meeting workflow needs
SenseVoice and full Large v3; you can explicitly select Turbo instead. English
dictation's Parakeet Unified model is about 565 MB. The [model guide](docs/model-guide.md)
distinguishes download sizes, working memory, and total Mac RAM recommendations.

## Build and test

```bash
git clone https://github.com/ederntjw/mimo.git
cd mimo

# Build, test, and install an isolated development lane.
./scripts/dev-test.sh --lane A

# Run the complete Swift package test suite directly.
swift test --package-path native/MuesliNative \
  --scratch-path "$HOME/Library/Caches/muesli-spm/test"
```

Signed app bundles require the complete LocalVQE runtime used for acoustic echo
cancellation:

```bash
source scripts/localvqe_runtime.sh
if ! muesli_localvqe_runtime_is_complete native/MuesliNative/LocalVQE/lib; then
  ./scripts/build_localvqe.sh
fi
```

Contributor builds use fixed dev lanes (`A`, `B`, or `C`) so they do not overwrite
the production app or share its support directory. See [AGENTS.md](AGENTS.md) for
the exact packaging/cache rules and [CONTRIBUTING.md](CONTRIBUTING.md) for the full
development workflow.

## Project map

```text
native/MuesliNative/   macOS application, shared services, and Swift tests
native/MuesliXcode/    generated Xcode application target
muesli-ios/            iPhone companion project
scripts/               development, verification, packaging, and release tools
docs/                  product, privacy, release, and engineering documentation
assets/                Mimo artwork and supporting application assets
```

Before opening a large pull request, please start with an issue describing the
problem and intended behavior. Every change should include proportionate tests and
preserve the local-first path.

## Open-source components

The application also relies on excellent open-source work including
[FluidAudio](https://github.com/FluidInference/FluidAudio),
[WhisperKit](https://github.com/argmaxinc/WhisperKit),
[LocalVQE](https://github.com/localai-org/LocalVQE), and Apple's native audio,
Core ML, and SwiftUI frameworks.

## License

Mimo is available under the [MIT License](LICENSE).
Required copyright and third-party notices are preserved in [LICENSE](LICENSE)
and [NOTICE](NOTICE).

Maintainers: see [Mimo release signing and notarization](docs/mimo-release-setup.md)
for the GitHub download setup and release checks.
