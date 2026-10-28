import SwiftUI

enum PowerUp: CaseIterable {
    case shield, magnet, slow

    var symbol: String {
        switch self {
        case .shield: return "shield.fill"
        case .magnet: return "scope"
        case .slow: return "tortoise.fill"
        }
    }

    var color: Color {
        switch self {
        case .shield: return Color(red: 0.42, green: 0.80, blue: 1.0)
        case .magnet: return Color(red: 1.0, green: 0.68, blue: 0.30)
        case .slow: return Color(red: 0.72, green: 0.55, blue: 1.0)
        }
    }
}

/// Small deterministic generator, so the daily challenge is the same course for everyone.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Plain game state. Stepped once per display frame by `GameLoop`, drawn by `PlayfieldView`.
/// Steering input arrives from the camera queue, so target and rawSteer sit behind a lock.
final class Engine {
    struct Bar {
        var y: CGFloat
        var gapX: CGFloat
        var gapW: CGFloat
        var baseX: CGFloat
        /// Moving walls: the gap swings around baseX.
        var amp: CGFloat = 0
        var phase: CGFloat = 0
        var speed: CGFloat = 0
        var passed = false
        var dashed = false
        /// A shield absorbed the hit on this bar.
        var forgiven = false
        /// Smallest clearance to the wall while the ball was in the bar.
        var minMargin: CGFloat = .infinity
    }

    struct Pickup {
        var kind: PowerUp
        var x: CGFloat
        var y: CGFloat
    }

    var size: CGSize = .zero
    private(set) var px: CGFloat = 0.5
    private(set) var bars: [Bar] = []
    private(set) var pickups: [Pickup] = []
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

    /// 0 Calm, 1 Normal, 2 Fast.
    var level = 1
    private var levelScale: CGFloat { [0.8, 1.0, 1.25][min(max(level, 0), 2)] }
    /// Set for the daily challenge; the same seed gives the same course.
    var seed: UInt64?
    private var seeded: SeededRNG?

    private(set) var score: Double = 0
    /// Floors passed this round, and the lightning earned for them. Dashed floors count the same.
    private(set) var floors = 0
    private(set) var lightning = 0
    /// Prototype curve: floors 1-5 give 1 lightning each, 6-10 give 2, 11-15 give 3, and so on.
    static func reward(forFloor n: Int) -> Int { 1 + max(0, n - 1) / 5 }
    private(set) var dashLeft: Double = 0
    private(set) var cooldown: Double = 0
    private(set) var worldSpeed: CGFloat = 0

    // Combo and power-ups
    private(set) var combo = 0
    var multiplier: Int { min(1 + combo / 4, 4) }
    private(set) var shield = false
    private(set) var magnetLeft: Double = 0
    private(set) var slowLeft: Double = 0

    // Round stats
    private(set) var dashes = 0
    private(set) var maxMultiplier = 1
    private(set) var collected = 0
    private(set) var shieldSaves = 0
    private(set) var playTime: Double = 0

    var onEnd: (() -> Void)?
    var onDash: (() -> Void)?
    var onFloor: (() -> Void)?
    var onPickup: ((PowerUp) -> Void)?
    var onShieldBreak: (() -> Void)?
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

    private func pull(toward t: CGFloat, by k: CGFloat) {
        lock.lock()
        _target += (t - _target) * k
        lock.unlock()
    }

    private func rand(_ range: ClosedRange<CGFloat>) -> CGFloat {
        if seeded != nil { return CGFloat.random(in: range, using: &seeded!) }
        return CGFloat.random(in: range)
    }

    func reset() {
        bars = []
        pickups = []
        trail = []
        score = 0
        floors = 0
        lightning = 0
        dashLeft = 0
        cooldown = 0
        combo = 0
        shield = false
        magnetLeft = 0
        slowLeft = 0
        dashes = 0
        maxMultiplier = 1
        collected = 0
        shieldSaves = 0
        playTime = 0
        travel = 150
        lastGapX = size.width / 2
        seeded = seed.map { SeededRNG(seed: $0) }
        px = 0.5
        target = 0.5
    }

    func dash() {
        guard running, cooldown <= 0 else { return }
        dashLeft = dashDuration
        cooldown = dashCooldown
        dashes += 1
        onDash?()
    }

    private func spawn() {
        let w = size.width
        let gapW = max(118, 230 - CGFloat(score) * 0.35)
        let lo = gapW / 2 + 18
        let hi = w - gapW / 2 - 18
        let maxShift = w * 0.6
        // Every random value is drawn on every spawn, so a seeded course is the same whatever the score.
        let candidate = rand(lo...hi)
        let swing = rand(0...1)
        let swingSpeed = rand(1.0...1.8)
        let swingPhase = rand(0...6.28)
        let pickupChance = rand(0...1)
        let pickupKind = rand(0...2.999)
        let pickupOffset = rand(-0.25...0.25)
        let x = min(max(candidate, lastGapX - maxShift), lastGapX + maxShift)
        let gx = min(max(x, lo), hi)
        lastGapX = gx
        var bar = Bar(y: -thick, gapX: gx, gapW: gapW, baseX: gx)
        // Walls start to swing once the round is going well.
        if score >= 120, swing < 0.5 {
            bar.amp = min(24 + CGFloat(score) * 0.05, 60)
            bar.speed = swingSpeed
            bar.phase = swingPhase
            bar.gapX = min(max(gx + bar.amp * sin(bar.phase), lo), hi)
        }
        bars.append(bar)
        if running, pickupChance < 0.2 {
            let kind = PowerUp.allCases[Int(pickupKind)]
            let pickupX = min(max(gx + pickupOffset * gapW, 30), w - 30)
            pickups.append(Pickup(kind: kind, x: pickupX, y: -thick - spacing * 0.5))
        }
    }

    private func collect(_ kind: PowerUp) {
        collected += 1
        switch kind {
        case .shield: shield = true
        case .magnet: magnetLeft = 6
        case .slow: slowLeft = 4
        }
        onPickup?(kind)
    }

    /// `now` is a monotonic timestamp in seconds.
    func step(_ now: TimeInterval) {
        guard size.width > 0, size.height > 0 else { return }
        if paused { last = now; return }
        let dt = min(max(now - (last ?? now), 0), 1.0 / 20.0)
        last = now
        let base: CGFloat = running ? (250 + CGFloat(min(score * 0.25, 260))) * levelScale : 90
        let v = base * (dashing ? 2.6 : 1) * (slowLeft > 0 ? 0.6 : 1)
        worldSpeed = v
        let d = CGFloat(dt)

        // Steering
        if !running {
            attractPhase += dt
            target = 0.5 + 0.32 * CGFloat(sin(attractPhase * 0.8))
        } else if bot {
            let ahead = bars.filter { !$0.passed }.max(by: { $0.y < $1.y })
            if let b = ahead { target = b.gapX / size.width }
        } else if magnetLeft > 0, !holding {
            let ahead = bars.filter { !$0.passed }.max(by: { $0.y < $1.y })
            if let b = ahead { pull(toward: b.gapX / size.width, by: CGFloat(1 - exp(-dt * 2.2))) }
        }
        px += (target - px) * CGFloat(1 - exp(-dt * 34))
        px = min(max(px, 0), 1)
        if holding { return }

        // World
        for i in bars.indices {
            bars[i].y += v * d
            if bars[i].amp > 0 {
                bars[i].phase += bars[i].speed * d
                let half = bars[i].gapW / 2 + 18
                bars[i].gapX = min(max(bars[i].baseX + bars[i].amp * sin(bars[i].phase), half), size.width - half)
            }
        }
        for i in pickups.indices { pickups[i].y += v * d }
        travel += v * d
        if travel >= spacing {
            travel = 0
            spawn()
        }
        bars.removeAll { $0.y > size.height + 40 }

        trail.append(px * size.width)
        if trail.count > 18 { trail.removeFirst(trail.count - 18) }

        guard running else {
            pickups.removeAll { $0.y > size.height + 40 }
            return
        }
        score += Double(v * d) * 0.05
        playTime += dt
        if dashLeft > 0 { dashLeft = max(0, dashLeft - dt) }
        if cooldown > 0 { cooldown = max(0, cooldown - dt) }
        if magnetLeft > 0 { magnetLeft = max(0, magnetLeft - dt) }
        if slowLeft > 0 { slowLeft = max(0, slowLeft - dt) }

        let x = px * size.width
        let py = playerY

        var kept: [Pickup] = []
        for p in pickups {
            if abs(p.x - x) < radius + 16 && abs(p.y - py) < radius + 16 {
                collect(p.kind)
            } else if p.y < size.height + 40 {
                kept.append(p)
            }
        }
        pickups = kept

        for i in bars.indices {
            let b = bars[i]
            let overlaps = b.y + thick > py - radius && b.y < py + radius
            if overlaps {
                if dashing {
                    bars[i].dashed = true
                } else if !b.forgiven {
                    let margin = min(x - radius - (b.gapX - b.gapW / 2), (b.gapX + b.gapW / 2) - (x + radius))
                    if margin < 0 {
                        if shield {
                            shield = false
                            bars[i].forgiven = true
                            shieldSaves += 1
                            combo = 0
                            onShieldBreak?()
                        } else {
                            running = false
                            onEnd?()
                            return
                        }
                    } else {
                        bars[i].minMargin = min(bars[i].minMargin, margin)
                    }
                }
            }
            if !bars[i].passed && b.y > py + radius {
                bars[i].passed = true
                // A clean pass keeps the combo; scraping the wall or a shield hit breaks it.
                let clean = bars[i].dashed || (!bars[i].forgiven && bars[i].minMargin >= 12)
                combo = clean ? combo + 1 : 0
                let m = multiplier
                maxMultiplier = max(maxMultiplier, m)
                score += (bars[i].dashed ? 25 : 10) * Double(m)
                floors += 1
                lightning += Engine.reward(forFloor: floors) * m
                onFloor?()
            }
        }
    }
}
