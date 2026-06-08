import Foundation
import SwiftData

// MARK: - Archive Structures (private)

private struct MonthlySleepArchive: Codable {
    let month: String
    let avgBedtimeHour: Double
    let avgDurationHours: Double
    let dataPoints: Int
}

private struct MonthlyRoutineEntry: Codable {
    let routineId: String
    let title: String
    let adherenceRate: Double
    let totalOccurrences: Int
    let completedCount: Int
}

private struct MonthlyRoutineArchive: Codable {
    let month: String
    let routines: [MonthlyRoutineEntry]
}

private struct YearlySummary: Codable {
    let year: String
    var avgBedtimeHour: Double?
    var avgDurationHours: Double?
    var routineAdherence: [String: Double]
    var monthsAggregated: Int
}

// MARK: - DataLifecycleManager

@MainActor
final class DataLifecycleManager {

    static let shared = DataLifecycleManager()

    static let hotPeriodMonthsKey  = "donna_lifecycle_hotPeriodMonths"
    static let chatHistoryMonthsKey = "donna_lifecycle_chatHistoryMonths"
    private static let lastRunKey  = "donna_lifecycle_lastRun"

    static var hotPeriodMonths: Int {
        let v = UserDefaults.standard.integer(forKey: hotPeriodMonthsKey)
        return v > 0 ? v : 6
    }

    static var chatHistoryMonths: Int {
        let v = UserDefaults.standard.integer(forKey: chatHistoryMonthsKey)
        return v > 0 ? v : 3
    }

    private init() {}

    // MARK: - Entry Points

    /// Runs the lifecycle pass at most once per week.
    func runIfNeeded(modelContext: ModelContext) {
        if let last = UserDefaults.standard.object(forKey: Self.lastRunKey) as? Date {
            let threshold = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: Date()) ?? Date()
            guard last < threshold else { return }
        }
        run(modelContext: modelContext)
    }

    /// Runs the full lifecycle pass unconditionally.
    func run(modelContext: ModelContext) {
        // Always extract patterns before any deletion so no learning data is lost.
        _ = PatternExtractor().extract(from: modelContext)

        archiveSleepWindows(modelContext: modelContext)
        archiveRoutineOccurrences(modelContext: modelContext)
        deleteOldChatMessages(modelContext: modelContext)
        consolidateYearlySummaries(modelContext: modelContext)

        try? modelContext.save()
        UserDefaults.standard.set(Date(), forKey: Self.lastRunKey)
    }

    // MARK: - HOT → WARM: Sleep Windows

    private func archiveSleepWindows(modelContext: ModelContext) {
        let cutoff = date(monthsAgo: Self.hotPeriodMonths)
        guard let all = try? modelContext.fetch(FetchDescriptor<SleepWindow>()) else { return }
        let toArchive = all.filter { $0.dataLayer == .hot && $0.date < cutoff }

        for (month, windows) in Dictionary(grouping: toArchive, by: { monthKey(from: $0.date) }) {
            let prefKey = "archive_sleep_\(month)"
            guard !preferenceExists(key: prefKey, in: modelContext) else { continue }

            let avgBedtime = circularMeanHour(windows.map { fractionalHour($0.bedtime) })
            let avgDuration = windows.map { Double($0.durationMinutes) / 60.0 }.reduce(0, +) / Double(windows.count)

            let archive = MonthlySleepArchive(
                month: month,
                avgBedtimeHour: avgBedtime,
                avgDurationHours: avgDuration,
                dataPoints: windows.count
            )
            if let json = encode(archive) {
                modelContext.insert(Preference(key: prefKey, value: json, scope: .global, source: .observed))
            }
            windows.forEach { modelContext.delete($0) }
        }
    }

    // MARK: - HOT → WARM: Routine Occurrences

    private func archiveRoutineOccurrences(modelContext: ModelContext) {
        let cutoff = date(monthsAgo: Self.hotPeriodMonths)
        guard let all = try? modelContext.fetch(FetchDescriptor<RoutineOccurrence>()) else { return }
        let toArchive = all.filter { $0.dataLayer == .hot && $0.scheduledDate < cutoff }

        for (month, occurrences) in Dictionary(grouping: toArchive, by: { monthKey(from: $0.scheduledDate) }) {
            let prefKey = "archive_routine_\(month)"
            guard !preferenceExists(key: prefKey, in: modelContext) else { continue }

            var groups: [String: (title: String, completed: Int, total: Int)] = [:]
            for occ in occurrences {
                guard let routine = occ.routine else { continue }
                let key = routine.id.uuidString
                var e = groups[key] ?? (routine.title, 0, 0)
                e.total += 1
                if occ.status == .completed { e.completed += 1 }
                groups[key] = e
            }

            let entries = groups.map { id, data in
                MonthlyRoutineEntry(
                    routineId: id,
                    title: data.title,
                    adherenceRate: data.total > 0 ? Double(data.completed) / Double(data.total) : 0,
                    totalOccurrences: data.total,
                    completedCount: data.completed
                )
            }
            let archive = MonthlyRoutineArchive(month: month, routines: entries)
            if let json = encode(archive) {
                modelContext.insert(Preference(key: prefKey, value: json, scope: .global, source: .observed))
            }
            occurrences.forEach { modelContext.delete($0) }
        }
    }

    // MARK: - Delete Old Chat Messages

    private func deleteOldChatMessages(modelContext: ModelContext) {
        let cutoff = date(monthsAgo: Self.chatHistoryMonths)
        guard let all = try? modelContext.fetch(FetchDescriptor<ChatMessage>()) else { return }
        all.filter { $0.timestamp < cutoff }.forEach { modelContext.delete($0) }
    }

    // MARK: - WARM → COLD: Yearly Summaries

    private func consolidateYearlySummaries(modelContext: ModelContext) {
        let coldCutoff = date(monthsAgo: 24)
        guard let allPrefs = try? modelContext.fetch(FetchDescriptor<Preference>()) else { return }

        // "archive_sleep_"   = 14 chars
        // "archive_routine_" = 16 chars
        let oldSleepPrefs = allPrefs.filter {
            $0.key.hasPrefix("archive_sleep_") &&
            (dateFromMonthKey(String($0.key.dropFirst(14))) ?? Date()) < coldCutoff
        }
        let oldRoutinePrefs = allPrefs.filter {
            $0.key.hasPrefix("archive_routine_") &&
            (dateFromMonthKey(String($0.key.dropFirst(16))) ?? Date()) < coldCutoff
        }
        guard !oldSleepPrefs.isEmpty || !oldRoutinePrefs.isEmpty else { return }

        var years = Set<String>()
        oldSleepPrefs.forEach   { years.insert(String($0.key.dropFirst(14).prefix(4))) }
        oldRoutinePrefs.forEach { years.insert(String($0.key.dropFirst(16).prefix(4))) }

        for year in years {
            let yearKey = "archive_yearly_\(year)"
            guard !preferenceExists(key: yearKey, in: modelContext) else { continue }

            let yearSleepPrefs   = oldSleepPrefs.filter   { $0.key.contains("_\(year)-") }
            let yearRoutinePrefs = oldRoutinePrefs.filter { $0.key.contains("_\(year)-") }

            // Aggregate sleep
            let sleepArchives: [MonthlySleepArchive] = yearSleepPrefs.compactMap { decode($0.value) }
            var avgBedtime: Double?
            var avgDuration: Double?
            if !sleepArchives.isEmpty {
                let weighted = sleepArchives.flatMap { Array(repeating: $0.avgBedtimeHour, count: $0.dataPoints) }
                avgBedtime = circularMeanHour(weighted)
                let total = sleepArchives.reduce(0) { $0 + $1.dataPoints }
                avgDuration = sleepArchives.reduce(0.0) {
                    $0 + $1.avgDurationHours * Double($1.dataPoints)
                } / Double(max(1, total))
            }

            // Aggregate routine adherence
            var routineAccum: [String: (sum: Double, count: Int)] = [:]
            for pref in yearRoutinePrefs {
                guard let archive: MonthlyRoutineArchive = decode(pref.value) else { continue }
                for entry in archive.routines {
                    var acc = routineAccum[entry.title] ?? (0, 0)
                    acc.sum   += entry.adherenceRate
                    acc.count += 1
                    routineAccum[entry.title] = acc
                }
            }
            let routineAdherence = routineAccum.mapValues { $0.count > 0 ? $0.sum / Double($0.count) : 0 }

            let summary = YearlySummary(
                year: year,
                avgBedtimeHour: avgBedtime,
                avgDurationHours: avgDuration,
                routineAdherence: routineAdherence,
                monthsAggregated: max(yearSleepPrefs.count, yearRoutinePrefs.count)
            )
            if let json = encode(summary) {
                modelContext.insert(Preference(key: yearKey, value: json, scope: .global, source: .observed))
            }
            (yearSleepPrefs + yearRoutinePrefs).forEach { modelContext.delete($0) }
        }
    }

    // MARK: - Helpers

    private func date(monthsAgo months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: -months, to: Date()) ?? Date()
    }

    private func monthKey(from date: Date) -> String {
        let c = Calendar.current
        return String(format: "%04d-%02d", c.component(.year, from: date), c.component(.month, from: date))
    }

    private func dateFromMonthKey(_ key: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f.date(from: key)
    }

    private func preferenceExists(key: String, in context: ModelContext) -> Bool {
        let d = FetchDescriptor<Preference>(predicate: #Predicate { $0.key == key })
        return (try? context.fetchCount(d)) ?? 0 > 0
    }

    private func fractionalHour(_ date: Date) -> Double {
        let c = Calendar.current
        return Double(c.component(.hour, from: date)) + Double(c.component(.minute, from: date)) / 60.0
    }

    /// Circular mean so that times near midnight average correctly.
    private func circularMeanHour(_ hours: [Double]) -> Double {
        guard !hours.isEmpty else { return 0 }
        let twoPi = 2.0 * Double.pi
        let radians = hours.map { $0 / 24.0 * twoPi }
        let sinMean = radians.map(sin).reduce(0, +) / Double(radians.count)
        let cosMean = radians.map(cos).reduce(0, +) / Double(radians.count)
        var mean = atan2(sinMean, cosMean) / twoPi * 24.0
        if mean < 0 { mean += 24.0 }
        return mean
    }

    private func encode<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func decode<T: Decodable>(_ json: String) -> T? {
        json.data(using: .utf8).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}
