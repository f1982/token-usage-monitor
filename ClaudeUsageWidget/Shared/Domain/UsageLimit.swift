import Foundation

struct UsageLimit: Codable, Equatable, Identifiable {
    var id: String
    var kind: String
    var label: String
    var percent: Double
    var resetsAt: Date?
}
