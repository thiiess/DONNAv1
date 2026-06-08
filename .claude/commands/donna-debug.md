# /donna-debug $ARGUMENTS

Investigate and fix a specific bug. Usage: /donna-debug <description>

1. Understand the bug from: $ARGUMENTS. If no description, ask.
2. Trace code path: user action → view → orchestrator → CommandHandler → model. Read all files before touching anything.
3. State hypothesis explicitly before writing any code.
4. Fix only the root cause. Run build to verify.
5. Report: what was wrong, what changed, which files touched.

## DONNA-specific debug checklist

**Chat freezing:** Check ChatMessageList is a separate child view. Check InteractionOrchestrator init() is empty. Check SWIFT_DEFAULT_ACTOR_ISOLATION is NOT in project.pbxproj.

**Proposal confirmation does nothing:** Bug is in CommandHandler.swift — check confirmation handler calls execute(). Add print("CommandHandler executing: \(command)") to confirm it's being called.

**Swipe gesture unreliable:** Check simultaneousGesture vs highPriorityGesture. On macOS consider explicit Edit/Delete buttons instead (#if os(macOS)).

**Gemini errors:** Check model name is gemini-2.5-flash. 429 = rate limit, 404 = wrong model name. Never log the API key.
