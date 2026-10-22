import AppKit

/// Orchestrates the dictation pipeline:
/// hotkey → record → transcribe (via the selected provider) → insert at cursor.
final class DictationController {
    private let recorder = AudioRecorder()
    private let hotkey = HotkeyMonitor()
    private let pill = PillWindow()
    private var busy = false

    func start() {
        hotkey.onPress = { [weak self] in self?.beginRecording() }
        hotkey.onRelease = { [weak self] in self?.finishRecording() }
        hotkey.onToggle = { [weak self] in
            guard let self else { return }
            self.recorder.isRunning ? self.finishRecording() : self.beginRecording()
        }
        hotkey.start()
    }

    func stop() { hotkey.stop() }

    // MARK: - Pipeline

    private func beginRecording() {
        guard !busy, !recorder.isRunning else { return }
        do {
            try recorder.start()
            pill.show(.listening)
        } catch {
            pill.flashError("Mic error")
            NSLog("Parla: audio start failed: \(error)")
        }
    }

    private func finishRecording() {
        guard recorder.isRunning else { return }
        let samples = recorder.stop()
        busy = true
        pill.show(.transcribing)

        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.provider().transcribe(
                    samples: samples,
                    language: AppSettings.shared.language.isEmpty ? nil : AppSettings.shared.language)
                await MainActor.run {
                    self.pill.hide()
                    TextInserter.insert(text, method: AppSettings.shared.insertMethod)
                    self.busy = false
                }
            } catch {
                await MainActor.run {
                    self.pill.flashError(Self.shortMessage(error))
                    self.busy = false
                }
                NSLog("Parla: transcription failed: \(error)")
            }
        }
    }

    private func provider() -> TranscriptionProvider {
        let s = AppSettings.shared
        switch s.provider {
        case .openAICompatible:
            return OpenAICompatibleProvider(baseURL: s.endpoint, apiKey: s.apiKey, model: s.model)
        case .localWhisper:
            return LocalWhisperProvider(modelPath: s.localModelPath)
        }
    }

    private static func shortMessage(_ error: Error) -> String {
        if let e = error as? TranscriptionError, let d = e.errorDescription { return d }
        return error.localizedDescription
    }
}
