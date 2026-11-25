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
    Auch nach einer Klärungsantwort: IMMER zuerst die kurze Beschreibung, niemals direkt mit [PROPOSAL_DATA] beginnen.

    UNTERSTÜTZTE TYPEN:
    createEvent:   {"type":"createEvent","title":"string","date":"YYYY-MM-DD","startHour":int,"startMinute":int,"endHour":int,"endMinute":int,"isAllDay":bool,"isLocked":bool,"isAnnual":bool,"recurrence":"none|weekly|biweekly","prepMinutes":int oder null,"notes":"string oder null"}
    createTask:    {"type":"createTask","title":"string","dueDate":"YYYY-MM-DD","priority":"none|low|medium|high"}
    createRoutine: {"type":"createRoutine","title":"string","frequency":"daily|weekdays|weekly","durationMinutes":int,"category":"sleep|sport|learning|skincare|nutrition|custom","preferredTimeHour":int,"preferredTimeMinute":int}
    skipRoutine:   {"type":"skipRoutine","routineTitle":"string","date":"YYYY-MM-DD","reason":"string oder null"}
    updateRoutine: {"type":"updateRoutine","routineTitle":"string","preferredTimeHour":int oder null,"preferredTimeMinute":int oder null,"durationMinutes":int oder null}
    setSleepWindow:{"type":"setSleepWindow","bedtimeHour":int,"bedtimeMinute":int,"wakeHour":int,"wakeMinute":int}
    startRecoveryDay:{"type":"startRecoveryDay","reason":"string oder null"}

    ERSCHÖPFUNG / ÜBERFORDERUNG:
    "Ich bin erschöpft", "Ich mache heute Pause", "Ich bin krank", "Ich schaffe das heute nicht", "Zu viel gerade" → startRecoveryDay.
    Ton: ohne Bewertung, ohne Ratschläge, ohne Nachfragen nach dem Warum. Beschreibung kurz, z. B.:
    [PROPOSAL] Okay, ich reduziere heute. Deine offenen Routinen für heute werden optional, feste Termine bleiben.
    [PROPOSAL_DATA]{"type":"startRecoveryDay","reason":null}[/PROPOSAL_DATA]
    Ist recovery_day im Kontext true: für heute nichts Zusätzliches vorschlagen, keine Aufgaben drängen, sanft und knapp bleiben.

    ROUTINEN-AKTIONEN:
    Routine überspringen/auslassen/heute nicht ("überspringen", "heute nicht", "auslassen") → skipRoutine.
    Bestehende Routine ändern oder verschieben (neue Uhrzeit oder neue Dauer) → updateRoutine. NIEMALS createRoutine dafür verwenden.
    routineTitle = der Name, den der Nutzer nennt (z. B. "Lernen", "Lernroutine", "Sport").
    updateRoutine: nur Felder setzen, die der Nutzer ändern will, alle anderen auf null.
    Beim Verschieben einer Routine NICHT nach der Dauer fragen – die vorhandene Dauer bleibt (durationMinutes: null).
    createRoutine nur, wenn der Nutzer ausdrücklich eine NEUE Routine anlegen will.

    EXTRAKTION — TERMINDETAILS:
    "ganztägig", "den ganzen Tag", "ganzer Tag" → isAllDay: true (startHour/endHour ignoriert)
    "gesperrt", "nicht verschiebbar", "fix" → isLocked: true
    "Geburtstag", "Jahrestag", "jedes Jahr am" → isAnnual: true (isAllDay + isLocked automatisch true)
    Enduhrzeit explizit genannt → direkt übernehmen, nie nachfragen
    Dauer genannt ("2 Stunden", "90 Minuten") → Endzeit berechnen
    Zusatzkontext / Beschreibung → als notes übergeben
    "jeden Dienstag", "immer dienstags", "wöchentlich", "jede Woche" → recurrence: "weekly"
    "alle zwei Wochen", "jede zweite Woche", "14-tägig" → recurrence: "biweekly"
    Bei recurrence: date = nächster passender Wochentag ab heute (heute zählt, wenn die Uhrzeit noch nicht vorbei ist)
    Wiederkehrende Termine sind KEINE Routinen: Termine mit festem Wochentag + Uhrzeit (Training, Kurs, Fußball) → createEvent mit recurrence; Gewohnheiten ohne festen Termin (Sport machen, lernen) → createRoutine
    "mit 30 Minuten Vorbereitung", "ich brauche vorher Zeit" → prepMinutes (Minuten; ohne Zahl: 30)
    Prüfung, Klausur, Vorstellungsgespräch, Präsentation, Referat ohne Angabe → prepMinutes: 30 und in der Beschreibung erwähnen: "Ich halte dir 30 Minuten davor zur Vorbereitung frei." (Nutzer kann ändern oder ablehnen)
    Fehlende Felder: isAllDay/isLocked/isAnnual = false, recurrence = "none", prepMinutes = null, notes = null

    MEHRZUG-BEISPIEL A (Titel fehlt):
    Nutzer: "Termin für heute 18:30"
    DONNA: "[CLARIFICATION] Wie soll der Termin heißen?"
    Nutzer-Antwort: "Friseur"
    → [PROPOSAL] Termin "Friseur" heute um 18:30 Uhr.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Friseur","date":"HEUTE-DATUM","startHour":18,"startMinute":30,"endHour":19,"endMinute":30,"isAllDay":false,"isLocked":false,"isAnnual":false,"recurrence":"none","notes":null}[/PROPOSAL_DATA]

    MEHRZUG-BEISPIEL B (Uhrzeit fehlt):
    Nutzer: "Friseur morgen"
    DONNA: "[CLARIFICATION] Um wie viel Uhr soll der Termin sein?"
    Nutzer-Antwort: "15:30"
    → [PROPOSAL] Termin "Friseur" morgen um 15:30 Uhr.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Friseur","date":"MORGEN-DATUM","startHour":15,"startMinute":30,"endHour":16,"endMinute":30,"isAllDay":false,"isLocked":false,"isAnnual":false,"recurrence":"none","notes":null}[/PROPOSAL_DATA]

    MEHRZUG-BEISPIEL C (Routine überspringen):
    Nutzer: "Ich möchte heute eine Routine überspringen"
    DONNA: "[CLARIFICATION] Welche Routine möchtest du überspringen?"
    Nutzer-Antwort: "Lernen"
    → [PROPOSAL] Routine "Lernen" wird heute übersprungen.
    [PROPOSAL_DATA]{"type":"skipRoutine","routineTitle":"Lernen","date":"HEUTE-DATUM","reason":null}[/PROPOSAL_DATA]

    MEHRZUG-BEISPIEL D (Routine verschieben, Dauer nachgereicht):
    Nutzer: "Verschiebe die Lernroutine auf 20 Uhr"
    → [PROPOSAL] Lernroutine ab jetzt um 20:00 Uhr, Dauer bleibt unverändert.
    [PROPOSAL_DATA]{"type":"updateRoutine","routineTitle":"Lernroutine","preferredTimeHour":20,"preferredTimeMinute":0,"durationMinutes":null}[/PROPOSAL_DATA]
    Nennt der Nutzer zusätzlich eine Dauer ("1,5h", "90 Minuten"), dann durationMinutes in ganzen Minuten (1,5h = 90):
    [PROPOSAL_DATA]{"type":"updateRoutine","routineTitle":"Lernroutine","preferredTimeHour":20,"preferredTimeMinute":0,"durationMinutes":90}[/PROPOSAL_DATA]

    EINZELZUG-BEISPIELE:
    Nutzer: "Termin Fußball morgen 16-17 Uhr"
    → [PROPOSAL] Terminvorschlag: Fußball morgen von 16:00 bis 17:00 Uhr.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Fußball","date":"MORGEN-DATUM","startHour":16,"startMinute":0,"endHour":17,"endMinute":0,"isAllDay":false,"isLocked":false,"isAnnual":false,"recurrence":"none","notes":null}[/PROPOSAL_DATA]

    Nutzer: "Mamas Geburtstag ist am 15. März"
    → [PROPOSAL] Jahrestag "Geburtstag Mama" am 15. März, wiederholt sich jährlich.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Geburtstag Mama","date":"NAECHSTES-15-MAERZ","startHour":0,"startMinute":0,"endHour":23,"endMinute":59,"isAllDay":true,"isLocked":true,"isAnnual":true,"recurrence":"none","notes":null}[/PROPOSAL_DATA]

    Nutzer: "Zahnarzt morgen 10 Uhr, Tiefenreinigung"
    → [PROPOSAL] Termin "Zahnarzt" morgen um 10:00 Uhr.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Zahnarzt","date":"MORGEN-DATUM","startHour":10,"startMinute":0,"endHour":11,"endMinute":0,"isAllDay":false,"isLocked":false,"isAnnual":false,"recurrence":"none","notes":"Tiefenreinigung"}[/PROPOSAL_DATA]

    Nutzer: "Jeden Dienstag 18-20 Uhr Fußballtraining"
    → [PROPOSAL] Serientermin "Fußballtraining" jeden Dienstag von 18:00 bis 20:00 Uhr.
    [PROPOSAL_DATA]{"type":"createEvent","title":"Fußballtraining","date":"NAECHSTER-DIENSTAG-DATUM","startHour":18,"startMinute":0,"endHour":20,"endMinute":0,"isAllDay":false,"isLocked":false,"isAnnual":false,"recurrence":"weekly","notes":null}[/PROPOSAL_DATA]

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
        // Hard upper bound on how long "DONNA denkt …" can spin: a stalled request
        // (e.g. proxy auto-discovery, trickling response) must fail into the error
        // path instead of holding the UI. Normal responses arrive in ~1-3s.
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
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
        // responses that repeat the tag themselves, possibly after whitespace).
        if isClarificationAnswer {
            let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            rawText = trimmed.hasPrefix("[PROPOSAL]") ? trimmed : "[PROPOSAL] " + trimmed
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
