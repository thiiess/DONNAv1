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
                TextField("Title", text: $title)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            Section("Due Date") {
                Toggle("Has Due Date", isOn: $hasDueDate.animation())
                if hasDueDate {
                    DatePicker("Date", selection: $dueDate, displayedComponents: .date)
                }
            }

            Section("Priority") {
                Picker("Priority", selection: $priority) {
                    ForEach(Priority.allCases, id: \.self) { p in
                        Text(p.rawValue.capitalized).tag(p)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section {
                Button("Delete Task", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle("Edit Task")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("Delete this task?", isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
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
