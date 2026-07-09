import Dispatch
import Foundation

// Regression canary for the fragile HTML parsing layer, runnable without
// XCTest (Command Line Tools ship no test framework). Wired to `make check`.
enum SelfTest {
    static func runBlocking(arguments: [String]) -> Never {
        Task.detached {
            exit(await run(arguments: arguments))
        }
        dispatchMain()
    }

    static func run(arguments: [String]) async -> Int32 {
        do {
            let html: String
            let isFixture: Bool
            if let path = arguments.first(where: { $0.hasSuffix(".html") }) {
                print("Parsing fixture \(path)")
                html = try String(contentsOfFile: path, encoding: .utf8)
                isFixture = true
            } else {
                print("Fetching live homepage...")
                html = try await StatusAPIClient().fetchHomepageHTML()
                isFixture = false
            }

            let uptime = try HomepageUptimeParser.assemble(html: html)
            var failures: [String] = []
            for (id, componentUptime) in uptime.sorted(by: { $0.key < $1.key }) {
                let bars = componentUptime.bars
                let eventDays = bars.filter { !$0.eventNames.isEmpty }.count
                let datedBars = bars.filter { $0.date != nil }.count
                print("  \(id): bars=\(bars.count) dated=\(datedBars) eventDays=\(eventDays) ninety=\(componentUptime.ninetyDayPercent)")
                if bars.count != 90 {
                    failures.append("\(id): expected 90 bars, got \(bars.count)")
                }
                if !(0...100).contains(componentUptime.ninetyDayPercent) {
                    failures.append("\(id): implausible ninety value \(componentUptime.ninetyDayPercent)")
                }
            }
            if uptime.count < 3 {
                failures.append("only \(uptime.count) components parsed")
            }

            if !isFixture {
                let summary = try await StatusAPIClient().fetchSummary()
                print("Summary: \(summary.status.description)")
                for component in summary.components where component.showcase {
                    print("  \(component.name): \(component.status.rawValue)")
                }
                if summary.components.isEmpty {
                    failures.append("summary has no components")
                }
            }

            guard failures.isEmpty else {
                print("SELFTEST FAIL")
                failures.forEach { print("  - \($0)") }
                return 1
            }
            print("SELFTEST PASS")
            return 0
        } catch {
            print("SELFTEST FAIL: \(error)")
            return 1
        }
    }
}
