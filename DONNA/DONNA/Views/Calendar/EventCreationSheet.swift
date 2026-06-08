import SwiftUI
import SwiftData

struct EventCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isLocked = false

    init() {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: .now)
        comps.minute = 0
        comps.hour = (comps.hour ?? 9) + 1
        let start = cal.date(from: comps) ?? .now
        let end   = cal.date(byAdding: .hour, value: 1, to: start) ?? start
        _startTime = State(initialValue: start)
        _endTime   = State(initialValue: end)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Event title", text: $title)
                    Toggle("Locked (cannot be moved)", isOn: $isLocked)
                }

                Section("Time") {
                    DatePicker("Starts", selection: $startTime,
                               displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: startTime) { _, newStart in
                            if endTime <= newStart {
                                endTime = Calendar.current.date(
                                    byAdding: .hour, value: 1, to: newStart
                                ) ?? newStart
                            }
                        }
                    DatePicker("Ends", selection: $endTime,
                               in: startTime...,
                               displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("New Event")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        save()
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let event = CalendarEvent(
            title: title.trimmingCharacters(in: .whitespaces),
            startTime: startTime,
            endTime: endTime,
            isLocked: isLocked
        )
        modelContext.insert(event)
    }
}

#Preview {
    let schema = Schema([CalendarEvent.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return EventCreationSheet().modelContainer(container)
}
