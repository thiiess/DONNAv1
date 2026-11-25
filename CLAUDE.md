# DONNA — Project Memory for Claude Code

## Automated Progress Log
<!-- auto-status: awaiting-review -->
<!-- sessions-since-review: 0 -->
<!-- review-threshold: 3 -->
- 2026-07-08 14:29–14:33 — Session #1 — bug fix: routed ProactiveMonitor.createProposalIfNew through CommandHandler instead of writing ChatMessage directly to modelContext; also gate dedup-key storage on successful persistence so a failed proposal insert can retry. Build: verified. Next: continue V2-S1 cleanup — audit ChatView.handleSend + persistAssistantResponse + markAllAssistantMessagesRead, which still bypass CommandHandler.
- 2026-07-08 14:36–14:41 — Session #2 — bug fix: added .postUserMessage / .markAssistantMessagesRead commands and routed ChatView.handleSend, persistAssistantResponse, markAllAssistantMessagesRead through CommandHandler so no chat mutation writes to modelContext directly anymore. Build: verified. Next: SettingsView.clearChatHistory and DONNAApp.deleteTestMessagesOnce still bypass CommandHandler — route them through a new .clearChatHistory command.
- 2026-07-08 14:44–14:48 — Session #3 — bug fix: added .clearChatHistory command and routed SettingsView.clearChatHistory + DONNAApp.deleteTestMessagesOnce through CommandHandler. With this, every ChatMessage mutation in the codebase now flows through CommandHandler. Build: verified. Next: V2-S2 weekly summary (Wochenzusammenfassung) — a ProactiveMonitor.generateWeeklySummaryIfDue that fires Sunday evening and posts a briefing-style ChatMessage.
- 2026-11-25 — Session (Claude, direct on Mac) — V2-S1 finished (persist(), last bypasses, expiring seenKeys), shared undo stack, DayView overlap lanes + all-day banner. Build: verified (xcodebuild, fresh DerivedData). Next: visual test of DayView; then orphan-occurrence migration, onboarding color bug, weekly summary (V2-S2).
⏸ Automation paused — please visually test in Xcode before continuing.

## What is DONNA
Personal AI secretary app for iOS and macOS. Combines calendar, tasks, routines, and an AI chat interface. Core philosophy: **consent-first** — the AI suggests, the user confirms. No action without explicit approval. Designed especially for people who struggle with self-organisation.

Project path: `~/Developer/DONNAv1/`
Xcode scheme: `DONNA` (not DONNAv1)
Language: SwiftUI + SwiftData
AI backend: Google Gemini API (`gemini-2.5-flash` — verify if session is >2 weeks old)
Sync: iCloud/CloudKit (temporarily disabled — no paid Apple Developer account yet)
GitHub: https://github.com/thiiess/DONNAv1 (public — never commit secrets)

---

## Architecture — Read This First

### Data flow
All state changes flow through `CommandHandler`. This is intentional and must not be bypassed. No view may write to SwiftData directly.

```
User input → InteractionOrchestrator → CommandHandler → SwiftData models
                      ↕
             InternalAssistantClient (Gemini — DONNA chat)
             ExternalResearchClient  (Gemini — web research, isolated)
```

### Data lifecycle (HOT / WARM / COLD)
- **HOT**: active day's events and tasks — always in memory
- **WARM**: last 30 days — loaded on demand
- **COLD**: archived — queried only on explicit search

### Two Gemini clients — never merge them
- `InternalAssistantClient` — powers the DONNA chat interface
- `ExternalResearchClient` — isolated external research, completely separate context

### Gemini multi-turn — how it works
- `tagPrefix(for:)` reconstructs type tags in conversation history before sending to Gemini
- When answering a clarification, the message is dynamically restructured as explicit question+answer pair
- A `[PROPOSAL]` prefill is appended as a trailing model turn to force correct format
- Debug print: `[DEBUG] InternalAssistantClient: clarification answer detected — adding [PROPOSAL] prefill (turn N)`

---

## V1 Bug Status

### ✅ All V1 bugs fixed (June 2026)
1. **Proposal confirmation not executing** — FIXED. `confirm()` guards on `pendingProposalJSON`, persists "Erledigt." on success, input blocked during `awaitingConsent` phase.
2. **Task swipe-to-complete unreliable** — FIXED. Replaced with `.contextMenu` on macOS (right-click), swipe actions kept on iOS via `#if os(iOS)` guard.
3. **DONNA requires multiple prompts / loses context** — FIXED. Tag prefixes reconstructed in history. Dynamic message restructuring + `[PROPOSAL]` prefill for clarification turns.
4. **No edit/delete UI for calendar events and tasks** — FIXED. `EventDetailView` and `TaskDetailView` fully rewritten as sheets with edit/save/delete. Week view tap → EventDetailView.
5. **Raw API errors shown to user** — FIXED. 503/429/401 mapped to German strings. Retry logic (3 attempts, 2s delay). Debug labels in DEBUG builds only: `[Debug: 503 Gemini]`, `[Debug: parse error — missingTypeTag]`.

### ⚠️ Known remaining issues (deferred to V2)
- **UndoManager**: 9 restore stubs are empty bodies + snapshots never captured in CommandHandler. Full undo system deferred to V2.
- **Proposal edit**: User cannot say "lieber 30 Minuten später" to adjust a proposal inline. Deferred to V2-S4.
- **Recurring events**: "Jeden Dienstag Fußball" not yet supported. Deferred to V2-S6.
- **Calendar navigation**: Too many taps to navigate days/weeks. Swipe gesture deferred to V2.

---

## V2 Status
Source of truth for open bugs: `DONNA_SPEC_V2.md` → „Bekannter Stand". Short version (25.11.):
- **V2-S1 Code-Cleanup**: ✅ DONE — no ChatMessage/SwiftData write bypasses CommandHandler anymore; every handler saves via `persist()`
- **V2-S2 Morgenbriefing**: ✅ built (weekly summary still open)
- **V2-S3**: unblocked — shared undo stack in place, snapshot capture + restore stubs still need their dedicated session
- **V2-S4**: clarification flow incl. `skipRoutine`/`updateRoutine` done; inline proposal editing open
- **V2-S6**: conflict detection + overlap layout in DayView done; prepTime/Someday/dependencies/recurring events open
- **V2-S6b EventKit, V2-S12 CloudKit**: not started (reserved for the stronger model)

---

## Critical Rules — Never Break These

### SwiftData naming
`Task` conflicts with `Swift.Task`. Always use explicit namespace:
- Model class: `DONNATask` (not `Task`) — file is `Task.swift` but class is `DONNATask`
- When calling Swift concurrency: `Swift.Task { ... }`

### Platform guards
macOS and iOS have different APIs. Every UIKit-only feature needs a guard:
```swift
#if os(iOS)
// iOS-only code here
#endif
```
Check every file you touch — missing guards cause build failures on macOS.

### Threading
- All SwiftUI views and `@Observable` classes must run on `@MainActor`
- Network calls (Gemini API) must run off the main thread — use `async/await` in a `Task { }`
- Never do SwiftData queries in `init()` — defer until the view is in the hierarchy
- Do NOT add `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` to project.pbxproj — removed intentionally (pinned URLSession to main thread causing 120s freezes)

### Gemini API
- Current model string: `gemini-2.5-flash` (verify if session is >2 weeks old)
- API key lives in Keychain via `KeychainHelper` — never hardcode, never print
- Free tier: 503 errors are common under load — retry logic already handles this
- Prefill pattern: trailing `{ role: "model", parts: [{ text: "[PROPOSAL] " }] }` forces correct output format

### Persistence & undo
- Every CommandHandler mutation ends with `return persist()` — never `try? modelContext.save()` + `.success()`. `persist()` reports `.failure` and rolls back on a failed save.
- `CommandHandler.undoManager` is `DONNAUndoManager.shared`. Never create a `DONNAUndoManager()` per handler — handlers are created per call, the undo stack must outlive them.

### Navigation (macOS)
- `NavigationSplitView` keeps the detail column's NavigationStack state across content swaps. Per-case `.id()` does not reset it, and driving the inner stack with an explicit `path` crashes (`AnyNavigationPath.Error.comparisonTypeMismatch`) when the column switches to a view without a matching `navigationDestination`. The split view is therefore re-created per tab via `.id(selectedTab)` in `ContentView` — keep it, and keep each tab's NavigationStack nested inside its own tab view.

### Build verification
After every set of changes:
```bash
xcodebuild -scheme DONNA -destination 'platform=macOS' build 2>&1 | tail -20
```
Fix all errors before reporting done.

---

## Design System (`DesignSystem.swift` — `DS` namespace)

### Colors
| Token | Light | Dark | Usage |
|-------|-------|------|-------|
| `DS.Colors.warmAccent` | `#C4783C` | `#E8A06A` | Buttons, active chips, sidebar active state, toggles |
| `DS.Colors.warmLight` | `#F5E6D8` | (dark bubble bg) | DONNA bubble background (light mode) |
| `DS.Colors.warmDark` | `#6B3410` | fixed | Text on warm light backgrounds |
| `DS.Colors.appBackground` | `NSColor.windowBackgroundColor` | system | All tab backgrounds — use everywhere |
| `DS.Colors.donnaBubbleBg` | `#F5E6D8` | `#2E2420` | DONNA chat bubble background |
| `DS.Colors.donnaBubbleFg` | `#6B3410` | `#E8A06A` | DONNA chat bubble text |

### Rules
- All sheets: plain `VStack`, no `Form`/`Section`/`List`
- Title fields: `.title2.weight(.semibold)` + bottom divider
- Date/time chips: active = `warmAccent` fill + white text, inactive = `warmAccent.opacity(0.15)` + `warmAccent` text
- Toggles: always `.tint(DS.Colors.warmAccent)`
- Sidebar active item: `warmAccent.opacity(0.15)` background + `warmAccent` text + `.medium` weight
- All tab backgrounds: `DS.Colors.appBackground`
- TextField focus ring: `.tint(DS.Colors.warmAccent)`

---

## File Map (complete)

| File | Purpose |
|------|---------|
| `CommandHandler.swift` | Executes all state mutations — single source of truth |
| `InteractionOrchestrator.swift` | Manages DONNA chat session, state machine, calls Gemini |
| `InternalAssistantClient.swift` | Gemini client for DONNA assistant — prefill, tag reconstruction |
| `ExternalResearchClient.swift` | Gemini client for research (isolated, no personal context) |
| `ResponseParser.swift` | Validates and parses Gemini output against contract |
| `ContextBuilder.swift` | Builds anonymised context snapshot for Gemini |
| `KeychainHelper.swift` | Secure API key storage |
| `Task.swift` | `DONNATask` model (class named DONNATask to avoid Swift.Task conflict) |
| `CalendarEvent.swift` | Calendar event model — includes `isAnnual`, `notes`, `isLocked`. No stored all-day flag: all-day/annual events are stored as 00:00–23:59 and detected via the computed `spansWholeDay` |
| `Routine.swift` | Routine model |
| `RoutineOccurrence.swift` | Individual routine occurrence |
| `ChatMessage.swift` | Persisted chat message model |
| `DesignSystem.swift` | All color tokens, spacing, typography — use `DS.Colors.*` everywhere |
| `ContentView.swift` | Root view + macOS sidebar (min 180pt, custom buttons with `.contentShape(Rectangle())`) |
| `ChatView.swift` | DONNA chat UI — `ChatMessageList` is a separate child view (prevents SwiftData freeze) |
| `MessageBubble.swift` | Chat bubble — `donnaBubbleBg/Fg` for DONNA, `warmAccent`+white for user |
| `CalendarView.swift` | Calendar with Day/Week/Month views |
| `DayView.swift` | Day view — all-day banner on top; timed events + routines in side-by-side lanes (warmAccent left bar for events) |
| `DayTimelineLayout.swift` | Pure lane/column layout for overlapping timeline items |
| `EventCreationSheet.swift` | New event sheet — chips, toggles, isAnnual, no Form |
| `EventDetailView.swift` | Edit event sheet — same layout as creation |
| `TaskListView.swift` | Task list — completion circle button, priority color bars |
| `TaskCreationSheet.swift` | New task sheet — German priority labels, no Form |
| `TaskDetailView.swift` | Edit task sheet — presented as `.sheet`, not navigation push |
| `RoutineListView.swift` | Routine list — uses CommandHandler for complete/skip |
| `SettingsView.swift` | Settings — toggles with warmAccent, switch style for science rules |
| `ProactiveMonitor.swift` | Monitors for conflicts, missed routines, sleep patterns |
| `ConflictDetector.swift` | Checks overlaps and sleep window violations |
| `ScienceEngine.swift` | Science rules (sport, sleep, learning, general) |
| `RoutineScheduler.swift` | Generates RoutineOccurrences |
| `UndoManager.swift` | Undo system — stubs not yet implemented (V2) |

---

## Event Creation — What DONNA Understands via Chat
- Title + time given → direct `[PROPOSAL]`, 1h default duration
- Time given, no title → `[CLARIFICATION]` asks for title
- Title given, no time → `[CLARIFICATION]` asks for time
- Explicit end time ("19-21 Uhr") → use directly, never ask
- Duration given ("2 Stunden") → calculate end time
- "ganztägig" / "den ganzen Tag" → `allDay: true`
- "gesperrt" / "nicht verschiebbar" / "fix" → `isLocked: true`
- "Geburtstag" / "Jahrestag" / "jedes Jahr" → `isAnnual: true` (auto-sets allDay + locked)
- Notes/context provided → passed as `notes` field

---

## Workflow Preferences
- Fix one thing at a time — don't refactor unrelated code
- Run build after every change, report errors immediately
- If a fix requires touching more than 3 files, pause and confirm with the user first
- Prefer `async/await` over completion handlers
- No `print()` statements in production code — use `#if DEBUG` for debug output
- When in doubt about intent: ask one short question, don't guess and implement
- Use `/donna-fix` for build errors, `/donna-debug <description>` for bugs

---

## What NOT to Do
- Do not re-enable CloudKit or push notifications without being asked
- Do not merge InternalAssistantClient and ExternalResearchClient
- Do not bypass CommandHandler for state changes
- Do not add `SWIFT_DEFAULT_ACTOR_ISOLATION` to build settings
- Do not hardcode or log the Gemini API key
- Do not use `Form`, `Section`, or `List` in sheets — plain VStack only
- Do not implement UndoManager restore stubs without a dedicated session for it
