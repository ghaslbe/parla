import Foundation

enum TranscriptionError: LocalizedError {
    case notConfigured(String)
    case server(String)
    case empty
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let s): return "Not configured: \(s)"
        case .server(let s):        return "Server error: \(s)"
        case .empty:                return "No speech detected."
        case .notImplemented(let s): return "\(s) is not implemented yet."
        }
    }
}

/// A pluggable speech-to-text backend. Everything model-specific lives behind
/// this protocol so the rest of the app never cares which engine is used.
protocol TranscriptionProvider {
    /// Transcribe 16 kHz mono Float32 samples. `language` is an ISO-639-1 code
    /// or nil for auto-detect.
    func transcribe(samples: [Float], language: String?) async throws -> String
}

/// Returned when a selected provider is not usable (e.g. OS too old).
struct UnavailableProvider: TranscriptionProvider {
    let reason: String
    func transcribe(samples: [Float], language: String?) async throws -> String {
        throw TranscriptionError.notConfigured(reason)
    }
}

enum WAV {
    /// Encode 16 kHz mono Float32 samples as a 16-bit PCM WAV file in memory.
    static func encode(samples: [Float], sampleRate: Int = 16_000) -> Data {
        var pcm = [Int16]()
        pcm.reserveCapacity(samples.count)
        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            pcm.append(Int16(clamped * 32767.0))
        }

        let byteRate = sampleRate * 2            // mono, 2 bytes/sample
        let dataSize = pcm.count * 2
        var d = Data(capacity: 44 + dataSize)

        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }

        d.append(contentsOf: Array("RIFF".utf8))
        u32(UInt32(36 + dataSize))
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8))
        u32(16)                 // fmt chunk size
        u16(1)                  // PCM
        u16(1)                  // channels
        u32(UInt32(sampleRate))
        u32(UInt32(byteRate))
        u16(2)                  // block align
        u16(16)                 // bits per sample
        d.append(contentsOf: Array("data".utf8))
        u32(UInt32(dataSize))
        pcm.withUnsafeBytes { raw in d.append(contentsOf: raw) }
        return d
    }
}
