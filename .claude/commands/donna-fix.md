
cat > ~/Developer/DONNAv1/.claude/commands/donna-fix.md << 'EOF'
# /donna-fix — Fix Build Errors

Run a full build, find all errors, and fix them. Do not ask for confirmation unless a fix would touch more than 3 files.

## Steps

1. Run the build:
xcodebuild -scheme DONNAv1 -destination 'platform=macOS' build 2>&1 | grep -E "(error:|warning:|Build succeeded|BUILD FAILED)"

2. If **Build succeeded**: report "✓ Build clean — nothing to fix." and stop.

3. If **BUILD FAILED**: list every error, identify root causes, fix in this order: missing imports → Task/DONNATask conflicts → missing #if os(iOS) guards → MainActor violations → everything else.

4. After fixes, run the build again. Repeat until clean or 3 rounds attempted.

5. If still failing after 3 rounds: show remaining errors and explain why they need human input.
