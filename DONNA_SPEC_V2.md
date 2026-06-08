# DONNA — Specification V2.0
### Erweiterungen, UX-Verbesserungen & Produktstrategie

> **Status:** Planung · Basis ist DONNA V1 (nach Session 14 auf GitHub)
> **Voraussetzung:** DONNA_SPEC.md V2.1 vollständig implementiert + auf GitHub gepusht
> **Philosophie:** Gleiche Kernprinzipien wie V1 – Consent-first, deterministisch, transparent
> **Leitfrage für jede neue Funktion:** „Würde jemand der sich schwer mit Organisation tut,
>  dieses Feature verstehen und nutzen – ohne sich überfordert zu fühlen?"

---

## Das Fundament: Für Menschen die sich schwer organisieren

Dies ist kein Zusatz. Es ist das Fundament von dem alle Entscheidungen abgeleitet werden.

**Was diese Menschen brauchen:**
- Maximal 1 Vorschlag gleichzeitig – nie überfordern
- Kleine Schritte statt großer Pläne
- Keine Bewertung, keine Schuldgefühle
- Erinnerungen die einladen, nicht alarmieren
- Erfolge sachlich benennen – keine Gamification

**Was DONNA bewusst NICHT baut (und das ist Stärke, nicht Schwäche):**
- ❌ Gamification: Kein Streak-Counter, keine Badges, keine Punkte. Streaks erzeugen Guilt.
- ❌ Kollaboration: Keine geteilten Routinen, keine Team-Features. Zerstört Consent-first.
- ❌ Vollautomatische Wochenpläne: Überfordern und werden nie so bestätigt wie schrittweise aufgebaute Strukturen.
- ❌ Bidirektionaler Kalender-Sync (CalDAV): Fremde Datenqualität, komplexe Merge-Konflikte. Stattdessen: read-only Import via EventKit (siehe V2-S6b).

**DONNAs Einzigartigkeit:** Das einzige System das aktiv weniger zeigt als vorhanden ist –
und das ist die richtige Entscheidung für diese Zielgruppe.

---

## V2 Roadmap – Übersicht

| Session | Inhalt | Priorität |
|---|---|---|
| V2-S1 | Code-Cleanup + CommandHandler Stubs | 🔴 Pflicht |
| V2-S2 | Morgenbriefing + Wochenzusammenfassung | 🔴 Pflicht |
| V2-S3 | Erschöpfungs-Modus + Kontextuelles Gedächtnis | 🔴 Pflicht |
| V2-S4 | Vorschlag bearbeiten + Chat-Verbesserungen | 🟡 Hoch |
| V2-S5 | Smarte Mustererkennung + Energie-Profil | 🟡 Hoch |
| V2-S6 | Fehlende Datenmodelle (prepTime, Someday, Dependencies) | 🟡 Hoch |
| V2-S6b | EventKit Integration – Kalender-Import read-only | 🟡 Hoch |
| V2-S7 | DONNA-Tab Redesign + Leere Zustände + Micro-Interactions | 🟡 Hoch |
| V2-S8 | KI-Verbesserungen (Konfidenz, Zeitton, Kumulativer Stress) | 🟢 Mittel |
| V2-S9 | WidgetKit + Siri Shortcuts + Live Activities | 🟢 Mittel |
| V2-S10 | Apple Health Integration (read-only) + Focus Modes | 🟢 Mittel |
| V2-S11 | Ton-Richtlinien V2 + System-Prompt Verbesserungen | 🟢 Mittel |
| V2-S12 | CloudKit Sync (mit paid Developer Account) | 🔵 Später |
| V2-S13 | Testing + Bug-Fixes + GitHub Release V2 | 🔴 Pflicht |

---

## V2-S1: Code-Cleanup

Bevor neue Features gebaut werden, wird der V1-Code bereinigt.

**Aufgaben:**
- Alle `// TODO:` Markierungen reviewen und umsetzen oder dokumentieren
- Unused imports entfernen
- CommandHandler Stubs mit echter SwiftData-Logik befüllen
- SwiftData direkte Writes aus UI-Schichten entfernen → CommandHandler
- Einheitliche Fehlerbehandlung in allen AI-Clients
- Doppelte Logik konsolidieren (ProactiveMonitor vs. PatternExtractor)
- Test-Coverage erhöhen: ConflictDetector, RoutineScheduler, ProfileUpdater

---

## V2-S2: Morgenbriefing + Wochenzusammenfassung

### Morgenbriefing
Push-Benachrichtigung zur konfigurierbaren Zeit (default: 8:00 Uhr).
Beim Öffnen der App: Briefing-Karte ganz oben im DONNA-Tab.

**Inhalt:**
- Anzahl Termine heute + wichtigster Termin
- Offene Routinen für heute
- Schlafqualität letzte Nacht (falls SleepWindow vorhanden)
- Eventuelle Konflikte
- Genau eine Frage oder ein Vorschlag

**Beispiel:**
> *„Guten Morgen. Heute: Arzttermin um 14 Uhr, Lernblock geplant, Sport offen.
> Dein Schlaf war 6,5h. Achtung: Lernblock und Arzttermin überschneiden sich.
> Soll ich den Lernblock verschieben?"*

**Technisch:**
- `ProactiveMonitor` generiert Briefing täglich morgens
- `NotificationScheduler` sendet Push zur konfigurierten Zeit
- Briefing als `ChatMessage(role: .assistant, outputType: .interpretation)` gespeichert
- Kollabierbar nach dem Lesen

### Wochenzusammenfassung
Jeden Sonntagabend (konfigurierbar):

**Beispiel:**
> *„Diese Woche: 4 von 5 Lernblöcken erledigt, Sport 2× gemacht. Schlaf Ø 6,8h – stabil.
> Nächste Woche: Prüfung am Donnerstag – soll ich mehr Lernzeit einplanen?"*

---

## V2-S3: Erschöpfungs-Modus + Kontextuelles Gedächtnis

### Erschöpfungs-Modus

**Trigger-Phrasen (DONNA erkennt automatisch):**
- „Ich bin erschöpft" / „Ich mache heute Pause" / „Ich bin krank"
- „Ich schaffe das heute nicht" / „Zu viel gerade"

**DONNAs Reaktion:**
1. Bestätigt ohne Bewertung: *„Okay, ich reduziere heute."*
2. Markiert alle nicht-fixen Routinen als optional
3. Fragt einmal: *„Soll ich Sport auf morgen verschieben oder lieber streichen?"*
4. Speichert Kontext als `Preference(key: "exhaustion_day", value: date)`

**Langzeit-Erkennung nach 3+ Erschöpfungs-Tagen in 2 Wochen:**
> *„Ich habe bemerkt dass du öfter erschöpft bist. Soll ich generell weniger planen?"*

**Technisch:**
- Neuer `ContextMode`: `.recovery`
- `InteractionOrchestrator` erkennt Erschöpfungs-Intent via Gemini
- `ProactiveMonitor` zählt Erschöpfungs-Tage

### Kontext-Sensitives Gedächtnis

**Problem heute:** Wenn DONNA eine Frage gestellt hat und der Nutzer nicht antwortet,
geht die Frage verloren. Das ist schlechte Sekretärin.

**Fix:**
- Nach 24 Stunden: gleiche Frage nochmal, leicht umformuliert
- Danach: nie wieder
- Wichtige Aussagen werden als `Preference` mit Kontext gespeichert
- Zeitgebundene Kontexte haben Ablaufdatum: „Prüfung am 15. Mai" → DONNA erinnert vorher

---

## V2-S4: Vorschlag bearbeiten + Chat-Verbesserungen

### Vorschlag bearbeiten

```
┌─────────────────────────────────┐
│ 💪 VORSCHLAG                    │
│ Sport: Donnerstag, 18:00 Uhr   │
│ Grund: Ruhetag nach Fußball    │
├──────────┬──────────┬───────────┤
│ ✓ Ja    │ ✎ Ändern │ ✗ Nein   │
└──────────┴──────────┴───────────┘
```

„Ändern" öffnet minimalen Inline-Editor: Zeit anpassen, Tag verschieben, dann bestätigen.

### Chat-Verbesserungen

**Stop-Button:**
- Während DONNA antwortet: „Stopp"-Button sichtbar
- Bricht API-Call ab via `URLSession.cancel()`

**Letzte Nachricht bearbeiten:**
- Lang drücken auf eigene Nachricht → „Bearbeiten"
- Sendet neu, löscht alte Antwort

**Antwort regenerieren:**
- Lang drücken auf DONNAs Antwort → „Neu generieren"

**Spracheingabe:**
- Mikrofon-Button rechts neben Textfeld
- Lokale Transkription via `SFSpeechRecognizer` (kein Cloud-Upload)
- Live-Transkription direkt im Eingabefeld

---

## V2-S5: Smarte Mustererkennung + Energie-Profil

### Routine-Erkennung aus Verhalten
- 3× dienstags Fußball eingetragen → DONNA fragt: *„Soll ich Fußball als Dienstags-Routine anlegen?"*
- 4× abends zwischen 20–21h gelernt → *„Soll ich einen festen Lernblock anlegen?"*

### Sport-Intelligenz
- Fußball → Ausdauer + Beine → Mittwoch Ruhetag vorschlagen
- Konfigurierbare Sport-Typen und Intensitäten
- Automatische Muskelgruppen-Zuordnung aus Titel-Keywords

### Persönliches Energie-Profil
DONNA lernt wann der Nutzer tatsächlich Aufgaben erledigt (Uhrzeit + Wochentag)
und schlägt Aufgaben zu den produktivsten Zeiten vor.

**Beispiel nach 4 Wochen:**
> *„Du erledigst Aufgaben am häufigsten montags zwischen 10 und 12 Uhr.
> Soll ich wichtige Aufgaben bevorzugt dort planen?"*

---

## V2-S6: Fehlende Datenmodelle

### Vorbereitungszeit für Termine
```swift
// CalendarEvent Erweiterung
var prepTimeMinutes: Int? // optional
```
DONNA fragt beim Anlegen wichtiger Termine:
> *„Brauchst du davor Zeit zur Vorbereitung? Ich kann 30 Minuten freihalten."*

### Someday-Stapel
Aufgaben ohne Datum landen im Someday-Modus.
DONNA fragt einmal pro Woche: *„Du hast 3 Dinge im Wartestapel. Ist eins davon jetzt dran?"*

```swift
// Task Erweiterung
var isSomeday: Bool = false
```

### Aufgaben-Abhängigkeiten (eine Ebene tief)
```swift
// Task Erweiterung
var blockedByTaskId: UUID? // optional
```
DONNA sagt: *„Hausarbeit ist noch blockiert – Literaturrecherche fehlt noch."*

### Intelligente Terminserie-Erinnerung
CalendarEvent bekommt kein volles Recurrence-Modell (zu komplex).
Aber: DONNA merkt sich einmalige Termine und fragt nach ~11 Monaten:
> *„Du warst letztes Jahr im März beim Zahnarzt. Soll ich dir helfen, einen Termin zu finden?"*

### Wiederkehrende Termine (einfach)
CalendarEvent bekommt optionale Recurrence:
- `.weekly(weekday:)` — z.B. jeden Dienstag
- `.biweekly(weekday:)` — alle zwei Wochen
Kein RRFC-5545-Modell. Nur diese zwei Fälle.
DONNA fragt nach 3× gleichem Wochentag: 
„Du trägst Fußball jede Woche dienstags ein. 
Soll ich das als Serientermin anlegen?"

---

## V2-S6b: EventKit Integration – Kalender-Import

### Prinzip: Import statt Sync

Der Unterschied ist entscheidend:

- **Sync** (was wir nicht bauen): Bidirektionale Verbindung, automatische Änderungen in beide Richtungen, komplexe Merge-Konflikte. DONNA verliert die Kontrolle über ihre Daten.
- **Import via EventKit** (was wir bauen): DONNA liest deinen bestehenden Kalender read-only. Sie plant drum herum, ändert aber nichts. DONNA bleibt die einzige Wahrheitsquelle für ihre eigenen Daten.

### Unterstützte Kalender (automatisch via EventKit)
- Apple Calendar
- Google Calendar (wenn im iPhone/Mac hinterlegt)
- Outlook / Exchange (wenn im System hinterlegt)
- Jeden anderen Kalender der im iOS/macOS Kalender-App sichtbar ist

### Funktionsweise

**Beim ersten Start (nach Onboarding):**
> *„Darf ich deinen bestehenden Kalender einlesen? Ich schaue mir nur an was du schon geplant hast und plane drum herum. Ich ändere dort nichts."*

Nutzer wählt: Ja (welche Kalender?) / Nein / Später

**Im Kalender-View:**
- Externe Termine erscheinen grau/gedimmt – klar als „extern" markiert
- DONNA-eigene Termine erscheinen normal farbig
- Externe Termine können nicht bearbeitet werden – nur angesehen

**Für DONNAs Planung:**
- `ConflictDetector` berücksichtigt externe Termine als nicht-verschiebbar
- DONNA schlägt keine Zeiten vor die mit externen Terminen kollidieren
- Externe Termine erscheinen im Morgenbriefing

**Synchronisation:**
- EventKit-Daten werden beim App-Start und bei Bedarf neu eingelesen
- Kein Hintergrund-Sync – nur wenn App aktiv ist
- Nutzer kann Zugriff jederzeit in Settings widerrufen

### Technisch
```swift
// Neues Modell für externe Termine (read-only, nicht in SwiftData gespeichert)
struct ExternalCalendarEvent {
    let title: String
    let startTime: Date
    let endTime: Date
    let calendarName: String
    let isAllDay: Bool
    // Kein id der mit SwiftData kollidiert
    let externalIdentifier: String
}

// EventKitManager – neuer Service
final class EventKitManager {
    func requestAccess() async -> Bool
    func fetchEvents(from: Date, to: Date) -> [ExternalCalendarEvent]
    func revokeAccess()
}
```

- `EventKitManager` liefert Events temporär in den `ConflictDetector`
- Keine SwiftData-Persistenz für externe Events (sie leben im EKStore)
- Datenschutz-Erklärung in Settings: „Deine Kalender-Daten verlassen niemals das Gerät"

### Was explizit NICHT gebaut wird
- ❌ Schreiben zurück in den System-Kalender
- ❌ Automatischer bidirektionaler Sync
- ❌ Import von Kontakten oder anderen Daten
- ❌ Zugriff auf Kalender-Inhalte die der Nutzer nicht explizit freigegeben hat

---

### Neue Tab-Struktur
```
┌─────────────────────────────┐
│  HEUTE                      │  ← Morgenbriefing-Karte (kollabierbar)
├─────────────────────────────┤
│  OFFEN                      │  ← Max. 1 Vorschlag gleichzeitig
│  [Vorschlag-Karte]          │
├─────────────────────────────┤
│  CHAT                       │  ← Freies Gespräch
└─────────────────────────────┘
```

### Eins-nach-dem-anderen-Prinzip
Jeder Tab zeigt eine primäre Aktion:
- Kalender: nächster Termin prominent
- Tasks: dringendste offene Aufgabe
- Routinen: nächste fällige Routine

### Micro-Interactions

**Aufgabe erledigen:**
- Keine Checkbox – zu klinisch
- Wischen → satte ruhige Haptik (`.heavy`) → Karte fällt sanft weg
- Kein Jubelmoment, kein Konfetti – entspricht DONNAs Tonalität

**Vorschlag-Timing:**
- Erscheint erst nach 3 Sekunden Inaktivität
- Nicht als Modal sondern als persistente Karte
- Tap anywhere dismisses mit leiser Haptik

**Leer-Zustand → erster Inhalt:**
- Leerer Zustand faded sanft weg
- Neue Karte erscheint mit `.spring()` von unten

### Leere Zustände als Einladung
| Bereich | Text |
|---|---|
| Leerer Kalender | *„Kein Termin heute. Schreib mir was du planst."* |
| Keine Aufgaben | *„Alles erledigt – oder noch nichts geplant? Ich helfe dir."* |
| Keine Routinen | *„Routinen helfen langfristig. Soll ich dir ein paar vorschlagen?"* |
| Leerer Chat | *„Hallo. Was beschäftigt dich heute?"* |

### Nacht-Modus
Nach 22 Uhr (oder innerhalb des SleepWindows):
- Interface wechselt zu noch ruhigeren Farben + gedämpftem Dimming
- DONNA sagt einmal: *„Es ist spät. Du kannst mir auch morgen früh sagen, was du planst."*
- Danach nie wieder – nur das gedämmte Interface bleibt

---

## V2-S8: KI-Verbesserungen

### Konfidenz-Tracking für Vorschläge
- 3 Ablehnungen desselben Vorschlags-Typs → DONNA hört auf
- DONNA fragt einmal: *„Ich habe bemerkt dass du Lernblock-Vorschläge immer ablehnst. Soll ich aufhören?"*

### Intent-Konfidenz als Routing-Signal
- Konfidenz < 0.7 → erst Rückfrage, kein direkter Vorschlag
- Verhindert falsche Vorschläge bei mehrdeutiger Sprache

### Zeitbasiertes Prompt-Engineering
System-Prompt passt sich der Tageszeit an:
- Morgens (6–10h): strukturierend, aktiver Ton
- Mittags (10–18h): neutral, sachlich
- Abends (18–22h): kürzer, weniger fordernd
- Nachts (22–6h): minimal, nur Dringendes

### Kumulativer Stress als Regel
Neue `ScienceEngine`-Regel: Wenn >3 Abende pro Woche belegt:
> *„Diese Woche ist dein Abend 4× verplant. Soll ich Donnerstag freihalten?"*

---

## V2-S9: WidgetKit + Siri Shortcuts + Live Activities

### WidgetKit (höchster ROI, sofort)
- Klein (2×2): nächster Termin/Routine ODER aktiver DONNA-Vorschlag
- Tap → öffnet direkt Chat
- Mittel (2×4): Tagesübersicht mit Briefing-Zusammenfassung

### Siri Shortcuts (pragmatisch)
Vordefinierte Shortcuts die der Nutzer hinzufügen kann:
- „Hey Siri, sag DONNA ich bin erschöpft" → Recovery-Modus
- „Hey Siri, was hat DONNA heute geplant" → Briefing vorlesen
- Implementierung via `AppIntents` Framework

### Live Activities (Dynamic Island)
- Termin in <30 Minuten: Countdown + Terminname in Dynamic Island
- Verschwindet automatisch nach dem Termin
- Kein Nutzereingriff nötig

---

## V2-S10: Apple Health + Focus Modes

### Apple Health (nur lesen)
- Schlafdaten aus Health lesen (mit Nutzer-Erlaubnis)
- Abgleich mit SleepWindow: Hat der Nutzer wirklich geschlafen wann geplant?
- Präzisere Schlafanalyse ohne manuelle Eingabe
- **Niemals zurückschreiben** – kein Scope-Creep

### Focus Modes Integration
- DONNA weiß wenn Nutzer in „Nicht stören – Schlafen" ist
- Morgenbriefing-Push wird auf das Ende des Focus Modes verschoben
- `UNNotificationTrigger` mit Wake-Time aus SleepWindow koordiniert

---

## V2-S11: Ton-Richtlinien V2

### Prinzipien
- Maximal 2 Sätze pro Antwort
- Nie Ausrufezeichen
- Nie „Super!", „Toll!", „Wunderbar!"
- Bei Ausfällen: sachlich, nie vorwurfsvoll
- Immer konkret, nie vage

### Beispiele

| ❌ So nicht | ✅ So |
|---|---|
| „Du hast Sport nicht gemacht!" | „Sport ist diese Woche ausgefallen." |
| „Super, 3 Aufgaben erledigt!" | „3 Aufgaben heute erledigt." |
| „Du solltest mehr schlafen!" | „Dein Schlaf war diese Woche unter 6h." |
| „Kein Problem, ich erledige das!" | „Vorschlag: Termin auf Donnerstag verschieben." |

### Für die Zielgruppe spezifisch
- *„Kein Stress. Was schaffst du heute realistisch?"*
- *„Eines nach dem anderen."*
- *„Das ist okay. Soll ich es verschieben?"*

---

## V2-S12: CloudKit Sync

Voraussetzung: bezahlter Apple Developer Account (99€/Jahr)

- SwiftData `ModelConfiguration(cloudKitDatabase: .automatic)`
- Sync zwischen iPhone und Mac über privaten iCloud-Container
- Kein eigener Server
- Offline-first bleibt garantiert

---

## Geplante V3-Features

*Dieser Abschnitt wächst mit echter Nutzungserfahrung aus V2.*

### Apple Watch (V3-S1–S2)
Nicht als Task-Liste. Drei klar definierte Rollen:
1. Haptic-Alerts für Routinen zur richtigen Zeit
2. Ein einziger „Erledigt"-Button wenn Routine fällig
3. „Pause heute"-Complication → aktiviert Recovery-Modus mit einem Tap

### Sprachmemo als Eingabe (V3-S3)
- 20-Sekunden-Memo aufnehmen
- DONNA transkribiert lokal via `SFSpeechRecognizer`
- Extrahiert strukturiert: Termin? Aufgabe? Notiz?
- Kein Cloud-Upload des Audios

### Jahresrückblick (V3-S4)
Am 31. Dezember generiert DONNA einen kurzen persönlichen Brief:
> *„2025: Du hast Sport 67× gemacht. Dein Schlaf war im Herbst am besten.
> Du hast 3 große Projekte abgeschlossen."*
- Drei Sätze, DONNAs Tonalität
- Als PDF exportierbar
- Das einzige Feature das Nutzer emotional berührt und das kein Konkurrent macht

### Kontextmodus „Reise" (V3-S5)
- Erkennt automatisch wenn Nutzer mehrere Tage von zuhause weg ist
- Routinen werden pausiert (nicht gestrichen)
- Schlafschutz gilt für Reisezeitzone
- Kein manuelles Konfigurieren

### Offline-KI via On-Device-Model (V3-S6)
- Optionale lokale Inference für Nutzer ohne Gemini-Key
- Apple Intelligence / Core ML für einfache Intent-Erkennung
- Kein Feature-Parity mit Gemini – nur Grundfunktionen

### Offen für weitere Ideen
- Siri Deep Integration
- Weitere Sprachen
- Exportfunktionen (Wochenbericht als PDF)
- Weitere wissenschaftliche Grundlagen (Ernährung, Meditation)
- Kalender-Import als read-only Ansicht (nicht Sync)

---

## Entscheidungsmatrix für neue Feature-Ideen

Bevor ein neues Feature in eine Spec aufgenommen wird, muss es diese Fragen bestehen:

| Frage | Erwartete Antwort |
|---|---|
| Würde jemand der sich schlecht organisiert dieses Feature verstehen? | Ja |
| Erfordert es explizite Nutzer-Bestätigung? | Ja |
| Fügt es mehr als es wegnimmt? | Ja |
| Ist es ohne dieses Feature unmöglich etwas Wichtiges zu tun? | Ja |
| Führt es zu Gamification, Druck oder Schuldgefühlen? | Nein |
| Erhöht es die Komplexität ohne klaren Nutzen? | Nein |

---

*Ende der Spezifikation · Version 2.0*
*Aufbauend auf DONNA V1 · Raum für V3 bewusst offen gelassen*
