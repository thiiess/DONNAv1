import SwiftUI
import SwiftData

struct TaskDetailView: View {
    let task: Task

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: Priority
    @State private var showingDeleteConfirmation = false

    init(task: Task) {
        self.task = task
        _title      = State(initialValue: task.title)
        _notes      = State(initialValue: task.notes ?? "")
        _hasDueDate = State(initialValue: task.dueDate != nil)
        _dueDate    = State(initialValue: task.dueDate ?? Date())
        _priority   = State(initialValue: task.priority)
    }

    var body: some View {
        Form {
            Section {
                TextField("Titel", text: $title)
                TextField("Notizen", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Fälligkeitsdatum") {
                Toggle("Fälligkeitsdatum", isOn: $hasDueDate.animation())
                if hasDueDate {
                    DatePicker("Datum", selection: $dueDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
            }

            Section("Priorität") {
                Picker("Priorität", selection: $priority) {
                    ForEach(Priority.allCases, id: \.self) { p in
                        Text(p.rawValue.capitalized).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Aufgabe löschen", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle("Aufgabe bearbeiten")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("Aufgabe löschen?", isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                _ = CommandHandler(modelContext: modelContext).execute(.deleteTask(id: task.id))
                dismiss()
            }
        }
    }

    private func save() {
        var changes = TaskChanges()
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        changes.title    = .set(trimmed)
        changes.notes    = notes.isEmpty ? .clear : .set(notes)
        changes.dueDate  = hasDueDate ? .set(dueDate) : .clear
        changes.priority = .set(priority)
        _ = CommandHandler(modelContext: modelContext).execute(.updateTask(id: task.id, changes: changes))
        dismiss()
    }
}

#Preview {
    let schema = Schema([Task.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let task = Task(title: "Buy groceries", dueDate: Date(), priority: .medium)
    container.mainContext.insert(task)
    return NavigationStack { TaskDetailView(task: task) }.modelContainer(container)
}
