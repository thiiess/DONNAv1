# DONNA — Project Memory for Claude Code

## What is DONNA
Personal AI secretary app for iOS and macOS. Combines calendar, tasks, routines, and an AI chat interface. Core philosophy: **consent-first** — the AI suggests, the user confirms. No action without explicit approval.

Project path: `~/Developer/DONNAv1/`
Language: SwiftUI + SwiftData
AI backend: Google Gemini API (currently gemini-2.5-flash)
Sync: iCloud/CloudKit (temporarily disabled — no paid Apple Developer account yet)

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

---

## Known Bugs (V1 — outstanding)
These issues exist and should be fixed before adding new features:
1. **Proposal confirmation not executing** — DONNA proposes an action, user confirms, but CommandHandler does not execute
2. **Task swipe-to-complete unreliable** — gesture sometimes fires, sometimes doesn't
3. **DONNA requires multiple prompts to act** — orchestrator doesn't always pick up intent on first message
4. **No edit/delete UI** for existing calendar events and tasks

---

## Critical Rules — Never Break These

### SwiftData naming
`Task` conflicts with `Swift.Task`. Always use explicit namespace:
- Model class: `DONNATask` (not `Task`)
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
- Do NOT add `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` to project.pbxproj — this was removed intentionally (it pinned URLSession to the main thread causing 120s freezes)

### Gemini API
- Always verify the current model name before using it — they change frequently
- Current model string (verify if session is more than 2 weeks old): `gemini-2.5-flash`
- API key lives in Keychain via `KeychainHelper` — never hardcode it, never print it

### Build verification
After every set of changes: run `xcodebuild -scheme DONNAv1 -destination 'platform=macOS' build 2>&1 | tail -20` and fix all errors before reporting done.

---

## File Map

| File | Purpose |
|------|---------|
| `CommandHandler.swift` | Executes all state mutations — single source of truth |
| `InteractionOrchestrator.swift` | Manages DONNA chat session, calls Gemini |
| `InternalAssistantClient.swift` | Gemini client for DONNA assistant |
| `ExternalResearchClient.swift` | Gemini client for research (isolated) |
| `KeychainHelper.swift` | Secure API key storage |
| `DONNATask.swift` | Task model (NOT Task.swift — naming conflict) |
| `CalendarEvent.swift` | Calendar event model |
| `Routine.swift` | Routine model |
| `ChatMessage.swift` | Persisted chat message model |
| `ChatView.swift` | DONNA chat UI — contains ChatMessageList child view |
| `CalendarView.swift` | Calendar UI |
| `TaskView.swift` | Task list UI |

---

## Design System
- Dark-first, Apple-adjacent but with its own character
- Accent color: to be defined (ask user if unsure)
- Font: SF Pro (system default)
- Avoid generic SwiftUI default styling — add visual personality
- Date/time pickers: prefer `GraphicalDatePickerStyle` or compact inline pickers over stepper wheels

---

## Workflow Preferences
- Fix one thing at a time — don't refactor unrelated code
- Run build after every change, report errors immediately
- If a fix requires touching more than 3 files, pause and confirm with the user first
- Prefer `async/await` over completion handlers
- No print() statements left in production code (use only for active debugging, then remove)
- When in doubt about intent: ask one short question, don't guess and implement

---

## What NOT to Do
- Do not re-enable CloudKit or push notifications without being asked
- Do not merge InternalAssistantClient and ExternalResearchClient
- Do not bypass CommandHandler for state changes
- Do not add SWIFT_DEFAULT_ACTOR_ISOLATION to build settings
- Do not hardcode or log the Gemini API key
