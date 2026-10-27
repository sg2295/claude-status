import Foundation

enum ParseError: Error, CustomStringConvertible {
    case uptimeValuesNotFound
    case noComponentsParsed

    var description: String {
        switch self {
        case .uptimeValuesNotFound:
            return "uptime percentages not found in homepage HTML or uptime_showcase response"
        case .noComponentsParsed:
            return "no component uptime data could be parsed"
        }
    }
}

// Extracts the uptime section data of status.claude.com (Atlassian Statuspage).
// Three independent extractions, merged by day index:
//   1. uptimeValues: the exact displayed 90-day percentages (required)
//   2. SVG rect fills: the exact per-day bar colors (required per component)
//   3. uptimeData: per-day dates, outage seconds, incident names
//      (soft; only tooltips are lost when it fails)
// The homepage ships them in one of two shapes:
//   - Lazy: each component has a `data-uptime-lazy="<id>"` placeholder and the
//     page's script fetches GET /uptime_showcase?components=<id>,<id>, a JSON
//     object holding the rect markup (components), uptimeData (timelines) and
//     uptimeValues (values). See assemble(showcase:).
//   - Inline: all three are embedded in the homepage HTML as JS assignments
//     and SVG markup. See assemble(html:).
// Fallback if uptimeValues ever disappears: Statuspage computes
//   uptime = 1 - (m + 0.3 * p) / (elapsed_days * 86400)
// from the day-level outage seconds in uptimeData (verified against the
// month-level uptime_percentage values of /uptime/{id}.json).
enum HomepageUptimeParser {

    static func assemble(html: String) throws -> [String: ComponentUptime] {
        try merge(values: parseUptimeValues(html), colors: parseRectColors(html), dayData: parseUptimeData(html))
    }

    static func assemble(showcase data: Data) throws -> [String: ComponentUptime] {
        let showcase = try JSONDecoder().decode(UptimeShowcase.self, from: data)
        guard let values = showcase.values else { throw ParseError.uptimeValuesNotFound }
        let markup = (showcase.components ?? [:]).values.joined(separator: "\n")
        return try merge(values: values, colors: parseRectColors(markup), dayData: showcase.timelines)
    }

    // Component ids of the lazy-load placeholders, in page order, deduplicated
    // and capped at the server's batch limit. Empty for the inline shape.
    static func parseLazyComponentIDs(_ html: String) -> [String] {
        let re = #/data-uptime-lazy="([a-z0-9]+)"/#
        var seen = Set<String>()
        var ids: [String] = []
        for match in html.matches(of: re) where seen.insert(String(match.output.1)).inserted {
            ids.append(String(match.output.1))
        }
        return Array(ids.prefix(showcaseBatchLimit))
    }

    static let showcaseBatchLimit = 60

    private static func merge(
        values: [UptimeValue], colors: [String: [String]], dayData: [String: UptimeComponentRaw]?
    ) throws -> [String: ComponentUptime] {
        var out: [String: ComponentUptime] = [:]
        for value in values {
            // 90 bars expected; tolerate small template drift, reject nonsense.
            guard let hexes = colors[value.component], (85...95).contains(hexes.count) else { continue }
            let days = dayData?[value.component]?.days
            let aligned = days?.count == hexes.count ? days : nil
            let bars = hexes.enumerated().map { index, hex in
                let day = aligned?[index]
                return DayBar(
                    id: index,
                    colorHex: hex,
                    date: day?.date,
                    partialSeconds: day?.outages?.p ?? 0,
                    majorSeconds: day?.outages?.m ?? 0,
                    eventNames: day?.relatedEvents?.map { $0.name } ?? []
                )
            }
            out[value.component] = ComponentUptime(
                componentID: value.component,
                ninetyDayPercent: value.ninety,
                bars: bars
            )
        }
        guard !out.isEmpty else { throw ParseError.noComponentsParsed }
        return out
    }

    static func parseUptimeValues(_ html: String) throws -> [UptimeValue] {
        let re = #/uptimeValues\s*=\s*(\[.*?\])\s*[;\n]/#.dotMatchesNewlines()
        guard let match = html.firstMatch(of: re) else { throw ParseError.uptimeValuesNotFound }
        return try JSONDecoder().decode([UptimeValue].self, from: Data(String(match.output.1).utf8))
    }

    // componentID -> hex colors ordered day-0 (oldest) ... day-89 (today).
    // Attribute order inside the rect tag is not assumed.
    static func parseRectColors(_ html: String) -> [String: [String]] {
        let rectRe = #/<rect\b[^>]*uptime-day component-[^>]*>/#
        let fillRe = #/fill="(#[0-9a-fA-F]{3,8})"/#
        let idRe = #/component-([a-z0-9]+) day-([0-9]+)/#

        var acc: [String: [(Int, String)]] = [:]
        for match in html.matches(of: rectRe) {
            let tag = String(match.output)
            guard let fill = tag.firstMatch(of: fillRe),
                  let ids = tag.firstMatch(of: idRe),
                  let day = Int(ids.output.2)
            else { continue }
            acc[String(ids.output.1), default: []].append((day, String(fill.output.1)))
        }
        return acc.mapValues { pairs in pairs.sorted { $0.0 < $1.0 }.map { $0.1 } }
    }

    // Soft extraction: a literal "};" inside an incident name would truncate the
    // lazy match; that only loses tooltips, never bars. Matches the first of the
    // two identical assignments (window.uptimeData = ..., var uptimeData = ...).
    static func parseUptimeData(_ html: String) -> [String: UptimeComponentRaw]? {
        let re = #/uptimeData\s*=\s*(\{.*?\})\s*[;\n]/#.dotMatchesNewlines()
        guard let match = html.firstMatch(of: re) else { return nil }
        return try? JSONDecoder().decode([String: UptimeComponentRaw].self, from: Data(String(match.output.1).utf8))
    }
}
