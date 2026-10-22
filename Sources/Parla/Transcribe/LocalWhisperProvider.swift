import Foundation

/// Built-in offline transcription via whisper.cpp (Metal). Fully on-device:
/// audio never leaves the Mac.
struct LocalWhisperProvider: TranscriptionProvider {
    let modelPath: String

    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard samples.count > 1600 else { throw TranscriptionError.empty }
        guard !modelPath.isEmpty else {
            throw TranscriptionError.notConfigured("no local model selected — download one in Settings")
        }

        // whisper_full is a blocking CPU/GPU call; run it off the cooperative pool.
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let text = try WhisperEngine.shared.transcribe(
                        samples: samples, modelPath: modelPath, language: language)
                    if text.isEmpty { cont.resume(throwing: TranscriptionError.empty) }
                    else { cont.resume(returning: text) }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }
}
