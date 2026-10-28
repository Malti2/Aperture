import SwiftUI

/// Draws the engine state. The engine itself is stepped by `GameLoop`, not from here.
struct PlayfieldView: View {
    let engine: Engine
    let phase: Phase
    let ball: ShopItem
    let trailSkin: ShopItem
    let theme: Theme
    /// Horizontal touch position as 0...1.
    let onDrag: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    _ = timeline.date // redraw every frame
                    draw(context: &context, size: size)
                }
            }
            .onChange(of: geo.size, initial: true) { _, new in engine.size = new }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard engine.size.width > 0 else { return }
                    onDrag(min(max(value.location.x / engine.size.width, 0), 1))
                }
        )
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let full = CGRect(origin: .zero, size: size)
        context.fill(
            Path(full),
            with: .linearGradient(
                Gradient(colors: [theme.top, theme.bottom]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            )
        )
        let accent = theme.accent
        let dimmed = phase != .playing

        for bar in engine.bars {
            let fade = bar.passed ? 0.55 : 1.0
            let tint: Color = bar.dashed ? accent : .white
            let leftW = max(0, bar.gapX - bar.gapW / 2)
            let rightX = bar.gapX + bar.gapW / 2
            let rects = [
                CGRect(x: -20, y: bar.y, width: leftW + 20, height: engine.thick),
                CGRect(x: rightX, y: bar.y, width: size.width - rightX + 20, height: engine.thick)
            ]
            for r in rects {
                let p = Path(roundedRect: r, cornerRadius: 11)
                context.fill(p, with: .color(tint.opacity((dimmed ? 0.10 : 0.16) * fade)))
                context.stroke(p, with: .color(tint.opacity((dimmed ? 0.35 : 0.8) * fade)), lineWidth: 1.5)
            }
        }

        for p in engine.pickups {
            let pr: CGFloat = 15
            let rect = CGRect(x: p.x - pr, y: p.y - pr, width: pr * 2, height: pr * 2)
            context.fill(Path(ellipseIn: rect.insetBy(dx: -8, dy: -8)),
                         with: .radialGradient(Gradient(colors: [p.kind.color.opacity(0.4), p.kind.color.opacity(0)]),
                                               center: CGPoint(x: p.x, y: p.y), startRadius: 0, endRadius: pr + 8))
            context.fill(Path(ellipseIn: rect), with: .color(p.kind.color.opacity(0.25)))
            context.stroke(Path(ellipseIn: rect), with: .color(p.kind.color), lineWidth: 1.5)
            var icon = context.resolve(Image(systemName: p.kind.symbol))
            icon.shading = .color(p.kind.color)
            context.draw(icon, at: CGPoint(x: p.x, y: p.y))
        }

        // The Shop shows only the ball picker; the idle ball swinging behind it stays hidden.
        if phase == .shop { return }
        let y = engine.playerY
        let r = engine.radius
        let step = max(6, engine.worldSpeed * 0.012)
        for (i, x) in engine.trail.reversed().enumerated() {
            let k = 1 - Double(i) / 18
            let rr = r * CGFloat(0.35 + 0.6 * k)
            let rect = CGRect(x: x - rr, y: y + CGFloat(i) * step - rr, width: rr * 2, height: rr * 2)
            let tint: Color = engine.dashing ? accent
                : trailSkin.rainbow ? Color(hue: Double(i) / 18 * 0.8, saturation: 0.6, brightness: 1) : trailSkin.color
            context.fill(Path(ellipseIn: rect), with: .color(tint.opacity((trailSkin.cost == 0 ? 0.16 : 0.3) * k)))
        }
        let x = engine.px * size.width
        let glowR = r * (engine.dashing ? 4.2 : 2.6)
        context.fill(
            Path(ellipseIn: CGRect(x: x - glowR, y: y - glowR, width: glowR * 2, height: glowR * 2)),
            with: .radialGradient(
                Gradient(colors: [accent.opacity(engine.dashing ? 0.7 : 0.35), accent.opacity(0)]),
                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: glowR
            )
        )
        context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(ball.color))
        if engine.shield {
            let sr = r + 9
            context.stroke(Path(ellipseIn: CGRect(x: x - sr, y: y - sr, width: sr * 2, height: sr * 2)),
                           with: .color(PowerUp.shield.color.opacity(0.9)), lineWidth: 2.5)
        }
    }
}
