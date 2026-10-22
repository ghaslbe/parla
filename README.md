<div align="center">

# Parla

**Free, open-source, model-agnostic push-to-talk dictation for macOS.**

Hold a key, speak, and your words are typed at the cursor in whatever app you're in.
Transcription runs on your Mac by default — nothing is uploaded.

`macOS 13+` · `Apple Silicon` · `Swift` · `MIT`

</div>

---

## Why

Most good dictation apps are closed and lock you into a single transcription
engine. Parla does the opposite: **transcription is a swappable backend**, so
you can run whatever model you like — Apple's on-device model, a local
whisper.cpp model, or any remote/local OpenAI-compatible server.

It's free, it's open, and by default your audio never leaves the machine.

## Features

- 🎙️ **Push-to-talk** — hold a key, speak, release. Or press-to-toggle.
- ⌨️ **Types at your cursor** in any app, without clobbering your clipboard.
- 🔀 **Three transcription backends**, switchable in Settings (see below).
- 🔒 **Local by default** — audio stays on your Mac; no telemetry.
- 🪶 **Lightweight menu-bar app** — no Dock icon, no window in your face.
- 🧩 **Hackable** — add a new engine in ~30 lines behind one protocol.

## Transcription backends

| Backend | Setup | Runs on | Notes |
|---|---|---|---|
| **Apple on-device** *(default)* | none | your Mac | macOS 26+. System manages language assets automatically. |
| **Built-in whisper.cpp** | download a model in-app | your Mac's GPU (Metal) | Works offline. Whisper tiny → large-v3-turbo. |
| **OpenAI-compatible** | enter an endpoint URL | wherever you point it | OpenAI, Groq, LM Studio, llama.cpp server, faster-whisper-server, … |

All three are selected from **Settings → Transcription**. The audio never
leaves your Mac for the two local options; with the OpenAI-compatible option it
goes only to the server you choose.

## Install & build

Requirements: **Xcode** (for the macOS SDK + Metal), **CMake**, and **Swift 5.9+**.

```sh
git clone <your-fork-url> parla
cd parla
make run          # build everything, assemble Parla.app, launch it
```

Other targets:

```sh
make app          # build the release .app bundle (no launch)
make debug        # fast debug bundle
make clean        # remove build artifacts
```

The first build runs `scripts/build-whisper.sh`, which fetches whisper.cpp (a
pinned release) and compiles it into static libraries with the **Metal backend
embedded** — so the finished app is a single self-contained binary with no
runtime dependencies. Always build via `make`, not bare `swift build`, so those
libraries exist first.

> **Note on signing.** Builds are ad-hoc signed for local use. To share the app
> with others you'll need a Developer ID signature + notarization, otherwise
> Gatekeeper will block it on other Macs.

## Usage

1. Launch Parla — a 🎙️ icon appears in the menu bar.
2. Grant the three permissions (see below) and relaunch.
3. **Hold right ⌥**, speak, release. The transcript is typed at your cursor.

Open **Settings** from the menu-bar icon to change the trigger key, pick a
backend, set the language, or switch the insert method.

### Permissions

macOS will prompt for these the first time they're needed; you can also manage
them in **System Settings → Privacy & Security**, and re-check them from Parla's
Settings window.

| Permission | Why |
|---|---|
| **Microphone** | to capture your voice |
| **Accessibility** | to type the text at your cursor |
| **Input Monitoring** | to detect the dictation key being held |

## Configuration

Everything is in the Settings window:

- **Trigger** — right ⌥ / ⌘ / ⌃, or fn. Hold-to-talk or press-to-toggle.
- **Backend** — Apple on-device, built-in whisper.cpp, or OpenAI-compatible.
  - *whisper.cpp:* download/select/delete models in-app.
  - *OpenAI-compatible:* endpoint (`…/v1`), optional API key, model name.
- **Language** — ISO code (e.g. `en`, `de`) or empty for auto-detect.
- **Output** — type directly (keeps clipboard) or paste via ⌘V.

### Using a remote or custom model

Point the OpenAI-compatible backend at any server speaking
`POST {endpoint}/audio/transcriptions` — for example a local
[`faster-whisper-server`](https://github.com/fedirz/faster-whisper-server),
`whisper.cpp`'s `whisper-server`, Groq, or OpenAI:

- **Endpoint:** `http://127.0.0.1:8080/v1` (whatever your server uses)
- **Model:** the model name your server expects
- **API key:** only if the server/provider requires one

## How it works

Five small pieces wired together by `DictationController`:

1. **Hotkey** — a `CGEventTap` detects the trigger key *(Input Monitoring)*.
2. **Audio** — `AVAudioEngine` captures the mic, resampled to 16 kHz mono *(Microphone)*.
3. **Transcription** — a `TranscriptionProvider` turns samples into text.
4. **Insert** — synthetic key events type the text at the cursor *(Accessibility)*.
5. **UI** — menu-bar item, floating "listening" pill, SwiftUI settings.

The whole point is step 3: anything model-specific lives behind the
`TranscriptionProvider` protocol, so the rest of the app never cares which
engine runs.

```swift
protocol TranscriptionProvider {
    func transcribe(samples: [Float], language: String?) async throws -> String
}
```

### Project layout

```
Sources/Parla/
  main.swift                 entry point (+ hidden --selftest modes)
  Core/      AppDelegate, DictationController, Settings, ModelManager
  Audio/     AudioRecorder          mic → 16 kHz mono Float32
  Hotkey/    HotkeyMonitor          CGEventTap push-to-talk
  Transcribe/ TranscriptionProvider (protocol)
             AppleSpeechProvider          Apple on-device (macOS 26+)
             LocalWhisperProvider + WhisperEngine   whisper.cpp (Metal)
             OpenAICompatibleProvider     any HTTP server
  Insert/    TextInserter           type at cursor / paste
  UI/        PillWindow, SettingsView
Sources/CWhisper/            module map exposing whisper.cpp to Swift
scripts/build-whisper.sh     fetches + builds whisper.cpp (Metal, static)
scripts/bundle.sh            assembles + ad-hoc signs Parla.app
```

### Verifying the engines

Hidden developer self-tests run a backend on a 16 kHz mono WAV and print the
transcript — no mic or accessibility prompts needed:

```sh
.build/release/Parla --selftest <model.bin> <audio.wav>   # whisper.cpp
.build/release/Parla --selftest-apple <audio.wav>         # Apple on-device
```

## Roadmap

- [x] Apple on-device provider (SpeechAnalyzer / SpeechTranscriber, macOS 26+)
- [x] Built-in whisper.cpp provider (embedded Metal engine, on-device models)
- [x] In-app model download (Whisper tiny → large-v3-turbo)
- [x] OpenAI-compatible provider (any remote/local server)
- [ ] Optional LLM cleanup pass (punctuation, filler removal)
- [ ] Move API key to the Keychain
- [ ] Personal dictionary / text snippets
- [ ] Developer ID signing + notarization for distribution
- [ ] Linux port

## Contributing

Issues and PRs welcome. A new transcription backend is the easiest place to
start: implement `TranscriptionProvider`, add a case to `ProviderKind`, and wire
it into `DictationController.provider()`.

## Acknowledgements

- [whisper.cpp](https://github.com/ggml-org/whisper.cpp) by Georgi Gerganov and
  contributors — the embedded offline engine.
- Apple's Speech framework (`SpeechAnalyzer` / `SpeechTranscriber`).

## License

[MIT](LICENSE).
