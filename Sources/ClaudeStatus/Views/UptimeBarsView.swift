import SwiftUI

struct UptimeBarsView: View {
    let bars: [DayBar]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(bars) { bar in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color(hex: bar.colorHex) ?? .gray)
                    .frame(width: 3, height: 34)
                    .help(bar.tooltip)
            }
        }
    }
}
