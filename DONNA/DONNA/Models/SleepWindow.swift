import Foundation
import SwiftData

@Model class SleepWindow {
    @Attribute(.unique) var id: UUID
    var date: Date
    var bedtime: Date
    var wakeTime: Date
    var isProtected: Bool
    var dataLayer: DataLayer

    var durationMinutes: Int {
        let seconds = wakeTime.timeIntervalSince(bedtime)
        let adjusted = seconds < 0 ? seconds + 86400 : seconds
        return Int(adjusted / 60)
    }

    init(id: UUID = UUID(), date: Date, bedtime: Date, wakeTime: Date, isProtected: Bool = true, dataLayer: DataLayer = .hot) {
        self.id = id
        self.date = date
        self.bedtime = bedtime
        self.wakeTime = wakeTime
        self.isProtected = isProtected
        self.dataLayer = dataLayer
    }
}
