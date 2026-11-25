import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<ContextMode> { $0.isActive }) private var activeModes: [ContextMode]

    @State private var apiKeyDraft = ""
    @State private var maskedKey: String?
    @State private var showDeleteKeyConfirmation = false
    @State private var showClearChatConfirmation = false
    #if DEBUG
    @State private var briefingKeyCleared = false
    @State private var weeklySummaryPosted = false
    #endif

    @AppStorage("donna_science_sport")    private var scienceSport    = true
    @AppStorage("donna_science_sleep")    private var scienceSleep    = true
    @AppStorage("donna_science_learning") private var scienceLearning = true
    @AppStorage("donna_science_general")  private var scienceGeneral  = true

    @AppStorage("donna_briefing_enabled") private var briefingEnabled = false
    @AppStorage("donna_briefing_time")    private var briefingTimeInterval: Double = {
        var c = DateComponents(); c.hour = 7; c.minute = 30
        return Calendar.current.date(from: c)?.timeIntervalSinceReferenceDate ?? 0
    }()

    @AppStorage(ProactiveMonitor.weeklySummaryEnabledKey) private var weeklySummaryEnabled = false
    @AppStorage(ProactiveMonitor.weeklySummaryTimeKey) private var weeklySummaryTimeInterval: Double = ProactiveMonitor.defaultWeeklySummaryTime

    private var weeklySummaryTime: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: weeklySummaryTimeInterval) },
            set: { weeklySummaryTimeInterval = $0.timeIntervalSinceReferenceDate }
        )
    }

    private var briefingTime: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSinceReferenceDate: briefingTimeInterval) },
            set: { briefingTimeInterval = $0.timeIntervalSinceReferenceDate }
        )
    }

    private static let keychainKey = "donna_gemini_api_key"

    var body: some View {
        NavigationStack {
            Form {
                learnedProfileSection
                wissenschaftSection
                kontextmodusSection
                datenschutzSection
                morgenbriefingSection
                wochenrueckblickSection
                #if DEBUG
                debugSection
                #endif
                apiKeySection
            }
            .scrollContentBackground(.hidden)
            .background(DS.Colors.appBackground)
            #if os(macOS)
            .padding(.trailing, DS.Spacing.horizontal)
            #endif
            .navigationTitle("Einstellungen")
            #if os(iOS)
            .toolbarBackground(DS.Colors.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
        }
        .onAppear(perform: refreshMaskedKey)
    }

    // MARK: - Lernprofil

    private var learnedProfileSection: some View {
        Section {
            NavigationLink {
                LearnedProfileView()
            } label: {
                Label("Was DONNA über mich weiß", systemImage: "brain.head.profile")
                    .foregroundStyle(DS.Colors.textPrimary)
            }
            NavigationLink {
                StorageDashboardView()
            } label: {
                Label("Speicher-Dashboard", systemImage: "internaldrive")
                    .foregroundStyle(DS.Colors.textPrimary)
            }
        } header: {
            Text("Lernprofil")
                .foregroundStyle(DS.Colors.warmAccent)
                .font(.caption.weight(.semibold))
                .textCase(nil)
        }
        .listRowBackground(DS.Colors.backgroundSecondary)
    }

    // MARK: - Wissenschaftliche Regeln

    private var wissenschaftSection: some View {
        Section {
            Toggle(isOn: $scienceSport) {
                Label("Sport", systemImage: "figure.run")
                    .foregroundStyle(DS.Colors.textPrimary)
            }
            .tint(DS.Colors.warmAccent)
            .toggleStyle(.switch)
            Toggle(isOn: $scienceSleep) {
                Label("Schlaf", systemImage: "moon.zzz.fill")
                    .foregroundStyle(DS.Colors.textPrimary)
            }
            .tint(DS.Colors.warmAccent)
            .toggleStyle(.switch)
            Toggle(isOn: $scienceLearning) {
                Label("Lernen", systemImage: "book.fill")
                    .foregroundStyle(DS.Colors.textPrimary)
            }
            .tint(DS.Colors.warmAccent)
            .toggleStyle(.switch)
            Toggle(isOn: $scienceGeneral) {
                Label("Allgemein", systemImage: "checklist")
                    .foregroundStyle(DS.Colors.textPrimary)
            }
            .tint(DS.Colors.warmAccent)
            .toggleStyle(.switch)
        } header: {
            Text("Wissenschaftliche Regeln")
                .foregroundStyle(DS.Colors.warmAccent)
                .font(.caption.weight(.semibold))
                .textCase(nil)
        } footer: {
            Text("Deaktivierte Regeln werden von der ScienceEngine nicht mehr geprüft.")
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .listRowBackground(DS.Colors.backgroundSecondary)
    }

    // MARK: - Kontextmodus

    private var kontextmodusSection: some View {
        Section {
            if let active = activeModes.first {
                HStack {
                    Text("Aktiver Modus")
                        .foregroundStyle(DS.Colors.textSecondary)
                    Spacer()
                    Text(active.name.capitalized)
                        .foregroundStyle(DS.Colors.textPrimary)
                        .font(.body.weight(.medium))
                }
            } else {
                Text("Kein Modus aktiv")
                    .foregroundStyle(DS.Colors.textTertiary)
            }

            HStack(spacing: 10) {
                ForEach(["normal", "study", "work"], id: \.self) { modeName in
                    let label: String = {
                        switch modeName {
                        case "normal": return "Alltag"
                        case "study":  return "Studium"
                        default:       return "Beruf"
                        }
                    }()
                    let isActive = activeModes.first?.name == modeName
                    Button {
                        withAnimation(DS.animation) { switchContextMode(to: modeName) }
                    } label: {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: DS.Radius.chip)
                                    .fill(isActive ? DS.Colors.warmAccent : DS.Colors.backgroundTertiary)
                            )
                            .foregroundStyle(isActive ? .white : DS.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .animation(DS.animation, value: isActive)
                }
            }
        } header: {
            Text("Kontextmodus")
                .foregroundStyle(DS.Colors.warmAccent)
                .font(.caption.weight(.semibold))
                .textCase(nil)
        } footer: {
            Text("Passt DONNAs Vorschläge und Prioritäten an deine aktuelle Lebensphase an.")
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .listRowBackground(DS.Colors.backgroundSecondary)
    }

    private func switchContextMode(to name: String) {
        _ = CommandHandler(modelContext: modelContext).execute(.activateContextMode(name: name, until: nil))
    }

    // MARK: - Datenschutz

    private var datenschutzSection: some View {
        Section {
            Button(role: .destructive) {
                showClearChatConfirmation = true
            } label: {
                Label("Chat-Verlauf löschen", systemImage: "trash")
                    .foregroundStyle(DS.Colors.destructive)
            }
            .confirmationDialog(
                "Chat-Verlauf löschen?",
                isPresented: $showClearChatConfirmation,
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive, action: clearChatHistory)
            } message: {
                Text("Alle Chatnachrichten werden unwiderruflich gelöscht. DONNAs Lernprofil bleibt erhalten.")
            }
        } header: {
            Text("Datenschutz")
                .foregroundStyle(DS.Colors.warmAccent)
                .font(.caption.weight(.semibold))
                .textCase(nil)
        } footer: {
            Text("Nur anonymisierter Gesprächstext geht an die Gemini API. Kein Klarname, kein Ort, keine Kalender-ID.")
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .listRowBackground(DS.Colors.backgroundSecondary)
    }

    private func clearChatHistory() {
        _ = CommandHandler(modelContext: modelContext).execute(.clearChatHistory)
    }

    // MARK: - Morgenbriefing

    private var morgenbriefingSection: some View {
        Section {
            Toggle("Morgenbriefing aktivieren", isOn: $briefingEnabled)
                .foregroundStyle(DS.Colors.textPrimary)
                .tint(DS.Colors.warmAccent)
                .onChange(of: briefingEnabled) { _, enabled in handleBriefingEnabledChange(enabled) }
                .onChange(of: briefingTimeInterval) { _, _ in handleBriefingTimeChange() }
            if briefingEnabled {
                DatePicker("Uhrzeit", selection: briefingTime, displayedComponents: .hourAndMinute)
                    .foregroundStyle(DS.Colors.textPrimary)
            }
        } header: {
            Text("Morgenbriefing")
                .foregroundStyle(DS.Colors.warmAccent)
                .font(.caption.weight(.semibold))
                .textCase(nil)
        } footer: {
            Text("Täglich eine kurze Zusammenfassung deines Tages – als Benachrichtigung und als Karte im DONNA-Tab.")
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .listRowBackground(DS.Colors.backgroundSecondary)
    }

    private func handleBriefingEnabledChange(_ enabled: Bool) {
        guard enabled else {
            NotificationScheduler.shared.cancelMorningBriefing()
            return
        }
        // Persist the (possibly still-default) time so the app-launch / background path reads a real value.
        briefingTimeInterval = briefingTime.wrappedValue.timeIntervalSinceReferenceDate
        Swift.Task {
            let granted = await NotificationScheduler.shared.requestPermission()
            await MainActor.run {
                if granted {
                    NotificationScheduler.shared.scheduleMorningBriefing(at: briefingTime.wrappedValue)
                } else {
                    briefingEnabled = false
                }
            }
        }
    }

    // MARK: - Wochenrückblick

    private var wochenrueckblickSection: some View {
        Section {
            Toggle("Wochenrückblick aktivieren", isOn: $weeklySummaryEnabled)
                .foregroundStyle(DS.Colors.textPrimary)
                .tint(DS.Colors.warmAccent)
                .onChange(of: weeklySummaryEnabled) { _, enabled in handleWeeklySummaryEnabledChange(enabled) }
                .onChange(of: weeklySummaryTimeInterval) { _, _ in
                    guard weeklySummaryEnabled else { return }
                    NotificationScheduler.shared.scheduleWeeklySummary(at: weeklySummaryTime.wrappedValue)
                }
            if weeklySummaryEnabled {
                DatePicker("Sonntags um", selection: weeklySummaryTime, displayedComponents: .hourAndMinute)
                    .foregroundStyle(DS.Colors.textPrimary)
            }
        } header: {
            Text("Wochenrückblick")
                .foregroundStyle(DS.Colors.warmAccent)
                .font(.caption.weight(.semibold))
                .textCase(nil)
        } footer: {
            Text("Sonntagabends ein kurzer Blick auf die Woche und auf die nächste – ohne Bewertung.")
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .listRowBackground(DS.Colors.backgroundSecondary)
    }

    private func handleWeeklySummaryEnabledChange(_ enabled: Bool) {
        guard enabled else {
            NotificationScheduler.shared.cancelWeeklySummary()
            return
        }
        weeklySummaryTimeInterval = weeklySummaryTime.wrappedValue.timeIntervalSinceReferenceDate
        Swift.Task {
            // The in-app summary works without permission; only the nudge needs it.
            if await NotificationScheduler.shared.requestPermission() {
                await MainActor.run {
                    NotificationScheduler.shared.scheduleWeeklySummary(at: weeklySummaryTime.wrappedValue)
                }
            }
        }
    }

    private func handleBriefingTimeChange() {
        guard briefingEnabled else { return }
        NotificationScheduler.shared.scheduleMorningBriefing(at: briefingTime.wrappedValue)
    }

    // MARK: - Debug (DEBUG builds only)

    #if DEBUG
    private var debugSection: some View {
        Section {
            Button {
                clearTodaysBriefingKey()
            } label: {
                Label(briefingKeyCleared ? "Briefing-Sperre gelöscht ✓" : "Heutiges Briefing zurücksetzen",
                      systemImage: "arrow.counterclockwise")
                    .foregroundStyle(DS.Colors.warmAccent)
            }
            Button {
                postWeeklySummaryNow()
            } label: {
                Label(weeklySummaryPosted ? "Wochenrückblick gepostet ✓" : "Wochenrückblick jetzt erzeugen",
                      systemImage: "calendar.badge.clock")
                    .foregroundStyle(DS.Colors.warmAccent)
            }
        } header: {
            Text("Debug")
                .foregroundStyle(DS.Colors.warmAccent)
                .font(.caption.weight(.semibold))
                .textCase(nil)
        } footer: {
            Text("Löscht die Tagessperre, damit das Morgenbriefing beim nächsten App-Start neu erzeugt wird. Nur in DEBUG-Builds sichtbar.")
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .listRowBackground(DS.Colors.backgroundSecondary)
    }

    private func postWeeklySummaryNow() {
        UserDefaults.standard.removeObject(forKey: ProactiveMonitor.weeklySummaryStoreKey(for: Date()))
        ProactiveMonitor().generateWeeklySummary(modelContext: modelContext)
        weeklySummaryPosted = true
    }

    private func clearTodaysBriefingKey() {
        // Mirrors the dedup key in ProactiveMonitor.generateMorningBriefing.
        let dayKey = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date())).prefix(10)
        UserDefaults.standard.removeObject(forKey: "briefing_generated_\(dayKey)")
        briefingKeyCleared = true
    }
    #endif

    // MARK: - API Key

    private var apiKeySection: some View {
        Section {
            if let masked = maskedKey {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundStyle(DS.Colors.textTertiary)
                    Text(masked)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(DS.Colors.textSecondary)
                    Spacer()
                    Button("Löschen", role: .destructive) {
                        showDeleteKeyConfirmation = true
                    }
                    .font(.callout)
                    .buttonStyle(.borderless)
                    .foregroundStyle(DS.Colors.destructive)
                }
                .confirmationDialog(
                    "API-Schlüssel löschen?",
                    isPresented: $showDeleteKeyConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Löschen", role: .destructive, action: deleteKey)
                } message: {
                    Text("DONNA kann danach keine KI-Antworten mehr geben.")
                }
            }

            TextField("Neuen API-Schlüssel eingeben", text: $apiKeyDraft)
                .foregroundStyle(DS.Colors.textPrimary)
                #if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                #endif

            Button("Speichern") { saveKey() }
                .foregroundStyle(DS.Colors.warmAccent)
                .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        } header: {
            Text("KI-Verbindung (Gemini)")
                .foregroundStyle(DS.Colors.warmAccent)
                .font(.caption.weight(.semibold))
                .textCase(nil)
        } footer: {
            Text("Den kostenlosen API-Schlüssel erhältst du unter aistudio.google.com. Er wird ausschließlich sicher im Keychain des Geräts gespeichert.")
                .foregroundStyle(DS.Colors.textTertiary)
        }
        .listRowBackground(DS.Colors.backgroundSecondary)
    }

    // MARK: - Helpers

    private func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainHelper.save(key: Self.keychainKey, value: trimmed)
        apiKeyDraft = ""
        refreshMaskedKey()
    }

    private func deleteKey() {
        KeychainHelper.delete(key: Self.keychainKey)
        maskedKey = nil
        apiKeyDraft = ""
    }

    private func refreshMaskedKey() {
        guard let key = KeychainHelper.load(key: Self.keychainKey), !key.isEmpty else {
            maskedKey = nil
            return
        }
        maskedKey = "••••••\(key.suffix(4))"
    }
}

#Preview {
    SettingsView()
}
