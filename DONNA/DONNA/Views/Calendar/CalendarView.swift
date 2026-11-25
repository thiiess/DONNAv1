import SwiftUI
import SwiftData

// MARK: - Calendar Mode

private enum CalendarMode: String, CaseIterable {
    case day   = "Tag"
    case week  = "Woche"
    case month = "Monat"
}

// MARK: - CalendarView

struct CalendarView: View {
    @State private var selectedDate: Date = .now
    @State private var calendarMode: CalendarMode = .day
    @State private var showingCreationSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Ansicht", selection: $calendarMode) {
                    ForEach(CalendarMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, DS.Spacing.horizontal)
                .padding(.vertical, 8)
                .background(DS.Colors.appBackground)

                navHeader

                Rectangle()
                    .fill(DS.Colors.separator)
                    .frame(height: 1)

                switch calendarMode {
                case .day:
                    DayView(date: selectedDate)
                        .background(DS.Colors.appBackground)
                case .week:
                    WeekView(weekStart: weekStart)
                        .background(DS.Colors.appBackground)
                case .month:
                    MonthView(month: selectedDate) { day in
                        // Tapping a day opens it in the day view.
                        withAnimation(DS.animation) {
                            selectedDate = day
                            calendarMode = .day
                        }
                    }
                    .background(DS.Colors.appBackground)
                }
            }
            .background(DS.Colors.appBackground)
            .navigationTitle("Kalender")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DS.Colors.appBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreationSheet = true } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(DS.Colors.warmAccent)
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Heute") {
                        withAnimation(DS.animation) { selectedDate = .now }
                    }
                    .foregroundStyle(DS.Colors.warmAccent)
                }
            }
            .sheet(isPresented: $showingCreationSheet) {
                EventCreationSheet(initialDate: selectedDate)
            }
        }
    }

    // MARK: - Navigation Header

    private var navHeader: some View {
        HStack {
            Button {
                withAnimation(DS.animation) { selectedDate = shift(by: -1) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .padding(8)
            }
            .buttonStyle(.plain)

            Spacer()

            switch calendarMode {
            case .day:
                VStack(spacing: 3) {
                    Text(selectedDate, format: .dateTime.weekday(.wide))
                        .font(DS.Typography.caption)
                        .foregroundStyle(DS.Colors.textSecondary)
                    Text(selectedDate, format: .dateTime.day().month(.wide).year())
                        .font(DS.Typography.subheading)
                        .foregroundStyle(DS.Colors.textPrimary)
                        .fontDesign(.default)
                        .monospacedDigit()
                }
            case .week:
                Text(weekRangeLabel)
                    .font(DS.Typography.subheading)
                    .foregroundStyle(DS.Colors.textPrimary)
                    .monospacedDigit()
            case .month:
                Text(selectedDate, format: .dateTime.month(.wide).year())
                    .font(DS.Typography.subheading)
                    .foregroundStyle(DS.Colors.textPrimary)
            }

            Spacer()

            Button {
                withAnimation(DS.animation) { selectedDate = shift(by: 1) }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .foregroundStyle(DS.Colors.textSecondary)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.horizontal)
        .padding(.vertical, 10)
        .background(DS.Colors.appBackground)
    }

    // MARK: - Helpers

    private var weekStart: Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: selectedDate)) ?? selectedDate
    }

    private var weekRangeLabel: String {
        let cal = Calendar.current
        guard let weekEnd = cal.date(byAdding: .day, value: 6, to: weekStart) else {
            return weekStart.formatted(.dateTime.month(.abbreviated).day())
        }
        let start = weekStart.formatted(.dateTime.month(.abbreviated).day())
        let end   = weekEnd.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(start) – \(end)"
    }

    private func shift(by value: Int) -> Date {
        let cal = Calendar.current
        switch calendarMode {
        case .day:   return cal.date(byAdding: .day,   value: value,      to: selectedDate) ?? selectedDate
        case .week:  return cal.date(byAdding: .day,   value: value * 7,  to: selectedDate) ?? selectedDate
        case .month: return cal.date(byAdding: .month, value: value,      to: selectedDate) ?? selectedDate
        }
    }
}

// MARK: - WeekView

private struct WeekView: View {
    let weekStart: Date

    @Query private var allEvents: [CalendarEvent]
    @Query private var allOccurrences: [RoutineOccurrence]
    @State private var selectedEvent: CalendarEvent? = nil

    private var days: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    WeekDayRow(day: day,
                               events: eventsOn(day),
                               occurrences: occurrencesOn(day),
                               onEventTap: { selectedEvent = $0 })
                    Rectangle()
                        .fill(DS.Colors.separator)
                        .frame(height: 1)
                }
            }
        }
        .scrollIndicators(.hidden)
        .sheet(item: $selectedEvent) { event in
            NavigationStack { EventDetailView(event: event) }
        }
    }

    private func eventsOn(_ day: Date) -> [CalendarEvent] {
        allEvents
            .filter { Calendar.current.isDate($0.startTime, inSameDayAs: day) }
            .sorted { $0.startTime < $1.startTime }
    }

    private func occurrencesOn(_ day: Date) -> [RoutineOccurrence] {
        allOccurrences
            .filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: day) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }
}

private struct WeekDayRow: View {
    let day: Date
    let events: [CalendarEvent]
    let occurrences: [RoutineOccurrence]
    let onEventTap: (CalendarEvent) -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day, format: .dateTime.weekday(.wide).day().month(.abbreviated))
                .font(.caption.weight(.semibold))
                .foregroundStyle(isToday ? DS.Colors.warmAccent : DS.Colors.textSecondary)

            if events.isEmpty && occurrences.isEmpty {
                Text("No events")
                    .font(.caption)
                    .foregroundStyle(DS.Colors.textTertiary)
            } else {
                ForEach(events) { event in
                    HStack(spacing: 6) {
                        Circle().fill(DS.Colors.warmAccent).frame(width: 6, height: 6)
                        Text(event.title).font(.caption).foregroundStyle(DS.Colors.textPrimary)
                        Spacer()
                        Text(event.startTime, format: .dateTime.hour().minute())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onEventTap(event) }
                }
                ForEach(occurrences) { occ in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(occ.status == .completed ? DS.Colors.success : DS.Colors.textTertiary)
                            .frame(width: 6, height: 6)
                        Text(occ.routine?.title ?? "Routine")
                            .font(.caption)
                            .foregroundStyle(DS.Colors.textPrimary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Spacing.horizontal)
        .padding(.vertical, 10)
        .background(isToday ? DS.Colors.warmAccent.opacity(0.06) : Color.clear)
    }
}

// MARK: - MonthView

private struct MonthView: View {
    let month: Date
    var onSelectDay: (Date) -> Void = { _ in }

    @Query private var allEvents: [CalendarEvent]
    @Query private var allOccurrences: [RoutineOccurrence]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    /// German two-letter weekday names, rotated to the calendar's first weekday so the
    /// header lines up with `gridDays` (Monday-first in German regions, Sunday-first in US).
    private var weekdaySymbols: [String] {
        let symbols = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let first = Calendar.current.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        VStack(spacing: 0) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DS.Colors.textTertiary)
                        .frame(height: 28)
                }
            }
            .padding(.horizontal, DS.Spacing.horizontal)

            Rectangle().fill(DS.Colors.separator).frame(height: 1)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(gridDays.indices, id: \.self) { i in
                        if let day = gridDays[i] {
                            MonthDayCell(day: day, hasEvents: hasActivity(on: day))
                                .contentShape(Rectangle())
                                .onTapGesture { onSelectDay(day) }
                        } else {
                            Color.clear.frame(height: 44)
                        }
                    }
                }
                .padding(.horizontal, DS.Spacing.horizontal)
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var gridDays: [Date?] {
        let cal = Calendar.current
        guard
            let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: month)),
            let range = cal.range(of: .day, in: .month, for: month)
        else { return [] }

        let firstWeekday = (cal.component(.weekday, from: firstDay) - cal.firstWeekday + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: firstWeekday)
        for offset in 0..<range.count {
            days.append(cal.date(byAdding: .day, value: offset, to: firstDay))
        }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private func hasActivity(on day: Date) -> Bool {
        let cal = Calendar.current
        return allEvents.contains { cal.isDate($0.startTime, inSameDayAs: day) }
            || allOccurrences.contains { cal.isDate($0.scheduledDate, inSameDayAs: day) }
    }
}

private struct MonthDayCell: View {
    let day: Date
    let hasEvents: Bool

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        VStack(spacing: 2) {
            Text(day, format: .dateTime.day())
                .font(.caption.monospacedDigit())
                .foregroundStyle(isToday ? DS.Colors.appBackground : DS.Colors.textPrimary)
                .frame(width: 28, height: 28)
                .background(isToday ? DS.Colors.warmAccent : Color.clear, in: Circle())

            Circle()
                .fill(hasEvents ? DS.Colors.warmAccent : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(height: 44)
    }
}

// MARK: - Preview

#Preview {
    let schema = Schema([CalendarEvent.self, RoutineOccurrence.self, Routine.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return CalendarView().modelContainer(container)
}
