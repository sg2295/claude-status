import AppKit
import ServiceManagement
import SwiftUI

struct StatusPanelView: View {
    let store: StatusStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 500)
        .task {
            if store.summary == nil { await store.refreshSummary() }
            await store.refreshUptimeIfStale()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(PageIndicator.color(for: store.summary?.status.indicator ?? ""))
                .frame(width: 10, height: 10)
            Text(store.summary?.status.description ?? "Loading status...")
                .fontWeight(.semibold)
            Spacer()
            if let fetchedAt = store.summaryFetchedAt {
                Text("Updated \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        if store.summary == nil {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(40)
        } else {
            // No ScrollView: a MenuBarExtra window sizes to the content's ideal
            // height, and ScrollView has no intrinsic height, so it collapses
            // to zero there. The card stack's own height drives the window.
            VStack(spacing: 10) {
                ForEach(store.showcaseComponents) { component in
                    ComponentCardView(
                        component: component,
                        uptime: store.uptime[component.id]
                    )
                }
            }
            .padding(12)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if store.uptimeError != nil && store.uptime.isEmpty {
                Text("Uptime history unavailable, showing live status only")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                Spacer()
                Button("status.claude.com") {
                    NSWorkspace.shared.open(URL(string: "https://status.claude.com")!)
                }
                Spacer()
                LaunchAtLoginToggle()
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
        .padding(10)
    }
}

// Registers/unregisters the running app bundle as a login item. Works with
// ad-hoc signing for a locally built app; a plain `swift run` binary (no
// bundle) fails to register, in which case the toggle snaps back.
private struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: $enabled)
            .toggleStyle(.checkbox)
            .font(.caption)
            .onChange(of: enabled) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}
