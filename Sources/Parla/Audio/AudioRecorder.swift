import AVFoundation

/// Captures microphone audio and delivers it as 16 kHz mono Float32 samples,
/// which is the format Whisper (and every OpenAI-compatible endpoint) expects.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat: AVAudioFormat
    private let lock = NSLock()
    private var samples: [Float] = []
    private var running = false

    init() {
        // 16 kHz, mono, 32-bit float, non-interleaved.
        targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                     sampleRate: 16_000,
                                     channels: 1,
                                     interleaved: false)!
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    /// Begin capture. Throws if the engine cannot start (e.g. no input device).
    func start() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        running = true
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    /// Stop capture and return everything recorded as 16 kHz mono samples.
    @discardableResult
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }

        lock.lock()
        running = false
        let out = samples
        samples.removeAll(keepingCapacity: false)
        lock.unlock()
        return out
    }

    // MARK: - Resampling

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if error != nil { return }

        guard let ch = out.floatChannelData else { return }
        let count = Int(out.frameLength)
        guard count > 0 else { return }
        let ptr = ch[0]

        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: count))
        lock.unlock()
    }
}
