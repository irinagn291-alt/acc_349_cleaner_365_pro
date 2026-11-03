import Foundation

struct ReviewSummary: Codable, Equatable {
    var reviewed: Int = 0
    var total: Int = 0
    var queued: Int = 0
    var updated: Date? = nil
    static let suite = "group.app.cleaner365.iphone"
    static let key = "reviewSummary"
    static func read(defaults: UserDefaults? = UserDefaults(suiteName: suite)) -> ReviewSummary {
        guard let data = defaults?.data(forKey: key), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    func write(defaults: UserDefaults? = UserDefaults(suiteName: Self.suite)) {
        if let data = try? JSONEncoder().encode(self) { defaults?.set(data, forKey: Self.key) }
    }
}
