import AppKit

@MainActor
enum StatusIconRenderer {
    private static var cache: [IconState: NSImage] = [:]

    static func image(for state: IconState) -> NSImage {
        if let cached = cache[state] { return cached }

        let symbolName = state == .unknown ? "questionmark" : "sparkle"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Claude status")!
            .withSymbolConfiguration(config)!

        let tint: NSColor? = switch state {
        case .degraded: .systemOrange
        case .major: .systemRed
        case .operational, .unknown: nil
        }

        let image: NSImage
        if let tint {
            // Draw the glyph then flood its alpha with the tint color; this is
            // reliable in the status bar where symbol palette configurations
            // are sometimes ignored.
            let size = NSSize(width: 18, height: 18)
            let baseSize = base.size
            image = NSImage(size: size, flipped: false) { rect in
                let origin = NSPoint(
                    x: rect.midX - baseSize.width / 2,
                    y: rect.midY - baseSize.height / 2
                )
                base.draw(in: NSRect(origin: origin, size: baseSize))
                tint.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            image.isTemplate = false
        } else {
            image = base
            image.isTemplate = true
        }
        cache[state] = image
        return image
    }
}
