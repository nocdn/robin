import Foundation

struct CohereTranscriptionClient {
    let settings: AppSettings

    func transcribe(audioURL: URL) async throws -> String {
        guard let endpoint = URL(string: settings.endpoint) else {
            throw RobinError.invalidEndpoint(settings.endpoint)
        }
        Logger.shared.info("Preparing Cohere transcription request endpoint=\(settings.endpoint) model=\(settings.model) language=\(settings.language)")

        var request = URLRequest(url: endpoint)
        let boundary = "Boundary-\(UUID().uuidString)"
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try makeMultipartBody(audioURL: audioURL, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RobinError.invalidResponse
        }
        Logger.shared.info("Cohere response status=\(httpResponse.statusCode) bytes=\(data.count)")

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
            throw RobinError.apiError(status: httpResponse.statusCode, body: body)
        }

        let decoded = try JSONDecoder().decode(TranscriptionResponse.self, from: data)
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeMultipartBody(audioURL: URL, boundary: String) throws -> Data {
        var body = Data()
        body.appendFormField(name: "model", value: settings.model, boundary: boundary)
        body.appendFormField(name: "language", value: settings.language, boundary: boundary)

        let audioData = try Data(contentsOf: audioURL)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(audioURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")
        body.append("--\(boundary)--\r\n")
        return body
    }
}

private struct TranscriptionResponse: Decodable {
    let text: String
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendFormField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }
}
