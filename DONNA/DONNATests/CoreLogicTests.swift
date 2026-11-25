import XCTest
import SwiftData
@testable import DONNA

/// Headless tests for the logic that was verified by hand on 25.11. — run with
/// `xcodebuild test -scheme DONNA -destination 'platform=macOS'`.
/// Every test uses an in-memory store, so real data is never touched.
@MainActor
final class CoreLogicTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var handler: CommandHandler { CommandHandler(modelContext: context) }

    override func setUp() async throws {
        let schema = Schema([
            DONNATask.self, CalendarEvent.self, Routine.self, RoutineOccurrence.self,
            SleepWindow.self, Preference.self, LearnedProfile.self, ChatMessage.self, ContextMode.self,
        ])
        container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        context = container.mainContext
        DONNAUndoManager.shared.clear()
    }

    private func events() -> [CalendarEvent] { (try? context.fetch(FetchDescriptor<CalendarEvent>())) ?? [] }

    private func date(daysFromNow d: Int, hour: Int, minute: Int = 0) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: Date()))!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    // MARK: Undo

    func testUndoCreateEventDeletesIt() {
        _ = handler.execute(.createEvent(title: "Kino", start: date(daysFromNow: 1, hour: 18), end: date(daysFromNow: 1, hour: 19), locked: false, notes: nil))
        XCTAssertEqual(events().count, 1)
        _ = handler.execute(.undo)
        XCTAssertEqual(events().count, 0)
    }

    func testUndoDeleteEventRestoresSameEvent() {
        _ = handler.execute(.createEvent(title: "Zahnarzt", start: date(daysFromNow: 2, hour: 9), end: date(daysFromNow: 2, hour: 10), locked: true, notes: "x"))
        let original = events()[0]
        let id = original.id
        _ = handler.execute(.deleteEvent(id: id))
        XCTAssertTrue(events().isEmpty)
        _ = handler.execute(.undo)
        let restored = events()
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0].id, id)
        XCTAssertEqual(restored[0].title, "Zahnarzt")
        XCTAssertTrue(restored[0].isLocked)
    }

    func testChatMessagesDoNotOverwritePendingUndo() {
        _ = handler.execute(.createEvent(title: "A", start: date(daysFromNow: 1, hour: 10), end: date(daysFromNow: 1, hour: 11), locked: false, notes: nil))
        _ = handler.execute(.postAssistantMessage(content: "Erledigt.", outputType: .interpretation))
        XCTAssertTrue(DONNAUndoManager.shared.canUndo)
        XCTAssertEqual(DONNAUndoManager.shared.actionLabel, "Termin erstellt")
    }

    // MARK: Series

    func testWeeklySeriesMaterialisesTwelveWeeksAndDeleteFollowingEndsIt() {
        _ = handler.execute(.createEventSeries(title: "Fußball", start: date(daysFromNow: 1, hour: 18), end: date(daysFromNow: 1, hour: 20), locked: false, notes: nil, recurrence: .weekly))
        let series = events().sorted { $0.startTime < $1.startTime }
        XCTAssertGreaterThanOrEqual(series.count, 12)
        XCTAssertEqual(Set(series.compactMap(\.seriesID)).count, 1)

        let cutoff = series[3]
        _ = handler.execute(.deleteEventSeries(seriesID: cutoff.seriesID!, from: cutoff.startTime))
        let remaining = events()
        XCTAssertEqual(remaining.count, 3)
        XCTAssertTrue(remaining.allSatisfy { $0.recurrenceRaw == nil }, "survivors must end the series")

        _ = handler.execute(.extendEventSeries)
        XCTAssertEqual(events().count, 3, "an ended series must not be re-generated")
    }

    func testUndoCreateSeriesRemovesAllInstances() {
        _ = handler.execute(.createEventSeries(title: "Kurs", start: date(daysFromNow: 1, hour: 9), end: date(daysFromNow: 1, hour: 10), locked: false, notes: nil, recurrence: .biweekly))
        XCTAssertFalse(events().isEmpty)
        _ = handler.execute(.undo)
        XCTAssertTrue(events().isEmpty)
    }

    // MARK: Sleep window (was: only protected the night it was created)

    func testSleepWindowProtectsEveryNight() {
        _ = handler.execute(.setSleepWindow(bedtime: date(daysFromNow: 0, hour: 23), wakeTime: date(daysFromNow: 1, hour: 7)))
        let windows = (try? context.fetch(FetchDescriptor<SleepWindow>())) ?? []
        let detector = ConflictDetector()
        let late = detector.checkTimedEvent(start: date(daysFromNow: 40, hour: 23, minute: 30), end: date(daysFromNow: 41, hour: 0, minute: 30), against: [], sleepWindows: windows)
        XCTAssertNotNil(late.blockReason)
        let noon = detector.checkTimedEvent(start: date(daysFromNow: 40, hour: 12), end: date(daysFromNow: 40, hour: 13), against: [], sleepWindows: windows)
        XCTAssertNil(noon.blockReason)
    }

    // MARK: Routines (was: ended after 30 days)

    func testExtendRoutineOccurrencesKeepsThirtyDaysAhead() {
        _ = handler.execute(.createRoutine(definition: RoutineDefinition(title: "Lernen", frequency: .daily, preferredTimeOfDay: date(daysFromNow: 0, hour: 20), durationMinutes: 60)))
        let routine = ((try? context.fetch(FetchDescriptor<Routine>())) ?? [])[0]
        // Simulate the future: drop everything beyond day 5, then extend.
        for occ in routine.occurrences where occ.scheduledDate > date(daysFromNow: 5, hour: 23) { context.delete(occ) }
        try? context.save()
        _ = handler.execute(.extendRoutineOccurrences)
        let latest = routine.occurrences.map(\.scheduledDate).max()!
        XCTAssertGreaterThan(latest, date(daysFromNow: 29, hour: 0))
        let days = routine.occurrences.map { Calendar.current.startOfDay(for: $0.scheduledDate) }
        XCTAssertEqual(days.count, Set(days).count, "no duplicate days")
    }

    // MARK: Recovery day

    func testRecoveryDayMakesTodaysRoutinesOptionalAndUndoRestores() {
        _ = handler.execute(.createRoutine(definition: RoutineDefinition(title: "Sport", frequency: .daily, preferredTimeOfDay: date(daysFromNow: 0, hour: 23, minute: 30), durationMinutes: 15)))
        _ = handler.execute(.startRecoveryDay(date: Date()))
        let today = ((try? context.fetch(FetchDescriptor<RoutineOccurrence>())) ?? [])
            .filter { Calendar.current.isDateInToday($0.scheduledDate) }
        XCTAssertTrue(today.allSatisfy { $0.status == .skipped })
        _ = handler.execute(.undo)
        XCTAssertTrue(today.allSatisfy { $0.status == .scheduled })
    }

    // MARK: Day layout

    func testOverlappingItemsGetSeparateLanes() {
        let a = DayTimelineLayout.Input(id: "A", start: date(daysFromNow: 0, hour: 9), end: date(daysFromNow: 0, hour: 11))
        let b = DayTimelineLayout.Input(id: "B", start: date(daysFromNow: 0, hour: 10), end: date(daysFromNow: 0, hour: 12))
        let c = DayTimelineLayout.Input(id: "C", start: date(daysFromNow: 0, hour: 14), end: date(daysFromNow: 0, hour: 15))
        let slots = DayTimelineLayout.slots(for: [a, b, c])
        XCTAssertEqual(slots["A"], .init(column: 0, columnCount: 2))
        XCTAssertEqual(slots["B"], .init(column: 1, columnCount: 2))
        XCTAssertEqual(slots["C"], .init(column: 0, columnCount: 1))
    }

    // MARK: Proposal editing

    func testProposalDraftKeepsUnshownFieldsAndFixesEndBeforeStart() throws {
        let json = #"{"type":"createEvent","title":"Kino","date":"2027-01-10","startHour":18,"startMinute":0,"endHour":19,"endMinute":0,"isLocked":true,"notes":"Popcorn"}"#
        var draft = try XCTUnwrap(ProposalDraft(json: json))
        draft.start = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: draft.date)!
        let out = try XCTUnwrap(draft.json())
        let dict = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
        XCTAssertEqual(dict["startHour"] as? Int, 21)
        XCTAssertEqual(dict["endHour"] as? Int, 22, "end before start keeps the proposed length")
        XCTAssertEqual(dict["notes"] as? String, "Popcorn")
        XCTAssertEqual(dict["isLocked"] as? Bool, true)
    }
}
