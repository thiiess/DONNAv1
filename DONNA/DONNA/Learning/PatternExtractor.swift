import Foundation
import SwiftData

// MARK: - Result Types

struct SleepPatternData {
    let avgBedtimeHour: Double      // 0.0–23.99 (e.g. 23.5 = 23:30)
    let avgDurationHours: Double
    let trend: Trend
    let dataPoints: Int
    /// Consecutive recent nights with < 6h sleep (max 7), newest first.
    let recentDeficitStreak: Int
}

struct RoutineAdherenceData {
    let routineId: UUID
    let routineTitle: String
    let adherenceRate: Double       // 0.0–1.0
    let totalOccurrences: Int
}

struct PatternResult {
    var sleep: SleepPatternData?
    var routineAdherence: [RoutineAdherenceData]
    /// weekday (1 = Sunday … 7 = Saturday) → completion rate
    var weeklyProductivity: [Int: Double]
    var totalDataPoints: Int
}

// MARK: - PatternExtractor

@MainActor
final class PatternExtractor {

    static let minimumOccurrences = 3

    func extract(from context: ModelContext) -> PatternResult {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()

        let sleep = extractSleepPatterns(context: context, cutoff: cutoff)
        let routineAdherence = extractRoutineAdherence(context: context, cutoff: cutoff)
        let weeklyProductivity = extractWeeklyPatterns(context: context, cutoff: cutoff)

        let routinePoints = routineAdherence.reduce(0) { $0 + $1.totalOccurrences }
        let total = (sleep?.dataPoints ?? 0) + routinePoints

        return PatternResult(
            sleep: sleep,
            routineAdherence: routineAdherence,
            weeklyProductivity: weeklyProductivity,
            totalDataPoints: total
        )
    }

    // MARK: - Sleep

    private func extractSleepPatterns(context: ModelContext, cutoff: Date) -> SleepPatternData? {
        let descriptor = FetchDescriptor<SleepWindow>(
            sortBy: [SortDescriptor(\.date)]
        )
        guard let all = try? context.fetch(descriptor) else { return nil }
        let windows = all.filter { $0.date >= cutoff }
        guard windows.count >= Self.minimumOccurrences else { return nil }

        let avgBedtime = circularMeanHour(windows.map { fractionalHour($0.bedtime) })
        let avgDuration = windows.map { Double($0.durationMinutes) / 60.0 }.reduce(0, +) / Double(windows.count)
        let trend = computeSleepTrend(windows: windows)
        let streak = computeDeficitStreak(windows: all)

        return SleepPatternData(
            avgBedtimeHour: avgBedtime,
            avgDurationHours: avgDuration,
            trend: trend,
            dataPoints: windows.count,
            recentDeficitStreak: streak
        )
    }

    // MARK: - Routine adherence

    private func extractRoutineAdherence(context: ModelContext, cutoff: Date) -> [RoutineAdherenceData] {
        let descriptor = FetchDescriptor<RoutineOccurrence>()
        guard let all = try? context.fetch(descriptor) else { return [] }
        let occurrences = all.filter { $0.scheduledDate >= cutoff }

        // Group by routineId
        var groups: [UUID: (title: String, completed: Int, total: Int)] = [:]
        for occ in occurrences {
            guard let routine = occ.routine else { continue }
            var entry = groups[routine.id] ?? (routine.title, 0, 0)
            entry.total += 1
            if occ.status == .completed { entry.completed += 1 }
            groups[routine.id] = entry
        }

        return groups.compactMap { id, data in
            guard data.total >= Self.minimumOccurrences else { return nil }
            return RoutineAdherenceData(
                routineId: id,
                routineTitle: data.title,
                adherenceRate: Double(data.completed) / Double(data.total),
                totalOccurrences: data.total
            )
        }.sorted { $0.routineTitle < $1.routineTitle }
    }

    // MARK: - Weekly patterns

    private func extractWeeklyPatterns(context: ModelContext, cutoff: Date) -> [Int: Double] {
        let descriptor = FetchDescriptor<RoutineOccurrence>()
        guard let all = try? context.fetch(descriptor) else { return [:] }
        let occurrences = all.filter { $0.scheduledDate >= cutoff }

        var byWeekday: [Int: (completed: Int, total: Int)] = [:]
        for occ in occurrences {
            let weekday = Calendar.current.component(.weekday, from: occ.scheduledDate)
            var entry = byWeekday[weekday] ?? (0, 0)
            entry.total += 1
            if occ.status == .completed { entry.completed += 1 }
            byWeekday[weekday] = entry
        }

        return byWeekday.compactMapValues { data in
            guard data.total >= Self.minimumOccurrences else { return nil }
            return Double(data.completed) / Double(data.total)
        }
    }

    // MARK: - Helpers

    private func fractionalHour(_ date: Date) -> Double {
        let cal = Calendar.current
        let h = cal.component(.hour, from: date)
        let m = cal.component(.minute, from: date)
        return Double(h) + Double(m) / 60.0
    }

    /// Circular mean so that times near midnight average correctly (e.g. 23:30 + 00:30 → 00:00).
    private func circularMeanHour(_ hours: [Double]) -> Double {
        let twoPi = 2.0 * Double.pi
        let angles = hours.map { $0 / 24.0 * twoPi }
        let sinMean = angles.map { sin($0) }.reduce(0, +) / Double(angles.count)
        let cosMean = angles.map { cos($0) }.reduce(0, +) / Double(angles.count)
        var mean = atan2(sinMean, cosMean) / twoPi * 24.0
        if mean < 0 { mean += 24.0 }
        return mean
    }

    /// Counts consecutive nights (newest-first, up to 7) where duration < 6h.
    private func computeDeficitStreak(windows: [SleepWindow]) -> Int {
        let sorted = windows.sorted { $0.date > $1.date }
        let cal = Calendar.current
        var streak = 0
        var checkDate = cal.startOfDay(for: Date())
        for _ in 0..<7 {
            let match = sorted.first { cal.isDate($0.date, inSameDayAs: checkDate) }
            guard let w = match, Double(w.durationMinutes) / 60.0 < 6.0 else { break }
            streak += 1
            checkDate = cal.date(byAdding: .day, value: -1, to: checkDate) ?? checkDate
        }
        return streak
    }

    private func computeSleepTrend(windows: [SleepWindow]) -> Trend {
        guard windows.count >= 6 else { return .stable }
        let half = windows.count / 2
        let firstAvg = windows.prefix(half).map { Double($0.durationMinutes) }.reduce(0, +) / Double(half)
        let secondAvg = windows.suffix(half).map { Double($0.durationMinutes) }.reduce(0, +) / Double(half)
        let diff = secondAvg - firstAvg   // in minutes
        if diff > 15 { return .improving }
        if diff < -15 { return .declining }
        return .stable
    }
}
