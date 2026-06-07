import Foundation
import AppKit

// MARK: - LLM Service (OpenAI-Compatible API)
final class LLMService {
    static let shared = LLMService()

    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    private var baseURL: String {
        UserDefaults.standard.string(forKey: SettingsKeys.llmBaseURL) ?? "https://api.groq.com/openai/v1"
    }

    private var model: String {
        UserDefaults.standard.string(forKey: SettingsKeys.llmModel) ?? "llama-3.3-70b-versatile"
    }

    private var apiKey: String {
        UserDefaults.standard.string(forKey: SettingsKeys.llmApiKey) ?? ""
    }

    // MARK: - Public API

    func polish(text: String) async throws -> String {
        let systemPrompt = """
        You are a transcription polishing assistant. Fix small errors in transcribed text —
        spelling mistakes, missing punctuation, incorrect words that sound similar (homophones),
        and formatting issues. Keep the SAME LANGUAGE as the input. Do NOT rephrase, summarize,
        or change the meaning. Only fix obvious transcription errors.
        Return ONLY the corrected text, nothing else.
        """
        return try await chatCompletion(systemPrompt: systemPrompt, userMessage: text)
    }

    func translate(text: String, to targetLanguage: String) async throws -> String {
        let systemPrompt = """
        You are a translator. Translate the following text to \(targetLanguage).
        Keep the original meaning, tone, and style. Preserve formatting like line breaks.
        Return ONLY the translated text, nothing else.
        """
        return try await chatCompletion(systemPrompt: systemPrompt, userMessage: text)
    }

    // MARK: - OpenAI Chat Completion

    private func chatCompletion(systemPrompt: String, userMessage: String) async throws -> String {
        guard !apiKey.isEmpty else { throw LLMError.noApiKey }

        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(base)/chat/completions") else {
            throw LLMError.invalidURL(baseURL)
        }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userMessage]
            ],
            "temperature": 0.1,
            "max_tokens": 4096
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LLMError.networkError(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw LLMError.apiError(statusCode: httpResponse.statusCode, message: errorText)
        }

        struct LLMResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable {
                    let content: String?
                }
                let message: Message
            }
            let choices: [Choice]
        }

        do {
            let result = try decoder.decode(LLMResponse.self, from: data)
            guard let content = result.choices.first?.message.content, !content.isEmpty else {
                throw LLMError.emptyResponse
            }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch let error as LLMError {
            throw error
        } catch {
            throw LLMError.decodingError
        }
    }

    static func validate(baseURL: String, model: String, apiKey: String) async -> Bool {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let url = URL(string: "\(base)/chat/completions") else { return false }

        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "user", "content": "test"]],
            "max_tokens": 1
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return ((response as? HTTPURLResponse)?.statusCode ?? 500) < 500
        } catch {
            return false
        }
    }
}

// MARK: - Errors
enum LLMError: Error, LocalizedError {
    case noApiKey; case invalidURL(String); case invalidResponse
    case networkError(String); case apiError(statusCode: Int, message: String)
    case decodingError; case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "LLM API key not set. Configure in Settings."
        case .invalidURL(let u): return "Invalid Base URL: \(u)"
        case .invalidResponse: return "Invalid response from LLM API."
        case .networkError(let msg): return "Network error: \(msg)"
        case .apiError(let code, let msg): return "LLM Error (\(code)): \(msg)"
        case .decodingError: return "Failed to decode LLM response."
        case .emptyResponse: return "LLM returned empty response."
        }
    }
}
