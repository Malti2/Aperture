import SwiftUI

enum Phase { case menu, playing, paused, over }

struct ContentView: View {
    @StateObject private var cam = CameraService()
    @State private var engine = Engine()
    @State private var phase: Phase = .menu
    @State private var best = UserDefaults.standard.integer(forKey: "best")
    @State private var lastScore = 0
    @State private var endedAt = Date.distantPast
    @State private var showSettings = false
    @AppStorage("steerGain") private var steerGain = 1.6
    @AppStorage("haptics") private var haptics = true
    @Environment(\.scenePhase) private var scenePhase

    private let demo = CommandLine.arguments.contains("-demo")
    private let autoplay = CommandLine.arguments.contains("-autoplay")
    private let demoPaused = CommandLine.arguments.contains("-paused")
    private let demoSettings = CommandLine.arguments.contains("-settings")

    var body: some View {
        ZStack {
            playfield
            hud
            switch phase {
            case .menu: menuCard
            case .over: overCard
            case .paused: pauseOverlay
            case .playing: EmptyView()
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .background(CaptureEventView(engine: engine).allowsHitTesting(false))
        .preferredColorScheme(.dark)
        .onAppear(perform: setup)
        .sheet(isPresented: $showSettings) { settingsSheet }
        .onChange(of: steerGain) { _, v in Engine.steerGain = CGFloat(v) }
        .onChange(of: showSettings) { _, open in
            if open {
                cam.stop()
            } else if phase == .menu {
                engine.steerBaseline = engine.rawSteer
                startCamera()
            }
        }
        .onChange(of: scenePhase) { _, new in
            // The Camera Control overlay can make the scene inactive.
            // Keep the session running then, otherwise the overlay closes at once.
            switch new {
            case .active:
                if !demo && !showSettings && phase != .over { cam.start(engine: engine) }
            case .background:
                cam.stop()
                if phase == .playing { pauseGame() }
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
                    if phase == .menu { beginPlay(); return }
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
                            if phase == .playing {
                                Button { pauseGame() } label: {
                                    Image(systemName: "pause.fill").frame(width: 38, height: 38)
                                }
                                .buttonStyle(.glass)
                                .buttonBorderShape(.circle)
                            }
                            Label(Engine.levelNames[min(max(engine.level, 0), 2)], systemImage: "speedometer")
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .glassEffect(.regular, in: .capsule)
                        }
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

    // MARK: Cards

    private var menuCard: some View {
        ZStack {
            VStack(spacing: 16) {
                Text("Aperture")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text("Swipe Camera Control to start")
                    .font(.headline)
                if best > 0 {
                    Text("Best \(best)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill").font(.title3).frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                Text("Camera on, not recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 320)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            GeometryReader { geo in
                Image(systemName: "arrow.right")
                    .font(.system(size: 30, weight: .bold))
                    .padding(14)
                    .glassEffect(.regular, in: Circle())
                    .phaseAnimator([0.0, 10.0]) { view, dx in
                        view.offset(x: dx)
                    } animation: { _ in .easeInOut(duration: 0.6) }
                    .position(x: geo.size.width - 40, y: geo.size.height * 0.78)
            }
            .allowsHitTesting(false)
        }
    }

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Steering speed")
                        Slider(value: $steerGain, in: 1.0...2.6, step: 0.1)
                    }
                    Toggle("Haptics", isOn: $haptics)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private var overCard: some View {
        VStack(spacing: 14) {
            Text("Crashed").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(lastScore)").font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
            Text("Best \(best)").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Back") { enterMenu() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                Button("Retry") { retry() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(maxWidth: 320)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    // MARK: Flow

    private func setup() {
        Engine.steerGain = CGFloat(steerGain)
        engine.onEnd = { DispatchQueue.main.async { finish() } }
        engine.onDash = { if haptics { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() } }
        engine.pressHandler = { handlePress() }
        engine.onSteer = { value in
            // Start only when the control moves away from the value it had when the menu appeared.
            if phase == .menu && !showSettings && abs(value - engine.steerBaseline) > 0.015 { beginPlay() }
        }
        enterMenu()
        if demoSettings { showSettings = true }
        if demoPaused {
            engine.bot = true
            beginPlay()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { pauseGame() }
        }
        if autoplay {
            engine.bot = true
            beginPlay()
        }
    }

    private func handlePress() {
        switch phase {
        case .playing: engine.dash()
        case .menu, .paused: break
        case .over: if Date().timeIntervalSince(endedAt) > 0.8 { retry() }
        }
    }

    private func enterMenu() {
        let slider = engine.target
        engine.reset()
        engine.target = slider
        engine.steerBaseline = engine.rawSteer
        engine.running = false
        engine.holding = true
        cam.recenter(engine: engine)
        engine.steerBaseline = 0.5
        withAnimation(.smooth) { phase = .menu }
        startCamera()
    }

    private func retry() {
        let slider = engine.target
        engine.reset()
        engine.target = slider
        engine.holding = false
        engine.running = true
        cam.recenter(engine: engine)
        withAnimation(.smooth) { phase = .playing }
        startCamera()
    }

    private func startCamera() {
        guard !demo else { return }
        if cam.authorization == .notDetermined {
            cam.requestAccess(engine: engine)
        } else {
            cam.start(engine: engine)
        }
    }

    private func pauseGame() {
        guard phase == .playing else { return }
        engine.paused = true
        withAnimation(.smooth) { phase = .paused }
    }

    private func resumeGame() {
        guard phase == .paused else { return }
        engine.paused = false
        cam.recenter(engine: engine)
        withAnimation(.smooth) { phase = .playing }
    }

    private var pauseOverlay: some View {
        VStack(spacing: 22) {
            Text("Paused")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            SwipeToContinue { resumeGame() }
                .frame(maxWidth: 300)
        }
        .padding(28)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private func beginPlay() {
        guard phase == .menu, !showSettings else { return }
        engine.holding = false
        engine.running = true
        withAnimation(.smooth) { phase = .playing }
    }

    private func finish() {
        guard phase == .playing else { return }
        lastScore = Int(engine.score)
        if lastScore > best {
            best = lastScore
            UserDefaults.standard.set(best, forKey: "best")
        }
        endedAt = Date()
        if haptics { UINotificationFeedbackGenerator().notificationOccurred(.error) }
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


/// Slide-to-continue control in the style of the iOS call and alarm sliders.
struct SwipeToContinue: View {
    let onDone: () -> Void
    @State private var offset: CGFloat = 0
    private let knob: CGFloat = 56

    var body: some View {
        GeometryReader { geo in
            let maxX = max(geo.size.width - knob - 8, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                    .glassEffect(.regular, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
                Text("swipe to continue")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.leading, knob * 0.6)
                    .opacity(1 - Double(offset / maxX))
                Circle().fill(Color.white.opacity(0.92))
                    .frame(width: knob, height: knob)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .overlay(Image(systemName: "chevron.right").font(.title2.weight(.bold)).foregroundStyle(.black.opacity(0.8)))
                    .offset(x: 4 + offset)
                    .gesture(
                        DragGesture()
                            .onChanged { v in offset = min(max(v.translation.width, 0), maxX) }
                            .onEnded { _ in
                                let done = offset > maxX * 0.85
                                withAnimation(.smooth) { offset = 0 }
                                if done { onDone() }
                            }
                    )
            }
        }
        .frame(height: knob + 8)
    }
}
