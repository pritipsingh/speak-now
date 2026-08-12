import Foundation

/// Uploads recorded audio to the AgentOS backend and returns the cleaned text.
///
/// POSTs multipart/form-data to `POST {backend}/dictation/transcribe`. The backend
/// runs gpt-4o-transcribe and the agno dictation agent, returning `{raw, text}`.
final class TranscriptionClient {
    /// Backend base URL, resolved each call so Server settings changes take effect
    /// without a relaunch. Precedence: Settings (UserDefaults) → env → localhost.
    static func backendBaseURL() -> URL {
        if let saved = UserDefaults.standard.string(forKey: "speak.backendURL"),
            !saved.isEmpty, let url = URL(string: saved)
        {
            return url
        }
        let env = ProcessInfo.processInfo.environment["WISPR_BACKEND_URL"]
        return URL(string: env ?? "http://127.0.0.1:8000") ?? URL(string: "http://127.0.0.1:8000")!
    }

    struct Response: Decodable {
        let raw: String
        let text: String
        let cleaned: Bool
    }

    enum ClientError: LocalizedError {
        case badStatus(Int, String)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let body):
                return "Backend returned HTTP \(code): \(body)"
            }
        }
    }

    func transcribe(fileURL: URL, appContext: String?) async throws -> String {
        let endpoint = Self.backendBaseURL().appendingPathComponent("dictation/transcribe")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"

        let boundary = "wispr-\(UUID().uuidString)"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Shared-secret for hosted backends (empty for local dev).
        let token = UserDefaults.standard.string(forKey: "speak.accessToken") ?? ""
        if !token.isEmpty { request.setValue(token, forHTTPHeaderField: "X-Speak-Token") }

        // Language preference: "" (or "auto") lets the model detect; an ISO-639-1
        // code (e.g. "en", "hi") locks transcription to that language.
        let language = UserDefaults.standard.string(forKey: "speak.language") ?? ""

        var fields = [
            "clean": "true",
            "app_context": appContext ?? "",
        ]
        if !language.isEmpty && language != "auto" { fields["language"] = language }

        let audioData = try Data(contentsOf: fileURL)
        request.httpBody = Self.multipartBody(
            boundary: boundary,
            fileField: "audio",
            fileName: fileURL.lastPathComponent,
            mimeType: "audio/m4a",
            fileData: audioData,
            fields: fields
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        // Clean up the temp recording once uploaded.
        try? FileManager.default.removeItem(at: fileURL)

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.badStatus(-1, "No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.badStatus(http.statusCode, body)
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.text
    }

    /// Build a multipart/form-data body with one file part and any number of text fields.
    private static func multipartBody(
        boundary: String,
        fileField: String,
        fileName: String,
        mimeType: String,
        fileData: Data,
        fields: [String: String]
    ) -> Data {
        var body = Data()
        let boundaryLine = "--\(boundary)\r\n"

        for (key, value) in fields where !value.isEmpty {
            body.appendString(boundaryLine)
            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }

        body.appendString(boundaryLine)
        body.appendString(
            "Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n")
        body.appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")
        return body
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let data = string.data(using: .utf8) { append(data) }
    }
}
