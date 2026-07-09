import SwiftUI

struct ComponentCardView: View {
    let component: Component
    let uptime: ComponentUptime?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(component.name)
                    .fontWeight(.semibold)
                Spacer()
                Text(component.status.label)
                    .font(.subheadline)
                    .foregroundStyle(component.status.color)
            }
            if let uptime {
                UptimeBarsView(bars: uptime.bars)
                HStack(spacing: 8) {
                    caption("90 days ago")
                    separator
                    // uptimeValues is pre-rounded by Statuspage; the site would
                    // show a clean 100 as "100.0" where this renders "100.00".
                    caption(String(format: "%.2f %% uptime", uptime.ninetyDayPercent))
                    separator
                    caption("Today")
                }
            } else {
                Text("Uptime history unavailable")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private var separator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }
}
