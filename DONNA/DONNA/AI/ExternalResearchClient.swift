import Foundation

// MARK: - ExternalResearchClient
//
// Aufruf 2 (spec §3.3): external web research via Gemini + Google Search Grounding.
// Receives only an anonymous query string — zero personal data, zero calendar context.
// Architecturally isolated from InternalAssistantClient; no shared state, no shared context.

final class ExternalResearchClient {

    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    private static let apiKeyName = "donna_gemini_api_key"

    /// Performs a grounded web search for `query` and returns the raw response text.
    /// `query` must be fully anonymised before calling — the caller is responsible
    /// for stripping all personal data (names, locations, schedule details).
    func research(query: String) async throws -> String {
        guard let apiKey = KeychainHelper.load(key: Self.apiKeyName) else {
            throw AssistantError.missingAPIKey
        }

        guard var components = URLComponents(string: Self.endpoint) else {
            throw AssistantError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else {
            throw AssistantError.invalidURL
        }

        // Google Search Grounding enabled via tools array (spec §3.3 + §15).
        // No system_instruction, no calendar context — anonymous query only.
        let body: [String: Any] = [
            "contents": [
                ["role": "user", "parts": [["text": query]]]
            ],
            "tools": [["google_search": [:]]]
        ]

        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AssistantError.networkError("Serialisierung fehlgeschlagen: \(error.localizedDescription)")
        }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AssistantError.networkError(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AssistantError.networkError("Keine HTTP-Antwort erhalten.")
        }
        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "–"
            throw AssistantError.apiError(http.statusCode, body)
        }

        return try extractText(from: data)
    }

    // MARK: - Private helpers

    private func extractText(from data: Data) throws -> String {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let candidates = json["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let parts = content["parts"] as? [[String: Any]],
            let text = parts.first?["text"] as? String,
            !text.isEmpty
        else {
            throw AssistantError.malformedResponse
        }
        return text
    }
}
