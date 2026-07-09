import Foundation

// MARK: - Statuspage summary API (api/v2/summary.json)

struct Summary: Codable, Sendable {
    let components: [Component]
    let status: PageStatus
}

struct PageStatus: Codable, Sendable {
    let indicator: String   // none | minor | major | critical
    let description: String
}

struct Component: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let status: ComponentStatus
    let position: Int
    let showcase: Bool
}

enum ComponentStatus: String, Codable, Sendable {
    case operational
    case degradedPerformance = "degraded_performance"
    case partialOutage = "partial_outage"
    case majorOutage = "major_outage"
    case underMaintenance = "under_maintenance"
    case unknown

    // A future status value must not fail the whole summary decode.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ComponentStatus(rawValue: raw) ?? .unknown
    }
}

// MARK: - Homepage-embedded uptime data

struct UptimeValue: Codable, Sendable {
    let component: String   // component id
    let ninety: Double
    let sixty: Double
    let thirty: Double
}

struct UptimeComponentRaw: Codable, Sendable {
    let days: [UptimeDayRaw]?
}

struct UptimeDayRaw: Codable, Sendable {
    let date: String?
    let outages: Outages?
    let relatedEvents: [RelatedEvent]?

    struct Outages: Codable, Sendable {
        let p: Int?   // partial outage seconds
        let m: Int?   // major outage seconds
    }

    struct RelatedEvent: Codable, Sendable {
        let name: String
        let code: String
    }

    enum CodingKeys: String, CodingKey {
        case date, outages
        case relatedEvents = "related_events"
    }
}

// MARK: - View-facing models

struct ComponentUptime: Sendable {
    let componentID: String
    let ninetyDayPercent: Double
    let bars: [DayBar]
}

struct DayBar: Identifiable, Sendable {
    let id: Int            // 0 (oldest) ... 89 (today)
    let colorHex: String
    let date: String?
    let partialSeconds: Int
    let majorSeconds: Int
    let eventNames: [String]
}

extension DayBar {
    var tooltip: String {
        guard let date else { return "" }
        var lines = [date]
        if majorSeconds > 0 { lines.append("Major outage: \(Self.duration(majorSeconds))") }
        if partialSeconds > 0 { lines.append("Partial outage: \(Self.duration(partialSeconds))") }
        lines.append(contentsOf: eventNames)
        if lines.count == 1 { lines.append("No incidents") }
        return lines.joined(separator: "\n")
    }

    private static func duration(_ seconds: Int) -> String {
        let minutes = (seconds + 59) / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
