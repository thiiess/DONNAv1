import Foundation
import SwiftData

// MARK: - OrchestratorPhase

enum OrchestratorPhase: String {
    case idle
    case interpreting
    case clarifying
    case proposing
    case awaitingConsent = "awaiting_consent"
    case executing
    case blocked
}

// MARK: - InteractionOrchestrator

@MainActor
@Observable
final class InteractionOrchestrator {

    // MARK: - Observable state

    var phase: OrchestratorPhase = .idle

    /// Human-readable proposal text shown in ProposalCard.
    var currentProposal: String?

    /// Clarification question from the AI.
    var currentClarification: String?

    /// Explanation of a conflict or block.
    var currentExplanation: String?

    /// Raw JSON string from the AI's [PROPOSAL_DATA] block.
    var pendingProposalJSON: String?

    /// Human-readable error for the last failed operation.
    var lastError: String?

    /// Last assistant interpretation / fallback message.
    var lastAssistantMessage: String?

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let contextBuilder = ContextBuilder()
    private let assistantClient = InternalAssistantClient()
    private let researchClient = ExternalResearchClient()
    private let parser = ResponseParser()

    // MARK: - Init

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Main processing pipeline

    func process(userInput: String, conversationHistory: [ChatMessage] = []) async {
        clearTransientState()
        phase = .interpreting

        let events       = (try? modelContext.fetch(FetchDescriptor<CalendarEvent>())) ?? []
        let occurrences  = (try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>())) ?? []
        let sleepWindows = (try? modelContext.fetch(FetchDescriptor<SleepWindow>())) ?? []
        let modes        = (try? modelContext.fetch(FetchDescriptor<ContextMode>())) ?? []
        let activeMode   = modes.first(where: { $0.isActive })

        guard let contextJSON = contextBuilder.buildJSON(
            userText: userInput,
            systemPhase: aiPhase(for: phase),
            events: events,
            occurrences: occurrences,
            sleepWindows: sleepWindows,
            activeContextMode: activeMode
        ) else {
            fail("Kontext konnte nicht erstellt werden.")
            return
        }

        let rawResponse: String
        do {
            rawResponse = try await assistantClient.send(
                contextJSON: contextJSON,
                userMessage: userInput,
                conversationHistory: conversationHistory
            )
        } catch {
            var msg = error.localizedDescription
            #if DEBUG
            if let ae = error as? AssistantError, case .apiError(let code, _) = ae {
                msg += " [Debug: \(code) Gemini]"
            } else {
                msg += " [Debug: \(error)]"
            }
            #endif
            fail(msg)
            return
        }

        let parsed: ParsedAIResponse
        do {
            parsed = try parser.parse(rawResponse)
        } catch {
            var msg = "Das habe ich leider nicht verstanden. Bitte versuche es noch einmal."
            #if DEBUG
            msg += " [Debug: parse error — \(error)]"
            #endif
            fail(msg)
            return
        }

        applyResponse(parsed)
    }

    // MARK: - Consent lifecycle

    /// User confirmed a proposal — parse the JSON, build DONNACommand, execute.
    func confirm() {
        guard phase == .awaitingConsent else { return }
        phase = .executing

        guard let jsonStr = pendingProposalJSON else {
            persistSystemMessage("Vorschlag konnte nicht ausgeführt werden – Aktionsdaten fehlen.")
            phase = .idle
            return
        }

        guard let command = buildCommand(from: jsonStr) else {
            persistSystemMessage("Aktion konnte nicht verarbeitet werden – unbekanntes Format.")
            phase = .idle
            return
        }

        let handler = CommandHandler(modelContext: modelContext)
        let result = handler.execute(command)
        switch result {
        case .success:
            persistSystemMessage("Erledigt.")
        case .blocked(let reason):
            currentExplanation = reason
            phase = .blocked
            return
        case .failure(let error):
            lastError = error.localizedDescription
            persistSystemMessage("Fehler: \(error.localizedDescription)")
        }
        phase = .idle
    }

    private func persistSystemMessage(_ text: String) {
        let msg = ChatMessage(role: .assistant, content: text)
        modelContext.insert(msg)
        try? modelContext.save()
    }

    func reject() {
        clearTransientState()
        phase = .idle
    }

    // MARK: - External research

    func research(query: String) async -> String {
        do {
            return try await researchClient.research(query: query)
        } catch {
            return "Recherche nicht verfügbar: \(error.localizedDescription)"
        }
    }

    // MARK: - Command builder

    private func buildCommand(from jsonStr: String) -> DONNACommand? {
        guard let data = try? JSONSerialization.jsonObject(with: Data(jsonStr.utf8)) as? [String: Any],
              let type = data["type"] as? String else { return nil }
        let cal = Calendar.current

        switch type {
        case "createEvent":
            let title    = data["title"]    as? String ?? "Termin"
            let dateStr  = data["date"]     as? String ?? ""
            let isAllDay = data["isAllDay"] as? Bool ?? false
            let isLocked = data["isLocked"] as? Bool ?? false
            let isAnnual = data["isAnnual"] as? Bool ?? false
            let notes    = data["notes"]    as? String
            guard let base = DateFormatter.isoDate.date(from: dateStr) else { return nil }
            let start: Date
            let end: Date
            if isAllDay || isAnnual {
                start = cal.startOfDay(for: base)
                end   = cal.date(bySettingHour: 23, minute: 59, second: 0, of: base) ?? base
            } else {
                let startHour = data["startHour"]   as? Int ?? 9
                let startMin  = data["startMinute"] as? Int ?? 0
                let endHour   = data["endHour"]     as? Int ?? 10
                let endMin    = data["endMinute"]   as? Int ?? 0
                guard let s = cal.date(bySettingHour: startHour, minute: startMin, second: 0, of: base),
                      let e = cal.date(bySettingHour: endHour,   minute: endMin,   second: 0, of: base)
                else { return nil }
                start = s
                end   = e
            }
            return .createEvent(title: title, start: start, end: end, locked: isLocked, notes: notes, isAnnual: isAnnual)

        case "createTask":
            let title      = data["title"]    as? String ?? "Aufgabe"
            let dueDateStr = data["dueDate"]  as? String
            let dueDate    = dueDateStr.flatMap { DateFormatter.isoDate.date(from: $0) }
            let priority   = Priority(rawValue: data["priority"] as? String ?? "none") ?? .none
            return .createTask(title: title, dueDate: dueDate, priority: priority)

        case "createRoutine":
            let title     = data["title"]             as? String ?? "Routine"
            let freq      = RoutineFrequency(rawValue: data["frequency"] as? String ?? "daily") ?? .daily
            let duration  = data["durationMinutes"]   as? Int ?? 30
            let category  = RoutineCategory(rawValue: data["category"] as? String ?? "custom") ?? .custom
            let h         = data["preferredTimeHour"]   as? Int
            let m         = data["preferredTimeMinute"] as? Int
            let preferred: Date? = (h != nil && m != nil)
                ? cal.date(bySettingHour: h!, minute: m!, second: 0, of: Date())
                : nil
            return .createRoutine(definition: RoutineDefinition(
                title: title, frequency: freq,
                preferredTimeOfDay: preferred, durationMinutes: duration, category: category
            ))

        case "setSleepWindow":
            let bedH = data["bedtimeHour"]   as? Int ?? 23
            let bedM = data["bedtimeMinute"] as? Int ?? 0
            let wakH = data["wakeHour"]      as? Int ?? 7
            let wakM = data["wakeMinute"]    as? Int ?? 0
            guard let bed  = cal.date(bySettingHour: bedH, minute: bedM, second: 0, of: Date()),
                  let wake = cal.date(bySettingHour: wakH, minute: wakM, second: 0, of: Date())
            else { return nil }
            return .setSleepWindow(bedtime: bed, wakeTime: wake)

        default:
            return nil
        }
    }

    // MARK: - Private helpers

    private func applyResponse(_ parsed: ParsedAIResponse) {
        switch parsed.outputType {
        case .interpretation:
            lastAssistantMessage = parsed.content
            phase = .idle

        case .clarification:
            currentClarification = parsed.content
            phase = .clarifying

        case .proposal:
            if let json = parsed.proposalJSON {
                currentProposal     = parsed.content
                pendingProposalJSON  = json
                phase = .awaitingConsent
            } else {
                // AI sent [PROPOSAL] without [PROPOSAL_DATA] — treat as interpretation
                lastAssistantMessage = parsed.content
                phase = .idle
            }

        case .explanation:
            currentExplanation = parsed.content
            phase = .blocked
        }
    }

    private func fail(_ message: String) {
        lastError = message
        lastAssistantMessage = message
        phase = .idle
    }

    private func clearTransientState() {
        currentProposal     = nil
        currentClarification = nil
        currentExplanation  = nil
        pendingProposalJSON  = nil
        lastError           = nil
        lastAssistantMessage = nil
    }

    private func aiPhase(for phase: OrchestratorPhase) -> SystemPhase {
        switch phase {
        case .idle:            return .idle
        case .interpreting:    return .interpreting
        case .clarifying:      return .clarifying
        case .proposing:       return .proposing
        case .awaitingConsent: return .awaitingConsent
        case .executing:       return .interpreting
        case .blocked:         return .blocked
        }
    }
}
