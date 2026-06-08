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
                TextField("Titel", text: $title)
                TextField("Notizen", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section("Zeit") {
                DatePicker("Beginn", selection: $startTime)
                    .datePickerStyle(.compact)
                DatePicker("Ende", selection: $endTime)
                    .datePickerStyle(.compact)
            }

            Section {
                Toggle("Gesperrt (nicht verschiebbar)", isOn: $isLocked)
            }

            Section {
                Button("Termin löschen", role: .destructive) {
                    if event.isLocked {
                        showingLockedDeleteConfirmation = true
                    } else {
                        showingDeleteConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Termin bearbeiten")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty
                              || endTime <= startTime)
            }
        }
        .confirmationDialog("Termin löschen?",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { deleteEvent() }
        }
        .confirmationDialog("Termin ist gesperrt. Trotzdem löschen?",
                            isPresented: $showingLockedDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Gesperrten Termin löschen", role: .destructive) { deleteEvent() }
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
