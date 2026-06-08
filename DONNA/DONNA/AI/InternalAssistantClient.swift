import Foundation

// MARK: - AssistantError

enum AssistantError: LocalizedError {
    case missingAPIKey
    case invalidURL
    case networkError(String)
    case apiError(Int, String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:        return "Kein Gemini API-Schlüssel im Keychain gefunden."
        case .invalidURL:           return "Ungültige API-URL."
        case .networkError(let m):  return "Netzwerkfehler: \(m)"
        case .apiError(let c, _):
            switch c {
            case 429: return "DONNA ist gerade überlastet. Bitte versuche es in einem Moment erneut."
            case 503: return "DONNA ist vorübergehend nicht verfügbar. Bitte versuche es gleich nochmal."
            case 401, 403: return "API-Schlüssel ungültig. Bitte prüfe die Einstellungen."
            default:  return "Serverfehler (\(c)). Bitte versuche es erneut."
            }
        case .malformedResponse:    return "Ungültige oder leere API-Antwort."
        }
    }
}

// MARK: - InternalAssistantClient

final class InternalAssistantClient {

    private static let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    private static let apiKeyName = "donna_gemini_api_key"

    // System prompt enforces the AI Interface Contract (Section 6 of the spec).
    private static let systemPrompt = """
    Du bist DONNAs interner Assistent. Du erhältst anonymisierten Kalender-Kontext und eine Nutzernachricht.

    DEINE AUFGABE:
    Liefere genau EINE Antwort in genau EINEM der vier erlaubten Typen. Beginne jede Antwort mit dem entsprechenden Tag.

    ERLAUBTE ANTWORTTYPEN:
    [INTERPRETATION] – Beschreibe kurz, was der Nutzer meinen könnte.
    [CLARIFICATION] – Stelle genau EINE Rückfrage, NUR wenn Titel oder Zeit wirklich fehlen.
    [PROPOSAL] – Klarer Vorschlag mit Bestätigungstext + Pflicht-JSON am Ende.
    [EXPLANATION] – Erkläre sachlich einen Konflikt oder eine Blockade.

    WANN DIREKT ZUM VORSCHLAG:
    Wenn der Nutzer einen Titel und eine Zeit nennt → SOFORT [PROPOSAL], keine Rückfrage.
    Wenn "morgen", "heute" oder ein Wochentag genannt werden → Datum ableiten, kein Nachfragen.
    Nur [CLARIFICATION] wenn wirklich nichts Wesentliches bekannt ist.

    [PROPOSAL] PFLICHTFORMAT — IMMER EXAKT SO:
    Beginne mit einer kurzen deutschen Beschreibung des Vorschlags, dann auf einer neuen Zeile:
    [PROPOSAL_DATA]{"type":"...","title":"..."}[/PROPOSAL_DATA]

    UNTERSTÜTZTE TYPEN (alle Felder PFLICHT):
    createEvent:   {"type":"createEvent","title":"string","date":"YYYY-MM-DD","startHour":int,"startMinute":int,"endHour":int,"endMinute":int}
    createTask:    {"type":"createTask","title":"string","dueDate":"YYYY-MM-DD","priority":"none|low|medium|high"}
    createRoutine: {"type":"createRoutine","title":"string","frequency":"daily|weekdays|weekly","durationMinutes":int,"category":"sleep|sport|learning|skincare|nutrition|custom","preferredTimeHour":int,"preferredTimeMinute":int}
    setSleepWindow:{"type":"setSleepWindow","bedtimeHour":int,"bedtimeMinute":int,"wakeHour":int,"wakeMinute":int}

    BEISPIELE:
    Nutzer: "Termin Fußball morgen 16-17 Uhr"
    → [PROPOSAL] Terminvorschlag: Fußball morgen von 16:00 bis 17:00 Uhr.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Fußball","date":"MORGEN-DATUM","startHour":16,"startMinute":0,"endHour":17,"endMinute":0}[/PROPOSAL_DATA]

    Nutzer: "Erinnere mich an Hausaufgaben bis Freitag"
    → [PROPOSAL] Aufgabe "Hausaufgaben" mit Fälligkeit Freitag.
    [PROPOSAL_DATA]{"type":"createTask","title":"Hausaufgaben","dueDate":"FREITAG-DATUM","priority":"medium"}[/PROPOSAL_DATA]

    VERBOTENE PHRASEN (Antwort wird verworfen):
    "Ich werde", "Ich habe", "Das wird", "Am besten", "Du solltest", "Ich mache das"

    REGELN:
    - Kein Markdown, keine Sternchen, keine Aufzählungen.
    - Nur eine kurze Beschreibung vor dem [PROPOSAL_DATA] Block.
    - Nenne keine Namen, Orte oder IDs aus dem Kontext.
    """

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 120
        return URLSession(configuration: config)
    }()

    /// Sends the anonymised context JSON and the user message to Gemini and returns
    /// the raw text response. Throws `AssistantError` on any failure.
    func send(contextJSON: String, userMessage: String, conversationHistory: [ChatMessage] = []) async throws -> String {
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

        var contents: [[String: Any]] = conversationHistory.suffix(10).map { msg in
            let geminiRole = msg.role == .user ? "user" : "model"
            let text: String
            if msg.role == .assistant {
                // Re-attach the type tag so Gemini sees its own prior responses
                // in the same structured format the system prompt requires.
                text = Self.tagPrefix(for: msg.outputType) + " " + msg.content
            } else {
                text = msg.content
            }
            return ["role": geminiRole, "parts": [["text": text]]]
        }
        let todayStr = DateFormatter.isoDate.string(from: Date())
        contents.append(["role": "user", "parts": [["text": "Heute: \(todayStr)\n\nKontext:\n\(contextJSON)\n\nNutzernachricht: \(userMessage)"]]])

        let body: [String: Any] = [
            "system_instruction": [
                "parts": [["text": Self.systemPrompt]]
            ],
            "contents": contents
        ]

        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw AssistantError.networkError("Request-Serialisierung fehlgeschlagen: \(error.localizedDescription)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
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

    private static func tagPrefix(for outputType: AIOutputType) -> String {
        switch outputType {
        case .interpretation: return "[INTERPRETATION]"
        case .clarification:  return "[CLARIFICATION]"
        case .proposal:       return "[PROPOSAL]"
        case .explanation:    return "[EXPLANATION]"
        }
    }

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
