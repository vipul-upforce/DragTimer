import AppKit

/// Gestimer-style rubber-band from the menu-bar origin to the cursor.
/// Layered strokes keep it readable on light and dark wallpapers; ticks
/// along the path reinforce the “drag = duration” metaphor.
@MainActor
final class DragLineCanvas: NSView {
    var origin: NSPoint = .zero { didSet { needsDisplay = true } }
    var cursor: NSPoint = .zero { didSet { needsDisplay = true } }
    var isActive = false { didSet { needsDisplay = true } }
    /// 0…1 — reaches 1 once a creatable timer duration (≥ 60s) is reached.
    var progress: CGFloat = 0 { didSet { needsDisplay = true } }

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { self }

    override func draw(_ dirtyRect: NSRect) {
        guard isActive, let ctx = NSGraphicsContext.current?.cgContext else { return }

        let start = convertFromScreen(origin)
        let end = convertFromScreen(cursor)
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > 0.5 else {
            drawOrigin(at: start, in: ctx, ready: false)
            return
        }

        let ready = progress >= 1
        let ux = dx / length
        let uy = dy / length

        ctx.saveGState()
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        // 1) Soft drop shadow — contrast on bright desktops.
        strokeLine(from: start, to: end, width: ready ? 6 : 5,
                   color: NSColor.black.withAlphaComponent(0.22), in: ctx)

        // 2) Light halo — contrast on dark desktops / wallpapers.
        strokeLine(from: start, to: end, width: ready ? 4.5 : 3.5,
                   color: NSColor.white.withAlphaComponent(ready ? 0.55 : 0.35), in: ctx)

        // 3) Core stroke — crisp measuring tape.
        let core = ready
            ? NSColor.controlAccentColor.withAlphaComponent(0.95)
            : NSColor.labelColor.withAlphaComponent(0.72)
        strokeLine(from: start, to: end, width: ready ? 2.25 : 1.75, color: core, in: ctx)

        // 4) Duration ticks along the band (skip near the caps).
        drawTicks(from: start, ux: ux, uy: uy, length: length, ready: ready, in: ctx)

        // 5) Caps.
        drawOrigin(at: start, in: ctx, ready: ready)
        drawTip(at: end, towardX: ux, towardY: uy, in: ctx, ready: ready)

        ctx.restoreGState()
    }

    // MARK: - Pieces

    private func strokeLine(from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor, in ctx: CGContext) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.move(to: start)
        ctx.addLine(to: end)
        ctx.strokePath()
    }

    private func drawTicks(from start: CGPoint, ux: CGFloat, uy: CGFloat, length: CGFloat, ready: Bool, in ctx: CGContext) {
        // Tick every ~36pt ≈ one fine duration step in the mapper’s short range.
        let spacing: CGFloat = 36
        guard length > spacing * 1.4 else { return }

        let px = -uy // perpendicular
        let py = ux
        let majorEvery = 5
        var index = 1
        var d = spacing
        while d < length - 14 {
            let cx = start.x + ux * d
            let cy = start.y + uy * d
            let isMajor = index % majorEvery == 0
            let half: CGFloat = isMajor ? 5.5 : 3.0
            let alpha: CGFloat = ready ? (isMajor ? 0.7 : 0.4) : (isMajor ? 0.45 : 0.28)
            let color = (ready ? NSColor.controlAccentColor : NSColor.labelColor)
                .withAlphaComponent(alpha)

            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(isMajor ? 1.6 : 1.1)
            ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: cx - px * half, y: cy - py * half))
            ctx.addLine(to: CGPoint(x: cx + px * half, y: cy + py * half))
            ctx.strokePath()

            d += spacing
            index += 1
        }
    }

    private func drawOrigin(at point: CGPoint, in ctx: CGContext, ready: Bool) {
        // Outer halo
        fillCircle(at: point, radius: 7, color: NSColor.white.withAlphaComponent(0.25), in: ctx)
        // Body
        fillCircle(at: point, radius: 4.2,
                   color: (ready ? NSColor.controlAccentColor : NSColor.labelColor).withAlphaComponent(0.9),
                   in: ctx)
        // Specular
        fillCircle(at: point, radius: 1.6, color: NSColor.white.withAlphaComponent(0.85), in: ctx)
    }

    private func drawTip(at point: CGPoint, towardX: CGFloat, towardY: CGFloat, in ctx: CGContext, ready: Bool) {
        let outer: CGFloat = ready ? 11 : 8.5
        let inner: CGFloat = ready ? 5.5 : 4.0
        let accent = NSColor.controlAccentColor

        // Soft ground shadow under the tip.
        fillCircle(at: CGPoint(x: point.x, y: point.y - 1), radius: outer + 1,
                   color: NSColor.black.withAlphaComponent(0.18), in: ctx)

        // White ring for contrast.
        fillCircle(at: point, radius: outer, color: NSColor.white.withAlphaComponent(0.92), in: ctx)

        // Accent ring / fill.
        if ready {
            fillCircle(at: point, radius: outer - 1.5, color: accent.withAlphaComponent(0.95), in: ctx)
            fillCircle(at: point, radius: inner, color: NSColor.white.withAlphaComponent(0.95), in: ctx)
            // Tiny chevron hint toward drag direction (reads as “pull”).
            ctx.setFillColor(accent.withAlphaComponent(0.95).cgColor)
            let tip = CGPoint(x: point.x + towardX * 2.2, y: point.y + towardY * 2.2)
            let left = CGPoint(x: point.x - towardX * 2.5 - towardY * 3.2,
                               y: point.y - towardY * 2.5 + towardX * 3.2)
            let right = CGPoint(x: point.x - towardX * 2.5 + towardY * 3.2,
                                y: point.y - towardY * 2.5 - towardX * 3.2)
            ctx.move(to: tip)
            ctx.addLine(to: left)
            ctx.addLine(to: right)
            ctx.closePath()
            ctx.fillPath()
        } else {
            strokeCircle(at: point, radius: outer - 2.2,
                         width: 2,
                         color: accent.withAlphaComponent(0.85),
                         in: ctx)
            fillCircle(at: point, radius: inner - 0.5,
                       color: accent.withAlphaComponent(0.9), in: ctx)
        }
    }

    private func fillCircle(at point: CGPoint, radius: CGFloat, color: NSColor, in ctx: CGContext) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                   width: radius * 2, height: radius * 2))
    }

    private func strokeCircle(at point: CGPoint, radius: CGFloat, width: CGFloat, color: NSColor, in ctx: CGContext) {
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(width)
        ctx.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                     width: radius * 2, height: radius * 2))
    }

    private func convertFromScreen(_ screenPoint: NSPoint) -> NSPoint {
        guard let window else { return screenPoint }
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        return convert(windowPoint, from: nil)
    }
}
