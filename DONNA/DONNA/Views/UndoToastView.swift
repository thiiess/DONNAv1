import SwiftUI
import SwiftData

/// Small banner that appears after every undoable action ("Termin gelöscht · Rückgängig")
/// and briefly confirms a performed undo. It only *triggers* the undo — the restore runs
/// through CommandHandler like every other mutation.
struct UndoToastView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var visible = false
    @State private var errorText: String?

    private var undo: DONNAUndoManager { DONNAUndoManager.shared }

    var body: some View {
        Group {
            if visible, let text = currentText {
                HStack(spacing: 12) {
                    Image(systemName: undo.canUndo ? "arrow.uturn.backward.circle" : "checkmark.circle")
                        .foregroundStyle(DS.Colors.warmAccent)
                    Text(text)
                        .font(.callout)
                        .foregroundStyle(DS.Colors.textPrimary)
                        .lineLimit(1)
                    if undo.canUndo {
                        Button("Rückgängig", action: performUndo)
                            .buttonStyle(.plain)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(DS.Colors.warmAccent)
                            #if os(macOS)
                            .keyboardShortcut("z", modifiers: [.command, .shift])
                            #endif
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DS.Colors.backgroundSecondary, in: Capsule())
                .overlay(Capsule().stroke(DS.Colors.warmAccent.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(DS.animation, value: visible)
        .task(id: undo.revision) {
            guard undo.revision > 0 else { return }
            errorText = nil
            visible = true
            // Long enough to react to an action, short for the "rückgängig gemacht" confirmation.
            let seconds: Double = undo.canUndo ? 6 : 2.5
            try? await Swift.Task.sleep(for: .seconds(seconds))
            visible = false
        }
    }

    private var currentText: String? {
        if let errorText { return errorText }
        if let label = undo.actionLabel, undo.canUndo { return label }
        if let undone = undo.lastUndoneLabel { return "Rückgängig gemacht: \(undone)" }
        return nil
    }

    private func performUndo() {
        let result = CommandHandler(modelContext: modelContext).execute(.undo)
        if case .failure(let error) = result {
            errorText = error.localizedDescription
        }
    }
}
