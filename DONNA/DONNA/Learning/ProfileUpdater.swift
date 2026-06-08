import Foundation
import SwiftData

/// Consumes a PatternResult, updates LearnedProfile, and generates clarification
/// ChatMessages for newly detected patterns (subject to a 30-day cooldown).
@MainActor
final class ProfileUpdater {

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Public API

    func update(with result: PatternResult) {
        syncLearnedProfile(result)
        proposeNewPatterns(result)
    }

    // MARK: - LearnedProfile sync

    private func syncLearnedProfile(_ result: PatternResult) {
        let profile = fetchOrCreateProfile()

        if let sleep = result.sleep {
            profile.avgBedtime = dateFromHour(sleep.avgBedtimeHour)
            profile.avgSleepDuration = sleep.avgDurationHours
            profile.sleepTrend = sleep.trend
        }

        // Encode routine adherence map  [routineId: rate]
        let adherenceMap = Dictionary(
            uniqueKeysWithValues: result.routineAdherence.map {
                ($0.routineId.uuidString, $0.adherenceRate)
            }
        )
        profile.routineAdherence = (try? JSONEncoder().encode(adherenceMap)) ?? Data()

        // Encode weekly productivity map  ["1": rate, ...]
        let weeklyMap = Dictionary(
            uniqueKeysWithValues: result.weeklyProductivity.map { (String($0.key), $0.value) }
        )
        profile.weeklyPatterns = (try? JSONEncoder().encode(weeklyMap)) ?? Data()

        profile.lastUpdated = Date()
        profile.totalDataPoints = result.totalDataPoints

        try? context.save()
    }

    // MARK: - Pattern proposals

    private func proposeNewPatterns(_ result: PatternResult) {
        if let sleep = result.sleep {
            proposeIfNeeded(
                key: "avg_bedtime",
                value: String(format: "%.4f", sleep.avgBedtimeHour),
                message: "Ich habe bemerkt, dass du meist gegen \(formattedHour(sleep.avgBedtimeHour)) Uhr schläfst. Soll ich das als Standard merken?"
            )
            proposeIfNeeded(
                key: "avg_sleep_duration",
                value: String(format: "%.2f", sleep.avgDurationHours),
                message: "Deine durchschnittliche Schlafdauer beträgt \(String(format: "%.1f", sleep.avgDurationHours)) Stunden. Soll ich das als Richtwert speichern?"
            )
        }

        for adherence in result.routineAdherence {
            let pct = Int(adherence.adherenceRate * 100)
            proposeIfNeeded(
                key: "routine_adherence_\(adherence.routineId.uuidString)",
                value: String(format: "%.4f", adherence.adherenceRate),
                message: "Du h\u{00E4}ltst deine Routine \u{201E}\(adherence.routineTitle)\u{201C} zu \(pct)\u{202F}% ein. Soll ich das festhalten?"
            )
        }
    }

    private func proposeIfNeeded(key: String, value: String, message: String) {
        guard !hasConfirmedPreference(key: key) else { return }
        guard !isOnCooldown(key: key) else { return }

        let msg = ChatMessage(
            role: .assistant,
            content: message,
            outputType: .clarification
        )
        context.insert(msg)

        // Record ask timestamp as a cooldown marker
        let cooldownKey = "cooldown_\(key)"
        if let existing = fetchPreference(key: cooldownKey) {
            existing.confirmedAt = Date()
        } else {
            let cooldown = Preference(
                key: cooldownKey,
                value: value,
                scope: .global,
                isActive: false,
                source: .observed,
                confirmedAt: Date()
            )
            context.insert(cooldown)
        }

        try? context.save()
    }

    // MARK: - Confirmation (called by CommandHandler.handleConfirmPreference)

    func confirmPreference(key: String, value: String) {
        if let existing = fetchPreference(key: key) {
            existing.value = value
            existing.confirmedAt = Date()
            existing.isActive = true
            existing.source = .observed
        } else {
            context.insert(Preference(
                key: key,
                value: value,
                scope: .global,
                isActive: true,
                source: .observed,
                confirmedAt: Date()
            ))
        }
        try? context.save()
    }

    // MARK: - Helpers

    private func fetchOrCreateProfile() -> LearnedProfile {
        let descriptor = FetchDescriptor<LearnedProfile>()
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let profile = LearnedProfile()
        context.insert(profile)
        return profile
    }

    private func fetchPreference(key: String) -> Preference? {
        let descriptor = FetchDescriptor<Preference>()
        return (try? context.fetch(descriptor))?.first { $0.key == key }
    }

    private func hasConfirmedPreference(key: String) -> Bool {
        guard let pref = fetchPreference(key: key) else { return false }
        return pref.isActive && pref.confirmedAt != nil
    }

    private func isOnCooldown(key: String) -> Bool {
        let cooldownKey = "cooldown_\(key)"
        guard let pref = fetchPreference(key: cooldownKey),
              let askedAt = pref.confirmedAt else { return false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return askedAt > cutoff
    }

    private func dateFromHour(_ hour: Double) -> Date {
        var comps = DateComponents()
        comps.hour = Int(hour) % 24
        comps.minute = Int((hour - Double(Int(hour))) * 60)
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func formattedHour(_ hour: Double) -> String {
        let h = Int(hour) % 24
        let m = Int((hour - Double(Int(hour))) * 60)
        return String(format: "%02d:%02d", h, m)
    }
}
