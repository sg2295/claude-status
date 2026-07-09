import AppKit
import Foundation
import Observation

enum IconState: String, Sendable {
    case operational
    case degraded
    case major
    case unknown
}

@MainActor @Observable
final class StatusStore {
    private(set) var summary: Summary?
    private(set) var summaryFetchedAt: Date?
    private(set) var uptime: [String: ComponentUptime] = [:]
    private(set) var uptimeFetchedAt: Date?
    private(set) var uptimeError: String?
    private(set) var consecutiveFailures = 0
    private(set) var isRefreshing = false

    private let client = StatusAPIClient()

    // Testing hook: CLAUDE_STATUS_FORCE_STATE=operational|degraded|major|unknown
    private let forcedState = ProcessInfo.processInfo
        .environment["CLAUDE_STATUS_FORCE_STATE"]
        .flatMap { IconState(rawValue: $0) }

    // The icon reacts only to these components. Matched by name (what the user
    // asked to track) OR id (survives a rename), so either changing alone keeps
    // the tracking intact.
    static let trackedNames: Set<String> = ["claude.ai", "Claude Code"]
    static let trackedIDs: Set<String> = ["rwppv331jlwc", "yyzkbfz2thpt"]

    static let pollInterval: Duration = .seconds(90)
    static let uptimeTTL: TimeInterval = 300
    static let failuresBeforeUnknown = 3

    var iconState: IconState {
        if let forcedState { return forcedState }
        guard let summary, consecutiveFailures < Self.failuresBeforeUnknown else { return .unknown }
        let tracked = summary.components.filter {
            Self.trackedNames.contains($0.name) || Self.trackedIDs.contains($0.id)
        }
        if tracked.contains(where: { $0.status == .majorOutage }) { return .major }
        if tracked.contains(where: { $0.status != .operational && $0.status != .unknown }) { return .degraded }
        return .operational
    }

    var showcaseComponents: [Component] {
        (summary?.components ?? [])
            .filter { $0.showcase }
            .sorted { $0.position < $1.position }
    }

    init() {
        Task { await pollLoop() }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refreshSummary() }
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await refreshSummary()
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    func refreshSummary() async {
        do {
            summary = try await client.fetchSummary()
            summaryFetchedAt = Date()
            consecutiveFailures = 0
        } catch {
            consecutiveFailures += 1
        }
    }

    func refreshUptimeIfStale() async {
        if let fetchedAt = uptimeFetchedAt,
           Date().timeIntervalSince(fetchedAt) < Self.uptimeTTL,
           !uptime.isEmpty {
            return
        }
        await refreshUptime()
    }

    func refreshUptime() async {
        do {
            uptime = try await client.fetchUptime()
            uptimeFetchedAt = Date()
            uptimeError = nil
        } catch {
            // Keep previously cached bars; the panel falls back to status-only cards.
            uptimeError = "\(error)"
        }
    }

    func refreshAll() async {
        isRefreshing = true
        await refreshSummary()
        await refreshUptime()
        isRefreshing = false
    }
}
