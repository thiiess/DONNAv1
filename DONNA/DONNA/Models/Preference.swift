import Foundation
import SwiftData

@Model class Preference {
    @Attribute(.unique) var id: UUID
    var key: String
    var value: String
    var scope: PreferenceScope
    var isActive: Bool
    var source: PreferenceSource
    var confirmedAt: Date?
    var createdAt: Date

    init(id: UUID = UUID(), key: String, value: String, scope: PreferenceScope, isActive: Bool = true, source: PreferenceSource, confirmedAt: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.key = key
        self.value = value
        self.scope = scope
        self.isActive = isActive
        self.source = source
        self.confirmedAt = confirmedAt
        self.createdAt = createdAt
    }
}
