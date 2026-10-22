import Foundation
import AVFoundation
import Speech

/// On-device transcription using Apple's built-in speech model via the
/// SpeechAnalyzer / SpeechTranscriber API (macOS 26+). No model to manage —
/// the system downloads and stores the language assets for you, and everything
/// runs on-device.
@available(macOS 26.0, *)
struct AppleSpeechProvider: TranscriptionProvider {

    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard samples.count > 1600 else { throw TranscriptionError.empty }

        let locale = try await Self.resolveLocale(language)
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        try await Self.ensureInstalled(transcriber)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TranscriptionError.notConfigured("no compatible audio format")
        }
        let buffer = try Self.makeBuffer(from: samples, to: format)

        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()

        // Collect finalized transcript text as it arrives.
        async let collected: String = {
            var acc = AttributedString()
            for try await result in transcriber.results {
                acc += result.text
            }
            return String(acc.characters)
        }()

        try await analyzer.start(inputSequence: stream)
        cont.yield(AnalyzerInput(buffer: buffer))
        cont.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let text = try await collected.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw TranscriptionError.empty }
        return text
    }

    // MARK: - Helpers

    /// Pick a supported locale for the requested language (ISO code), falling
    /// back to the current locale.
    private static func resolveLocale(_ language: String?) async throws -> Locale {
        let supported = await SpeechTranscriber.supportedLocales
        guard !supported.isEmpty else {
            throw TranscriptionError.notConfigured("Apple speech model not available on this Mac")
        }
        if let lang = language, !lang.isEmpty {
            if let match = supported.first(where: { $0.language.languageCode?.identifier == lang }) {
                return match
            }
            return Locale(identifier: lang)
        }
        let current = Locale.current
        if let match = supported.first(where: {
            $0.language.languageCode?.identifier == current.language.languageCode?.identifier
        }) {
            return match
        }
        return supported.first ?? current
    }

    /// Ensure the language assets for this transcriber are installed on-device.
    private static func ensureInstalled(_ transcriber: SpeechTranscriber) async throws {
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    /// Convert our 16 kHz mono Float32 samples into the analyzer's preferred format.
    private static func makeBuffer(from samples: [Float], to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let srcFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                      sampleRate: 16_000, channels: 1, interleaved: false)!
        guard let src = AVAudioPCMBuffer(pcmFormat: srcFormat,
                                         frameCapacity: AVAudioFrameCount(samples.count)) else {
            throw TranscriptionError.notConfigured("could not allocate audio buffer")
        }
        src.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { p in
            src.floatChannelData![0].update(from: p.baseAddress!, count: samples.count)
        }

        if srcFormat == format { return src }

        guard let converter = AVAudioConverter(from: srcFormat, to: format) else {
            throw TranscriptionError.notConfigured("no audio converter")
        }
        let ratio = format.sampleRate / srcFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(samples.count) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw TranscriptionError.notConfigured("could not allocate output buffer")
        }
        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return src
        }
        if let error { throw error }
        return out
    }
}
