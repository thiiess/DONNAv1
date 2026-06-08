import Foundation

enum TaskStatus: String, Codable { case open, completed, cancelled }
enum Priority: String, Codable, CaseIterable { case none, low, medium, high }
enum RoutineFrequency: String, Codable { case daily, weekdays, weekly, custom }
enum RoutineCategory: String, Codable { case sleep, sport, learning, skincare, nutrition, custom }
enum OccurrenceStatus: String, Codable { case scheduled, completed, skipped, rescheduled }
enum PreferenceScope: String, Codable { case global, routine, context }
enum PreferenceSource: String, Codable { case explicit, observed, `default` }
enum MessageRole: String, Codable { case user, assistant }
enum AIOutputType: String, Codable { case interpretation, clarification, proposal, explanation }
enum DataLayer: String, Codable { case hot, warm, cold }
enum Trend: String, Codable { case stable, improving, declining }
