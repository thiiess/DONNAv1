// NOTE: Add this file to a new "DONNATests" XCTest target in Xcode (File → New → Target → Unit Testing Bundle).
// No changes to any existing file are required.

import XCTest
@testable import DONNA

final class ScienceEngineTests: XCTestCase {

    let engine = ScienceEngine()

    // MARK: Helpers

    private func date(daysAgo: Int = 0, hour: Int = 10, minute: Int = 0) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let base = cal.date(byAdding: .day, value: -daysAgo, to: today)!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: base)!
    }

    private func sportSession(
        title: String,
        daysAgo: Int = 0,
        hour: Int = 10,
        durationMinutes: Int = 60,
        isIntense: Bool = true
    ) -> SportSessionSnapshot {
        let start = date(daysAgo: daysAgo, hour: hour)
        return SportSessionSnapshot(
            id: UUID(),
            title: title,
            date: start,
            startTime: start,
            endTime: start.addingTimeInterval(Double(durationMinutes) * 60),
            durationMinutes: durationMinutes,
            isIntense: isIntense
        )
    }

    private func sleepWindow(
        bedHour: Int = 23,
        wakeHour: Int = 7,
        daysAgo: Int = 0,
        isProtected: Bool = true
    ) -> ScienceSleepSnapshot {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: Date()))!
        let bed = cal.date(bySettingHour: bedHour, minute: 0, second: 0, of: day)!
        let wake = cal.date(bySettingHour: wakeHour, minute: 0, second: 0, of: day)!
        return ScienceSleepSnapshot(date: day, bedtime: bed, wakeTime: wake, isProtected: isProtected)
    }

    private func learningSession(
        daysAgo: Int = 0,
        startHour: Int = 14,
        durationMinutes: Int = 60,
        hasPlannedBreak: Bool = false,
        endHour: Int? = nil
    ) -> LearningSessionSnapshot {
        let start = date(daysAgo: daysAgo, hour: startHour)
        let computedEnd = endHour.map { date(daysAgo: daysAgo, hour: $0) }
            ?? start.addingTimeInterval(Double(durationMinutes) * 60)
        return LearningSessionSnapshot(
            id: UUID(),
            title: "Lernen",
            date: start,
            startTime: start,
            endTime: computedEnd,
            durationMinutes: durationMinutes,
            hasPlannedBreak: hasPlannedBreak
        )
    }

    private func activity(category: RoutineCategory, startHour: Int, durationMinutes: Int) -> ActivityBlockSnapshot {
        let start = date(hour: startHour)
        let end = start.addingTimeInterval(Double(durationMinutes) * 60)
        return ActivityBlockSnapshot(startTime: start, endTime: end, category: category)
    }

    // MARK: - Sport Rule 1: Same Muscle Group < 48 h

    func testSameMuscleGroup_triggersWarning() {
        let recent = sportSession(title: "Beintraining", daysAgo: 1, isIntense: true)
        let planned = sportSession(title: "Kniebeugen", daysAgo: 0)
        let result = engine.checkSameMuscleGroup(plannedSession: planned, recentSessions: [recent])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .warning)
        XCTAssertEqual(result?.category, .sport)
    }

    func testSameMuscleGroup_noWarningWhenNotIntense() {
        let recent = sportSession(title: "Beintraining", daysAgo: 1, isIntense: false)
        let planned = sportSession(title: "Kniebeugen", daysAgo: 0)
        let result = engine.checkSameMuscleGroup(plannedSession: planned, recentSessions: [recent])
        XCTAssertNil(result)
    }

    func testSameMuscleGroup_noWarningWhenOver48h() {
        let recent = sportSession(title: "Beintraining", daysAgo: 3, isIntense: true)
        let planned = sportSession(title: "Kniebeugen", daysAgo: 0)
        let result = engine.checkSameMuscleGroup(plannedSession: planned, recentSessions: [recent])
        XCTAssertNil(result)
    }

    func testSameMuscleGroup_noWarningForDifferentGroup() {
        let recent = sportSession(title: "Bankdrücken", daysAgo: 1, isIntense: true) // upper
        let planned = sportSession(title: "Kniebeugen", daysAgo: 0) // legs
        let result = engine.checkSameMuscleGroup(plannedSession: planned, recentSessions: [recent])
        XCTAssertNil(result)
    }

    // MARK: - Sport Rule 2: > 6 Sessions/Week Without Rest Day

    func testWeeklySessionCount_triggersWhenSevenDays() {
        let sessions = (0..<7).map { sportSession(title: "Laufen", daysAgo: $0) }
        let result = engine.checkWeeklySessionCount(sessionsLastSevenDays: sessions)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .warning)
    }

    func testWeeklySessionCount_noWarningSixDays() {
        let sessions = (0..<6).map { sportSession(title: "Laufen", daysAgo: $0) }
        let result = engine.checkWeeklySessionCount(sessionsLastSevenDays: sessions)
        XCTAssertNil(result)
    }

    func testWeeklySessionCount_noWarningWithRestDay() {
        // 7 sessions but only 6 unique days (two sessions on day 0)
        var sessions = (0..<6).map { sportSession(title: "Laufen", daysAgo: $0) }
        sessions.append(sportSession(title: "Kraft", daysAgo: 0, hour: 17)) // same day, different time
        let result = engine.checkWeeklySessionCount(sessionsLastSevenDays: sessions)
        XCTAssertNil(result)
    }

    // MARK: - Sport Rule 3: Cardio + Strength Same Day

    func testCardioAndStrength_triggersInfoWithoutBreak() {
        let cardio = SportSessionSnapshot(
            id: UUID(), title: "Laufen", date: date(hour: 8),
            startTime: date(hour: 8), endTime: date(hour: 9),
            durationMinutes: 60, isIntense: true
        )
        let strength = SportSessionSnapshot(
            id: UUID(), title: "Krafttraining", date: date(hour: 9, minute: 10),
            startTime: date(hour: 9, minute: 10), endTime: date(hour: 10, minute: 10),
            durationMinutes: 60, isIntense: true
        )
        let result = engine.checkCardioAndStrengthSameDay(sessionsToday: [cardio, strength])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .info)
    }

    func testCardioAndStrength_noWarningWithAdequateBreak() {
        let cardio = SportSessionSnapshot(
            id: UUID(), title: "Laufen", date: date(hour: 7),
            startTime: date(hour: 7), endTime: date(hour: 8),
            durationMinutes: 60, isIntense: true
        )
        let strength = SportSessionSnapshot(
            id: UUID(), title: "Krafttraining", date: date(hour: 9, minute: 30),
            startTime: date(hour: 9, minute: 30), endTime: date(hour: 10, minute: 30),
            durationMinutes: 60, isIntense: true
        )
        let result = engine.checkCardioAndStrengthSameDay(sessionsToday: [cardio, strength])
        XCTAssertNil(result)
    }

    func testCardioAndStrength_noWarningCardioOnly() {
        let sessions = [sportSession(title: "Laufen")]
        let result = engine.checkCardioAndStrengthSameDay(sessionsToday: sessions)
        XCTAssertNil(result)
    }

    // MARK: - Sport Rule 4: Leg Training After Running

    func testLegAfterRunning_triggersWarning() {
        let yesterday = [sportSession(title: "Fußball", daysAgo: 1)]
        let planned = sportSession(title: "Beintraining")
        let result = engine.checkLegTrainingAfterRunning(plannedSession: planned, yesterdaySessions: yesterday)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .warning)
    }

    func testLegAfterRunning_noWarningForUpperBody() {
        let yesterday = [sportSession(title: "Fußball", daysAgo: 1)]
        let planned = sportSession(title: "Bankdrücken")
        let result = engine.checkLegTrainingAfterRunning(plannedSession: planned, yesterdaySessions: yesterday)
        XCTAssertNil(result)
    }

    func testLegAfterRunning_noWarningWhenYesterdayNoRunning() {
        let yesterday = [sportSession(title: "Krafttraining", daysAgo: 1)]
        let planned = sportSession(title: "Kniebeugen")
        let result = engine.checkLegTrainingAfterRunning(plannedSession: planned, yesterdaySessions: yesterday)
        XCTAssertNil(result)
    }

    // MARK: - Sleep Rule 1: < 6 h Sleep

    func testShortSleep_triggersWarning() {
        let sw = sleepWindow(bedHour: 2, wakeHour: 6) // 4 h
        let result = engine.checkShortSleep(sleepWindow: sw)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .warning)
        XCTAssertEqual(result?.category, .sleep)
    }

    func testShortSleep_noWarningWith7h() {
        let sw = sleepWindow(bedHour: 23, wakeHour: 6) // 7 h
        let result = engine.checkShortSleep(sleepWindow: sw)
        XCTAssertNil(result)
    }

    func testShortSleep_noWarningExactly6h() {
        let sw = sleepWindow(bedHour: 1, wakeHour: 7) // 6 h
        let result = engine.checkShortSleep(sleepWindow: sw)
        XCTAssertNil(result)
    }

    // MARK: - Sleep Rule 2: Consecutive Short Sleep

    func testConsecutiveShortSleep_triggersCriticalAfter3Days() {
        let windows = (0..<4).map { sleepWindow(bedHour: 3, wakeHour: 6, daysAgo: $0) } // 3 h each
        let result = engine.checkConsecutiveShortSleep(recentSleepWindows: windows)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .critical)
    }

    func testConsecutiveShortSleep_noWarningWhenBroken() {
        var windows = (0..<3).map { sleepWindow(bedHour: 3, wakeHour: 6, daysAgo: $0) }
        windows.append(sleepWindow(bedHour: 23, wakeHour: 7, daysAgo: 3)) // 8 h breaks streak
        let result = engine.checkConsecutiveShortSleep(recentSleepWindows: windows)
        XCTAssertNil(result)
    }

    func testConsecutiveShortSleep_noWarningFor2Days() {
        let windows = (0..<2).map { sleepWindow(bedHour: 3, wakeHour: 6, daysAgo: $0) }
        let result = engine.checkConsecutiveShortSleep(recentSleepWindows: windows)
        XCTAssertNil(result)
    }

    // MARK: - Sleep Rule 3: Circadian Variation

    func testCircadianVariation_triggersInfoWithHighVariation() {
        // Bedtimes: 22:00, 22:00, 00:30, 22:00 → 00:30 deviates > 90 min from avg ~22:07
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func sw(_ bedHour: Int, _ bedMin: Int, daysAgo: Int) -> ScienceSleepSnapshot {
            let d = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            let bed = cal.date(bySettingHour: bedHour, minute: bedMin, second: 0, of: d)!
            let wake = cal.date(bySettingHour: 7, minute: 0, second: 0, of: d)!
            return ScienceSleepSnapshot(date: d, bedtime: bed, wakeTime: wake, isProtected: true)
        }
        let windows = [sw(22, 0, daysAgo: 0), sw(22, 0, daysAgo: 1), sw(0, 30, daysAgo: 2), sw(22, 0, daysAgo: 3)]
        let result = engine.checkCircadianVariation(recentSleepWindows: windows)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .info)
    }

    func testCircadianVariation_noWarningWithStableSchedule() {
        let windows = (0..<7).map { sleepWindow(bedHour: 23, wakeHour: 7, daysAgo: $0) }
        let result = engine.checkCircadianVariation(recentSleepWindows: windows)
        XCTAssertNil(result)
    }

    func testCircadianVariation_noWarningWithFewDataPoints() {
        let windows = (0..<2).map { sleepWindow(bedHour: 23, wakeHour: 7, daysAgo: $0) }
        let result = engine.checkCircadianVariation(recentSleepWindows: windows)
        XCTAssertNil(result)
    }

    // MARK: - Sleep Rule 4: Routine In Sleep Window

    func testRoutineInSleepWindow_triggersCritical() {
        let sw = sleepWindow(bedHour: 23, wakeHour: 7)
        let occ = PlannedOccurrenceSnapshot(
            routineId: UUID(),
            category: .sport,
            title: "Yoga",
            startTime: date(hour: 23, minute: 30),
            durationMinutes: 30
        )
        let result = engine.checkRoutineInSleepWindow(occurrence: occ, sleepWindow: sw)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .critical)
    }

    func testRoutineInSleepWindow_noWarningWhenNotProtected() {
        let sw = ScienceSleepSnapshot(
            date: Calendar.current.startOfDay(for: Date()),
            bedtime: date(hour: 23),
            wakeTime: date(hour: 7),
            isProtected: false
        )
        let occ = PlannedOccurrenceSnapshot(
            routineId: UUID(), category: .sport, title: "Yoga",
            startTime: date(hour: 23, minute: 30), durationMinutes: 30
        )
        let result = engine.checkRoutineInSleepWindow(occurrence: occ, sleepWindow: sw)
        XCTAssertNil(result)
    }

    func testRoutineInSleepWindow_noWarningBeforeSleepTime() {
        let sw = sleepWindow(bedHour: 23, wakeHour: 7)
        let occ = PlannedOccurrenceSnapshot(
            routineId: UUID(), category: .sport, title: "Yoga",
            startTime: date(hour: 20), durationMinutes: 60
        )
        let result = engine.checkRoutineInSleepWindow(occurrence: occ, sleepWindow: sw)
        XCTAssertNil(result)
    }

    // MARK: - Learning Rule 1: Long Block Without Break

    func testLongLearningBlock_triggersInfo() {
        let session = learningSession(durationMinutes: 120, hasPlannedBreak: false)
        let result = engine.checkLongLearningBlock(session: session)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .info)
        XCTAssertEqual(result?.category, .learning)
    }

    func testLongLearningBlock_noWarningWithBreak() {
        let session = learningSession(durationMinutes: 120, hasPlannedBreak: true)
        let result = engine.checkLongLearningBlock(session: session)
        XCTAssertNil(result)
    }

    func testLongLearningBlock_noWarningFor90min() {
        let session = learningSession(durationMinutes: 90, hasPlannedBreak: false)
        let result = engine.checkLongLearningBlock(session: session)
        XCTAssertNil(result)
    }

    // MARK: - Learning Rule 2: Learning Before Sleep

    func testLearningBeforeSleep_triggersInfo() {
        let sw = sleepWindow(bedHour: 23, wakeHour: 7)
        let session = learningSession(startHour: 22, durationMinutes: 50, endHour: 22)
        // endTime = 22:50, bedtime = 23:00 → 10 min gap
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(bySettingHour: 22, minute: 50, second: 0, of: today)!
        let s = LearningSessionSnapshot(
            id: UUID(), title: "Lernen", date: today,
            startTime: cal.date(bySettingHour: 22, minute: 0, second: 0, of: today),
            endTime: start,
            durationMinutes: 50
        )
        let result = engine.checkLearningBeforeSleep(session: s, sleepWindow: sw)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .info)
    }

    func testLearningBeforeSleep_noWarningWith60minGap() {
        let sw = sleepWindow(bedHour: 23, wakeHour: 7)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let endTime = cal.date(bySettingHour: 22, minute: 0, second: 0, of: today)!
        let s = LearningSessionSnapshot(
            id: UUID(), title: "Lernen", date: today,
            startTime: cal.date(bySettingHour: 21, minute: 0, second: 0, of: today),
            endTime: endTime,
            durationMinutes: 60
        )
        let result = engine.checkLearningBeforeSleep(session: s, sleepWindow: sw)
        XCTAssertNil(result)
    }

    // MARK: - Learning Rule 3: Learning Absence

    func testLearningAbsence_triggersWarning() {
        let result = engine.checkLearningAbsence(
            hasActiveLearningRoutine: true,
            recentLearningDates: [],
            today: Date()
        )
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .warning)
    }

    func testLearningAbsence_noWarningNoActiveRoutine() {
        let result = engine.checkLearningAbsence(
            hasActiveLearningRoutine: false,
            recentLearningDates: [],
            today: Date()
        )
        XCTAssertNil(result)
    }

    func testLearningAbsence_noWarningWithRecentSession() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let result = engine.checkLearningAbsence(
            hasActiveLearningRoutine: true,
            recentLearningDates: [yesterday],
            today: Date()
        )
        XCTAssertNil(result)
    }

    func testLearningAbsence_triggersWhenLastSessionWas4DaysAgo() {
        let fourDaysAgo = Calendar.current.date(byAdding: .day, value: -4, to: Date())!
        let result = engine.checkLearningAbsence(
            hasActiveLearningRoutine: true,
            recentLearningDates: [fourDaysAgo],
            today: Date()
        )
        XCTAssertNotNil(result)
    }

    // MARK: - General Rule 1: Daily Overload

    func testDailyOverload_triggersWarning() {
        let activities = [
            activity(category: .sport, startHour: 8, durationMinutes: 360),   // 6 h
            activity(category: .learning, startHour: 15, durationMinutes: 300) // 5 h
        ]
        let result = engine.checkDailyOverload(activities: activities)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .warning)
        XCTAssertEqual(result?.category, .custom)
    }

    func testDailyOverload_noWarningUnder10h() {
        let activities = [
            activity(category: .sport, startHour: 8, durationMinutes: 300),   // 5 h
            activity(category: .learning, startHour: 14, durationMinutes: 90) // 1.5 h
        ]
        let result = engine.checkDailyOverload(activities: activities)
        XCTAssertNil(result)
    }

    // MARK: - General Rule 2: No Recovery Time

    func testNoRecoveryTime_triggersWarning() {
        let a1 = activity(category: .sport, startHour: 8, durationMinutes: 60)   // ends 9:00
        let a2 = activity(category: .learning, startHour: 9, durationMinutes: 60) // starts 9:00 → 0 min gap
        let result = engine.checkNoRecoveryTime(activities: [a1, a2])
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.severity, .warning)
    }

    func testNoRecoveryTime_noWarningWithAdequateGap() {
        let a1 = activity(category: .sport, startHour: 8, durationMinutes: 60)    // ends 9:00
        let a2 = activity(category: .learning, startHour: 9, durationMinutes: 60) // wait, starts 9:00 — 0 min
        // Use a proper 20-min gap
        let start2 = date(hour: 9, minute: 20)
        let end2 = start2.addingTimeInterval(60 * 60)
        let b2 = ActivityBlockSnapshot(startTime: start2, endTime: end2, category: .learning)
        let result = engine.checkNoRecoveryTime(activities: [a1, b2])
        XCTAssertNil(result)
    }

    func testNoRecoveryTime_ignoreSleepAndSkincare() {
        let a1 = activity(category: .sleep, startHour: 8, durationMinutes: 60)
        let a2 = activity(category: .skincare, startHour: 9, durationMinutes: 30)
        let result = engine.checkNoRecoveryTime(activities: [a1, a2])
        XCTAssertNil(result) // sleep and skincare not counted as demanding
    }

    // MARK: - Localization

    func testLocalizationDE() {
        let sw = sleepWindow(bedHour: 3, wakeHour: 6)
        let warning = engine.checkShortSleep(sleepWindow: sw)!
        // Just verify both languages are non-empty
        XCTAssertFalse(warning.message.de.isEmpty)
        XCTAssertFalse(warning.message.en.isEmpty)
        XCTAssertNotEqual(warning.message.de, warning.message.en)
    }

    func testSuggestionPresent() {
        let sw = sleepWindow(bedHour: 3, wakeHour: 6)
        let warning = engine.checkShortSleep(sleepWindow: sw)!
        XCTAssertNotNil(warning.suggestion)
        XCTAssertFalse(warning.suggestion!.de.isEmpty)
        XCTAssertFalse(warning.suggestion!.en.isEmpty)
    }

    // MARK: - checkAll integration

    func testCheckAll_returnsMultipleWarnings() {
        // Short sleep + learning absence + overload all in one call
        let shortSleep = sleepWindow(bedHour: 3, wakeHour: 6)
        let overloadActivities = [
            activity(category: .sport, startHour: 6, durationMinutes: 360),
            activity(category: .learning, startHour: 13, durationMinutes: 300)
        ]
        let warnings = engine.checkAll(
            sleepWindowToday: shortSleep,
            allActivitiesToday: overloadActivities,
            hasActiveLearningRoutine: true,
            recentLearningDates: []
        )
        XCTAssertTrue(warnings.contains { $0.category == .sleep })
        XCTAssertTrue(warnings.contains { $0.severity == .warning && $0.category == .custom })
        XCTAssertTrue(warnings.contains { $0.category == .learning })
    }

    func testCheckAll_consecutiveSleepReplacesSingleSleepWarning() {
        let windows = (0..<4).map { sleepWindow(bedHour: 3, wakeHour: 6, daysAgo: $0) }
        let todaySleep = sleepWindow(bedHour: 3, wakeHour: 6)
        let warnings = engine.checkAll(
            sleepWindowToday: todaySleep,
            recentSleepWindows: windows
        )
        let sleepWarnings = warnings.filter { $0.category == .sleep }
        // Critical replaces the simple warning; should have exactly one sleep warning (critical)
        XCTAssertEqual(sleepWarnings.filter { $0.severity == .critical }.count, 1)
        XCTAssertEqual(sleepWarnings.filter { $0.severity == .warning }.count, 0)
    }

    func testCheckAll_emptyInputProducesNoWarnings() {
        let warnings = engine.checkAll()
        XCTAssertTrue(warnings.isEmpty)
    }
}
