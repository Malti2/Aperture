import SwiftUI

enum Phase { case menu, ready, playing, over }

struct ContentView: View {
    @StateObject private var cam = CameraService()
    @State private var engine = Engine()
    @State private var phase: Phase = .menu
    @State private var best = UserDefaults.standard.integer(forKey: "best")
    @State private var lastScore = 0
    @State private var endedAt = Date.distantPast
    @State private var showBanner = false
    @State private var readyAt = Date.distantFuture
    @Environment(\.scenePhase) private var scenePhase

    private let demo = CommandLine.arguments.contains("-demo")
    private let autoplay = CommandLine.arguments.contains("-autoplay")
    private let showReady = CommandLine.arguments.contains("-ready")

    var body: some View {
        ZStack {
            playfield
            hud
            switch phase {
            case .menu: menuCard
            case .over: overCard
            case .ready: readyOverlay
            case .playing: EmptyView()
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .background(CaptureEventView(engine: engine).allowsHitTesting(false))
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if showBanner {
                Label("Camera on for Camera Control. Nothing is recorded.", systemImage: "camera.fill")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onAppear(perform: setup)
        .onChange(of: scenePhase) { _, new in
            // The Camera Control overlay can make the scene inactive.
            // Keep the session running then, otherwise the overlay closes at once.
            switch new {
            case .active:
                if !demo && (phase == .playing || phase == .ready) { cam.start(engine: engine) }
            case .background:
                cam.stop()
                if phase == .playing || phase == .ready {
                    engine.running = false
                    engine.holding = false
                    phase = .menu
                }
            default:
                break
            }
        }
    }

    // MARK: Playfield

    private var playfield: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                engine.step(timeline.date, size)
                draw(context: &context, size: size)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard engine.size.width > 0 else { return }
                    if phase == .ready { beginPlay(); return }
                    guard phase == .playing else { return }
                    engine.target = min(max(value.location.x / engine.size.width, 0), 1)
                }
        )
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        let full = CGRect(origin: .zero, size: size)
        context.fill(
            Path(full),
            with: .linearGradient(
                Gradient(colors: [Color(red: 0.03, green: 0.03, blue: 0.07), Color(red: 0.07, green: 0.08, blue: 0.16)]),
                startPoint: CGPoint(x: size.width / 2, y: 0),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            )
        )
        let accent = Color(red: 0.42, green: 0.80, blue: 1.0)
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

        let y = engine.playerY
        let r = engine.radius
        let step = max(6, engine.worldSpeed * 0.012)
        for (i, x) in engine.trail.reversed().enumerated() {
            let k = 1 - Double(i) / 18
            let rr = r * CGFloat(0.35 + 0.6 * k)
            let rect = CGRect(x: x - rr, y: y + CGFloat(i) * step - rr, width: rr * 2, height: rr * 2)
            context.fill(Path(ellipseIn: rect), with: .color((engine.dashing ? accent : .white).opacity(0.16 * k)))
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
        context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white))
    }

    // MARK: HUD

    private var hud: some View {
        VStack(spacing: 0) {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 10) {
                        HStack(spacing: 12) {
                            Label("\(Int(engine.score))", systemImage: "bolt.fill")
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                                .glassEffect(.regular, in: .capsule)
                            Spacer()
                            Label(Engine.levelNames[min(max(engine.level, 0), 2)], systemImage: "speedometer")
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .glassEffect(.regular, in: .capsule)
                        }
                        Label(cameraText, systemImage: "camera.fill")
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 62)
            }
            Spacer()
            if phase == .playing {
                TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                    Button {
                        engine.dash()
                    } label: {
                        ZStack {
                            Circle()
                                .trim(from: 0, to: engine.charge)
                                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 44, height: 44)
                            Image(systemName: "bolt.fill").font(.title3)
                        }
                        .frame(width: 60, height: 60)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private var cameraText: String {
        if demo { return "Demo mode" }
        switch cam.authorization {
        case .authorized: return cam.running ? "Camera on, not recorded" : "Camera starting"
        case .notDetermined: return "Camera off"
        default: return "Camera blocked"
        }
    }

    // MARK: Cards

    private var menuCard: some View {
        VStack(spacing: 18) {
            Text("Aperture")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("Swipe Camera Control to steer through the gaps. Press it fully to dash through a wall. Double light press to switch to the Speed control.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if best > 0 {
                Text("Best \(best)").font(.headline.monospacedDigit())
            }
            if !demo {
                Text("The camera turns on only while you play, so Camera Control works. Nothing is recorded, saved or sent.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button("Play") { start() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            Text("Touch also works: drag to steer, tap the bolt to dash.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !demo {
                Text("\(cam.controlsInfo). Overlay activations: \(cam.overlayCount)")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(28)
        .frame(maxWidth: 340)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var overCard: some View {
        VStack(spacing: 14) {
            Text("Crashed").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(lastScore)").font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
            Text("Best \(best)").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
            Button("Play again") { start() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding(28)
        .frame(maxWidth: 320)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    // MARK: Flow

    private func setup() {
        engine.onEnd = { DispatchQueue.main.async { finish() } }
        engine.onDash = { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
        engine.pressHandler = { handlePress() }
        engine.onSteer = { value in
            // Start only when the control moves away from the value it had when Ready began.
            if phase == .ready && abs(value - engine.steerBaseline) > 0.015 { beginPlay() }
        }
        if showReady { start() }
        if autoplay {
            engine.bot = true
            start()
        }
    }

    private func handlePress() {
        switch phase {
        case .playing: engine.dash()
        case .menu: start()
        case .ready: break
        case .over: if Date().timeIntervalSince(endedAt) > 0.8 { start() }
        }
    }

    private func start() {
        let slider = engine.target
        engine.reset()
        engine.target = slider
        engine.steerBaseline = slider
        if autoplay {
            beginPlay()
        } else {
            engine.running = false
            engine.holding = true
            withAnimation(.smooth) { phase = .ready }
        }
        if !demo {
            if cam.authorization == .notDetermined {
                cam.requestAccess(engine: engine)
            } else {
                cam.start(engine: engine)
            }
        }
        announceCamera()
    }

    private func beginPlay() {
        guard phase == .ready else { return }
        engine.holding = false
        engine.running = true
        withAnimation(.smooth) { phase = .playing }
    }

    private var readyOverlay: some View {
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 8) {
                    Text("Swipe to start")
                        .font(.title2.weight(.bold))
                    Text("Slide your finger along Camera Control, on the right edge of your iPhone. The game begins with your first swipe.")
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Text("No Camera Control? Drag on the screen instead.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(22)
                .frame(maxWidth: 270)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .position(x: geo.size.width / 2 - 24, y: geo.size.height * 0.55)
                Image(systemName: "arrow.right")
                    .font(.system(size: 34, weight: .bold))
                    .padding(14)
                    .glassEffect(.regular, in: Circle())
                    .phaseAnimator([0.0, 10.0]) { view, dx in
                        view.offset(x: dx)
                    } animation: { _ in .easeInOut(duration: 0.6) }
                    .position(x: geo.size.width - 40, y: geo.size.height * 0.62)
            }
        }
        .allowsHitTesting(false)
    }

    private func announceCamera() {
        guard cam.authorization != .denied && cam.authorization != .restricted else { return }
        withAnimation(.smooth) { showBanner = true }
        Task {
            if demo { return }
            try? await Task.sleep(for: .seconds(3.5))
            withAnimation(.smooth) { showBanner = false }
        }
    }

    private func finish() {
        guard phase == .playing else { return }
        lastScore = Int(engine.score)
        if lastScore > best {
            best = lastScore
            UserDefaults.standard.set(best, forKey: "best")
        }
        endedAt = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        if !demo { cam.stop() }
        withAnimation(.smooth) { phase = .over }
    }
}

@main
struct ApertureApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
