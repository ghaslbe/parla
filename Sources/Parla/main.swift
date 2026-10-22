import AppKit
import Foundation

// Hidden developer self-test: `Parla --selftest <model.bin> <audio.wav>`.
// Runs the linked whisper.cpp engine on a 16 kHz mono WAV and prints the text,
// so the transcription path can be verified without mic/accessibility prompts.
if CommandLine.arguments.contains("--selftest") {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--selftest"), args.count > i + 2 else {
        FileHandle.standardError.write(Data("usage: Parla --selftest <model.bin> <audio.wav>\n".utf8))
        exit(2)
    }
    let modelPath = args[i + 1]
    let wavPath = args[i + 2]
    do {
        let samples = try decodeWav16kMono(path: wavPath)
        fputs("selftest: \(samples.count) samples, model \(modelPath)\n", stderr)
        let text = try WhisperEngine.shared.transcribe(samples: samples, modelPath: modelPath, language: "en")
        print(text)
        exit(0)
    } catch {
        fputs("selftest failed: \(error)\n", stderr)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Accessory: lives in the menu bar, no Dock icon, no app-switcher entry.
app.setActivationPolicy(.accessory)
app.run()

/// Minimal 16-bit PCM WAV reader for the self-test. Assumes mono 16 kHz.
private func decodeWav16kMono(path: String) throws -> [Float] {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    // Find the "data" chunk rather than assuming a fixed 44-byte header.
    guard let dataRange = data.range(of: Data("data".utf8)) else {
        throw NSError(domain: "wav", code: 1, userInfo: [NSLocalizedDescriptionKey: "no data chunk"])
    }
    let pcmStart = dataRange.upperBound + 4   // skip the 4-byte chunk size
    let pcm = data.subdata(in: pcmStart..<data.count)
    let count = pcm.count / 2
    var out = [Float](repeating: 0, count: count)
    pcm.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        let p = raw.bindMemory(to: Int16.self)
        for k in 0..<count { out[k] = Float(Int16(littleEndian: p[k])) / 32768.0 }
    }
    return out
}
