import SwiftUI
import SwiftData

struct DayView: View {
    let date: Date

    @Query private var allEvents: [CalendarEvent]
    @Query private var allOccurrences: [RoutineOccurrence]
    @State private var selectedEvent: CalendarEvent? = nil

    private let startHour = 6
    private let endHour = 23
    private let hourHeight: CGFloat = 64
    private let timeLabelWidth: CGFloat = 44

    private var totalHeight: CGFloat {
        CGFloat(endHour - startHour + 1) * hourHeight
    }

    private var dayEvents: [CalendarEvent] {
        allEvents
            .filter { Calendar.current.isDate($0.startTime, inSameDayAs: date) }
            .sorted { $0.startTime < $1.startTime }
    }

    /// All-day and annual entries are day markers, not time blocks — they live in a
    /// banner above the grid instead of covering the whole timeline.
    private var allDayEvents: [CalendarEvent] {
        dayEvents.filter { $0.isAnnual || $0.spansWholeDay }
    }

    private var timedEvents: [CalendarEvent] {
        dayEvents.filter { !$0.isAnnual && !$0.spansWholeDay }
    }

    /// Occurrences whose routine was deleted (`routine == nil`) are leftovers and would
    /// otherwise render as anonymous "Routine" blocks.
    private var dayOccurrences: [RoutineOccurrence] {
        allOccurrences
            .filter { $0.routine != nil }
            .filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: date) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    private enum TimelineID: Hashable {
        case event(UUID)
        case occurrence(UUID)
    }

    /// Side-by-side lanes for everything drawn on the grid, events and routines together.
    private var slots: [TimelineID: DayTimelineLayout.Slot] {
        var items = timedEvents.map {
            DayTimelineLayout.Input(id: TimelineID.event($0.id), start: $0.startTime, end: $0.endTime)
        }
        items += dayOccurrences.map {
            DayTimelineLayout.Input(
                id: TimelineID.occurrence($0.id),
                start: $0.scheduledDate,
                end: $0.scheduledDate.addingTimeInterval(TimeInterval(occurrenceMinutes($0) * 60))
            )
        }
        return DayTimelineLayout.slots(for: items, minimumDuration: TimeInterval(24 / hourHeight * 3600))
    }

    private let laneGap: CGFloat = 2

    private var isEmptyToday: Bool {
        Calendar.current.isDateInToday(date) && dayEvents.isEmpty && dayOccurrences.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if !allDayEvents.isEmpty {
                allDayBanner
            }
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    timeLabels
                        .frame(width: timeLabelWidth)

                    ZStack(alignment: .topLeading) {
                        gridLines
                        if isEmptyToday {
                            Text("Kein Termin heute. Schreib mir, was du planst.")
                                .font(DS.Typography.caption)
                                .foregroundStyle(DS.Colors.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, hourHeight * 3 + 20)
                        }
                        GeometryReader { geo in
                            let currentSlots = slots
                            ZStack(alignment: .topLeading) {
                                eventOverlays(width: geo.size.width, slots: currentSlots)
                                occurrenceOverlays(width: geo.size.width, slots: currentSlots)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: totalHeight)
                    .clipped()
                }
                .padding(.top, 8)
                .padding(.horizontal, DS.Spacing.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .background(DS.Colors.backgroundPrimary)
        .sheet(item: $selectedEvent) { event in
            NavigationStack { EventDetailView(event: event) }
        }
    }

    // MARK: - Sub-views

    private var allDayBanner: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("ganzt.")
                .font(.caption2)
                .foregroundStyle(DS.Colors.textTertiary)
                .frame(width: timeLabelWidth, alignment: .trailing)
                .padding(.trailing, 6)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(allDayEvents) { event in
                    HStack(spacing: 6) {
                        if event.isAnnual {
                            Image(systemName: "gift")
                                .font(.caption2)
                                .foregroundStyle(DS.Colors.warmAccent)
                        }
                        Text(event.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DS.Colors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.chip)
                            .fill(DS.Colors.warmAccent.opacity(0.15))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selectedEvent = event }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DS.Spacing.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Colors.separator).frame(height: 1)
        }
    }

    /// Horizontal position and width for an item's lane inside a grid of `width` points.
    private func laneFrame(_ slot: DayTimelineLayout.Slot?, width: CGFloat) -> (x: CGFloat, width: CGFloat) {
        let slot = slot ?? DayTimelineLayout.Slot(column: 0, columnCount: 1)
        let laneWidth = width / CGFloat(slot.columnCount)
        return (CGFloat(slot.column) * laneWidth + laneGap, max(0, laneWidth - laneGap * 2))
    }

    private var timeLabels: some View {
        VStack(spacing: 0) {
            ForEach(startHour...endHour, id: \.self) { hour in
                Text(String(format: "%02d:00", hour))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(DS.Colors.textTertiary)
                    .frame(height: hourHeight, alignment: .top)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 2)
                    .padding(.trailing, 6)
            }
        }
    }

    private var gridLines: some View {
        VStack(spacing: 0) {
            ForEach(startHour...endHour, id: \.self) { _ in
                Rectangle()
                    .fill(DS.Colors.separator)
                    .frame(maxWidth: .infinity)
                    .frame(height: 1)
                Color.clear
                    .frame(height: hourHeight - 1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func eventOverlays(width: CGFloat, slots: [TimelineID: DayTimelineLayout.Slot]) -> some View {
        ForEach(timedEvents) { event in
            let yOff = yOffset(for: event.startTime)
            let h = max(24, eventHeight(start: event.startTime, end: event.endTime))
            let lane = laneFrame(slots[.event(event.id)], width: width)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .fill(DS.Colors.backgroundSecondary)
                Rectangle()
                    .fill(DS.Colors.warmAccent)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if event.recurrence != nil {
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundStyle(DS.Colors.warmAccent)
                        }
                        Text(event.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DS.Colors.textPrimary)
                            .lineLimit(h > 36 ? 2 : 1)
                    }
                    if h > 48 {
                        Text(event.startTime, format: .dateTime.hour().minute())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(DS.Colors.textSecondary)
                    }
                }
                .padding(.leading, 10)
                .padding(.trailing, 6)
                .padding(.vertical, 4)
            }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.chip))
            .frame(width: lane.width, height: h)
            .contentShape(Rectangle())
            .offset(x: lane.x, y: yOff)
            .onTapGesture { selectedEvent = event }
        }
    }

    @ViewBuilder
    private func occurrenceOverlays(width: CGFloat, slots: [TimelineID: DayTimelineLayout.Slot]) -> some View {
        ForEach(dayOccurrences) { occ in
            let yOff = yOffset(for: occ.scheduledDate)
            let h = max(24, occurrenceHeight(occ))
            let lane = laneFrame(slots[.occurrence(occ.id)], width: width)
            RoundedRectangle(cornerRadius: DS.Radius.chip)
                .fill(chipColor(occ))
                .overlay(alignment: .topLeading) {
                    HStack(spacing: 4) {
                        if occ.status == .completed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(DS.Colors.textPrimary.opacity(0.9))
                        }
                        Text(occ.routine?.title ?? "Routine")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(DS.Colors.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .frame(width: lane.width, height: h)
                .offset(x: lane.x, y: yOff)
                .animation(DS.animation, value: occ.status)
        }
    }

    // MARK: - Calculations

    private func yOffset(for date: Date) -> CGFloat {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let totalMinutes = (hour - startHour) * 60 + minute
        return max(0, CGFloat(totalMinutes) / 60.0 * hourHeight)
    }

    private func eventHeight(start: Date, end: Date) -> CGFloat {
        let minutes = max(15.0, end.timeIntervalSince(start) / 60.0)
        return CGFloat(minutes) / 60.0 * hourHeight
    }

    private func occurrenceMinutes(_ occ: RoutineOccurrence) -> Int {
        max(15, occ.routine?.durationMinutes ?? 30)
    }

    private func occurrenceHeight(_ occ: RoutineOccurrence) -> CGFloat {
        CGFloat(occurrenceMinutes(occ)) / 60.0 * hourHeight
    }

    private func chipColor(_ occ: RoutineOccurrence) -> Color {
        switch occ.status {
        case .completed:
            return DS.Colors.success.opacity(0.75)
        case .skipped:
            return DS.Colors.textTertiary.opacity(0.5)
        default:
            guard let cat = occ.routine?.category else { return DS.Colors.warmAccent.opacity(0.7) }
            return DS.Colors.category(cat).opacity(0.85)
        }
    }
}

#Preview {
    let schema = Schema([CalendarEvent.self, RoutineOccurrence.self, Routine.self])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    return DayView(date: .now).modelContainer(container)
}
