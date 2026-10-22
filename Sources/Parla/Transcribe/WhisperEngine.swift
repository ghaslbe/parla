import Foundation
import CWhisper

/// Thin wrapper around whisper.cpp. Loads a GGML model once, caches the context
/// (model load is the expensive part), and runs transcription on a serial queue
/// because a `whisper_context` is not thread-safe.
final class WhisperEngine {
    static let shared = WhisperEngine()

    private let queue = DispatchQueue(label: "dev.parla.whisper")
    private var ctx: OpaquePointer?
    private var loadedPath: String?

    private init() {}

    enum EngineError: LocalizedError {
        case modelMissing(String)
        case loadFailed(String)
        case inferenceFailed(Int32)

        var errorDescription: String? {
            switch self {
            case .modelMissing(let p): return "Model not found at \(p)"
            case .loadFailed(let p):   return "Could not load model \(p)"
            case .inferenceFailed(let c): return "whisper_full failed (\(c))"
            }
        }
    }

    /// Transcribe 16 kHz mono samples. Blocking; call off the main thread.
    func transcribe(samples: [Float], modelPath: String, language: String?) throws -> String {
        try queue.sync {
            try load(modelPath)
            guard let ctx else { throw EngineError.loadFailed(modelPath) }

            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            params.print_realtime = false
            params.print_progress = false
            params.print_timestamps = false
            params.print_special = false
            params.translate = false
            params.single_segment = false
            params.no_context = true
            params.suppress_blank = true
            params.n_threads = Int32(max(1, ProcessInfo.processInfo.activeProcessorCount - 1))

            // `language` must outlive the whisper_full call.
            let langC: UnsafeMutablePointer<CChar>? = {
                guard let language, !language.isEmpty else { return nil }
                return strdup(language)
            }()
            defer { if let langC { free(langC) } }
            if let langC {
                params.language = UnsafePointer(langC)
                params.detect_language = false
            } else {
                params.language = nil
                params.detect_language = true
            }

            let rc = samples.withUnsafeBufferPointer { buf in
                whisper_full(ctx, params, buf.baseAddress, Int32(buf.count))
            }
            if rc != 0 { throw EngineError.inferenceFailed(rc) }

            var text = ""
            let n = whisper_full_n_segments(ctx)
            for i in 0..<n {
                if let seg = whisper_full_get_segment_text(ctx, i) {
                    text += String(cString: seg)
                }
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    // MARK: - Model lifecycle

    private func load(_ path: String) throws {
        if loadedPath == path, ctx != nil { return }
        guard FileManager.default.fileExists(atPath: path) else {
            throw EngineError.modelMissing(path)
        }
        if let ctx { whisper_free(ctx); self.ctx = nil }

        var cparams = whisper_context_default_params()
        cparams.use_gpu = true       // Metal
        cparams.flash_attn = false   // not supported on every GPU; keep it safe

        let newCtx = path.withCString { whisper_init_from_file_with_params($0, cparams) }
        guard let newCtx else { throw EngineError.loadFailed(path) }
        ctx = newCtx
        loadedPath = path
    }
}
