import SwiftUI
import SwiftData

struct EventDetailView: View {
    let event: CalendarEvent

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isLocked: Bool
    @State private var showingDeleteConfirmation = false
    @State private var showingLockedDeleteConfirmation = false

    init(event: CalendarEvent) {
        self.event = event
        _title     = State(initialValue: event.title)
        _notes     = State(initialValue: event.notes ?? "")
        _startTime = State(initialValue: event.startTime)
        _endTime   = State(initialValue: event.endTime)
        _isLocked  = State(initialValue: event.isLocked)
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section("Time") {
                DatePicker("Start", selection: $startTime)
                DatePicker("End", selection: $endTime)
            }

            Section {
                Toggle("Locked — cannot be moved", isOn: $isLocked)
            }

            Section {
                Button("Delete Event", role: .destructive) {
                    if event.isLocked {
                        showingLockedDeleteConfirmation = true
                    } else {
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Edit Event")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                              || endTime <= startTime)
            }
        }
        .confirmationDialog("Delete this event?",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteEvent() }
        }
        .confirmationDialog("This event is locked. Delete it anyway?",
                            isPresented: $showingLockedDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete Locked Event", role: .destructive) { deleteEvent() }
        }
    }

    private func save() {
        var changes = EventChanges()
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, endTime > startTime else { return }
        changes.title     = .set(trimmed)
        changes.startTime = .set(startTime)
        changes.endTime   = .set(endTime)
        changes.isLocked  = .set(isLocked)
        changes.notes     = notes.isEmpty ? .clear : .set(notes)
        _ = CommandHandler(modelContext: modelContext).execute(.updateEvent(id: event.id, changes: changes))
        dismiss()
    }

    private func deleteEvent() {
        _ = CommandHandler(modelContext: modelContext).execute(.deleteEvent(id: event.id))
        dismiss()
    }
}

#Preview {
    let schema = Schema([CalendarEvent.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let event = CalendarEvent(title: "Team Meeting",
                              startTime: Date(),
                              endTime: Date().addingTimeInterval(3600))
    container.mainContext.insert(event)
    return NavigationStack { EventDetailView(event: event) }.modelContainer(container)
}
