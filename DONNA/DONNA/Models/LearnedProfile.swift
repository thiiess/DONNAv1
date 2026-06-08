import Foundation
import SwiftData

@Model class LearnedProfile {
    @Attribute(.unique) var id: UUID
    var avgBedtime: Date?
    var avgSleepDuration: Double?
    var sleepTrend: Trend
    var productiveHoursStart: Int?
    var productiveHoursEnd: Int?
    var avgSportPerWeek: Double?
    var routineAdherence: Data
    var weeklyPatterns: Data
    var lastUpdated: Date
    var totalDataPoints: Int

    init(id: UUID = UUID(), avgBedtime: Date? = nil, avgSleepDuration: Double? = nil, sleepTrend: Trend = .stable, productiveHoursStart: Int? = nil, productiveHoursEnd: Int? = nil, avgSportPerWeek: Double? = nil, routineAdherence: Data = Data(), weeklyPatterns: Data = Data(), lastUpdated: Date = Date(), totalDataPoints: Int = 0) {
        self.id = id
        self.avgBedtime = avgBedtime
        self.avgSleepDuration = avgSleepDuration
        self.sleepTrend = sleepTrend
        self.productiveHoursStart = productiveHoursStart
        self.productiveHoursEnd = productiveHoursEnd
        self.avgSportPerWeek = avgSportPerWeek
        self.routineAdherence = routineAdherence
        self.weeklyPatterns = weeklyPatterns
        self.lastUpdated = lastUpdated
        self.totalDataPoints = totalDataPoints
    }
}
