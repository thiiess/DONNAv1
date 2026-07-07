import SwiftUI
import SwiftData

// MARK: - Storage Row Model

private struct StorageCategoryRow: Identifiable {
    let id: String
    let name: String
    let icon: String
    let hotCount: Int
    let warmCount: Int
    let coldCount: Int
    let bytesPerRecord: Int

    var totalCount: Int { hotCount + warmCount + coldCount }
    var estimatedKB: Double { Double(totalCount * bytesPerRecord) / 1024.0 }
    var hasLayers: Bool { warmCount > 0 || coldCount > 0 }
}

// MARK: - StorageDashboardView

struct StorageDashboardView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var rows: [StorageCategoryRow] = []
    @State private var isRunning = false
    @State private var showConfirmClean = false

    @State private var hotPeriodMonths  = DataLifecycleManager.hotPeriodMonths
    @State private var chatHistoryMonths = DataLifecycleManager.chatHistoryMonths

    private let hotOptions  = [3, 6, 12]
    private let chatOptions = [1, 3, 6]

    private var totalKB: Double { rows.map(\.estimatedKB).reduce(0, +) }

    var body: some View {
        List {
            overviewSection
            detailSection
            retentionSection
            cleanupSection
        }
        .navigationTitle("Speicher")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .onAppear { loadStats() }
    }

    // MARK: - Sections

    private var overviewSection: some View {
        Section {
            HStack {
                Label("Gesamt (geschätzt)", systemImage: "internaldrive")
                Spacer()
                Text(formatKB(totalKB))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        } header: {
            Text("Übersicht")
        }
    }

    private var detailSection: some View {
        Section {
            ForEach(rows) { row in
                DisclosureGroup {
                    if row.hasLayers {
                        layerRow("HOT",  count: row.hotCount,  color: .orange)
                        layerRow("WARM", count: row.warmCount, color: .yellow)
                        layerRow("COLD", count: row.coldCount, color: .blue)
                    } else {
                        layerRow("HOT", count: row.hotCount, color: .orange)
                    }
                } label: {
                    HStack {
                        Label(row.name, systemImage: row.icon)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(row.totalCount) Einträge")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(formatKB(row.estimatedKB))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .monospacedDigit()
                        }
                    }
                }
            }
        } header: {
            Text("Kategorien")
        } footer: {
            Text("Geschätzte Werte – tatsächliche Größen können abweichen.")
        }
    }

    private var retentionSection: some View {
        Section {
            Picker("HOT-Zeitraum", selection: $hotPeriodMonths) {
                ForEach(hotOptions, id: \.self) { months in
                    Text("\(months) Monate").tag(months)
                }
            }
            .onChange(of: hotPeriodMonths) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: DataLifecycleManager.hotPeriodMonthsKey)
            }

            Picker("Chat-Verlauf", selection: $chatHistoryMonths) {
                ForEach(chatOptions, id: \.self) { months in
                    Text("\(months) Monate").tag(months)
                }
            }
            .onChange(of: chatHistoryMonths) { _, newValue in
                UserDefaults.standard.set(newValue, forKey: DataLifecycleManager.chatHistoryMonthsKey)
            }
        } header: {
            Text("Aufbewahrungsfristen")
        } footer: {
            Text("Ältere Einträge werden beim nächsten Bereinigen komprimiert oder gelöscht.")
        }
    }

    private var cleanupSection: some View {
        Section {
            Button {
                showConfirmClean = true
            } label: {
                HStack {
                    if isRunning {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Wird bereinigt…")
                    } else {
                        Label("Jetzt bereinigen", systemImage: "sparkles.rectangle.stack")
                    }
                }
            }
            .disabled(isRunning)
            .confirmationDialog(
                "Speicher bereinigen?",
                isPresented: $showConfirmClean,
                titleVisibility: .visible
            ) {
                Button("Bereinigen", role: .destructive) { runCleanup() }
            } message: {
                Text("Alte Einträge werden komprimiert. Chat-Nachrichten älter als \(chatHistoryMonths) Monate werden gelöscht. Dies kann nicht rückgängig gemacht werden.")
            }
        } footer: {
            if let last = UserDefaults.standard.object(forKey: "donna_lifecycle_lastRun") as? Date {
                Text("Zuletzt bereinigt: \(last.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helper Views

    private func layerRow(_ label: String, count: Int, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text("\(count)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.leading, 8)
    }

    // MARK: - Data Loading

    private func loadStats() {
        guard let tasks        = try? modelContext.fetch(FetchDescriptor<DONNATask>()),
              let events       = try? modelContext.fetch(FetchDescriptor<CalendarEvent>()),
              let routines     = try? modelContext.fetch(FetchDescriptor<Routine>()),
              let occurrences  = try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>()),
              let sleepWindows = try? modelContext.fetch(FetchDescriptor<SleepWindow>()),
              let chatMessages = try? modelContext.fetch(FetchDescriptor<ChatMessage>()),
              let preferences  = try? modelContext.fetch(FetchDescriptor<Preference>())
        else { return }

        rows = [
            makeCategoryRow(id: "tasks",     name: "Aufgaben",        icon: "checkmark.circle",
                            items: tasks.map(\.dataLayer),            bytesPerRecord: 250),
            makeCategoryRow(id: "events",    name: "Kalendereinträge", icon: "calendar",
                            items: events.map(\.dataLayer),           bytesPerRecord: 300),
            makeCategoryRow(id: "routines",  name: "Routinen",        icon: "arrow.clockwise",
                            items: Array(repeating: .hot, count: routines.count),
                            bytesPerRecord: 300),
            makeCategoryRow(id: "occ",       name: "Routine-Einträge", icon: "checklist",
                            items: occurrences.map(\.dataLayer),      bytesPerRecord: 150),
            makeCategoryRow(id: "sleep",     name: "Schlaffenster",   icon: "moon.zzz",
                            items: sleepWindows.map(\.dataLayer),     bytesPerRecord: 100),
            makeCategoryRow(id: "chat",      name: "Chat-Nachrichten", icon: "bubble.left.and.bubble.right",
                            items: chatMessages.map(\.dataLayer),     bytesPerRecord: 600),
            makeCategoryRow(id: "prefs",     name: "Einstellungen",   icon: "gearshape",
                            items: Array(repeating: .hot, count: preferences.count),
                            bytesPerRecord: 250),
        ]
    }

    private func makeCategoryRow(
        id: String,
        name: String,
        icon: String,
        items: [DataLayer],
        bytesPerRecord: Int
    ) -> StorageCategoryRow {
        StorageCategoryRow(
            id: id,
            name: name,
            icon: icon,
            hotCount:  items.filter { $0 == .hot  }.count,
            warmCount: items.filter { $0 == .warm }.count,
            coldCount: items.filter { $0 == .cold }.count,
            bytesPerRecord: bytesPerRecord
        )
    }

    // MARK: - Cleanup

    private func runCleanup() {
        isRunning = true
        Swift.Task { @MainActor in
            DataLifecycleManager.shared.run(modelContext: modelContext)
            loadStats()
            isRunning = false
        }
    }

    // MARK: - Formatting

    private func formatKB(_ kb: Double) -> String {
        if kb < 1 { return "< 1 KB" }
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        return String(format: "%.1f MB", kb / 1024.0)
    }
}

#Preview {
    NavigationStack {
        StorageDashboardView()
    }
    .modelContainer(for: [
        DONNATask.self, CalendarEvent.self, Routine.self,
        RoutineOccurrence.self, SleepWindow.self, ChatMessage.self, Preference.self,
    ], inMemory: true)
}
