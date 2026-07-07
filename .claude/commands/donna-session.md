# /donna-session — Start a Focused Coding Session

1. Run a build to check current state:
xcodebuild -scheme DONNAv1 -destination 'platform=macOS' build 2>&1 | tail -5

2. Report in one paragraph: build clean or broken? Which known V1 bugs are relevant today? Any risk areas?

3. Ask the user: "What are we working on today?" — then wait.

4. Once answered, confirm scope: exact files that will be touched, what will NOT change. Confirm: "Ready. Should I start?"

## Checklist
- [ ] Touching files with Task? → Check DONNATask / Swift.Task naming
- [ ] Adding UIKit APIs? → Add #if os(iOS) guards
- [ ] Modifying Gemini client? → Verify model name is gemini-2.5-flash
- [ ] Touching ChatView? → Keep ChatMessageList as separate child view
- [ ] New async work? → Must not run on MainActor

## At session end
After the build is clean and work is summarised, append a short entry to PROGRESS.md (create it if missing). Append only — never rewrite existing entries. Format:

## <session-id> — <date>
Done: <one or two lines>
Open / next: <what the next session must pick up>
Build: clean / broken

Do NOT modify DONNA_SPEC_V2.md — the spec stays the plan, PROGRESS.md is the log.
