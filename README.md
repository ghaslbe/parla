# Parla

A free, open-source, **model-agnostic** push-to-talk dictation app for macOS.
Hold a key, speak, and the transcribed text is typed at your cursor in any app.

Speech never has to leave your Mac: point Parla at a local Whisper server (or
the built-in whisper.cpp engine, coming soon) and nothing is uploaded anywhere.
Or point it at any OpenAI-compatible endpoint — your choice.

> Working name. MIT-licensed. macOS 13+, Apple Silicon.

## Why

Most good dictation apps are closed and lock you into one transcription engine.
Parla does the opposite: transcription is a swappable backend, so you can run
**any model you like** — local or remote.

## How it works

Five small pieces:

1. **Hotkey** — a `CGEventTap` detects your trigger key (default: hold right ⌥).
   Push-to-talk, or press-to-toggle. *(Needs Input Monitoring permission.)*
2. **Audio** — `AVAudioEngine` captures the mic and resamples to 16 kHz mono.
   *(Needs Microphone permission.)*
3. **Transcription** — a `TranscriptionProvider` turns samples into text:
   - **Built-in whisper.cpp** — fully offline, on-device transcription on the
     GPU (Metal). Models download from inside the app. Audio never leaves the Mac.
   - **OpenAI-compatible** (`POST {endpoint}/audio/transcriptions`) — works with
     OpenAI, Groq, LM Studio, llama.cpp server, faster-whisper-server, …
4. **Insert** — types the text at your cursor via synthetic key events, without
   clobbering your clipboard (or via ⌘V paste). *(Needs Accessibility permission.)*
5. **UI** — a menu-bar item, a floating "listening" pill, and a settings window.

## Build & run

Requires Xcode (for Metal + the macOS SDK), CMake, and Swift 5.9+.

```sh
make run        # build whisper.cpp + release, assemble Parla.app, launch it
make app        # build the .app bundle
make debug      # fast debug bundle
```

The first build runs `scripts/build-whisper.sh`, which clones whisper.cpp
(pinned tag) and compiles it into static libraries with the Metal backend
embedded — so the final app is a single self-contained binary with no runtime
dependencies. Use `make` (not bare `swift build`), so those libs exist first.

### Default (offline) transcription

Open Settings → Transcription → **Built-in whisper.cpp**, download a model
(start with `base.en` for English or `base`/`small` for other languages), and
you are done. Everything runs on your Mac's GPU; nothing is uploaded.

On first launch, grant the three permissions in **System Settings → Privacy &
Security** (Microphone, Accessibility, Input Monitoring), then re-launch. The
settings window has a "Grant" button and a re-check for each.

## Using any other model (OpenAI-compatible)

Prefer a remote model, or a server you already run? Point Parla at any
OpenAI-compatible endpoint — e.g.
[`faster-whisper-server`](https://github.com/fedirz/faster-whisper-server),
`whisper.cpp`'s `whisper-server`, Groq, or OpenAI — in settings:

- **Backend**: OpenAI-compatible server
- **Endpoint**: `http://127.0.0.1:8080/v1` (whatever your server uses)
- **Model**: the model name your server expects
- **API key**: only if your server/provider needs one

Hold right ⌥, speak, release — the text lands at your cursor.

## Roadmap

- [x] Built-in whisper.cpp provider (bundled Metal engine, on-device models)
- [x] One-click model download (Whisper tiny → large-v3-turbo)
- [x] OpenAI-compatible provider (any remote/local server)
- [ ] Optional local LLM cleanup pass (punctuation, filler removal)
- [ ] Move API key to the Keychain
- [ ] Personal dictionary / text snippets
- [ ] Developer ID signing + notarization for distribution
- [ ] Linux port

## Project layout

```
Sources/Parla/
  main.swift                 entry point (+ hidden --selftest)
  Core/      AppDelegate, DictationController, Settings, ModelManager
  Audio/     AudioRecorder          (mic → 16 kHz mono Float32)
  Hotkey/    HotkeyMonitor          (CGEventTap push-to-talk)
  Transcribe/ TranscriptionProvider (protocol)
             OpenAICompatibleProvider, LocalWhisperProvider, WhisperEngine
  Insert/    TextInserter           (type at cursor / paste)
  UI/        PillWindow, SettingsView
Sources/CWhisper/            module map exposing whisper.cpp to Swift
scripts/build-whisper.sh     fetches + builds whisper.cpp (Metal, static)
scripts/bundle.sh            assembles + ad-hoc signs Parla.app
```

### Verify the engine

```sh
.build/release/Parla --selftest <model.bin> <audio.wav>
```
Runs the linked whisper.cpp on a 16 kHz mono WAV and prints the transcript —
handy for checking the engine without microphone/accessibility prompts.

## License

MIT — see [LICENSE](LICENSE).
