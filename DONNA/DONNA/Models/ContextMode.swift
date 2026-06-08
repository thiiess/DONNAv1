import Foundation
import SwiftData

@Model class ContextMode {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var isActive: Bool = false
    var startDate: Date?
    var endDate: Date?
    var overrides: Data = Data()

    init(id: UUID = UUID(), name: String, isActive: Bool = false, startDate: Date? = nil, endDate: Date? = nil, overrides: Data = Data()) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.startDate = startDate
        self.endDate = endDate
        self.overrides = overrides
    }
}
