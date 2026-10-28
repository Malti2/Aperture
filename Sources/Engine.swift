import SwiftUI

/// Plain game state. Stepped once per display frame by `GameLoop`, drawn by `PlayfieldView`.
/// Steering input arrives from the camera queue, so target and rawSteer sit behind a lock.
final class Engine {
    struct Bar {
        var y: CGFloat
        var gapX: CGFloat
        var gapW: CGFloat
        var passed = false
        var dashed = false
    }

    var size: CGSize = .zero
    private(set) var px: CGFloat = 0.5
    private(set) var bars: [Bar] = []
    private(set) var trail: [CGFloat] = []
    var running = false
    var holding = false
    var paused = false
    /// Slider travel is bounded, so the middle part of it reaches the whole field.
    static var steerGain: CGFloat = 4.0
    /// 0.005 (earlier step) divided by 0.001 (current step).
    static let stepScale: CGFloat = 5
    /// Demo flag: steers itself through the gaps.
    var bot = false
    private(set) var score: Double = 0
    /// Floors passed this round, and the lightning earned for them. Dashed floors count the same.
    private(set) var floors = 0
    private(set) var lightning = 0
    /// Prototype curve: floors 1-5 give 1 lightning each, 6-10 give 2, 11-15 give 3, and so on.
    static func reward(forFloor n: Int) -> Int { 1 + max(0, n - 1) / 5 }
    private(set) var dashLeft: Double = 0
    private(set) var cooldown: Double = 0
    private(set) var worldSpeed: CGFloat = 0

    var onEnd: (() -> Void)?
    var onDash: (() -> Void)?
    var onFloor: (() -> Void)?
    var onShopPick: ((Int) -> Void)?
    var pressHandler: (() -> Void)?
    var pressBegan: (() -> Void)?
    var pressCancel: (() -> Void)?

    let thick: CGFloat = 22
    let radius: CGFloat = 13
    private let dashDuration = 0.45
    private let dashCooldown = 2.0
    private let spacing: CGFloat = 250
    private var last: TimeInterval?
    private var travel: CGFloat = 0
    private var lastGapX: CGFloat = 0
    private var attractPhase: Double = 0

    private let lock = NSLock()
    private var _target: CGFloat = 0.5
    private var _rawSteer: CGFloat = 0.5

    var playerY: CGFloat { size.height * 0.8 }
    var dashing: Bool { dashLeft > 0 }
    var charge: Double { cooldown <= 0 ? 1 : max(0, 1 - cooldown / dashCooldown) }

    /// Where the ball wants to be, 0...1 across the field.
    var target: CGFloat {
        get { lock.lock(); defer { lock.unlock() }; return _target }
        set { lock.lock(); _target = newValue; lock.unlock() }
    }

    /// Last value reported by the Camera Control slider.
    var rawSteer: CGFloat {
        get { lock.lock(); defer { lock.unlock() }; return _rawSteer }
        set { lock.lock(); _rawSteer = newValue; lock.unlock() }
    }

    /// Relative mapping: the ball moves by the slider delta times the gain. A swipe delivers roughly
    /// a fixed number of steps, so the delta shrinks with the step size; stepScale keeps the feel.
    func steer(slider value: CGFloat) {
        lock.lock()
        let delta = value - _rawSteer
        _rawSteer = value
        if !paused { _target = min(max(_target + delta * Engine.steerGain * Engine.stepScale, 0), 1) }
        lock.unlock()
    }

    func reset() {
        bars = []
        trail = []
        score = 0
        floors = 0
        lightning = 0
        dashLeft = 0
        cooldown = 0
        travel = 150
        lastGapX = size.width / 2
        px = 0.5
        target = 0.5
    }

    func dash() {
        guard running, cooldown <= 0 else { return }
        dashLeft = dashDuration
        cooldown = dashCooldown
        onDash?()
    }

    private func spawn() {
        let w = size.width
        let gapW = max(118, 230 - CGFloat(score) * 0.35)
        let lo = gapW / 2 + 18
        let hi = w - gapW / 2 - 18
        let maxShift = w * 0.6
        let candidate = CGFloat.random(in: lo...hi)
        let x = min(max(candidate, lastGapX - maxShift), lastGapX + maxShift)
        let gx = min(max(x, lo), hi)
        lastGapX = gx
        bars.append(Bar(y: -thick, gapX: gx, gapW: gapW))
    }

    /// `now` is a monotonic timestamp in seconds.
    func step(_ now: TimeInterval) {
        guard size.width > 0, size.height > 0 else { return }
        if paused { last = now; return }
        let dt = min(max(now - (last ?? now), 0), 1.0 / 20.0)
        last = now
        let base: CGFloat = running ? 250 + CGFloat(min(score * 0.25, 260)) : 90
        let v = base * (dashing ? 2.6 : 1)
        worldSpeed = v
        let d = CGFloat(dt)

        // Steering
        if !running {
            attractPhase += dt
            target = 0.5 + 0.32 * CGFloat(sin(attractPhase * 0.8))
        } else if bot {
            let ahead = bars.filter { !$0.passed }.max(by: { $0.y < $1.y })
            if let b = ahead { target = b.gapX / size.width }
        }
        px += (target - px) * CGFloat(1 - exp(-dt * 34))
        px = min(max(px, 0), 1)
        if holding { return }

        // World
        for i in bars.indices { bars[i].y += v * d }
        travel += v * d
        if travel >= spacing {
            travel = 0
            spawn()
        }
        bars.removeAll { $0.y > size.height + 40 }

        trail.append(px * size.width)
        if trail.count > 18 { trail.removeFirst(trail.count - 18) }

        guard running else { return }
        score += Double(v * d) * 0.05
        if dashLeft > 0 { dashLeft = max(0, dashLeft - dt) }
        if cooldown > 0 { cooldown = max(0, cooldown - dt) }

        let x = px * size.width
        let py = playerY
        for i in bars.indices {
            let b = bars[i]
            let overlaps = b.y + thick > py - radius && b.y < py + radius
            if overlaps {
                if dashing {
                    bars[i].dashed = true
                } else {
                    let inGap = x - radius >= b.gapX - b.gapW / 2 && x + radius <= b.gapX + b.gapW / 2
                    if !inGap {
                        running = false
                        onEnd?()
                        return
                    }
                }
            }
            if !bars[i].passed && b.y > py + radius {
                bars[i].passed = true
                score += bars[i].dashed ? 25 : 10
                floors += 1
                lightning += Engine.reward(forFloor: floors)
                onFloor?()
            }
        }
    }
}
