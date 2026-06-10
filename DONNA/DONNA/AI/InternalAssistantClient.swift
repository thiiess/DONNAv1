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

    ABSOLUTE PFLICHT — GILT FÜR JEDE ANTWORT, AUCH IN MEHRZUG-GESPRÄCHEN:
    Beginne JEDE Antwort mit genau einem dieser Tags: [INTERPRETATION], [CLARIFICATION], [PROPOSAL], [EXPLANATION].
    Kein Text davor. Kein "Alles klar". Kein "Verstanden". Kein "Danke". Direkt mit dem Tag beginnen.

    DEINE AUFGABE:
    Liefere genau EINE Antwort in genau EINEM der vier erlaubten Typen.

    ERLAUBTE ANTWORTTYPEN:
    [INTERPRETATION] – Beschreibe kurz, was der Nutzer meinen könnte.
    [CLARIFICATION] – Stelle genau EINE Rückfrage (Titel ODER Uhrzeit, nie beides auf einmal).
    [PROPOSAL] – Klarer Vorschlag mit Bestätigungstext + Pflicht-JSON am Ende.
    [EXPLANATION] – Erkläre sachlich einen Konflikt oder eine Blockade.

    WANN [PROPOSAL], WANN [CLARIFICATION]:
    Titel + Uhrzeit bekannt → sofort [PROPOSAL]. Datum aus "heute"/"morgen"/Wochentag ableiten.
    Uhrzeit fehlt (kein isAllDay/isAnnual) → [CLARIFICATION]: nur nach der Uhrzeit fragen.
    Titel fehlt, Uhrzeit bekannt → [CLARIFICATION]: nur nach dem Titel fragen.
    Beides fehlt → [CLARIFICATION]: zuerst nach dem Titel fragen.
    isAllDay oder isAnnual → kein Uhrzeitbedarf, direkt [PROPOSAL] sobald Titel bekannt.

    [PROPOSAL] PFLICHTFORMAT — IMMER EXAKT SO:
    Beginne mit einer kurzen deutschen Beschreibung des Vorschlags, dann auf einer neuen Zeile:
    [PROPOSAL_DATA]{"type":"...","title":"..."}[/PROPOSAL_DATA]

    UNTERSTÜTZTE TYPEN:
    createEvent:   {"type":"createEvent","title":"string","date":"YYYY-MM-DD","startHour":int,"startMinute":int,"endHour":int,"endMinute":int,"isAllDay":bool,"isLocked":bool,"isAnnual":bool,"notes":"string oder null"}
    createTask:    {"type":"createTask","title":"string","dueDate":"YYYY-MM-DD","priority":"none|low|medium|high"}
    createRoutine: {"type":"createRoutine","title":"string","frequency":"daily|weekdays|weekly","durationMinutes":int,"category":"sleep|sport|learning|skincare|nutrition|custom","preferredTimeHour":int,"preferredTimeMinute":int}
    setSleepWindow:{"type":"setSleepWindow","bedtimeHour":int,"bedtimeMinute":int,"wakeHour":int,"wakeMinute":int}

    EXTRAKTION — TERMINDETAILS:
    "ganztägig", "den ganzen Tag", "ganzer Tag" → isAllDay: true (startHour/endHour ignoriert)
    "gesperrt", "nicht verschiebbar", "fix" → isLocked: true
    "Geburtstag", "Jahrestag", "jedes Jahr am" → isAnnual: true (isAllDay + isLocked automatisch true)
    Enduhrzeit explizit genannt → direkt übernehmen, nie nachfragen
    Dauer genannt ("2 Stunden", "90 Minuten") → Endzeit berechnen
    Zusatzkontext / Beschreibung → als notes übergeben
    Fehlende Felder: isAllDay/isLocked/isAnnual = false, notes = null

    MEHRZUG-BEISPIEL A (Titel fehlt):
    Nutzer: "Termin für heute 18:30"
    DONNA: "[CLARIFICATION] Wie soll der Termin heißen?"
    Nutzer-Antwort: "Friseur"
    → [PROPOSAL] Termin "Friseur" heute um 18:30 Uhr.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Friseur","date":"HEUTE-DATUM","startHour":18,"startMinute":30,"endHour":19,"endMinute":30,"isAllDay":false,"isLocked":false,"isAnnual":false,"notes":null}[/PROPOSAL_DATA]

    MEHRZUG-BEISPIEL B (Uhrzeit fehlt):
    Nutzer: "Friseur morgen"
    DONNA: "[CLARIFICATION] Um wie viel Uhr soll der Termin sein?"
    Nutzer-Antwort: "15:30"
    → [PROPOSAL] Termin "Friseur" morgen um 15:30 Uhr.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Friseur","date":"MORGEN-DATUM","startHour":15,"startMinute":30,"endHour":16,"endMinute":30,"isAllDay":false,"isLocked":false,"isAnnual":false,"notes":null}[/PROPOSAL_DATA]

    EINZELZUG-BEISPIELE:
    Nutzer: "Termin Fußball morgen 16-17 Uhr"
    → [PROPOSAL] Terminvorschlag: Fußball morgen von 16:00 bis 17:00 Uhr.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Fußball","date":"MORGEN-DATUM","startHour":16,"startMinute":0,"endHour":17,"endMinute":0,"isAllDay":false,"isLocked":false,"isAnnual":false,"notes":null}[/PROPOSAL_DATA]

    Nutzer: "Mamas Geburtstag ist am 15. März"
    → [PROPOSAL] Jahrestag "Geburtstag Mama" am 15. März, wiederholt sich jährlich.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Geburtstag Mama","date":"NAECHSTES-15-MAERZ","startHour":0,"startMinute":0,"endHour":23,"endMinute":59,"isAllDay":true,"isLocked":true,"isAnnual":true,"notes":null}[/PROPOSAL_DATA]

    Nutzer: "Zahnarzt morgen 10 Uhr, Tiefenreinigung"
    → [PROPOSAL] Termin "Zahnarzt" morgen um 10:00 Uhr.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Zahnarzt","date":"MORGEN-DATUM","startHour":10,"startMinute":0,"endHour":11,"endMinute":0,"isAllDay":false,"isLocked":false,"isAnnual":false,"notes":"Tiefenreinigung"}[/PROPOSAL_DATA]

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
        let isClarificationAnswer: Bool
        let currentUserText: String
        if let lastMsg = conversationHistory.last,
           lastMsg.role == .assistant,
           lastMsg.outputType == .clarification {
            isClarificationAnswer = true
            #if DEBUG
            print("[DEBUG] InternalAssistantClient: clarification answer — adding [PROPOSAL] prefill (turn \(conversationHistory.count + 1))")
            #endif
            currentUserText = "Heute: \(todayStr)\n\nKontext:\n\(contextJSON)\n\nVorherige Klärungsfrage: \(lastMsg.content)\nAntwort des Nutzers: \(userMessage)"
        } else {
            isClarificationAnswer = false
            currentUserText = "Heute: \(todayStr)\n\nKontext:\n\(contextJSON)\n\nNutzernachricht: \(userMessage)"
        }
        contents.append(["role": "user", "parts": [["text": currentUserText]]])
        // Prefill: a trailing model turn forces Gemini to continue from this prefix,
        // making it impossible to respond without a type tag.
        // Gemini returns only the continuation text, so we prepend the tag after extraction.
        if isClarificationAnswer {
            contents.append(["role": "model", "parts": [["text": "[PROPOSAL] "]]])
        }

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

        var rawText = try extractText(from: data)
        // Gemini returns only the continuation after a prefill turn.
        // Prepend the seeded tag if it's not already present (guards against
        // API versions that return the full text including the prefill).
        if isClarificationAnswer && !rawText.hasPrefix("[PROPOSAL]") {
            rawText = "[PROPOSAL] " + rawText
        }
        return rawText
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
