import Foundation

/// A downloadable Whisper model (GGML format, from the official whisper.cpp
/// model repo on Hugging Face).
struct WhisperModel: Identifiable, Hashable {
    let id: String          // e.g. "base.en"
    let approxSize: String  // human-readable
    var fileName: String { "ggml-\(id).bin" }
    var url: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!
    }

    static let catalog: [WhisperModel] = [
        .init(id: "tiny",            approxSize: "75 MB"),
        .init(id: "tiny.en",         approxSize: "75 MB"),
        .init(id: "base",            approxSize: "142 MB"),
        .init(id: "base.en",         approxSize: "142 MB"),
        .init(id: "small",           approxSize: "466 MB"),
        .init(id: "small.en",        approxSize: "466 MB"),
        .init(id: "medium",          approxSize: "1.5 GB"),
        .init(id: "large-v3-turbo",  approxSize: "1.6 GB"),
    ]
}

/// Downloads and tracks installed Whisper models under Application Support.
/// Observable so SwiftUI can show progress.
@MainActor
final class ModelManager: ObservableObject {
    static let shared = ModelManager()

    @Published var installed: Set<String> = []
    @Published var downloading: String?        // model id currently downloading
    @Published var progress: Double = 0        // 0...1
    @Published var lastError: String?
    @Published var activePath: String = AppSettings.shared.localModelPath

    private init() { refreshInstalled() }

    private func setActive(_ path: String) {
        AppSettings.shared.localModelPath = path
        activePath = path
    }

    var modelsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Parla/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    func localURL(for model: WhisperModel) -> URL {
        modelsDir.appendingPathComponent(model.fileName)
    }

    func isInstalled(_ model: WhisperModel) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: model).path)
    }

    func refreshInstalled() {
        installed = Set(WhisperModel.catalog.filter { isInstalled($0) }.map { $0.id })
    }

    /// Download a model with progress. On success, sets it as the active local model.
    func download(_ model: WhisperModel) {
        guard downloading == nil else { return }
        downloading = model.id
        progress = 0
        lastError = nil

        Task {
            do {
                try await performDownload(model)
                refreshInstalled()
                setActive(localURL(for: model).path)
                downloading = nil
            } catch {
                lastError = error.localizedDescription
                downloading = nil
                try? FileManager.default.removeItem(at: localURL(for: model)) // clean partial
            }
        }
    }

    func activate(_ model: WhisperModel) {
        guard isInstalled(model) else { return }
        setActive(localURL(for: model).path)
    }

    func delete(_ model: WhisperModel) {
        try? FileManager.default.removeItem(at: localURL(for: model))
        refreshInstalled()
        if AppSettings.shared.localModelPath == localURL(for: model).path {
            setActive("")
        }
    }

    private func performDownload(_ model: WhisperModel) async throws {
        let dest = localURL(for: model)
        let downloader = FileDownloader { [weak self] p in
            Task { @MainActor in self?.progress = p }
        }
        try await downloader.download(from: model.url, to: dest)
        progress = 1
    }
}

/// Efficient file download with progress, backed by URLSessionDownloadTask.
private final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?
    private var destination: URL!
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func download(from url: URL, to dest: URL) async throws {
        destination = dest
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // Must move the file out of the temp location synchronously here.
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            continuation?.resume(throwing: NSError(domain: "Parla", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Download failed (HTTP \(http.statusCode))"]))
            continuation = nil
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
