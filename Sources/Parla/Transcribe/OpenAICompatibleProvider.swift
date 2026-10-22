import Foundation

/// Talks to any server exposing `POST {baseURL}/audio/transcriptions` with the
/// OpenAI multipart contract. Works with OpenAI, Groq, LM Studio, llama.cpp's
/// server, faster-whisper-server, and friends — that is what makes Parla
/// model-agnostic out of the box.
struct OpenAICompatibleProvider: TranscriptionProvider {
    let baseURL: String
    let apiKey: String
    let model: String

    func transcribe(samples: [Float], language: String?) async throws -> String {
        guard samples.count > 1600 else { throw TranscriptionError.empty } // < ~0.1s
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed + "/audio/transcriptions") else {
            throw TranscriptionError.notConfigured("endpoint URL")
        }

        let wav = WAV.encode(samples: samples)
        let boundary = "parla-\(UUID().uuidString)"

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("model", model)
        if let language, !language.isEmpty { field("language", language) }
        field("response_format", "json")

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".utf8))
        body.append(Data("Content-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body
        req.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw TranscriptionError.server("HTTP \(http.statusCode): \(msg.prefix(300))")
        }

        // Response is `{ "text": "..." }`.
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let text = obj["text"] as? String {
            let out = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if out.isEmpty { throw TranscriptionError.empty }
            return out
        }
        throw TranscriptionError.server("unexpected response shape")
    }
}
