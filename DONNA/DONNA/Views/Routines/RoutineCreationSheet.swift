import SwiftUI
import SwiftData

struct RoutineCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title = ""
    @State private var category: RoutineCategory = .custom
    @State private var frequency: RoutineFrequency = .daily
    @State private var hasPreferredTime = false
    @State private var preferredTime: Date = .now
    @State private var durationMinutes = 30

    private let categories: [RoutineCategory] = [.sport, .sleep, .learning, .skincare, .nutrition, .custom]
    private let frequencies: [RoutineFrequency] = [.daily, .weekdays, .weekly]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Routine title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat.rawValue.capitalized).tag(cat)
                        }
                    }
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(frequencies, id: \.self) { freq in
                            Text(frequencyLabel(freq)).tag(freq)
                        }
                    }
                    Toggle("Preferred time", isOn: $hasPreferredTime)
                    if hasPreferredTime {
                        DatePicker("Time", selection: $preferredTime,
                                   displayedComponents: .hourAndMinute)
                    }
                }

                Section("Duration") {
                    Stepper("\(durationMinutes) minutes",
                            value: $durationMinutes, in: 5...240, step: 5)
                }
            }
            .navigationTitle("New Routine")
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
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let definition = RoutineDefinition(
            title: trimmed,
            frequency: frequency,
            preferredTimeOfDay: hasPreferredTime ? preferredTime : nil,
            durationMinutes: durationMinutes,
            category: category
        )
        _ = CommandHandler(modelContext: modelContext).execute(.createRoutine(definition: definition))
    }

    private func frequencyLabel(_ freq: RoutineFrequency) -> String {
        switch freq {
        case .daily:    return "Daily"
        case .weekdays: return "Weekdays (Mon–Fri)"
        case .weekly:   return "Weekly"
        case .custom:   return "Custom"
        }
    }
}

#Preview {
    let schema = Schema([Routine.self, RoutineOccurrence.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return RoutineCreationSheet().modelContainer(container)
}
