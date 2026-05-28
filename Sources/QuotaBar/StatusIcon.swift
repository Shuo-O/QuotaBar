import AppKit

enum StatusIcon {
    private static let iconSize: CGFloat = 20
    private static let gap: CGFloat = 4

    // MARK: - Ring mode image

    static func makeRingImage(snapshot: UsageSnapshot, showClaude: Bool, showCodex: Bool) -> NSImage {
        var items: [(name: String, percent: Double?, brandColor: NSColor)] = []
        if showClaude {
            items.append(("claude", snapshot.claude.percent,
                          NSColor(calibratedRed: 0.80, green: 0.47, blue: 0.36, alpha: 1)))
        }
        if showCodex {
            items.append(("codex", snapshot.codex.percent, NSColor.labelColor))
        }
        if items.isEmpty {
            items.append(("fallback", nil, NSColor.systemGray))
        }

        let w = CGFloat(items.count) * iconSize + CGFloat(max(items.count - 1, 0)) * gap
        let image = NSImage(size: NSSize(width: w, height: iconSize))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        for (i, item) in items.enumerated() {
            let x = CGFloat(i) * (iconSize + gap)
            drawSplitIcon(name: item.name, percent: item.percent, brandColor: item.brandColor,
                          in: NSRect(x: x, y: 0, width: iconSize, height: iconSize))
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func ringItemLength(showClaude: Bool, showCodex: Bool) -> CGFloat {
        let count = max([showClaude, showCodex].filter { $0 }.count, 1)
        return CGFloat(count) * iconSize + CGFloat(count - 1) * gap + 8
    }

    // MARK: - Split icon (bright sector = remaining, dark sector = used)

    private static func drawSplitIcon(name: String, percent: Double?, brandColor: NSColor, in rect: NSRect) {
        // No logo: fallback dot colored by remaining
        guard name != "fallback", let logo = loadLogo(named: name) else {
            let rem = percent.map { max(0.0, 100.0 - $0) }
            let color = rem.map { remainingColor($0) } ?? NSColor.systemGray
            color.withAlphaComponent(percent == nil ? 0.38 : 1.0).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            return
        }

        // No data: draw dim icon
        guard let pct = percent else {
            drawColored(logo, in: rect, tint: .systemGray, alpha: 0.35)
            return
        }

        let remaining = max(0.0, min(100.0, 100.0 - pct))

        // Step 1 – full icon in dark (= the "used" portion background)
        drawColored(logo, in: rect, tint: .black, alpha: 0.72)

        // Step 2 – clip to the remaining sector and overdraw with bright color
        guard remaining > 0.5 else { return }

        let sweep = CGFloat(remaining / 100.0) * 360.0
        let center = NSPoint(x: rect.midX, y: rect.midY)
        // Radius large enough to always cover the entire rect from its center
        let clipR = hypot(rect.width, rect.height)

        let sector = NSBezierPath()
        sector.move(to: center)
        // Start at 12 o'clock (90°), sweep clockwise = increasing usage covers bottom first
        sector.appendArc(withCenter: center, radius: clipR,
                         startAngle: 90, endAngle: 90 - sweep, clockwise: true)
        sector.close()

        NSGraphicsContext.saveGraphicsState()
        sector.addClip()
        drawColored(logo, in: rect, tint: remainingColor(remaining), alpha: 1.0)
        NSGraphicsContext.restoreGraphicsState()
    }

    // Draws `logo` filled with `tint` at `alpha`, using the logo's shape as a mask.
    private static func drawColored(_ logo: NSImage, in rect: NSRect, tint: NSColor, alpha: CGFloat) {
        // First pass: render logo pixels into the context (establishes alpha mask)
        logo.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)
        // Second pass: paint tint color only where logo pixels exist
        tint.withAlphaComponent(alpha).set()
        rect.fill(using: .sourceAtop)
    }

    // MARK: - Logo loading

    private static func loadLogo(named name: String) -> NSImage? {
        let candidates: [URL?] = [
            Bundle.main.resourceURL?.appendingPathComponent("Icons/\(name).svg"),
            Bundle.main.resourceURL?.appendingPathComponent("\(name).svg"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Icons/\(name).svg")
        ]
        return candidates.compactMap { $0 }.compactMap { NSImage(contentsOf: $0) }.first
    }

    // MARK: - Color helpers

    /// Green = plenty remaining, red = almost empty
    static func remainingColor(_ remaining: Double) -> NSColor {
        switch remaining {
        case 50...100: return .systemGreen
        case 20..<50:  return .systemYellow
        case 5..<20:   return .systemOrange
        default:       return .systemRed
        }
    }

    /// Green = low usage, red = high usage
    static func usageColor(_ percent: Double?) -> NSColor {
        guard let p = percent else { return .secondaryLabelColor }
        switch p {
        case 0..<50:  return .systemGreen
        case 50..<80: return .systemYellow
        case 80..<95: return .systemOrange
        default:      return .systemRed
        }
    }
}
