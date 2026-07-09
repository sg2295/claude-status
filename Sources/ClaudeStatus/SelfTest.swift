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
        var failures = await unitChecks()
        print(failures.isEmpty ? "Unit checks passed" : "Unit checks: \(failures.count) failing")
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
            for (id, componentUptime) in uptime.sorted(by: { $0.key < $1.key }) {
                let bars = componentUptime.bars
                let eventDays = bars.filter { !$0.eventNames.isEmpty }.count
                let datedBars = bars.filter { $0.date != nil }.count
                print("  \(sanitized(id)): bars=\(bars.count) dated=\(datedBars) eventDays=\(eventDays) ninety=\(componentUptime.ninetyDayPercent)")
                if bars.count != 90 {
                    failures.append("\(sanitized(id)): expected 90 bars, got \(bars.count)")
                }
                if !(0...100).contains(componentUptime.ninetyDayPercent) {
                    failures.append("\(sanitized(id)): implausible ninety value \(componentUptime.ninetyDayPercent)")
                }
            }
            if uptime.count < 3 {
                failures.append("only \(uptime.count) components parsed")
            }

            if !isFixture {
                let summary = try await StatusAPIClient().fetchSummary()
                print("Summary: \(sanitized(summary.status.description))")
                for component in summary.components where component.showcase {
                    print("  \(sanitized(component.name)): \(component.status.rawValue)")
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

    // Remote-origin strings (component names, incident text) are printed to
    // the terminal here; anything outside printable ASCII could smuggle
    // terminal escape sequences, so it is replaced with "?".
    static func sanitized(_ s: String) -> String {
        String(s.unicodeScalars.map { scalar in
            (32...126).contains(scalar.value) ? Character(scalar) : "?"
        })
    }

    // MARK: - Unit checks

    // Pure-logic checks for the hardening layer, run before the parse so a
    // network failure cannot skip them.
    private static func unitChecks() async -> [String] {
        var failures: [String] = []
        let defaultBase = "https://status.claude.com"

        if StatusAPIClient.resolveBaseURL(nil).absoluteString != defaultBase {
            failures.append("resolveBaseURL(nil) should be the default base")
        }
        if StatusAPIClient.resolveBaseURL("").absoluteString != defaultBase {
            failures.append("resolveBaseURL(empty) should fall back, not crash")
        }
        if StatusAPIClient.resolveBaseURL("not a url").absoluteString != defaultBase {
            failures.append("resolveBaseURL(garbage) should fall back to the default base")
        }
        if StatusAPIClient.resolveBaseURL("http://localhost:8080").absoluteString != "http://localhost:8080" {
            failures.append("resolveBaseURL should honor an http mock override")
        }

        switch await collectResult(byteCount: 10, limit: 100) {
        case .success(let data) where data.count == 10: break
        default: failures.append("collect should pass a 10-byte stream through a 100-byte limit")
        }
        switch await collectResult(byteCount: 101, limit: 100) {
        case .failure: break
        default: failures.append("collect should throw when the stream exceeds the limit")
        }

        if sanitized("claude.ai: OK") != "claude.ai: OK" {
            failures.append("sanitized should keep printable ASCII unchanged")
        }
        if sanitized("a\u{1B}[31mb") != "a?[31mb" {
            failures.append("sanitized should replace the ESC control character")
        }
        return failures
    }

    private static func collectResult(byteCount: Int, limit: Int) async -> Result<Data, any Error> {
        let stream = AsyncStream<UInt8> { continuation in
            for _ in 0..<byteCount { continuation.yield(0x41) }
            continuation.finish()
        }
        do {
            return .success(try await StatusAPIClient.collect(stream, limit: limit, url: "unit-check"))
        } catch {
            return .failure(error)
        }
    }
}
