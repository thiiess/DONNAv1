import Foundation

// MARK: - Warning Types

enum WarningSeverity: String, Codable, Equatable {
    case info, warning, critical
}

/// Bilingual message that resolves to the device locale at display time.
struct LocalizedMessage: Equatable {
    let de: String
    let en: String

    var localized: String {
        Locale.current.language.languageCode?.identifier == "de" ? de : en
    }
}

struct ScienceWarning: Equatable {
    let category: RoutineCategory
    let severity: WarningSeverity
    let message: LocalizedMessage
    let suggestion: LocalizedMessage?

    init(
        category: RoutineCategory,
        severity: WarningSeverity,
        message: LocalizedMessage,
        suggestion: LocalizedMessage? = nil
    ) {
        self.category = category
        self.severity = severity
        self.message = message
        self.suggestion = suggestion
    }
}

// MARK: - Sport Classification

enum SportType: Equatable {
    case cardio, strength, mixed, unknown

    static func inferred(from title: String) -> SportType {
        let t = title.lowercased()
        let cardioWords = ["lauf", "run", "joggen", "jogging", "cardio", "schwimm", "swim",
                           "fahrrad", "bike", "cycling", "fußball", "football", "soccer",
                           "tennis", "handball", "basketball", "badminton"]
        let strengthWords = ["kraft", "strength", "gewicht", "weight", "gym", "hantel",
                             "dumbbell", "barbell", "bench", "squat", "deadlift",
                             "rücken", "brust", "chest", "schulter", "shoulder",
                             "pull", "push", "bizeps", "trizeps", "bicep", "tricep"]
        let isCardio = cardioWords.contains { t.contains($0) }
        let isStrength = strengthWords.contains { t.contains($0) }
        if isCardio && isStrength { return .mixed }
        if isCardio { return .cardio }
        if isStrength { return .strength }
        return .unknown
    }
}

enum MuscleGroup: Equatable {
    case legs, upper, core, fullBody, unknown

    static func inferred(from title: String) -> MuscleGroup {
        let t = title.lowercased()
        let legWords = ["bein", "leg", "squat", "lunge", "knie", "wade", "hamstring", "quad",
                        "fußball", "football", "lauf", "run", "joggen", "jogging"]
        let upperWords = ["arm", "brust", "chest", "schulter", "shoulder", "rücken", "back",
                          "bench", "pull", "push", "bizeps", "trizeps", "bicep", "tricep"]
        let coreWords = ["core", "bauch", "abs", "planke", "plank", "rumpf", "mitte"]
        let isLegs = legWords.contains { t.contains($0) }
        let isUpper = upperWords.contains { t.contains($0) }
        let isCore = coreWords.contains { t.contains($0) }
        if isLegs && isUpper { return .fullBody }
        if isLegs { return .legs }
        if isUpper { return .upper }
        if isCore { return .core }
        return .unknown
    }
}

// MARK: - Input Snapshots (value types; caller converts SwiftData models before passing)

struct SportSessionSnapshot: Equatable {
    let id: UUID
    let title: String
    let date: Date
    let startTime: Date?
    let endTime: Date?
    let durationMinutes: Int
    var isIntense: Bool = true

    var sportType: SportType { SportType.inferred(from: title) }
    var muscleGroup: MuscleGroup { MuscleGroup.inferred(from: title) }
}

struct ScienceSleepSnapshot: Equatable {
    let date: Date
    let bedtime: Date
    let wakeTime: Date
    let isProtected: Bool

    var durationMinutes: Int {
        let s = wakeTime.timeIntervalSince(bedtime)
        return Int((s < 0 ? s + 86400 : s) / 60)
    }

    var durationHours: Double { Double(durationMinutes) / 60.0 }

    /// Bedtime in minutes from midnight, with 0–5 AM treated as 24–29 h to handle midnight crossings.
    var normalizedBedtimeMinutes: Int {
        let cal = Calendar.current
        var h = cal.component(.hour, from: bedtime)
        let m = cal.component(.minute, from: bedtime)
        if h < 6 { h += 24 }
        return h * 60 + m
    }
}

struct LearningSessionSnapshot: Equatable {
    let id: UUID
    let title: String
    let date: Date
    let startTime: Date?
    let endTime: Date?
    let durationMinutes: Int
    var hasPlannedBreak: Bool = false
}

struct PlannedOccurrenceSnapshot: Equatable {
    let routineId: UUID
    let category: RoutineCategory
    let title: String
    let startTime: Date
    let durationMinutes: Int

    var endTime: Date {
        startTime.addingTimeInterval(Double(durationMinutes) * 60)
    }
}

struct ActivityBlockSnapshot: Equatable {
    let startTime: Date
    let endTime: Date
    let category: RoutineCategory

    var durationMinutes: Int {
        max(0, Int(endTime.timeIntervalSince(startTime) / 60))
    }
}

// MARK: - ScienceEngine

final class ScienceEngine {

    // MARK: Sport – Rule 1
    // Same muscle group < 48 h after intense training → Warning

    func checkSameMuscleGroup(
        plannedSession: SportSessionSnapshot,
        recentSessions: [SportSessionSnapshot]
    ) -> ScienceWarning? {
        let group = plannedSession.muscleGroup
        guard group != .unknown, group != .fullBody else { return nil }

        let cutoff = plannedSession.date.addingTimeInterval(-48 * 3600)
        let hasConflict = recentSessions.contains {
            $0.id != plannedSession.id
            && $0.isIntense
            && ($0.muscleGroup == group || $0.muscleGroup == .fullBody)
            && $0.date > cutoff
            && $0.date < plannedSession.date
        }
        guard hasConflict else { return nil }

        return ScienceWarning(
            category: .sport,
            severity: .warning,
            message: LocalizedMessage(
                de: "Gleiche Muskelgruppe wurde vor weniger als 48 Stunden intensiv trainiert.",
                en: "The same muscle group was intensely trained less than 48 hours ago."
            ),
            suggestion: LocalizedMessage(
                de: "Plane mindestens 48 Stunden Erholung zwischen intensiven Einheiten derselben Muskelgruppe.",
                en: "Allow at least 48 hours of recovery between intense sessions targeting the same muscle group."
            )
        )
    }

    // MARK: Sport – Rule 2
    // > 6 training sessions/week without rest day → Warning

    func checkWeeklySessionCount(sessionsLastSevenDays: [SportSessionSnapshot]) -> ScienceWarning? {
        guard sessionsLastSevenDays.count > 6 else { return nil }
        let cal = Calendar.current
        let uniqueDays = Set(sessionsLastSevenDays.map { cal.startOfDay(for: $0.date) })
        guard uniqueDays.count == 7 else { return nil }

        return ScienceWarning(
            category: .sport,
            severity: .warning,
            message: LocalizedMessage(
                de: "Mehr als 6 Trainingseinheiten in 7 Tagen – kein Ruhetag erkannt.",
                en: "More than 6 training sessions in 7 days with no rest day detected."
            ),
            suggestion: LocalizedMessage(
                de: "Plane mindestens einen vollständigen Ruhetag pro Woche zur Regeneration ein.",
                en: "Schedule at least one complete rest day per week for recovery."
            )
        )
    }

    // MARK: Sport – Rule 3
    // Cardio + strength same day without adequate break → Info

    func checkCardioAndStrengthSameDay(
        sessionsToday: [SportSessionSnapshot],
        minBreakMinutes: Double = 60
    ) -> ScienceWarning? {
        let cardio = sessionsToday.filter { $0.sportType == .cardio }
        let strength = sessionsToday.filter { $0.sportType == .strength }
        guard !cardio.isEmpty, !strength.isEmpty else { return nil }

        for c in cardio {
            for s in strength {
                if let cEnd = c.endTime, let sStart = s.startTime,
                   sStart.timeIntervalSince(cEnd) / 60 >= minBreakMinutes { return nil }
                if let sEnd = s.endTime, let cStart = c.startTime,
                   cStart.timeIntervalSince(sEnd) / 60 >= minBreakMinutes { return nil }
            }
        }

        return ScienceWarning(
            category: .sport,
            severity: .info,
            message: LocalizedMessage(
                de: "Ausdauer- und Krafttraining am selben Tag ohne ausreichende Pause.",
                en: "Cardio and strength training on the same day without a sufficient break."
            ),
            suggestion: LocalizedMessage(
                de: "Plane mindestens 60 Minuten Abstand zwischen Ausdauer- und Krafttraining.",
                en: "Allow at least 60 minutes between cardio and strength training sessions."
            )
        )
    }

    // MARK: Sport – Rule 4
    // Leg training after football/running the next day → Warning

    func checkLegTrainingAfterRunning(
        plannedSession: SportSessionSnapshot,
        yesterdaySessions: [SportSessionSnapshot]
    ) -> ScienceWarning? {
        guard plannedSession.muscleGroup == .legs || plannedSession.muscleGroup == .fullBody else { return nil }
        let triggers = ["lauf", "run", "joggen", "jogging", "fußball", "football", "soccer"]
        let hadTrigger = yesterdaySessions.contains { s in
            triggers.contains { s.title.lowercased().contains($0) }
        }
        guard hadTrigger else { return nil }

        return ScienceWarning(
            category: .sport,
            severity: .warning,
            message: LocalizedMessage(
                de: "Beintraining nach Fußball oder Laufen am Vortag belastet die Beinmuskulatur zusätzlich.",
                en: "Leg training the day after football or running adds extra strain to already-worked leg muscles."
            ),
            suggestion: LocalizedMessage(
                de: "Erwäge einen anderen Muskelbereich oder wähle eine regenerative Einheit.",
                en: "Consider targeting a different muscle group or choosing a recovery-focused session."
            )
        )
    }

    // MARK: Sleep – Rule 1
    // < 6 h sleep → Warning

    func checkShortSleep(sleepWindow: ScienceSleepSnapshot) -> ScienceWarning? {
        guard sleepWindow.durationHours < 6.0 else { return nil }

        return ScienceWarning(
            category: .sleep,
            severity: .warning,
            message: LocalizedMessage(
                de: "Weniger als 6 Stunden Schlaf geplant – unter dem empfohlenen Minimum.",
                en: "Less than 6 hours of sleep planned – below the recommended minimum."
            ),
            suggestion: LocalizedMessage(
                de: "Erwachsene benötigen 7–9 Stunden Schlaf für optimale Erholung und Leistung.",
                en: "Adults need 7–9 hours of sleep for optimal recovery and performance."
            )
        )
    }

    // MARK: Sleep – Rule 2
    // < 6 h sleep on 3+ consecutive days → Critical

    func checkConsecutiveShortSleep(recentSleepWindows: [ScienceSleepSnapshot]) -> ScienceWarning? {
        let sorted = recentSleepWindows.sorted { $0.date < $1.date }
        var streak = 0
        for window in sorted {
            if window.durationHours < 6.0 {
                streak += 1
                if streak >= 3 {
                    return ScienceWarning(
                        category: .sleep,
                        severity: .critical,
                        message: LocalizedMessage(
                            de: "\(streak) aufeinanderfolgende Tage mit weniger als 6 Stunden Schlaf – kritischer Schlafmangel.",
                            en: "\(streak) consecutive days with less than 6 hours of sleep – critical sleep deprivation."
                        ),
                        suggestion: LocalizedMessage(
                            de: "Chronischer Schlafmangel beeinträchtigt Kognition, Immunsystem und Herzgesundheit erheblich.",
                            en: "Chronic sleep deprivation significantly impairs cognition, immune function, and cardiovascular health."
                        )
                    )
                }
            } else {
                streak = 0
            }
        }
        return nil
    }

    // MARK: Sleep – Rule 3
    // Sleep time varies > 90 min from weekly average → Info (circadian rhythm)

    func checkCircadianVariation(recentSleepWindows: [ScienceSleepSnapshot]) -> ScienceWarning? {
        guard recentSleepWindows.count >= 3 else { return nil }
        let minutes = recentSleepWindows.map { Double($0.normalizedBedtimeMinutes) }
        let average = minutes.reduce(0, +) / Double(minutes.count)
        let maxDeviation = minutes.map { abs($0 - average) }.max() ?? 0
        guard maxDeviation > 90 else { return nil }

        return ScienceWarning(
            category: .sleep,
            severity: .info,
            message: LocalizedMessage(
                de: "Deine Schlafzeit weicht mehr als 90 Minuten vom Wochendurchschnitt ab – mögliche Störung des Zirkadianrhythmus.",
                en: "Your bedtime deviates more than 90 minutes from the weekly average – possible disruption of your circadian rhythm."
            ),
            suggestion: LocalizedMessage(
                de: "Ein gleichmäßiger Schlafrhythmus verbessert Schlafqualität und Tagesenergie.",
                en: "A consistent sleep schedule improves sleep quality and daytime energy levels."
            )
        )
    }

    // MARK: Sleep – Rule 4
    // Routine planned in protected sleep window → Critical (blocked)

    func checkRoutineInSleepWindow(
        occurrence: PlannedOccurrenceSnapshot,
        sleepWindow: ScienceSleepSnapshot
    ) -> ScienceWarning? {
        guard sleepWindow.isProtected else { return nil }

        let cal = Calendar.current
        let day = cal.startOfDay(for: occurrence.startTime)

        func timeOnDay(_ source: Date, addDays: Int = 0) -> Date {
            let base = addDays == 0 ? day : cal.date(byAdding: .day, value: addDays, to: day)!
            let comps = cal.dateComponents([.hour, .minute], from: source)
            return cal.date(bySettingHour: comps.hour ?? 0,
                            minute: comps.minute ?? 0,
                            second: 0, of: base) ?? source
        }

        let bedtimeHour = cal.component(.hour, from: sleepWindow.bedtime)
        let bedOnDay = timeOnDay(sleepWindow.bedtime)
        // Wake is typically morning; if bedtime is in the evening, wake is next day
        let wakeOnDay = bedtimeHour >= 12
            ? timeOnDay(sleepWindow.wakeTime, addDays: 1)
            : timeOnDay(sleepWindow.wakeTime)

        let overlaps = occurrence.startTime < wakeOnDay && occurrence.endTime > bedOnDay
        guard overlaps else { return nil }

        return ScienceWarning(
            category: occurrence.category,
            severity: .critical,
            message: LocalizedMessage(
                de: "Diese Routine überschneidet sich mit dem geschützten Schlaffenster.",
                en: "This routine overlaps with the protected sleep window."
            ),
            suggestion: LocalizedMessage(
                de: "Verschiebe die Routine oder passe das Schlaffenster an.",
                en: "Reschedule the routine or adjust your sleep window."
            )
        )
    }

    // MARK: Learning – Rule 1
    // Learning block > 90 min without planned break → Info

    func checkLongLearningBlock(session: LearningSessionSnapshot) -> ScienceWarning? {
        guard session.durationMinutes > 90, !session.hasPlannedBreak else { return nil }

        return ScienceWarning(
            category: .learning,
            severity: .info,
            message: LocalizedMessage(
                de: "Lernblock über 90 Minuten ohne geplante Pause – Konzentration lässt typischerweise nach.",
                en: "Learning block longer than 90 minutes without a planned break – concentration typically declines."
            ),
            suggestion: LocalizedMessage(
                de: "Die Pomodoro-Methode empfiehlt 25-Minuten-Blöcke mit kurzen Pausen dazwischen.",
                en: "The Pomodoro technique suggests 25-minute blocks with short breaks in between."
            )
        )
    }

    // MARK: Learning – Rule 2
    // Learning directly before sleep (< 30 min gap) → Info

    func checkLearningBeforeSleep(
        session: LearningSessionSnapshot,
        sleepWindow: ScienceSleepSnapshot
    ) -> ScienceWarning? {
        guard let sessionEnd = session.endTime else { return nil }

        let cal = Calendar.current
        let day = cal.startOfDay(for: sessionEnd)
        let bedtimeComps = cal.dateComponents([.hour, .minute], from: sleepWindow.bedtime)
        guard let bedOnDay = cal.date(
            bySettingHour: bedtimeComps.hour ?? 23,
            minute: bedtimeComps.minute ?? 0,
            second: 0,
            of: day
        ) else { return nil }

        let gapMinutes = bedOnDay.timeIntervalSince(sessionEnd) / 60
        guard gapMinutes >= 0, gapMinutes < 30 else { return nil }

        return ScienceWarning(
            category: .learning,
            severity: .info,
            message: LocalizedMessage(
                de: "Lernen weniger als 30 Minuten vor dem Schlafen kann das Einschlafen erschweren.",
                en: "Learning less than 30 minutes before sleep may make it harder to fall asleep."
            ),
            suggestion: LocalizedMessage(
                de: "Plane mindestens 30 Minuten Abstand zwischen dem letzten Lernblock und der Schlafzeit.",
                en: "Allow at least 30 minutes between your last learning block and bedtime."
            )
        )
    }

    // MARK: Learning – Rule 3
    // No learning block for > 3 days with active learning routine → Warning

    func checkLearningAbsence(
        hasActiveLearningRoutine: Bool,
        recentLearningDates: [Date],
        today: Date = Date()
    ) -> ScienceWarning? {
        guard hasActiveLearningRoutine else { return nil }

        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -3, to: cal.startOfDay(for: today)) ?? today
        let hasRecent = recentLearningDates.contains { $0 >= cutoff }
        guard !hasRecent else { return nil }

        return ScienceWarning(
            category: .learning,
            severity: .warning,
            message: LocalizedMessage(
                de: "Kein Lernblock seit über 3 Tagen – aktive Lernroutine wird nicht eingehalten.",
                en: "No learning block for more than 3 days – your active learning routine is not being maintained."
            ),
            suggestion: LocalizedMessage(
                de: "Regelmäßiges Lernen in kurzen Einheiten ist effektiver als seltene, lange Blöcke.",
                en: "Regular learning in short sessions is more effective than rare, long blocks."
            )
        )
    }

    // MARK: General – Rule 1
    // Day with > 10 h planned activity → Warning (overload)

    func checkDailyOverload(activities: [ActivityBlockSnapshot]) -> ScienceWarning? {
        let totalMinutes = activities.reduce(0) { $0 + $1.durationMinutes }
        guard totalMinutes > 600 else { return nil }

        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        let durationText = mins > 0 ? "\(hours) Std. \(mins) Min." : "\(hours) Stunden"
        let durationTextEN = mins > 0 ? "\(hours) h \(mins) min" : "\(hours) hours"

        return ScienceWarning(
            category: .custom,
            severity: .warning,
            message: LocalizedMessage(
                de: "\(durationText) geplante Aktivität heute – mögliche Überlastung.",
                en: "\(durationTextEN) of planned activity today – possible overload."
            ),
            suggestion: LocalizedMessage(
                de: "Prüfe, ob alle Aktivitäten notwendig sind, und plane Puffer- und Erholungszeiten ein.",
                en: "Review whether all activities are necessary and build in buffer and recovery time."
            )
        )
    }

    // MARK: General – Rule 2
    // No recovery time between sport/learning/work back to back → Warning

    func checkNoRecoveryTime(
        activities: [ActivityBlockSnapshot],
        minRecoveryMinutes: Double = 15
    ) -> ScienceWarning? {
        let active = activities
            .filter { [.sport, .learning, .custom].contains($0.category) }
            .sorted { $0.startTime < $1.startTime }

        guard active.count >= 2 else { return nil }

        for i in 0..<(active.count - 1) {
            let gap = active[i + 1].startTime.timeIntervalSince(active[i].endTime) / 60
            if gap < minRecoveryMinutes {
                return ScienceWarning(
                    category: .custom,
                    severity: .warning,
                    message: LocalizedMessage(
                        de: "Keine Erholungszeit zwischen aufeinanderfolgenden intensiven Aktivitäten (Sport/Lernen/Arbeit).",
                        en: "No recovery time between consecutive demanding activities (sport/learning/work)."
                    ),
                    suggestion: LocalizedMessage(
                        de: "Plane mindestens 15 Minuten Pause zwischen intensiven Aktivitätsblöcken.",
                        en: "Schedule at least 15 minutes of downtime between demanding activity blocks."
                    )
                )
            }
        }

        return nil
    }

    // MARK: - Composite Check

    /// Runs all applicable rules and returns deduplicated warnings.
    func checkAll(
        date: Date = Date(),
        sportSessionsToday: [SportSessionSnapshot] = [],
        sportSessionsYesterday: [SportSessionSnapshot] = [],
        sportSessionsLastSevenDays: [SportSessionSnapshot] = [],
        learningSessions: [LearningSessionSnapshot] = [],
        sleepWindowToday: ScienceSleepSnapshot? = nil,
        recentSleepWindows: [ScienceSleepSnapshot] = [],
        plannedOccurrences: [PlannedOccurrenceSnapshot] = [],
        allActivitiesToday: [ActivityBlockSnapshot] = [],
        hasActiveLearningRoutine: Bool = false,
        recentLearningDates: [Date] = []
    ) -> [ScienceWarning] {
        var warnings: [ScienceWarning] = []

        // Sport: same muscle group (deduplicated per muscle group)
        let recentWithoutToday = sportSessionsLastSevenDays.filter { s in
            !sportSessionsToday.contains { $0.id == s.id }
        }
        var warnedMuscleGroups = Set<String>()
        for session in sportSessionsToday {
            let group = session.muscleGroup
            let key = "\(group)"
            guard !warnedMuscleGroups.contains(key) else { continue }
            if let w = checkSameMuscleGroup(plannedSession: session, recentSessions: recentWithoutToday) {
                warnings.append(w)
                warnedMuscleGroups.insert(key)
            }
        }

        // Sport: weekly session count
        if let w = checkWeeklySessionCount(sessionsLastSevenDays: sportSessionsLastSevenDays) {
            warnings.append(w)
        }

        // Sport: cardio + strength same day
        if let w = checkCardioAndStrengthSameDay(sessionsToday: sportSessionsToday) {
            warnings.append(w)
        }

        // Sport: leg training after running (once, not per session)
        let hasLegToday = sportSessionsToday.contains {
            $0.muscleGroup == .legs || $0.muscleGroup == .fullBody
        }
        if hasLegToday,
           let legSession = sportSessionsToday.first(where: {
               $0.muscleGroup == .legs || $0.muscleGroup == .fullBody
           }),
           let w = checkLegTrainingAfterRunning(
               plannedSession: legSession,
               yesterdaySessions: sportSessionsYesterday
           ) {
            warnings.append(w)
        }

        // Sleep: short sleep
        if let sw = sleepWindowToday, let w = checkShortSleep(sleepWindow: sw) {
            warnings.append(w)
        }

        // Sleep: consecutive short sleep (takes precedence over single short sleep)
        if let w = checkConsecutiveShortSleep(recentSleepWindows: recentSleepWindows) {
            // Remove single-night warning if already added; critical replaces it
            warnings.removeAll { $0.category == .sleep && $0.severity == .warning }
            warnings.append(w)
        }

        // Sleep: circadian variation
        if let w = checkCircadianVariation(recentSleepWindows: recentSleepWindows) {
            warnings.append(w)
        }

        // Sleep: routine in sleep window
        if let sw = sleepWindowToday {
            for occ in plannedOccurrences {
                if let w = checkRoutineInSleepWindow(occurrence: occ, sleepWindow: sw) {
                    warnings.append(w)
                }
            }
        }

        // Learning: long block (one warning per session)
        for session in learningSessions {
            if let w = checkLongLearningBlock(session: session) {
                warnings.append(w)
                break // one info is enough per day
            }
        }

        // Learning: before sleep
        if let sw = sleepWindowToday {
            for session in learningSessions {
                if let w = checkLearningBeforeSleep(session: session, sleepWindow: sw) {
                    warnings.append(w)
                    break
                }
            }
        }

        // Learning: absence
        if let w = checkLearningAbsence(
            hasActiveLearningRoutine: hasActiveLearningRoutine,
            recentLearningDates: recentLearningDates,
            today: date
        ) {
            warnings.append(w)
        }

        // General: daily overload
        if let w = checkDailyOverload(activities: allActivitiesToday) {
            warnings.append(w)
        }

        // General: no recovery time
        if let w = checkNoRecoveryTime(activities: allActivitiesToday) {
            warnings.append(w)
        }

        return warnings
    }
}
