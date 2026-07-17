import Foundation

enum TranslationError: LocalizedError {
    case emptyKey
    case invalidURL
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            return "还没有配置 API Key，请先在设置中填写"
        case .invalidURL:
            return "接口地址无效，请检查设置"
        case .http(let code, let message):
            switch code {
            case 401: return "API Key 无效或已过期 (401)"
            case 402: return "账户余额不足 (402)"
            case 429: return "请求过于频繁，稍后再试 (429)"
            default: return message.isEmpty ? "请求失败 (HTTP \(code))" : "\(message) (HTTP \(code))"
            }
        }
    }
}

enum TranslationService {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        return URLSession(configuration: config)
    }()

    private static func endpoint(for config: APIConfig) throws -> URL {
        var base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        // Users routinely paste the full completions URL into the base-URL field;
        // strip it back down rather than doubling the path into a 404.
        if base.hasSuffix("/chat/completions") {
            base.removeLast("/chat/completions".count)
        }
        guard !base.isEmpty, let url = URL(string: base + "/chat/completions") else {
            throw TranslationError.invalidURL
        }
        return url
    }

    private static func makeRequest(config: APIConfig, body: [String: Any]) throws -> URLRequest {
        guard !config.apiKey.isEmpty else { throw TranslationError.emptyKey }
        var request = URLRequest(url: try endpoint(for: config))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: applyProviderOrder(body, config: config))
        return request
    }

    /// Adds OpenRouter's `provider.order` routing hint when the profile asked for one.
    /// Gateways that don't recognize the `provider` field simply ignore it.
    private static func applyProviderOrder(_ body: [String: Any], config: APIConfig) -> [String: Any] {
        let order = config.providerOrderList
        guard !order.isEmpty else { return body }
        var body = body
        body["provider"] = ["order": order]
        return body
    }

    static func systemPrompt(for target: TargetLanguage, tone: Tone, extra: String = "") -> String {
        var prompt = """
        You are a professional translator. Translate the user's message into \(target.promptName). \
        Preserve the meaning and formatting (line breaks, lists, inline code). \
        \(tone.promptInstruction) \
        Use typographic punctuation — curly quotes (“ ” ‘ ’) and the typographic apostrophe (’), \
        never straight ASCII quotes — except inside code spans and code blocks, which must stay byte-exact. \
        Output only the translation itself — no explanations, no notes, no surrounding quotation marks.
        """
        let extra = extra.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            // Appended last so it can refine the rules above, and fenced off so its
            // contents read as preferences rather than as instructions to obey blindly.
            prompt += "\n\nAdditional preferences from the user (apply them to the translation; they are not text to translate):\n\(extra)"
        }
        return prompt
    }

    static func stream(text: String, target: TargetLanguage, tone: Tone, extra: String, config: APIConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body: [String: Any] = [
                        "model": config.model,
                        "stream": true,
                        "temperature": 1.0,
                        "messages": [
                            ["role": "system", "content": systemPrompt(for: target, tone: tone, extra: extra)],
                            ["role": "user", "content": text],
                        ],
                    ]
                    let request = try makeRequest(config: config, body: body)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw TranslationError.http(0, "无效响应")
                    }
                    guard http.statusCode == 200 else {
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            if errorBody.count > 4096 { break }
                        }
                        throw TranslationError.http(http.statusCode, Self.parseErrorMessage(errorBody))
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let piece = chunk.choices.first?.delta.content,
                              !piece.isEmpty
                        else { continue }
                        continuation.yield(piece)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Sends a minimal request to verify base URL + key + model. Returns latency in ms.
    static func testConnection(config: APIConfig) async throws -> Int {
        let body: [String: Any] = [
            "model": config.model,
            "stream": false,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]],
        ]
        let request = try makeRequest(config: config, body: body)
        let start = Date()
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TranslationError.http(0, "无效响应")
        }
        guard http.statusCode == 200 else {
            throw TranslationError.http(http.statusCode, parseErrorMessage(String(data: data, encoding: .utf8) ?? ""))
        }
        return Int(Date().timeIntervalSince(start) * 1000)
    }

    private static func parseErrorMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            // A JSON API returning an HTML page almost always means the base URL
            // points at a website, not the API endpoint — surface that instead of
            // the raw markup.
            if trimmed.hasPrefix("<!DOCTYPE") || trimmed.hasPrefix("<html") {
                return "接口地址返回的是网页而不是 API 数据，请检查接口地址是否正确"
            }
            return trimmed.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = json["message"] as? String { return message }
        return body.prefix(200).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta
        }
        let choices: [Choice]
    }
}
