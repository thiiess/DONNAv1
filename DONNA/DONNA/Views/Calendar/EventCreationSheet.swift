import SwiftUI
import SwiftData

struct EventCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query private var allEvents: [CalendarEvent]
    @Query private var sleepWindows: [SleepWindow]

    @State private var title = ""
    @State private var displayDate: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var isAllDay = false
    @State private var isLocked = false
    @State private var isAnnual = false
    @State private var notes = ""
    @State private var showingDatePicker = false
    @State private var showingTimePicker = false

    /// `initialDate` anchors the new event to the day the user is currently looking at;
    /// the time of day still defaults to the next full hour.
    init(initialDate: Date = .now) {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: initialDate)
        comps.minute = 0
        comps.hour = cal.component(.hour, from: .now) + 1
        let start = cal.date(from: comps) ?? initialDate
        let end   = cal.date(byAdding: .hour, value: 1, to: start) ?? start
        _displayDate = State(initialValue: cal.startOfDay(for: start))
        _startTime   = State(initialValue: start)
        _endTime     = State(initialValue: end)
    }

    private var conflict: ConflictResult {
        guard !isAllDay, !isAnnual else { return .none }
        return ConflictDetector().checkTimedEvent(
            start: startTime,
            end: endTime,
            against: allEvents,
            sleepWindows: sleepWindows
        )
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && conflict.blockReason == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider()
            scrollContent
            footer
        }
        .background(DS.Colors.backgroundPrimary)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        Text("Neuer Termin")
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

    // MARK: - Date + Time chips

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

    // MARK: - Inline date picker

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

    // MARK: - Inline time pickers

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

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack {
                Button("Abbrechen") { dismiss() }
                    .foregroundStyle(DS.Colors.textSecondary)
                    .buttonStyle(.plain)

                Spacer()

                Button("Hinzufügen") {
                    save()
                    dismiss()
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

    // MARK: - Save

    private func save() {
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

        _ = CommandHandler(modelContext: modelContext).execute(
            .createEvent(
                title:    trimmed,
                start:    actualStart,
                end:      actualEnd,
                locked:   isLocked,
                notes:    notes.isEmpty ? nil : notes,
                isAnnual: isAnnual
            )
        )
    }
}

#Preview {
    let schema = Schema([CalendarEvent.self, SleepWindow.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return EventCreationSheet().modelContainer(container)
}
