import Foundation

struct OllamaClient {
    private let baseURL = URL(string: "http://127.0.0.1:11434")!

    func models() async throws -> [String] {
        let data = try await request(path: "/api/tags", method: "GET", body: nil)
        let tags = try JSONDecoder().decode(OllamaTags.self, from: data)
        return tags.models
            .filter { $0.capabilities?.contains("completion") ?? true }
            .map(\.name)
            .sorted()
    }

    func generateEnglish(prompt: String, model: String, mode: InstrumentMode) async throws -> String {
        let subject = prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "a curious robot discovering the expressive power of the human voice"
            : prompt
        let task = mode == .sing
            ? "Write two to four short, singable English lyric lines about this subject: \(subject)"
            : "Write one or two short, natural English sentences to read aloud about this subject: \(subject)"
        let system = """
        Return only the requested text in natural English. Use only ASCII Latin letters, digits, spaces and standard English punctuation. No translations, explanations, titles, markdown, code fences, IPA, phonetic symbols, or text in any other language. Do not include thinking or analysis.
        """
        for _ in 0..<2 {
            let text = try await generate(prompt: task, system: system, model: model)
            if let english = Self.validatedEnglish(text) {
                return english
            }
        }
        throw ChimeraError(message: "Ollama did not return plain English after two attempts. No text was sent to the synthesizer.")
    }

    private func generate(prompt: String, system: String, model: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "system": system,
            "stream": false,
            "think": false,
            "options": ["temperature": 0.6, "num_predict": 160]
        ]
        let data = try await request(path: "/api/generate", method: "POST", body: JSONSerialization.data(withJSONObject: body))
        return try JSONDecoder().decode(OllamaGeneration.self, from: data).response
    }

    private func request(path: String, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 120
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ChimeraError(message: "Ollama request failed. Check that the Ollama service is running on port 11434.")
        }
        return data
    }

    private static func validatedEnglish(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") || text.contains("</think>") { return nil }
        let replacements: [String: String] = [
            "‘": "'", "’": "'", "“": "\"", "”": "\"",
            "–": "-", "—": "-", "…": "...", " ": " "
        ]
        for (source, replacement) in replacements {
            text = text.replacingOccurrences(of: source, with: replacement)
        }
        if text.count >= 2, let first = text.first, let last = text.last,
           (first == "\"" && last == "\"") || (first == "'" && last == "'") {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 \n\r\t.,!?;:'\"()-")
        guard !text.isEmpty,
              text.rangeOfCharacter(from: .letters) != nil,
              text.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        if text.split(whereSeparator: { $0.isWhitespace }).count >= 3,
           let language = NSLinguisticTagger.dominantLanguage(for: text), language != "en" {
            return nil
        }
        return text
    }
}

private struct OllamaTags: Decodable {
    let models: [OllamaModel]
}

private struct OllamaModel: Decodable {
    let name: String
    let capabilities: [String]?
}

private struct OllamaGeneration: Decodable {
    let response: String
}
