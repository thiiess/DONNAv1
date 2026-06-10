# DONNA — Master Specification (v2.1)

> **Status:** V1 abgeschlossen · V2 in Planung
> **Sprache der App:** Deutsch (UI) · Englisch (Code)
> **Zielplattformen:** iOS 17+ · macOS 14+
> **Tech Stack:** Swift 6 · SwiftUI · SwiftData · Google Gemini API (`gemini-2.5-flash`)
> **GitHub:** https://github.com/thiiess/DONNAv1 (privat)

---

## 1. Vision & Kernidee

DONNA ist eine **persönliche, lernende KI-Sekretärin** als native Apple-App.
Sie kombiniert Kalender, Aufgaben, Erinnerungen und Routinen mit einem KI-Chat,
der wie eine erfahrene Assistentin mitdenkt – ohne jemals selbstständig zu handeln.

**Leitprinzip:**
> Die Sekretärin denkt – das System entscheidet – der Nutzer bestätigt.

**Zielgruppe:** Menschen die sich schwer mit Selbstorganisation tun.
**Leitfrage für jede neue Funktion:** „Würde jemand der sich schwer mit Organisation tut, dieses Feature verstehen und nutzen – ohne sich überfordert zu fühlen?"

---

## 2. Kernprinzipien (nicht verhandelbar)

| Prinzip | Beschreibung |
|---|---|
| **Consent-first** | Jede Zustandsänderung erfordert explizite Nutzerbestätigung |
| **Deterministisch** | Gleicher Input + gleicher State = gleiches Verhalten, immer |
| **Undo-Garantie** | Jede ausführbare Aktion ist sofort rückgängig machbar (V2) |
| **KI ist advisory** | KI darf interpretieren, fragen, vorschlagen – niemals ausführen |
| **Lokal-first** | Volle Funktionalität offline; iCloud nur für Sync, kein eigener Server |
| **Transparent** | Nutzer sieht jederzeit, was DONNA gelernt hat und was sie sendet |
| **Datenschutz** | Persönliche Daten verlassen das Gerät nur mit expliziter Zustimmung |

**Was DONNA bewusst NICHT baut:**
- ❌ Gamification: Kein Streak-Counter, keine Badges, keine Punkte
- ❌ Kollaboration: Keine geteilten Routinen, keine Team-Features
- ❌ Vollautomatische Wochenpläne
- ❌ Bidirektionaler Kalender-Sync (CalDAV) — stattdessen read-only EventKit Import (V2-S6b)

---

## 3. System-Architektur

```
┌─────────────────────────────────────────────┐
│              UI / UX Layer                  │  SwiftUI Views
├─────────────────────────────────────────────┤
│           Interaction Orchestrator          │  Ablauf & State-Machine
├──────────────────────┬──────────────────────┤
│      AI Layer        │   Learning Engine    │  Advisory only / Muster
├──────────────────────┴──────────────────────┤
│         Deterministic Application Core      │  Einzige Ausführungsinstanz
├─────────────────────────────────────────────┤
│            Domain State Store               │  SwiftData + CloudKit
└─────────────────────────────────────────────┘
```

### Data flow (implementiert)
```
User input → InteractionOrchestrator → CommandHandler → SwiftData models
                      ↕
             InternalAssistantClient (Gemini — DONNA chat)
             ExternalResearchClient  (Gemini — web research, isolated)
```

### Gemini Multi-turn (implementiert)
- `tagPrefix(for:)` rekonstruiert Type-Tags in der Konversationshistorie
- Bei Klärungsantworten: dynamische Umstrukturierung als explizites Frage-Antwort-Paar
- `[PROPOSAL]`-Prefill als trailing model turn erzwingt korrektes Ausgabeformat
- Zwei getrennte Clients — nie zusammenführen: `InternalAssistantClient` + `ExternalResearchClient`

---

## 4. Datenmodelle (SwiftData — implementiert)

### CalendarEvent
```swift
@Model class CalendarEvent {
    var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date
    var isLocked: Bool
    var isAllDay: Bool
    var isAnnual: Bool          // Jahrestage/Geburtstage — auto-setzt allDay+locked
    var notes: String?
    var createdAt: Date
    var dataLayer: DataLayer
}
```

### DONNATask (Achtung: Klasse heißt DONNATask, nicht Task — Namenskonflikt mit Swift.Task)
```swift
@Model class DONNATask {
    var id: UUID
    var title: String
    var notes: String?
    var status: TaskStatus
    var dueDate: Date?
    var dueTimeIncluded: Bool
    var priority: Priority
    var createdAt: Date
    var completedAt: Date?
    var dataLayer: DataLayer
}
```

### Routine, RoutineOccurrence, SleepWindow, Preference, LearnedProfile, ChatMessage, ContextMode
→ Vollständig implementiert wie in v2.0 Spec beschrieben.

---

## 5. Command-Protokoll (implementiert)

```swift
enum DONNACommand {
    // Tasks
    case createTask(title: String, dueDate: Date?, priority: Priority, notes: String? = nil)
    case updateTask(id: UUID, changes: TaskChanges)
    case completeTask(id: UUID)
    case deleteTask(id: UUID)

    // Calendar
    case createEvent(title: String, start: Date, end: Date, locked: Bool,
                     allDay: Bool = false, isAnnual: Bool = false, notes: String? = nil)
    case updateEvent(id: UUID, changes: EventChanges)
    case deleteEvent(id: UUID)

    // Routines
    case createRoutine(definition: RoutineDefinition)
    case completeOccurrence(id: UUID)
    case skipOccurrence(id: UUID, reason: String?)
    case rescheduleOccurrence(id: UUID, newDate: Date)

    // Sleep, Preferences, Context, Undo
    // → implementiert, Undo-Restore-Stubs noch leer (V2)
}
```

**Wichtig:** Alle Zustandsänderungen laufen durch CommandHandler. Kein View darf direkt in SwiftData schreiben. Einzige Ausnahmen (akzeptiert): ChatMessage-Persistenz in ChatView/ProactiveMonitor, OnboardingView first-run bootstrap.

---

## 6. AI Interface Contract (implementiert)

### Erlaubte Output-Typen
- `[INTERPRETATION]` — beschreibt was der Nutzer meinen könnte
- `[CLARIFICATION]` — eine einzige Rückfrage zu fehlenden Infos
- `[PROPOSAL]` — hypothetische Aktion, klar als Vorschlag markiert
- `[PROPOSAL_DATA]{...}[/PROPOSAL_DATA]` — strukturierte JSON-Daten zum Proposal
- `[EXPLANATION]` — sachliche Erklärung eines Konflikts

### Was DONNA aus dem Chat extrahiert
| Nutzereingabe | DONNA-Verhalten |
|---|---|
| Titel + Uhrzeit | Direkt `[PROPOSAL]`, 1h Standarddauer |
| Nur Uhrzeit | `[CLARIFICATION]` fragt nach Titel |
| Nur Titel | `[CLARIFICATION]` fragt nach Uhrzeit |
| Explizite Endzeit ("19-21 Uhr") | Direkt übernehmen, nie fragen |
| Dauer ("2 Stunden") | Endzeit berechnen |
| "ganztägig" / "den ganzen Tag" | `allDay: true` |
| "gesperrt" / "nicht verschiebbar" | `isLocked: true` |
| "Geburtstag" / "Jahrestag" / "jedes Jahr" | `isAnnual: true` (auto: allDay + locked) |
| Notizen/Kontext | Als `notes` übergeben |

---

## 7. Design System (implementiert)

### Farbpalette (`DS.Colors.*` in DesignSystem.swift)
| Token | Light | Dark | Verwendung |
|---|---|---|---|
| `warmAccent` | `#C4783C` | `#E8A06A` | Buttons, aktive Chips, Sidebar, Toggles |
| `warmLight` | `#F5E6D8` | — | DONNA-Bubble Hintergrund (light) |
| `warmDark` | `#6B3410` | — | Text auf warmem Hintergrund |
| `appBackground` | `NSColor.windowBackgroundColor` | system | Alle Tab-Hintergründe |
| `donnaBubbleBg` | `#F5E6D8` | `#2E2420` | DONNA Chat-Bubble |
| `donnaBubbleFg` | `#6B3410` | `#E8A06A` | DONNA Chat-Bubble Text |

### UI-Regeln
- Sheets: plain `VStack`, kein `Form`/`Section`/`List`
- Titelfelder: `.title2.weight(.semibold)` + untere Divider-Linie
- Datum/Zeit-Chips: aktiv = `warmAccent` fill + weiß, inaktiv = `warmAccent.opacity(0.15)` + `warmAccent` Text
- Toggles: immer `.tint(DS.Colors.warmAccent)`
- Sidebar aktiv: `warmAccent.opacity(0.15)` Hintergrund + `warmAccent` Text
- Sidebar-Buttons: `.frame(maxWidth: .infinity)` + `.contentShape(Rectangle())` für vollen Tap-Bereich
- TaskDetailView: als `.sheet` präsentiert, nicht als NavigationLink push

---

## 8. Implementierter Feature-Stand (V1 abgeschlossen)

### ✅ Vollständig implementiert
- Kalender (Tag/Woche/Monat), Aufgaben, Routinen, DONNA-Chat, Einstellungen
- Termin erstellen/bearbeiten/löschen via UI und via DONNA-Chat
- Aufgabe erstellen/bearbeiten/löschen via UI
- Routine erstellen, Occurrences als erledigt/übersprungen markieren
- DONNA Chat: Multi-turn Konversation, Proposal-Flow, Bestätigung, Fehlerbehandlung
- Jahrestage/Geburtstage: `isAnnual` Flag, auto allDay + locked
- Ganztägige Termine, gesperrte Termine
- Notizen für Termine und Aufgaben
- Design System mit warmem Terrakotta-Farbschema
- Debug-Labels in DEBUG-Builds: `[Debug: 503 Gemini]`, `[Debug: parse error — ...]`
- Git-Repository auf GitHub

### ⚠️ Bewusst zurückgestellt (V2)
- Wiederkehrende Termine ("jeden Dienstag") — V2-S6
- Vorschlag inline bearbeiten ("lieber 30 Minuten später") — V2-S4
- Kalender-Swipe-Navigation — V2
- UndoManager Restore-Stubs (9 leere Methoden) — V2
- CloudKit Sync — V2-S12 (benötigt bezahlten Developer Account)
- Push Notifications — V2 (benötigt bezahlten Developer Account)

---

## 9. V2 Roadmap

| Session | Inhalt | Priorität | Status |
|---|---|---|---|
| V2-S1 | Code-Cleanup + CommandHandler Stubs | 🔴 Pflicht | ✅ Done |
| V2-S6b | EventKit Integration – Kalender-Import read-only | 🟡 Hoch | ⬜ Offen |
| V2-S2 | Morgenbriefing + Wochenzusammenfassung | 🔴 Pflicht | ⬜ Offen |
| V2-S3 | Erschöpfungs-Modus + Kontextuelles Gedächtnis | 🔴 Pflicht | ⬜ Offen |
| V2-S4 | Vorschlag bearbeiten + Chat-Verbesserungen | 🟡 Hoch | ⬜ Offen |
| V2-S5 | Smarte Mustererkennung + Energie-Profil | 🟡 Hoch | ⬜ Offen |
| V2-S6 | Fehlende Datenmodelle (prepTime, Someday, Recurrence) | 🟡 Hoch | ⬜ Offen |
| V2-S7 | DONNA-Tab Redesign + Leere Zustände + Micro-Interactions | 🟡 Hoch | ⬜ Offen |
| V2-S8 | KI-Verbesserungen (Konfidenz, Zeitton, Stress) | 🟢 Mittel | ⬜ Offen |
| V2-S9 | WidgetKit + Siri Shortcuts + Live Activities | 🟢 Mittel | ⬜ Offen |
| V2-S10 | Apple Health Integration (read-only) + Focus Modes | 🟢 Mittel | ⬜ Offen |
| V2-S11 | Ton-Richtlinien V2 + System-Prompt Verbesserungen | 🟢 Mittel | ⬜ Offen |
| V2-S12 | CloudKit Sync (mit paid Developer Account) | 🔵 Später | ⬜ Offen |
| V2-S13 | Testing + Bug-Fixes + GitHub Release V2 | 🔴 Pflicht | ⬜ Offen |

---

## 10. V2-S6b: EventKit Integration

### Prinzip: Import statt Sync
DONNA liest bestehende Kalender read-only via EventKit. Sie ändert dort nichts. DONNA bleibt einzige Wahrheitsquelle für ihre eigenen Daten.

### Technisch
```swift
struct ExternalCalendarEvent {
    let title: String
    let startTime: Date
    let endTime: Date
    let calendarName: String
    let isAllDay: Bool
    let externalIdentifier: String
}

final class EventKitManager {
    func requestAccess() async -> Bool
    func fetchEvents(from: Date, to: Date) -> [ExternalCalendarEvent]
    func revokeAccess()
}
```

- Externe Termine erscheinen grau/gedimmt in der Kalenderansicht
- `ConflictDetector` berücksichtigt externe Termine
- Externe Termine erscheinen im Morgenbriefing
- Keine SwiftData-Persistenz für externe Events

---

## 11. V2-S2: Morgenbriefing

Täglich morgens (konfigurierbar, default 8:00):
- Anzahl Termine + wichtigster Termin
- Offene Routinen für heute
- Eventuelle Konflikte
- Genau eine Frage oder ein Vorschlag

Beispiel:
> „Guten Morgen. Heute: Arzttermin um 14 Uhr, Lernblock geplant, Sport offen. Achtung: Lernblock und Arzttermin überschneiden sich. Soll ich den Lernblock verschieben?"

---

## 12. V2-S4: Vorschlag bearbeiten

```
┌─────────────────────────────────┐
│ VORSCHLAG                       │
│ Friseur: Heute, 18:00–19:00    │
├──────────┬──────────┬───────────┤
│ ✓ Ja    │ ✎ Ändern │ ✗ Nein   │
└──────────┴──────────┴───────────┘
```

„Ändern" öffnet minimalen Inline-Editor. Nutzer kann sagen „lieber 30 Minuten später" und Proposal wird angepasst.

---

## 13. V2-S6: Fehlende Datenmodelle

### Wiederkehrende Termine (einfach)
```swift
// CalendarEvent Erweiterung
enum Recurrence: String, Codable {
    case weekly(weekday: Int)
    case biweekly(weekday: Int)
}
var recurrence: Recurrence?
```
DONNA fragt nach 3× gleichem Wochentag: „Du trägst Fußball jede Woche dienstags ein. Soll ich das als Serientermin anlegen?"

### Vorbereitungszeit
```swift
var prepTimeMinutes: Int?
```

### Someday-Stapel
```swift
var isSomeday: Bool = false
```

### Aufgaben-Abhängigkeiten
```swift
var blockedByTaskId: UUID?
```

---

## 14. Ton-Richtlinien (gilt ab sofort)

| ❌ So nicht | ✅ So |
|---|---|
| „Du hast Sport nicht gemacht!" | „Sport ist diese Woche ausgefallen." |
| „Super, 3 Aufgaben erledigt!" | „3 Aufgaben heute erledigt." |
| „Du solltest mehr schlafen!" | „Dein Schlaf war diese Woche unter 6h." |

- Maximal 2 Sätze pro Antwort
- Nie Ausrufezeichen
- Nie „Super!", „Toll!", „Wunderbar!"
- Immer konkret, nie vage

---

## 15. Geplante V3-Features

- Apple Watch: Haptic-Alerts, Ein-Button-Erledigt, Pause-Complication
- Sprachmemo als Eingabe (lokale Transkription via SFSpeechRecognizer)
- Jahresrückblick (31. Dezember, als PDF exportierbar)
- Kontextmodus „Reise"
- Offline-KI via On-Device-Model (Apple Intelligence / Core ML)

---

## 16. Entscheidungsmatrix für neue Features

| Frage | Erwartete Antwort |
|---|---|
| Würde jemand der sich schlecht organisiert dieses Feature verstehen? | Ja |
| Erfordert es explizite Nutzer-Bestätigung? | Ja |
| Fügt es mehr als es wegnimmt? | Ja |
| Führt es zu Gamification, Druck oder Schuldgefühlen? | Nein |
| Erhöht es die Komplexität ohne klaren Nutzen? | Nein |

---

*Ende der Spezifikation · Version 2.1 · V1 abgeschlossen Juni 2026*
