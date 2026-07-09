import SwiftUI

struct ClaudeStatusApp: App {
    @State private var store = StatusStore()

    var body: some Scene {
        MenuBarExtra {
            StatusPanelView(store: store)
        } label: {
            MenuBarIconLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

// Child view so Observation registers the iconState read in a view body,
// guaranteeing the menu bar label refreshes when the state changes.
private struct MenuBarIconLabel: View {
    let store: StatusStore

    var body: some View {
        Image(nsImage: StatusIconRenderer.image(for: store.iconState))
    }
}
