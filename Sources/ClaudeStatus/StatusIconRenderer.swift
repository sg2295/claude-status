import AppKit

@MainActor
enum StatusIconRenderer {
    private static var cache: [IconState: NSImage] = [:]

    // Clawd, the Claude Code mascot, as a pixel grid ('#' = body, '.' = empty).
    // The eye pixels are left transparent so the menu bar shows through them.
    private static let clawd = [
        "..#########..",
        "..##.###.##..",
        "..##.###.##..",
        "..#########..",
        "#############",
        "#############",
        "#############",
        "..#########..",
        "..#.#...#.#..",
        "..#.#...#.#..",
    ]

    private static let pixelSize: CGFloat = 1.5
    private static let dotDiameter: CGFloat = 7
    private static let dotGap: CGFloat = 1.5

    static func image(for state: IconState) -> NSImage {
        if let cached = cache[state] { return cached }

        let dotColor: NSColor = switch state {
        case .operational: .systemGreen
        case .degraded: .systemOrange
        case .major: .systemRed
        case .unknown: .systemGray
        }

        let rows = clawd.count
        let cols = clawd[0].count
        let size = NSSize(
            width: CGFloat(cols) * pixelSize,
            height: CGFloat(rows) * pixelSize
        )
        // flipped so grid row 0 is the top of the icon
        let image = NSImage(size: size, flipped: true) { _ in
            // labelColor resolves at draw time: white on a dark menu bar,
            // black on a light one.
            NSColor.labelColor.set()
            for (y, row) in clawd.enumerated() {
                for (x, ch) in row.enumerated() where ch == "#" {
                    NSRect(
                        x: CGFloat(x) * pixelSize,
                        y: CGFloat(y) * pixelSize,
                        width: pixelSize,
                        height: pixelSize
                    ).fill()
                }
            }

            // Status dot badge, bottom right, with a transparent separation
            // ring punched out of the body behind it.
            let dotRect = NSRect(
                x: size.width - dotDiameter,
                y: size.height - dotDiameter,
                width: dotDiameter,
                height: dotDiameter
            )
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.setBlendMode(.clear)
                ctx.fillEllipse(in: dotRect.insetBy(dx: -dotGap, dy: -dotGap))
                ctx.setBlendMode(.normal)
                ctx.setFillColor(dotColor.cgColor)
                ctx.fillEllipse(in: dotRect)
            }
            return true
        }
        image.isTemplate = false
        cache[state] = image
        return image
    }
}
