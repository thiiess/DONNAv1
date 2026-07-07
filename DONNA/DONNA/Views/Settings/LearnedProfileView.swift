import SwiftUI
import SwiftData

struct LearnedProfileView: View {

    @Query private var profiles: [LearnedProfile]
    @Query private var preferences: [Preference]
    @Environment(\.modelContext) private var modelContext

    @State private var showResetConfirmation = false

    private var profile: LearnedProfile? { profiles.first }

    /// All preferences that are user-visible (excludes internal cooldown markers).
    private var displayedPreferences: [Preference] {
        preferences
            .filter { !$0.key.hasPrefix("cooldown_") }
            .sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        List {
            profileSummarySection
            preferencesSection
            resetSection
        }
        .navigationTitle("Was DONNA weiß")
        .confirmationDialog(
            "Beobachtete Präferenzen löschen?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Zurücksetzen", role: .destructive, action: deleteObservedPreferences)
        } message: {
            Text("Nur automatisch erkannte Präferenzen werden gelöscht. Explizit eingegebene Einstellungen bleiben erhalten.")
        }
    }

    // MARK: - Sections

    private var profileSummarySection: some View {
        Section("Was DONNA über mich weiß") {
            if let profile {
                profileRows(for: profile)
            } else {
                Text("Noch keine Daten gesammelt.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func profileRows(for profile: LearnedProfile) -> some View {
        if let bedtime = profile.avgBedtime {
            LabeledContent("Ø Schlafenszeit") {
                Text(bedtime, format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
            }
        }
        if let duration = profile.avgSleepDuration {
            LabeledContent("Ø Schlafdauer") {
                Text(String(format: "%.1f Std.", duration))
                    .foregroundStyle(.secondary)
            }
        }
        LabeledContent("Schlaftrend") {
            Text(profile.sleepTrend.localizedName)
                .foregroundStyle(profile.sleepTrend.trendColor)
        }
        if let start = profile.productiveHoursStart, let end = profile.productiveHoursEnd {
            LabeledContent("Produktive Stunden") {
                Text("\(start):00 – \(end):00")
                    .foregroundStyle(.secondary)
            }
        }
        if let sport = profile.avgSportPerWeek {
            LabeledContent("Ø Sport / Woche") {
                Text(String(format: "%.1f Einheiten", sport))
                    .foregroundStyle(.secondary)
            }
        }
        LabeledContent("Datenpunkte") {
            Text("\(profile.totalDataPoints)")
                .foregroundStyle(.secondary)
        }
        LabeledContent("Zuletzt aktualisiert") {
            Text(profile.lastUpdated, style: .relative)
                .foregroundStyle(.secondary)
        }
    }

    private var preferencesSection: some View {
        Section("Gespeicherte Präferenzen") {
            if displayedPreferences.isEmpty {
                Text("Keine Präferenzen gespeichert.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(displayedPreferences) { preference in
                    PreferenceRow(preference: preference)
                }
                .onDelete(perform: deletePreferences)
            }
        }
    }

    private var resetSection: some View {
        Section {
            Button("Beobachtete Präferenzen löschen", role: .destructive) {
                showResetConfirmation = true
            }
        } header: {
            Text("Profil zurücksetzen")
        } footer: {
            Text("Loescht alle automatisch erkannten Praeferenzen (Quelle: \u{201E}Beobachtet\u{201C}) sowie Cooldown-Marker. Explizit eingegebene Einstellungen bleiben erhalten.")
        }
    }

    // MARK: - Actions

    private func deletePreferences(at offsets: IndexSet) {
        let handler = CommandHandler(modelContext: modelContext)
        for index in offsets {
            _ = handler.execute(.deleteLearnedItem(key: displayedPreferences[index].key))
        }
    }

    private func deleteObservedPreferences() {
        let handler = CommandHandler(modelContext: modelContext)
        for pref in preferences where pref.source == .observed || pref.key.hasPrefix("cooldown_") {
            _ = handler.execute(.deleteLearnedItem(key: pref.key))
        }
    }
}

// MARK: - PreferenceRow

private struct PreferenceRow: View {
    let preference: Preference

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(preference.key.readableTitle)
                    .font(.body)
                Spacer()
                SourceBadge(source: preference.source)
            }
            Text(preference.value)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let confirmedAt = preference.confirmedAt {
                Text("Bestätigt \(confirmedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - SourceBadge

private struct SourceBadge: View {
    let source: PreferenceSource

    var body: some View {
        Text(source.localizedName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(source.badgeColor.opacity(0.15))
            .foregroundStyle(source.badgeColor)
            .clipShape(Capsule())
    }
}

// MARK: - Extensions

private extension Trend {
    var localizedName: String {
        switch self {
        case .stable:    return "Stabil"
        case .improving: return "Verbessernd"
        case .declining: return "Verschlechternd"
        }
    }

    var trendColor: Color {
        switch self {
        case .stable:    return .secondary
        case .improving: return .green
        case .declining: return .orange
        }
    }
}

private extension PreferenceSource {
    var localizedName: String {
        switch self {
        case .explicit:  return "Manuell"
        case .observed:  return "Beobachtet"
        case .`default`: return "Standard"
        }
    }

    var badgeColor: Color {
        switch self {
        case .explicit:  return .blue
        case .observed:  return .purple
        case .`default`: return .gray
        }
    }
}

private extension String {
    var readableTitle: String {
        self.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

#Preview {
    NavigationStack {
        LearnedProfileView()
    }
    .modelContainer(for: [LearnedProfile.self, Preference.self], inMemory: true)
}
