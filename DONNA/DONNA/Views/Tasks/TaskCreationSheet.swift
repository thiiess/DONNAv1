import SwiftUI
import SwiftData

struct TaskCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var notes = ""
    @State private var hasDueDate = false
    @State private var dueDate: Date = .now
    @State private var priority: Priority = .none

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            scrollContent
            footer
        }
        .background(DS.Colors.backgroundPrimary)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        Text("Neue Aufgabe")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DS.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                titleField
                dueDateSection
                prioritySection
                notesField
            }
            .padding(.horizontal, DS.Spacing.horizontal)
            .padding(.top, DS.Spacing.section)
            .padding(.bottom, DS.Spacing.section)
        }
    }

    // MARK: - Title

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Titel", text: $title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(DS.Colors.textPrimary)
            Rectangle()
                .fill(DS.Colors.separator)
                .frame(height: 1)
        }
    }

    // MARK: - Due date

    private var dueDateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Fälligkeitsdatum", isOn: $hasDueDate.animation())
                .tint(DS.Colors.warmAccent)
                .foregroundStyle(DS.Colors.textPrimary)
            if hasDueDate {
                DatePicker("", selection: $dueDate, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(DS.Colors.warmAccent)
            }
        }
    }

    // MARK: - Priority

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Priorität")
                .font(.caption)
                .foregroundStyle(DS.Colors.textTertiary)
            Picker("", selection: $priority) {
                ForEach(Priority.allCases, id: \.self) { p in
                    Text(priorityLabel(p)).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .tint(DS.Colors.warmAccent)
        }
    }

    // MARK: - Notes

    private var notesField: some View {
        ZStack(alignment: .topLeading) {
            if notes.isEmpty {
                Text("Notizen")
                    .font(.body)
                    .foregroundStyle(DS.Colors.textTertiary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $notes)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Abbrechen") { dismiss() }
                    .foregroundStyle(DS.Colors.textSecondary)
                    .buttonStyle(.plain)
                Spacer()
                Button("Hinzufügen") {
                    save()
                    dismiss()
                }
                .disabled(!canSave)
                .buttonStyle(.borderedProminent)
                .tint(DS.Colors.warmAccent)
            }
            .padding(.horizontal, DS.Spacing.horizontal)
            .padding(.vertical, 12)
        }
        .background(DS.Colors.backgroundPrimary)
    }

    // MARK: - Helpers

    private func priorityLabel(_ p: Priority) -> String {
        switch p {
        case .none:   return "Keine"
        case .low:    return "Niedrig"
        case .medium: return "Mittel"
        case .high:   return "Hoch"
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespaces)
        _ = CommandHandler(modelContext: modelContext).execute(
            .createTask(
                title: trimmed,
                dueDate: hasDueDate ? dueDate : nil,
                priority: priority,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
        )
    }
}

#Preview {
    let schema = Schema([DONNATask.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return TaskCreationSheet().modelContainer(container)
}
