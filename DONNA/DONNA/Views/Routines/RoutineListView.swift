import SwiftUI
import SwiftData

struct RoutineListView: View {
    @Query private var allOccurrences: [RoutineOccurrence]
    @Environment(\.modelContext) private var modelContext
    @State private var showingCreationSheet = false

    private var todayOccurrences: [RoutineOccurrence] {
        allOccurrences
            .filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: .now) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private var scheduled:  [RoutineOccurrence] { todayOccurrences.filter { $0.status == .scheduled } }
    private var completed:  [RoutineOccurrence] { todayOccurrences.filter { $0.status == .completed } }
    private var skipped:    [RoutineOccurrence] { todayOccurrences.filter { $0.status == .skipped || $0.status == .rescheduled } }

    var body: some View {
        NavigationStack {
            Group {
                if todayOccurrences.isEmpty {
                    VStack {
                        Spacer()
                        VStack(spacing: DS.Spacing.vertical) {
                            Image(systemName: "arrow.clockwise")
                                .font(.largeTitle)
                                .foregroundStyle(DS.Colors.warmAccent)
                            Text("Keine Routinen heute")
                                .font(DS.Typography.subheading)
                                .foregroundStyle(DS.Colors.textPrimary)
                            Text("Routinen hinzufügen, um zu beginnen.")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(DS.Spacing.section)
                        .background(DS.Colors.appBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.card)
                                .stroke(DS.Colors.separator, lineWidth: 1)
                        )
                        .padding(.horizontal, DS.Spacing.horizontal)
                        Spacer()
                    }
                    .background(DS.Colors.appBackground)
                } else {
                    List {
                        if !scheduled.isEmpty {
                            Section {
                                ForEach(scheduled) { occ in occurrenceRow(occ) }
                            } header: {
                                sectionHeader("Scheduled")
                            }
                        }
                        if !completed.isEmpty {
                            Section {
                                ForEach(completed) { occ in occurrenceRow(occ) }
                            } header: {
                                sectionHeader("Completed")
                            }
                        }
                        if !skipped.isEmpty {
                            Section {
                                ForEach(skipped) { occ in occurrenceRow(occ) }
                            } header: {
                                sectionHeader("Skipped")
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(DS.Colors.appBackground)
                }
            }
            .navigationTitle("Routines")
            .background(DS.Colors.appBackground)
            #if os(iOS)
            .toolbarBackground(DS.Colors.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreationSheet = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(DS.Colors.accent)
                    }
                }
            }
            .sheet(isPresented: $showingCreationSheet) {
                RoutineCreationSheet()
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(DS.Colors.textTertiary)
            .textCase(nil)
    }

    @ViewBuilder
    private func occurrenceRow(_ occ: RoutineOccurrence) -> some View {
        if let routine = occ.routine {
            NavigationLink {
                RoutineDetailView(routine: routine)
            } label: {
                OccurrenceRowContent(occurrence: occ, streak: streak(for: routine))
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: DS.Spacing.horizontal, bottom: 4, trailing: DS.Spacing.horizontal))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                // Recovery-day routines are "optional": skipped, but still completable.
                if occ.status == .scheduled || occ.skippedReason == CommandHandler.recoverySkipReason {
                    Button {
                        withAnimation(DS.animation) {
                            _ = CommandHandler(modelContext: modelContext)
                                .execute(.completeOccurrence(id: occ.id))
                        }
                    } label: {
                        Label("Complete", systemImage: "checkmark")
                    }
                    .tint(DS.Colors.success)
                }
            }
            .swipeActions(edge: .trailing) {
                if occ.status == .scheduled {
                    Button {
                        withAnimation(DS.animation) {
                            _ = CommandHandler(modelContext: modelContext)
                                .execute(.skipOccurrence(id: occ.id, reason: nil))
                        }
                    } label: {
                        Label("Skip", systemImage: "xmark")
                    }
                    .tint(DS.Colors.textTertiary)
                }
            }
        } else {
            OccurrenceRowContent(occurrence: occ, streak: 0)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    private func streak(for routine: Routine) -> Int {
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
}

// MARK: - Row Content

private struct OccurrenceRowContent: View {
    let occurrence: RoutineOccurrence
    let streak: Int

    private var categoryColor: Color {
        guard let cat = occurrence.routine?.category else { return DS.Colors.textSecondary }
        return DS.Colors.category(cat)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Category color dot
            Circle()
                .fill(categoryColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                Text(occurrence.routine?.title ?? "Routine")
                    .font(DS.Typography.body)
                    .foregroundStyle(statusTextColor)

                HStack(spacing: 8) {
                    if let time = occurrence.routine?.preferredTimeOfDay {
                        Text(time, format: .dateTime.hour().minute())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                    if let dur = occurrence.routine?.durationMinutes {
                        Text("\(dur) min")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.Colors.textTertiary)
                    }
                    if streak > 0 {
                        Text("\(streak)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(DS.Colors.textTertiary)
                    }
                }
            }

            Spacer()

            Image(systemName: statusIcon)
                .foregroundStyle(statusIconColor)
                .font(.body)
                .animation(DS.animation, value: occurrence.status)
        }
        .padding(.horizontal, DS.Spacing.horizontal)
        .padding(.vertical, DS.Spacing.vertical)
        .background(DS.Colors.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
    }

    private var statusIcon: String {
        switch occurrence.status {
        case .completed:   return "checkmark.circle.fill"
        case .skipped:     return "xmark.circle"
        case .rescheduled: return "clock.arrow.circlepath"
        case .scheduled:   return "circle"
        }
    }

    private var statusIconColor: Color {
        switch occurrence.status {
        case .completed:   return DS.Colors.success
        case .skipped:     return DS.Colors.textTertiary
        case .rescheduled: return DS.Colors.accent
        case .scheduled:   return DS.Colors.textTertiary
        }
    }

    private var statusTextColor: Color {
        occurrence.status == .completed ? DS.Colors.textSecondary : DS.Colors.textPrimary
    }
}

#Preview {
    let schema = Schema([Routine.self, RoutineOccurrence.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return RoutineListView().modelContainer(container)
}
