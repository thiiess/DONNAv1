# DONNA — Master Specification (v2.0)

> **Status:** Aktiv · Grundlage für Implementierung mit Claude Code  
> **Sprache der App:** Deutsch & Englisch (Lokalisierung ab Phase 1)  
> **Zielplattformen:** iOS 17+ · macOS 14+  
> **Tech Stack:** Swift 6 · SwiftUI · SwiftData · CloudKit · Google Gemini API (kostenlos)

---

## 1. Vision & Kernidee

DONNA ist eine **persönliche, lernende KI-Sekretärin** als native Apple-App.  
Sie kombiniert Kalender, Aufgaben, Erinnerungen und Routinen mit einem KI-Chat,  
der wie eine erfahrene Assistentin mitdenkt – ohne jemals selbstständig zu handeln.

**Leitprinzip:**
> Die Sekretärin denkt – das System entscheidet – der Nutzer bestätigt.

**Was DONNA ist:**
- Ein vollständig manuell bedienbares Produktivitätssystem (Kalender, Tasks, Routinen)
- Erweitert durch einen KI-Chat für natürlichsprachliche Eingaben und Vorschläge
- Eine Assistentin, die lernt, warnt und vorschlägt – niemals eigenständig ausführt
- Lokal-first mit iCloud-Sync zwischen iPhone und Mac

**Was DONNA nicht ist:**
- Kein autonomer Agent
- Kein Cloud-Dienst, der Daten verkauft oder weitergibt
- Kein Optimierer, der den Nutzer unter Druck setzt
- Kein System, das still im Hintergrund Dinge ändert

---

## 2. Kernprinzipien (nicht verhandelbar)

| Prinzip | Beschreibung |
|---|---|
| **Consent-first** | Jede Zustandsänderung erfordert explizite Nutzerbestätigung |
| **Deterministisch** | Gleicher Input + gleicher State = gleiches Verhalten, immer |
| **Undo-Garantie** | Jede ausführbare Aktion ist sofort rückgängig machbar |
| **KI ist advisory** | KI darf interpretieren, fragen, vorschlagen – niemals ausführen |
| **Lokal-first** | Volle Funktionalität offline; iCloud nur für Sync, kein eigener Server |
| **Transparent** | Nutzer sieht jederzeit, was DONNA gelernt hat und was sie sendet |
| **Datenschutz** | Persönliche Daten verlassen das Gerät nur mit expliziter Zustimmung |

---

## 3. System-Architektur

Das System besteht aus **sechs klar getrennten Schichten**.  
Keine Schicht übernimmt Aufgaben einer anderen.

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

### 3.1 Domain State Store
- **Technologie:** SwiftData mit CloudKit-Sync via `ModelConfiguration`
- **Verantwortung:** Persistenz aller Daten; einzige Wahrheitsquelle
- **Schreibzugriff:** Ausschließlich durch den Deterministic Core
- **Lesezugriff:** Read-only Snapshots für alle anderen Schichten
- **Darf nicht:** Regeln durchsetzen, Validierung, Entscheidungen treffen

### 3.2 Deterministic Application Core
- **Verantwortung:** Validierung, Regelanwendung, Ausführung, Undo
- **Unterkomponenten:**
  - `CommandHandler` – nimmt Commands entgegen, delegiert
  - `ConflictDetector` – prüft Überlappungen mit Events und Schlafzeiten
  - `ScienceEngine` – prüft wissenschaftliche Regeln (Sport, Schlaf, Lernen)
  - `RoutineScheduler` – generiert RoutineOccurrences
  - `UndoManager` – speichert genau einen Pre-Execution-Snapshot
- **Darf nicht:** Sprache interpretieren, KI aufrufen, UI-Entscheidungen treffen

### 3.3 AI Layer
- **Technologie:** Google Gemini API (`gemini-2.0-flash`) – kostenlos, kein Abo nötig
- **Zwei getrennte Aufrufe, strikt isoliert:**

**Aufruf 1 – Interner Assistent (DONNA)**
- Zuständig für: Sprachinterpretation, Rückfragen, Vorschlagsentwürfe, Erklärungen
- Bekommt: minimalen, anonymisierten Kalender-/Routinen-Kontext (kein Name, kein Klartext-Ort)
- Gibt zurück: genau einen der vier erlaubten Output-Typen (siehe Abschnitt 6)
- Weiß nie: wer der Nutzer ist, welche externe Recherche gerade läuft
- Komponente: `InternalAssistantClient`

**Aufruf 2 – Externe Recherche**
- Zuständig für: Wetter, allgemeine Fragen, Recherche im Internet
- Bekommt: nur die anonyme Suchanfrage – keine persönlichen Daten, kein Kontext
- Nutzt: Gemini mit aktiviertem **Google Search Grounding** (kostenlos eingebaut)
- Weiß nie: was im Kalender steht oder wer die Anfrage stellt
- Komponente: `ExternalResearchClient`

**Beide Aufrufe laufen über denselben kostenlosen Gemini API Key.**  
Die Trennung ist architektonisch erzwungen – kein gemeinsamer Kontext, kein Datenaustausch zwischen den beiden Clients.

**Kontext-Minimierung für Aufruf 1 (Pflicht):**  
Der `ContextBuilder` filtert vor jedem API-Call:
- Nur relevanter Zeitraum (z.B. nächste 12 Stunden)
- Keine Namen, keine Klarnamen von Orten
- Nur strukturelle Daten: Zeitfenster, Typ, Status, Konflikte
- **Darf nicht (beide Clients):** State ändern, Commands konstruieren, Consent annehmen, Daten zwischen Aufruf 1 und 2 teilen

### 3.4 Learning Engine
- **Verantwortung:** Mustererkennung, Profilaktualisierung, Daten-Lifecycle
- **Unterkomponenten:**
  - `PatternExtractor` – analysiert Verhalten (Schlaf, Routinen, Bestätigungen)
  - `ProfileUpdater` – aktualisiert `LearnedProfile`, fragt bei neuen Mustern nach
  - `DataLifecycleManager` – verschiebt Daten zwischen HOT / WARM / COLD
- **Lernprinzip:** Beobachten → Muster erkennen → Nutzer fragen → erst dann speichern
- **Darf nicht:** Still lernen, ohne den Nutzer zu informieren

### 3.5 Interaction Orchestrator
- **Verantwortung:** Interaktionsablauf, State-Machine, Routing
- **Zustände:** `idle` · `interpreting` · `clarifying` · `proposing` · `awaiting_consent` · `executing` · `blocked`
- **Proaktive Aufgaben:**
  - Erkennt unbemerkte Konflikte im Kalender
  - Erkennt vergessene Routinen nach Terminausfall
  - Beobachtet Schlafmangel-Muster
  - Löst Push-Benachrichtigungen aus
- **Darf nicht:** Sprache interpretieren, State direkt ändern, KI-Output als Befehl behandeln

### 3.6 UI Layer
- **Technologie:** SwiftUI (shared codebase iOS + macOS via `#if os(iOS)`)
- **Verantwortung:** Darstellung, Interaktion, Bestätigung/Ablehnung von Vorschlägen
- **Prinzipien:** Ruhig · übersichtlich · Vorschläge klar als Vorschläge markiert

---

## 4. Datenmodelle (SwiftData)

```swift
// MARK: - Task
@Model class Task {
    var id: UUID
    var title: String
    var notes: String?
    var status: TaskStatus          // open, completed, cancelled
    var dueDate: Date?
    var dueTimeIncluded: Bool
    var priority: Priority          // none, low, medium, high
    var createdAt: Date
    var completedAt: Date?
    var dataLayer: DataLayer        // hot, warm, cold
}

// MARK: - CalendarEvent
@Model class CalendarEvent {
    var id: UUID
    var title: String
    var startTime: Date
    var endTime: Date
    var isLocked: Bool              // kann nicht verschoben werden
    var notes: String?
    var createdAt: Date
    var dataLayer: DataLayer
}

// MARK: - Routine
@Model class Routine {
    var id: UUID
    var title: String
    var frequency: RoutineFrequency // daily, weekdays, weekly, custom
    var preferredTimeOfDay: Date?   // nur Uhrzeit-Komponente
    var durationMinutes: Int
    var priority: Priority
    var isActive: Bool
    var category: RoutineCategory   // sleep, sport, learning, skincare, custom
    var colorHex: String
    var maxSkipsBeforeWarning: Int  // default: 2
    var createdAt: Date
    var occurrences: [RoutineOccurrence]
}

// MARK: - RoutineOccurrence
@Model class RoutineOccurrence {
    var id: UUID
    var routine: Routine
    var scheduledDate: Date
    var status: OccurrenceStatus    // scheduled, completed, skipped, rescheduled
    var completedAt: Date?
    var skippedReason: String?
    var dataLayer: DataLayer
}

// MARK: - SleepWindow
@Model class SleepWindow {
    var id: UUID
    var date: Date                  // Datum dieser Schlafperiode
    var bedtime: Date               // Einschlafzeit
    var wakeTime: Date              // Aufwachzeit
    var isProtected: Bool           // default: true → blockiert Planung
    var durationMinutes: Int        // computed
    var dataLayer: DataLayer
}

// MARK: - Preference
@Model class Preference {
    var id: UUID
    var key: String                 // z.B. "productive_hours_start"
    var value: String               // JSON-kodiert
    var scope: PreferenceScope      // global, routine, context
    var isActive: Bool
    var source: PreferenceSource    // explicit, observed, default
    var confirmedAt: Date?
    var createdAt: Date
}

// MARK: - LearnedProfile (Singleton)
@Model class LearnedProfile {
    var id: UUID
    var avgBedtime: Date?           // Uhrzeit-Komponente
    var avgSleepDuration: Double?   // Stunden
    var sleepTrend: Trend           // stable, improving, declining
    var productiveHoursStart: Int?  // Stunde 0-23
    var productiveHoursEnd: Int?
    var avgSportPerWeek: Double?
    var routineAdherence: Data      // JSON: [routineId: adherenceRate]
    var weeklyPatterns: Data        // JSON: Wochentag-Muster
    var lastUpdated: Date
    var totalDataPoints: Int        // für Transparenz-Anzeige
}

// MARK: - ChatMessage
@Model class ChatMessage {
    var id: UUID
    var role: MessageRole           // user, assistant
    var content: String
    var outputType: AIOutputType?   // interpretation, clarification, proposal, explanation
    var relatedCommandId: UUID?
    var timestamp: Date
    var dataLayer: DataLayer
}

// MARK: - ContextMode
@Model class ContextMode {
    var id: UUID
    var name: String                // vacation, exam, normal, custom
    var isActive: Bool
    var startDate: Date?
    var endDate: Date?
    var overrides: Data             // JSON: welche Regeln gelten nicht
}

// MARK: - Enums
enum TaskStatus: String, Codable { case open, completed, cancelled }
enum Priority: String, Codable, CaseIterable { case none, low, medium, high }
enum RoutineFrequency: String, Codable { case daily, weekdays, weekly, custom }
enum RoutineCategory: String, Codable { case sleep, sport, learning, skincare, nutrition, custom }
enum OccurrenceStatus: String, Codable { case scheduled, completed, skipped, rescheduled }
enum PreferenceScope: String, Codable { case global, routine, context }
enum PreferenceSource: String, Codable { case explicit, observed, `default` }
enum MessageRole: String, Codable { case user, assistant }
enum AIOutputType: String, Codable { case interpretation, clarification, proposal, explanation }
enum DataLayer: String, Codable { case hot, warm, cold }
enum Trend: String, Codable { case stable, improving, declining }
```

---

## 5. Command-Protokoll

Alle Zustandsänderungen laufen als typisierte Commands durch den Core.  
Kein Command → keine Änderung. Kein Ausnahme.

```swift
enum DONNACommand {
    // Tasks
    case createTask(title: String, dueDate: Date?, priority: Priority)
    case updateTask(id: UUID, changes: TaskChanges)
    case completeTask(id: UUID)
    case deleteTask(id: UUID)

    // Calendar
    case createEvent(title: String, start: Date, end: Date, locked: Bool)
    case updateEvent(id: UUID, changes: EventChanges)
    case deleteEvent(id: UUID)

    // Routines
    case createRoutine(definition: RoutineDefinition)
    case completeOccurrence(id: UUID)
    case skipOccurrence(id: UUID, reason: String?)
    case rescheduleOccurrence(id: UUID, newDate: Date)

    // Sleep
    case setSleepWindow(bedtime: Date, wakeTime: Date)

    // Preferences & Profile
    case confirmPreference(key: String, value: String)
    case deleteLearnedItem(key: String)

    // Context
    case activateContextMode(name: String, until: Date?)
    case deactivateContextMode

    // Undo
    case undo
}
```

**Command Flow (immer in dieser Reihenfolge):**
1. Nutzer-Input → Orchestrator
2. Orchestrator → AI Layer (optional, für Sprachinterpretation)
3. AI → Proposal Draft (kein Command, nur Text)
4. UI zeigt Proposal an, wartet auf Bestätigung
5. Nutzer bestätigt → Orchestrator konstruiert Command (nicht die KI!)
6. Command → Core zur Validierung
7. Core prüft: Struktur · Konflikte · Schlaf · Wissenschaft
8. Bei Erfolg: Undo-Snapshot → Ausführung → State Store
9. Bei Ablehnung: Explanation zurück an UI

---

## 6. AI Interface Contract (frozen)

### Erlaubte Input-Felder (alle read-only):
```json
{
  "user_text": "string",
  "system_phase": "idle | interpreting | clarifying | proposing | awaiting_consent | blocked",
  "context_snapshot": {
    "upcoming_events": [{ "type": "string", "start_offset_minutes": 0, "duration_minutes": 0, "is_locked": false }],
    "open_routines_today": ["string"],
    "sleep_window": { "bedtime_hour": 23, "wake_hour": 7, "is_protected": true },
    "active_context_mode": "string | null",
    "conflict_flags": ["string"]
  }
}
```
→ Keine IDs, keine Klarnamen, kein interner State

### Erlaubte Output-Typen (genau einer pro Response):

**Interpretation** – Beschreibt, was der Nutzer meinen könnte. Keine Entscheidung.  
**Clarification** – Eine einzige neutrale Rückfrage zu fehlenden Infos.  
**Proposal Draft** – Hypothetische Aktion, klar als Vorschlag markiert, nie als Befehl.  
**Explanation** – Sachliche Erklärung eines Konflikts oder einer Blockade.

### Verbotene Phrasen (führen zu Response-Verwerfung):
`"Ich werde…"` · `"Ich habe…"` · `"Das wird…"` · `"Am besten…"` · `"Du solltest…"` · `"Ich mache das…"`

---

## 7. Science Engine – Regelkatalog

Die `ScienceEngine` gibt **Warnungen** aus, blockiert aber nicht (außer konfiguriert).  
Der Nutzer entscheidet immer final.

```swift
struct ScienceWarning {
    let category: RoutineCategory
    let severity: WarningSeverity   // info, warning, critical
    let message: LocalizedStringKey
    let suggestion: LocalizedStringKey?
}
```

### Sport-Regeln:
- Gleiche Muskelgruppe < 48 h nach intensivem Training → Warning
- Mehr als 6 Trainingseinheiten/Woche ohne Ruhetag → Warning
- Ausdauer + Kraft am selben Tag ohne Pause → Info
- Beintraining nach Fußball/Laufen am Folgetag → Warning

### Schlaf-Regeln:
- < 6 h Schlaf → Warning
- < 6 h Schlaf an 3+ aufeinanderfolgenden Tagen → Critical
- Schlafzeit variiert > 90 min im Wochendurchschnitt → Info (Zirkadianrhythmus)
- Routine in Schlafschutzfenster geplant → blockiert

### Lern-Regeln:
- Lernblock > 90 min ohne geplante Pause → Info
- Lernen direkt vor Schlaf (< 30 min) → Info
- Kein Lernblock seit > 3 Tagen bei aktiver Lernroutine → Warning

### Allgemeine Regeln:
- Tag mit > 10 h geplanter Aktivität → Warning (Überlastung)
- Keine Erholungszeit (Sport/Lernen/Arbeit lückenlos) → Warning

---

## 8. Learning Engine

### PatternExtractor – was analysiert wird:
- Durchschnittliche Einschlaf-/Aufwachzeit (letzte 30 Tage)
- Häufigste Trainingszeiten und -tage
- Routine-Adherence pro Routine (Prozentwert)
- Typische Bestätigungs- vs. Ablehnungs-Muster bei Vorschlägen
- Kontextmodus-Häufigkeit

### ProfileUpdater – Lernprozess:
```
Beobachtung (3+ Mal wiederholt)
    → PatternExtractor erstellt Muster
    → DONNA fragt: „Ich habe bemerkt, dass du meist um 23 Uhr schläfst.
                    Soll ich das als Standard merken?"
    → Nutzer bestätigt / ablehnt
    → Bei Bestätigung: Preference mit source=observed gespeichert
    → Bei Ablehnung: Muster verworfen, nicht erneut gefragt (30 Tage Cooldown)
```

### Transparenz-Ansicht (in Einstellungen):
- Liste aller Preferences mit Quelle (explicit / observed / default)
- Datum der letzten Bestätigung
- Löschen einzelner Einträge möglich
- „Was DONNA über mich weiß" – lesbarer Überblick des LearnedProfile

---

## 9. Datenstrategie (HOT / WARM / COLD)

### Definitionen:

| Layer | Zeitraum | Inhalt | Speicher |
|---|---|---|---|
| **HOT** | < 6 Monate + alle Zukunft | Volle Rohdaten | hoch |
| **WARM** | 6 Monate – 2 Jahre | Komprimierte Zusammenfassungen | mittel |
| **COLD** | > 2 Jahre | Jahres-Statistiken | minimal |

### DataLifecycleManager:
- Läuft wöchentlich im Hintergrund (Background App Refresh)
- Vor Komprimierung: PatternExtractor sichert alle Muster ins Profil
- HOT → WARM: Einzeleinträge → Monatliche Aggregate  
  Beispiel: 30 SleepWindow-Einträge → `{ month: "2025-01", avgBedtime: "23:12", avgDuration: 7.1 }`
- WARM → COLD: Monatliche Aggregate → Jahres-Zusammenfassung
- Vor COLD-Überführung: Export-Angebot an Nutzer (JSON)
- LearnedProfile und Preferences: immer HOT, werden nie archiviert

### Einstellungen (nutzerkontrolliert):
- HOT-Zeitraum: 3 / 6 / 12 Monate (default: 6)
- Chat-History: 1 / 3 / 6 Monate (default: 3)
- Vor Archivierung: Benachrichtigung + Export-Option
- „Speicher-Dashboard": zeigt Größe pro Kategorie

---

## 10. Sync-Strategie (CloudKit)

- **Technologie:** SwiftData + CloudKit via `ModelConfiguration(cloudKitDatabase: .automatic)`
- **Kein eigener Server**; Daten liegen ausschließlich im privaten iCloud-Container des Nutzers
- **Offline-first:** Alle Operationen funktionieren ohne Verbindung; Sync bei Verbindung automatisch
- **Conflict Resolution:** Last-write-wins (SwiftData Standard) – reicht für Single-User
- **Sync-Scope:** Alle HOT-Daten; WARM/COLD nur wenn Nutzer explizit aktiviert

---

## 11. UI-Struktur

### Haupt-Navigation (Tab Bar iOS / Sidebar macOS):
```
📅 Kalender     – Tages-/Wochen-/Monatsansicht, Events + Routines
✅ Aufgaben     – Task-Liste, nach Fälligkeit / Priorität gefiltert
🔄 Routinen     – Routine-Übersicht, heutige Occurrences, Streak
💬 DONNA        – Chat-Fenster + Vorschlags-Feed
⚙️ Einstellungen – Profil, Gelerntes, Speicher, Datenschutz
```

### Chat-View (DONNA):
- **Oben:** Vorschlags-Feed (proaktive Hinweise von DONNA, ungelesen zuerst)
- **Mitte:** Chat-Verlauf (user / assistant Bubbles, Output-Typ sichtbar)
- **Unten:** Texteingabe + Senden
- Vorschläge haben immer zwei Buttons: **Bestätigen** / **Ablehnen**

### Proposals-Bereich:
- Karte pro Vorschlag mit: Beschreibung · betroffene Daten · Zeitfenster
- Aktionen: Bestätigen · Ablehnen · Mehr Info (Explanation)
- Ungelesene Vorschläge → Badge auf Tab

### Einstellungen – wichtige Bereiche:
- **Was DONNA weiß:** LearnedProfile lesbar, löschbar
- **Datenschutz:** Letzter API-Kontext einsehbar · Daten-Sharing Protokoll
- **Speicher:** Dashboard mit HOT/WARM/COLD-Größen · Retention-Einstellungen
- **Wissenschaftliche Regeln:** welche aktiv, welche stummgeschaltet
- **Kontextmodus:** aktiver Modus, neue anlegen

### Benachrichtigungen (UserNotifications):
- Aufgaben-Erinnerungen (Fälligkeit)
- Routine-Erinnerungen (konfigurierbare Vorlaufzeit)
- DONNA-Hinweise (niedrigere Priorität, gebündelt)
- Schlafwarnung wenn Aktivitäten das Schlaffenster gefährden

---

## 12. Onboarding-Flow

Beim ersten Start führt DONNA ein strukturiertes Gespräch:
1. Sprache wählen (DE / EN)
2. Typische Schlafzeit (Bett / Aufstehen)
3. Produktive Tageszeit (Morgen / Mittag / Abend / variabel)
4. Erste Routinen anlegen (Sport, Lernen, Skincare – aus Vorlagen oder custom)
5. Kontextmodus wählen (Normaler Alltag / Studium / Beruf)
6. Kurze Erklärung der KI-Datenschutz-Policy
→ Daraus wird das initiale `LearnedProfile` + erste `Preferences` generiert

---

## 13. Lokalisierung

- Alle Strings via `LocalizedStringKey` / `String(localized:)`
- Localizable.strings für: `de`, `en`
- DONNAs Chat-Sprache folgt der App-Sprache
- Wissenschaftliche Hinweise sind vollständig lokalisiert
- Datumsformate: `.locale(Locale.current)` – automatisch

---

## 14. Projektstruktur

```
DONNA/
├── DONNA_SPEC.md
├── DONNA.xcodeproj
└── DONNA/
    ├── App/
    │   ├── DONNAApp.swift           # Entry Point, ModelContainer setup
    │   └── AppState.swift           # Globaler ObservableObject
    ├── Models/                      # Alle SwiftData @Model Klassen
    │   ├── Task.swift
    │   ├── CalendarEvent.swift
    │   ├── Routine.swift
    │   ├── RoutineOccurrence.swift
    │   ├── SleepWindow.swift
    │   ├── Preference.swift
    │   ├── LearnedProfile.swift
    │   ├── ChatMessage.swift
    │   ├── ContextMode.swift
    │   └── Enums.swift
    ├── Core/                        # Deterministic Application Core
    │   ├── CommandHandler.swift
    │   ├── ConflictDetector.swift
    │   ├── ScienceEngine.swift
    │   ├── RoutineScheduler.swift
    │   └── UndoManager.swift
    ├── AI/                          # AI Layer (zwei getrennte Clients)
    │   ├── ContextBuilder.swift         # Baut anonymisierten Kontext für Aufruf 1
    │   ├── InternalAssistantClient.swift # Aufruf 1: DONNA-Chat (kein PII)
    │   ├── ExternalResearchClient.swift  # Aufruf 2: Recherche (kein Kontext)
    │   └── ResponseParser.swift          # Validiert AI-Output gegen Contract
    ├── Orchestrator/
    │   ├── InteractionOrchestrator.swift
    │   ├── ProactiveMonitor.swift
    │   └── NotificationScheduler.swift
    ├── Learning/
    │   ├── PatternExtractor.swift
    │   ├── ProfileUpdater.swift
    │   └── DataLifecycleManager.swift
    ├── Views/
    │   ├── Calendar/
    │   │   ├── CalendarView.swift
    │   │   ├── DayView.swift
    │   │   └── EventDetailView.swift
    │   ├── Tasks/
    │   │   ├── TaskListView.swift
    │   │   └── TaskDetailView.swift
    │   ├── Routines/
    │   │   ├── RoutineListView.swift
    │   │   └── RoutineDetailView.swift
    │   ├── Chat/
    │   │   ├── ChatView.swift
    │   │   ├── MessageBubble.swift
    │   │   ├── ProposalCard.swift
    │   │   └── ProposalFeedView.swift
    │   ├── Onboarding/
    │   │   └── OnboardingView.swift
    │   └── Settings/
    │       ├── SettingsView.swift
    │       ├── LearnedProfileView.swift
    │       └── StorageDashboardView.swift
    ├── Utilities/
    │   ├── DateExtensions.swift
    │   └── JSONHelpers.swift
    └── Resources/
        ├── Localizable.xcstrings
        └── Assets.xcassets
```

---

## 15. Gemini API – Setup & Konfiguration

### API Key holen (kostenlos):
1. Geh auf **aistudio.google.com**
2. Mit Google-Konto anmelden
3. **„Get API Key"** → neuen Key erstellen
4. Key sicher speichern (kommt in den iOS Keychain, nie hardcoded)

### Kostenloses Limit (Stand 2025):
- **1.500 Anfragen/Tag** mit `gemini-2.0-flash`
- Für privaten DONNA-Gebrauch mehr als ausreichend
- Kein Abo, keine Kreditkarte nötig

### Endpunkte:
```
Aufruf 1 (Intern):   POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent
Aufruf 2 (Recherche): POST https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent
                       + tools: [{ "google_search": {} }]
```

### API Key Speicherung (sicher):
```swift
// Speichern (einmalig bei Einrichtung):
KeychainHelper.save(key: "donna_gemini_api_key", value: apiKey)

// Abrufen (bei jedem API-Call):
let apiKey = KeychainHelper.load(key: "donna_gemini_api_key")
```
→ Nie im Code hardcoden, nie in UserDefaults speichern

---



Jede Phase ist eine eigenständige Claude Code Session.  
**Jede Session beginnt mit:** `"Lies zuerst DONNA_SPEC.md, dann implementiere folgendes:"`

### Phase 1 – Foundation (Session 1–2)
**Session 1:** Xcode-Projekt aufsetzen, alle Datenmodelle (`Models/`), Enums, ModelContainer  
**Session 2:** `CommandHandler` + alle Command-Typen (ohne Logik, nur Struktur), `UndoManager`

### Phase 2 – Core Logic (Session 3–4)
**Session 3:** `ConflictDetector` (Überlappungen, Schlafschutz), `RoutineScheduler`  
**Session 4:** `ScienceEngine` (alle Regeln aus Abschnitt 7 implementieren + Tests)

### Phase 3 – Basis-UI (Session 5–6)
**Session 5:** Tab-Navigation, `CalendarView` (Tagesansicht), `TaskListView`  
**Session 6:** `RoutineListView`, manuelle Task/Event/Routine-Erstellung (ohne KI)

### Phase 4 – AI Layer (Session 7–8)
**Session 7:** `ContextBuilder` + `InternalAssistantClient` (Gemini API, Aufruf 1, anonymisierter Kontext)  
**Session 8:** `ExternalResearchClient` (Gemini + Search Grounding, Aufruf 2), `ResponseParser`, `InteractionOrchestrator`

### Phase 5 – Chat & Proposals (Session 9)
**Session 9:** `ChatView`, `MessageBubble`, `ProposalCard`, `ProposalFeedView`

### Phase 6 – Learning & Transparenz (Session 10)
**Session 10:** `PatternExtractor`, `ProfileUpdater`, `LearnedProfileView`, Bestätigungs-Flow

### Phase 7 – Proaktivität & Notifications (Session 11)
**Session 11:** `ProactiveMonitor`, `NotificationScheduler`, Badge-Logik

### Phase 8 – Sync & Lifecycle (Session 12)
**Session 12:** CloudKit-Konfiguration, `DataLifecycleManager`, `StorageDashboardView`

### Phase 9 – Onboarding & Polish (Session 13)
**Session 13:** `OnboardingView`, Lokalisierung (DE/EN), Einstellungen vollständig

### Phase 10 – Widgets & Final (Session 14)
**Session 14:** iOS Widget (WidgetKit), macOS-Anpassungen, App-Icon, TestFlight

---

## 16. Claude Code – Hinweise zur effizienten Nutzung

### Jede Session so formulieren:
```
"Lies zuerst DONNA_SPEC.md komplett.
Implementiere dann ausschließlich: [spezifische Aufgabe aus Phase X].
Schreibe Tests für [Komponente].
Ändere keine anderen Dateien.
Fasse am Ende zusammen, was fertig ist und was als nächstes kommt."
```

### Was Limits schont:
- Eine Session = eine Komponente (kein „mach das ganze Backend")
- Immer mit Tests abschließen (gibt natürliche Grenzen)
- Nie Design + Implementierung in einer Session mischen
- Bestehenden Code nur lesen wenn nötig, nicht erneut laden lassen
- Komplexe Sessions (AI Layer) in Unter-Sessions teilen

### Was Probleme verursacht:
- Zu viele offene Dateien gleichzeitig
- „Mach alles aus Phase X" ohne Aufteilung
- Fehlende Spec-Referenz → Claude erfindet Struktur neu

---

*Ende der Spezifikation · Version 2.1 · Grundlage für alle Implementierungen*
