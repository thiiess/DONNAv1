import SwiftUI
import SwiftData

struct RoutineDetailView: View {
    let routine: Routine

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        List {
            Section {
                streakRow
                infoRow(label: "Frequency", icon: "repeat",  value: frequencyLabel)
                if let time = routine.preferredTimeOfDay {
                    infoRow(label: "Time", icon: "clock",
                            value: time.formatted(.dateTime.hour().minute()))
                }
                infoRow(label: "Duration", icon: "timer",
                        value: "\(routine.durationMinutes) min")
                infoRow(label: "Category", icon: categoryIcon,
                        value: routine.category.rawValue.capitalized)
            }

            Section("History") {
                if sortedOccurrences.isEmpty {
                    Text("No occurrences yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedOccurrences) { occ in
                        occurrenceRow(occ)
                    }
                }
            }

            Section {
                Button("Delete Routine", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            }
        }
        .navigationTitle(routine.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { showingEditSheet = true }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            RoutineEditSheet(routine: routine)
        }
        .confirmationDialog("Delete \"\(routine.title)\"?",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete Routine", role: .destructive) {
                _ = CommandHandler(modelContext: modelContext).execute(.deleteRoutine(id: routine.id))
                dismiss()
            }
        }
    }

    // MARK: - Sub-views

    private var streakRow: some View {
        HStack {
            Label("Streak", systemImage: "flame.fill")
                .foregroundStyle(.orange)
            Spacer()
            Text(streak == 0 ? "–" : "\(streak) day\(streak == 1 ? "" : "s")")
                .font(.headline)
                .foregroundStyle(streak > 0 ? .orange : .secondary)
        }
    }

    private func infoRow(label: String, icon: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }

    private func occurrenceRow(_ occ: RoutineOccurrence) -> some View {
        HStack(spacing: 12) {
            Image(systemName: historyIcon(occ.status))
                .foregroundStyle(historyColor(occ.status))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(occ.scheduledDate,
                     format: .dateTime.weekday(.wide).day().month(.abbreviated))
                    .font(.subheadline)

                if let completedAt = occ.completedAt {
                    Text("Completed \(completedAt.formatted(.dateTime.hour().minute()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if occ.status == .skipped, let reason = occ.skippedReason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(occ.status.rawValue.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Computed

    private var sortedOccurrences: [RoutineOccurrence] {
        routine.occurrences.sorted { $0.scheduledDate > $1.scheduledDate }
    }

    private var streak: Int {
        let cal = Calendar.current
        let completedDays = Set(
            routine.occurrences
                .filter { $0.status == .completed }
                .map { cal.startOfDay(for: $0.scheduledDate) }
        )
        var count = 0
        var day = cal.startOfDay(for: .now)
        if !completedDays.contains(day) {
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        while completedDays.contains(day) {
            count += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return count
    }

    private var frequencyLabel: String {
        switch routine.frequency {
        case .daily:    return "Daily"
        case .weekdays: return "Weekdays"
        case .weekly:   return "Weekly"
        case .custom:   return "Custom"
        }
    }

    private var categoryIcon: String {
        switch routine.category {
        case .sleep:     return "moon.fill"
        case .sport:     return "figure.run"
        case .learning:  return "book.fill"
        case .skincare:  return "sparkles"
        case .nutrition: return "fork.knife"
        case .custom:    return "star.fill"
        }
    }

    private func historyIcon(_ status: OccurrenceStatus) -> String {
        switch status {
        case .completed:   return "checkmark.circle.fill"
        case .skipped:     return "xmark.circle"
        case .rescheduled: return "clock.arrow.circlepath"
        case .scheduled:   return "circle.dotted"
        }
    }

    private func historyColor(_ status: OccurrenceStatus) -> Color {
        switch status {
        case .completed:   return .green
        case .skipped:     return .secondary
        case .rescheduled: return .blue
        case .scheduled:   return .secondary
        }
    }
}

// MARK: - Edit Sheet

struct RoutineEditSheet: View {
    let routine: Routine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String
    @State private var frequency: RoutineFrequency
    @State private var hasPreferredTime: Bool
    @State private var preferredTime: Date

    init(routine: Routine) {
        self.routine = routine
        _title            = State(initialValue: routine.title)
        _frequency        = State(initialValue: routine.frequency)
        _hasPreferredTime = State(initialValue: routine.preferredTimeOfDay != nil)
        _preferredTime    = State(initialValue: routine.preferredTimeOfDay ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $frequency) {
                        Text("Daily").tag(RoutineFrequency.daily)
                        Text("Weekdays").tag(RoutineFrequency.weekdays)
                        Text("Weekly").tag(RoutineFrequency.weekly)
                    }
                    Toggle("Preferred time", isOn: $hasPreferredTime)
                    if hasPreferredTime {
                        DatePicker("Time", selection: $preferredTime,
                                   displayedComponents: .hourAndMinute)
                    }
                }
            }
            .navigationTitle("Edit Routine")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        _ = CommandHandler(modelContext: modelContext).execute(.updateRoutine(
            id: routine.id,
            title: trimmed,
            frequency: frequency,
            preferredTimeOfDay: hasPreferredTime ? preferredTime : nil
        ))
        dismiss()
    }
}

#Preview {
    let schema = Schema([Routine.self, RoutineOccurrence.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let routine = Routine(title: "Morning Run", frequency: .daily, durationMinutes: 30,
                          category: .sport)
    return NavigationStack {
        RoutineDetailView(routine: routine)
    }.modelContainer(container)
}
