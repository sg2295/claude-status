import Foundation

enum ParseError: Error, CustomStringConvertible {
    case uptimeValuesNotFound
    case noComponentsParsed

    var description: String {
        switch self {
        case .uptimeValuesNotFound:
            return "uptimeValues assignment not found in homepage HTML"
        case .noComponentsParsed:
            return "no component uptime data could be parsed from homepage HTML"
        }
    }
}

// Extracts the uptime section data that status.claude.com (Atlassian Statuspage)
// embeds in its homepage. Three independent extractions, merged by day index:
//   1. uptimeValues JS assignment: the exact displayed 90-day percentages (required)
//   2. SVG rect fills: the exact per-day bar colors (required per component)
//   3. uptimeData JS assignment: per-day dates, outage seconds, incident names
//      (soft; only tooltips are lost when it fails)
// Fallback if uptimeValues ever disappears: Statuspage computes
//   uptime = 1 - (m + 0.3 * p) / (elapsed_days * 86400)
// from the day-level outage seconds in uptimeData (verified against the
// month-level uptime_percentage values of /uptime/{id}.json).
enum HomepageUptimeParser {

    static func assemble(html: String) throws -> [String: ComponentUptime] {
        let values = try parseUptimeValues(html)
        let colors = parseRectColors(html)
        let dayData = parseUptimeData(html)

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
