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

    private var dayOccurrences: [RoutineOccurrence] {
        allOccurrences
            .filter { Calendar.current.isDate($0.scheduledDate, inSameDayAs: date) }
            .sorted { $0.scheduledDate < $1.scheduledDate }
    }

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 0) {
                timeLabels
                    .frame(width: timeLabelWidth)

                ZStack(alignment: .topLeading) {
                    gridLines
                    eventOverlays
                    occurrenceOverlays
                }
                .frame(maxWidth: .infinity, minHeight: totalHeight)
                .clipped()
            }
            .padding(.top, 8)
            .padding(.horizontal, DS.Spacing.horizontal)
        }
        .scrollIndicators(.hidden)
        .background(DS.Colors.backgroundPrimary)
        .sheet(item: $selectedEvent) { event in
            NavigationStack { EventDetailView(event: event) }
        }
    }

    // MARK: - Sub-views

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
    private var eventOverlays: some View {
        ForEach(dayEvents) { event in
            let yOff = yOffset(for: event.startTime)
            let h = max(24, eventHeight(start: event.startTime, end: event.endTime))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: DS.Radius.chip)
                    .fill(DS.Colors.backgroundSecondary)
                Rectangle()
                    .fill(DS.Colors.warmAccent)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.Colors.textPrimary)
                        .lineLimit(h > 36 ? 2 : 1)
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
            .frame(maxWidth: .infinity)
            .frame(height: h)
            .offset(y: yOff)
            .padding(.horizontal, 2)
            .onTapGesture { selectedEvent = event }
        }
    }

    @ViewBuilder
    private var occurrenceOverlays: some View {
        ForEach(dayOccurrences) { occ in
            let yOff = yOffset(for: occ.scheduledDate)
            let h = max(24, occurrenceHeight(occ))
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
                .frame(maxWidth: .infinity)
                .frame(height: h)
                .offset(y: yOff)
                .padding(.horizontal, 2)
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

    private func occurrenceHeight(_ occ: RoutineOccurrence) -> CGFloat {
        let minutes = max(15, occ.routine?.durationMinutes ?? 30)
        return CGFloat(minutes) / 60.0 * hourHeight
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
