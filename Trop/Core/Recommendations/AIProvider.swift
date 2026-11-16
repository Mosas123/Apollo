import Foundation

enum AIProvider: String, CaseIterable, Identifiable {
    case off
    case gemini
    case deepSeek
    case openRouter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Off"
        case .gemini: return "Google Gemini"
        case .deepSeek: return "DeepSeek"
        case .openRouter: return "OpenRouter"
        }
    }

    var defaultModel: String {
        switch self {
        case .off: return ""
        case .gemini: return "gemini-3.6-flash"
        case .deepSeek: return "deepseek-flash"
        case .openRouter: return "qwen/qwen3.7-flash"
        }
    }
}

enum AIError: LocalizedError {
    case notConfigured
    case http(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "AI provider is not configured."
        case .http(let code): return "AI provider returned HTTP \(code)."
        case .emptyResponse: return "The AI provider returned an empty response."
        }
    }
}

/// Minimal chat-completion client for the optional AI recommendations. Uses the
/// user's own API key (Settings). Gemini uses its REST endpoint; DeepSeek and
/// OpenRouter share the OpenAI-compatible shape.
struct AIProviderClient {
    let provider: AIProvider
    let apiKey: String
    let model: String

    @MainActor
    static func configured() -> AIProviderClient? {
        let settings = SettingsStore.shared
        guard let provider = AIProvider(rawValue: settings.aiProvider), provider != .off else { return nil }
        let key = settings.aiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        let model = settings.aiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        return AIProviderClient(
            provider: provider,
            apiKey: key,
            model: model.isEmpty ? provider.defaultModel : model
        )
    }

    /// Quick credential/connectivity check with a tiny prompt.
    func verify() async throws {
        let reply = try await complete("Reply with the single word: OK")
        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.emptyResponse
        }
    }

    func complete(_ prompt: String) async throws -> String {
        switch provider {
        case .gemini:
            return try await gemini(prompt)
        case .deepSeek, .openRouter:
            return try await openAICompatible(prompt)
        case .off:
            throw AIError.notConfigured
        }
    }

    private func gemini(_ prompt: String) async throws -> String {
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components?.url else { throw AIError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.9]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIError.http(status) }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let candidates = json?["candidates"] as? [[String: Any]]
        let content = candidates?.first?["content"] as? [String: Any]
        let parts = content?["parts"] as? [[String: Any]]
        return parts?.first?["text"] as? String ?? ""
    }

    private func openAICompatible(_ prompt: String) async throws -> String {
        let endpoint = provider == .deepSeek
            ? "https://api.deepseek.com/chat/completions"
            : "https://openrouter.ai/api/v1/chat/completions"
        guard let url = URL(string: endpoint) else { throw AIError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.9,
            "messages": [["role": "user", "content": prompt]]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw AIError.http(status) }

        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        return message?["content"] as? String ?? ""
    }
}
