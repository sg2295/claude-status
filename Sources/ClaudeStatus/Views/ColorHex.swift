import SwiftUI

extension Color {
    init?(hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: 1
        )
    }
}

// Statuspage's standard status labels and colors.
extension ComponentStatus {
    var label: String {
        switch self {
        case .operational: "Operational"
        case .degradedPerformance: "Degraded Performance"
        case .partialOutage: "Partial Outage"
        case .majorOutage: "Major Outage"
        case .underMaintenance: "Under Maintenance"
        case .unknown: "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .operational: Color(hex: "#2fcc66") ?? .green
        case .degradedPerformance: Color(hex: "#f1c40f") ?? .yellow
        case .partialOutage: Color(hex: "#e67e22") ?? .orange
        case .majorOutage: Color(hex: "#e74c3c") ?? .red
        case .underMaintenance: Color(hex: "#3498db") ?? .blue
        case .unknown: .secondary
        }
    }
}

enum PageIndicator {
    static func color(for indicator: String) -> Color {
        switch indicator {
        case "none": Color(hex: "#2fcc66") ?? .green
        case "minor": Color(hex: "#f1c40f") ?? .yellow
        case "major": Color(hex: "#e67e22") ?? .orange
        case "critical": Color(hex: "#e74c3c") ?? .red
        default: .secondary
        }
    }
}
