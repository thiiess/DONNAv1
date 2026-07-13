import SwiftUI
import SwiftData

struct EventDetailView: View {
    let event: CalendarEvent

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allEvents: [CalendarEvent]
    @Query private var sleepWindows: [SleepWindow]

    @State private var title: String
    @State private var notes: String
    @State private var displayDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isAllDay: Bool
    @State private var isLocked: Bool
    @State private var isAnnual: Bool
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false
    @State private var showingDeleteConfirmation = false
    @State private var showingLockedDeleteConfirmation = false

    init(event: CalendarEvent) {
        self.event = event
        _title       = State(initialValue: event.title)
        _notes       = State(initialValue: event.notes ?? "")
        _displayDate = State(initialValue: Calendar.current.startOfDay(for: event.startTime))
        _startTime   = State(initialValue: event.startTime)
        _endTime     = State(initialValue: event.endTime)
        _isLocked    = State(initialValue: event.isLocked)
        _isAnnual    = State(initialValue: event.isAnnual)
        let cal = Calendar.current
        let startIsDay = cal.startOfDay(for: event.startTime) == event.startTime
        let endComps = cal.dateComponents([.hour, .minute], from: event.endTime)
        _isAllDay = State(initialValue: startIsDay && endComps.hour == 23 && endComps.minute == 59)
    }

    private var conflict: ConflictResult {
        guard !isAllDay, !isAnnual else { return .none }
        return ConflictDetector().checkTimedEvent(
            start: startTime,
            end: endTime,
            against: allEvents,
            sleepWindows: sleepWindows,
            excludingEventId: event.id
        )
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (isAllDay || endTime > startTime)
            && conflict.blockReason == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            scrollContent
            deleteSection
            footer
        }
        .background(DS.Colors.backgroundPrimary)
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

    // MARK: - Header

    private var sheetHeader: some View {
        Text("Termin bearbeiten")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(DS.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.section) {
                titleField
                chipRow
                if showingDatePicker { datePicker }
                if showingTimePicker && !isAllDay { timePickers }
                conflictBanner
                toggleSection
                notesField
            }
            .padding(.horizontal, DS.Spacing.horizontal)
            .padding(.top, DS.Spacing.section)
            .padding(.bottom, DS.Spacing.section)
        }
    }

    // MARK: - Title

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Titel", text: $title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(DS.Colors.textPrimary)
            Rectangle()
                .fill(DS.Colors.separator)
                .frame(height: 1)
        }
    }

    // MARK: - Chip row

    private var dateChipBg: Color {
        showingDatePicker ? DS.Colors.warmAccent : DS.Colors.warmAccent.opacity(0.15)
    }
    private var dateChipFg: Color {
        showingDatePicker ? .white : DS.Colors.warmAccent
    }
    private var timeChipBg: Color {
        showingTimePicker ? DS.Colors.warmAccent : DS.Colors.warmAccent.opacity(0.15)
    }
    private var timeChipFg: Color {
        if isAllDay { return DS.Colors.warmAccent.opacity(0.35) }
        return showingTimePicker ? .white : DS.Colors.warmAccent
    }

    private var chipRow: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(DS.animation) {
                    showingDatePicker.toggle()
                    if showingDatePicker { showingTimePicker = false }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(displayDate, format: .dateTime.day().month().year())
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(dateChipFg)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(dateChipBg, in: RoundedRectangle(cornerRadius: DS.Radius.chip))
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(DS.animation) {
                    showingTimePicker.toggle()
                    if showingTimePicker { showingDatePicker = false }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(startTime, format: .dateTime.hour().minute())
                    Text("–").opacity(0.5)
                    Text(endTime, format: .dateTime.hour().minute())
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(timeChipFg)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(timeChipBg, in: RoundedRectangle(cornerRadius: DS.Radius.chip))
            }
            .buttonStyle(.plain)
            .disabled(isAllDay)
        }
    }

    // MARK: - Date picker

    private var datePicker: some View {
        DatePicker("", selection: $displayDate, displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(DS.Colors.warmAccent)
            .onChange(of: displayDate) { _, newDate in
                let cal = Calendar.current
                let sh = cal.component(.hour,   from: startTime)
                let sm = cal.component(.minute, from: startTime)
                let eh = cal.component(.hour,   from: endTime)
                let em = cal.component(.minute, from: endTime)
                startTime = cal.date(bySettingHour: sh, minute: sm, second: 0, of: newDate) ?? startTime
                endTime   = cal.date(bySettingHour: eh, minute: em, second: 0, of: newDate) ?? endTime
            }
    }

    // MARK: - Time pickers

    private var timePickers: some View {
        HStack(spacing: DS.Spacing.section) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Von")
                    .font(.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
                DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .onChange(of: startTime) { _, newStart in
                        if endTime <= newStart {
                            endTime = Calendar.current.date(
                                byAdding: .hour, value: 1, to: newStart
                            ) ?? newStart
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Bis")
                    .font(.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
                DatePicker("", selection: $endTime, in: startTime..., displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
            }
            Spacer()
        }
    }

    // MARK: - Conflict banner

    @ViewBuilder
    private var conflictBanner: some View {
        if let reason = conflict.blockReason {
            ConflictWarningBanner(message: reason, isBlocking: true)
        } else if let warning = conflict.overlapWarning {
            ConflictWarningBanner(message: warning, isBlocking: false)
        }
    }

    // MARK: - Toggles

    private var toggleSection: some View {
        VStack(spacing: 0) {
            Toggle("Ganztägig", isOn: $isAllDay.animation())
                .tint(DS.Colors.warmAccent)
                .foregroundStyle(isAnnual ? DS.Colors.textTertiary : DS.Colors.textPrimary)
                .padding(.vertical, 12)
                .disabled(isAnnual)
                .onChange(of: isAllDay) { _, allDay in
                    if allDay { showingTimePicker = false }
                }
            Divider()
            Toggle("Gesperrt (nicht verschiebbar)", isOn: $isLocked)
                .tint(DS.Colors.warmAccent)
                .foregroundStyle(isAnnual ? DS.Colors.textTertiary : DS.Colors.textPrimary)
                .padding(.vertical, 12)
                .disabled(isAnnual)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Toggle("Jahrestag", isOn: $isAnnual.animation())
                    .tint(DS.Colors.warmAccent)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .padding(.top, 12)
                    .onChange(of: isAnnual) { _, annual in
                        if annual {
                            isAllDay = true
                            isLocked = true
                            showingTimePicker = false
                        }
                    }
                Text("Wiederholt sich jährlich")
                    .font(.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
                    .padding(.bottom, 12)
                    .opacity(isAnnual ? 1 : 0)
            }
        }
    }

    // MARK: - Notes

    private var notesField: some View {
        ZStack(alignment: .topLeading) {
            if notes.isEmpty {
                Text("Notizen")
                    .font(.body)
                    .foregroundStyle(DS.Colors.textTertiary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $notes)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 80)
        }
    }

    // MARK: - Delete section

    private var deleteSection: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                if event.isLocked {
                    showingLockedDeleteConfirmation = true
                } else {
                    showingDeleteConfirmation = true
                }
            } label: {
                Text("Termin löschen")
                    .foregroundStyle(DS.Colors.destructive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Abbrechen") { dismiss() }
                    .foregroundStyle(DS.Colors.textSecondary)
                    .buttonStyle(.plain)
                Spacer()
                Button("Speichern") {
                    save()
                }
                .disabled(!canSave)
                .buttonStyle(.borderedProminent)
                .tint(DS.Colors.warmAccent)
            }
            .padding(.horizontal, DS.Spacing.horizontal)
            .padding(.vertical, 12)
        }
        .background(DS.Colors.backgroundPrimary)
    }

    // MARK: - Actions

    private func save() {
        var changes = EventChanges()
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let cal = Calendar.current
        let actualStart: Date
        let actualEnd: Date
        if isAllDay {
            actualStart = cal.startOfDay(for: displayDate)
            actualEnd   = cal.date(bySettingHour: 23, minute: 59, second: 0, of: displayDate) ?? displayDate
        } else {
            actualStart = startTime
            actualEnd   = endTime
        }
        guard isAllDay || actualEnd > actualStart else { return }

        changes.title     = .set(trimmed)
        changes.startTime = .set(actualStart)
        changes.endTime   = .set(actualEnd)
        changes.isLocked  = .set(isLocked)
        changes.isAnnual  = .set(isAnnual)
        changes.notes     = notes.isEmpty ? .clear : .set(notes)
        let result = CommandHandler(modelContext: modelContext).execute(.updateEvent(id: event.id, changes: changes))
        // A block leaves the sheet open so the edit isn't silently dropped — the banner
        // above already explains why.
        if case .blocked = result { return }
        dismiss()
    }

    private func deleteEvent() {
        _ = CommandHandler(modelContext: modelContext).execute(.deleteEvent(id: event.id))
        dismiss()
    }
}

#Preview {
    let schema = Schema([CalendarEvent.self, SleepWindow.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    let event = CalendarEvent(title: "Team Meeting",
                              startTime: Date(),
                              endTime: Date().addingTimeInterval(3600))
    container.mainContext.insert(event)
    return EventDetailView(event: event).modelContainer(container)
}
