import SwiftUI

enum Phase { case menu, shop, playing, paused, over }

/// Screen flow: menu, shop, playing, paused, over. Drawing and the shop live in their own views.
struct ContentView: View {
    @StateObject private var cam = CameraService()
    @State private var engine = Engine()
    @State private var loop = GameLoop()
    @State private var shopCommands = ShopCommands()
    @State private var phase: Phase = .menu
    @State private var best = UserDefaults.standard.integer(forKey: "best")
    @State private var lastScore = 0
    @State private var endedAt = Date.distantPast
    @State private var showSettings = false
    @State private var menuSelection = 0
    @State private var menuHintVisible = false
    @State private var menuHintToken = 0
    @State private var shopSelected = 0
    @State private var credited = 0
    // New key: the old range ended at 4.0, which is now the default and the middle of the slider.
    @AppStorage("steerGainV2") private var steerGain = 4.0
    @AppStorage("haptics") private var haptics = true
    @AppStorage("bank") private var bank = 0
    @AppStorage("owned") private var ownedRaw = "0"
    @AppStorage("equipped") private var equipped = 0
    @Environment(\.scenePhase) private var scenePhase

    private let demo = CommandLine.arguments.contains("-demo")
    private let autoplay = CommandLine.arguments.contains("-autoplay")
    private let demoPaused = CommandLine.arguments.contains("-paused")
    private let demoSettings = CommandLine.arguments.contains("-settings")
    private let demoShop = CommandLine.arguments.contains("-shop")
    private let demoCycle = CommandLine.arguments.contains("-cycle")

    var body: some View {
        ZStack {
            PlayfieldView(engine: engine, phase: phase, equipped: equipped, onDrag: handleDrag)
            HUDView(engine: engine, bank: bank, playing: phase == .playing, onPause: pauseGame)
            switch phase {
            case .menu:
                MenuCard(best: best, cameraStopped: cam.cameraStopped, selection: menuSelection,
                         hintVisible: menuHintVisible && !showSettings,
                         onSettings: { showSettings = true }, onShop: enterShop)
            case .shop:
                ShopView(bank: $bank, ownedRaw: $ownedRaw, equipped: $equipped, haptics: haptics,
                         initialSelection: shopSelected, commands: shopCommands,
                         demoCycle: demo && demoShop && demoCycle, skipEntryDelay: demo,
                         onSelect: { index in
                             shopSelected = index
                             cam.syncShop(index: index)
                         },
                         onBack: exitShop)
            case .over:
                OverCard(score: lastScore, best: best, onBack: enterMenu, onRetry: retry)
            case .paused:
                PauseOverlay(onResume: resumeGame)
            case .playing:
                EmptyView()
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .background(CaptureEventView(engine: engine).allowsHitTesting(false))
        .preferredColorScheme(.dark)
        .onAppear(perform: setup)
        .onDisappear { loop.stop() }
        .sheet(isPresented: $showSettings) {
            SettingsSheet(steerGain: $steerGain, haptics: $haptics) { showSettings = false }
                .background(CaptureEventView(engine: engine).allowsHitTesting(false))
        }
        .onChange(of: steerGain) { _, v in
            Engine.steerGain = CGFloat(v)
            cam.syncSettings(sensitivity: v, haptics: haptics)
            if showSettings { updateIdleTimer() }
        }
        .onChange(of: haptics) { _, v in
            cam.syncSettings(sensitivity: steerGain, haptics: v)
            if showSettings { updateIdleTimer() }
        }
        .onChange(of: phase) { _, new in
            updateIdleTimer()
            updateCameraControls()
            if new == .menu { showMenuHint() } else { hideMenuHint() }
        }
        .onChange(of: cam.overlayCount) { _, _ in
            if showSettings { updateIdleTimer() }
            else if phase == .menu { showMenuHint() }
        }
        .onChange(of: menuSelection) { _, index in
            cam.syncMenu(index: index)
            showMenuHint()
        }
        .onChange(of: showSettings) { _, open in
            updateIdleTimer()
            if open { hideMenuHint() } else { showMenuHint() }
            updateCameraControls()
            if scenePhase == .active { startCamera() }
        }
        .onChange(of: scenePhase) { _, new in
            updateIdleTimer()
            // The Camera Control overlay can make the scene inactive.
            // Keep the session running then, otherwise the overlay closes at once.
            switch new {
            case .active:
                if !demo && phase != .over { updateCameraControls(); cam.start(engine: engine) }
            case .background:
                bankSync()
                cam.stop()
                if phase == .playing { pauseGame() }
            default:
                break
            }
        }
        .onReceive(Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()) { _ in
            if phase == .playing && !engine.paused { bankSync() }
        }
    }

    // MARK: Small helpers

    /// Keep every app screen awake, including menus, Shop and Settings.
    /// Camera Control can briefly make the scene inactive; only background releases it.
    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = scenePhase != .background
    }

    private func hideMenuHint() {
        menuHintToken += 1
        menuHintVisible = false
    }

    private func showMenuHint() {
        guard phase == .menu, !showSettings else { return }
        menuHintToken += 1
        let token = menuHintToken
        withAnimation(.easeOut(duration: 0.18)) { menuHintVisible = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            guard menuHintToken == token else { return }
            withAnimation(.easeOut(duration: 0.25)) { menuHintVisible = false }
        }
    }

    /// Adds the lightning earned this round to the saved balance. Only the part not yet credited is added.
    /// The round score (and the high score) is separate and unchanged.
    private func bankSync() {
        let s = engine.lightning
        if s > credited {
            bank += s - credited
            credited = s
        }
    }

    private func handleDrag(_ x: CGFloat) {
        if phase == .menu && !showSettings { beginPlay(); return }
        guard phase == .playing else { return }
        engine.target = x
    }

    // MARK: Flow

    private func setup() {
        Engine.steerGain = CGFloat(steerGain)
        loop.onTick = { [engine] now in engine.step(now) }
        loop.start()
        engine.onEnd = { DispatchQueue.main.async { finish() } }
        engine.onDash = { if haptics { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() } }
        engine.pressHandler = { handlePress() }
        engine.onFloor = { DispatchQueue.main.async { bankSync() } }
        engine.onShopPick = { index in DispatchQueue.main.async { shopCommands.select?(index) } }
        engine.pressBegan = { shopCommands.pressBegan?() }
        engine.pressCancel = { shopCommands.pressCancel?() }
        cam.onMenuPick = { index in
            guard phase == .menu, !showSettings, (0...2).contains(index) else { return }
            menuSelection = index
        }
        cam.onSensitivity = { value in
            guard showSettings else { return }
            updateIdleTimer()
            steerGain = min(max((value * 10).rounded() / 10, 1), 7)
        }
        cam.onHaptics = { value in
            guard showSettings else { return }
            updateIdleTimer()
            haptics = value
        }
        cam.syncSettings(sensitivity: steerGain, haptics: haptics)
        enterMenu()
        if demoShop && demo {
            bank = demoCycle ? 900 : 172
            ownedRaw = "0,1"
            equipped = 0
            shopSelected = 2
            phase = .shop
        }
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
        guard !showSettings, scenePhase != .background else { return }
        switch phase {
        case .playing: engine.dash()
        case .menu:
            switch menuSelection {
            case 1: enterShop()
            case 2: showSettings = true
            default: beginPlay()
            }
        case .paused: break
        case .shop: shopCommands.pressEnded?()
        case .over: if Date().timeIntervalSince(endedAt) > 0.8 { retry() }
        }
    }

    private func updateCameraControls() {
        let mode: CameraService.ControlMode
        if showSettings { mode = .settings }
        else {
            switch phase {
            case .menu: mode = .menu
            case .shop: mode = .shop
            case .playing: mode = .steer
            case .paused, .over: mode = .none
            }
        }
        cam.setMode(mode, shopIndex: shopSelected)
        // Every screen change also checks the session (never refills the restart budget).
        if !demo && phase != .over && scenePhase != .background && cam.authorization == .authorized {
            cam.start(engine: engine, resetBudget: false)
        }
    }

    private func enterMenu() {
        menuSelection = 0
        cam.syncMenu(index: 0)
        let slider = engine.target
        engine.reset()
        engine.target = slider
        engine.running = false
        engine.holding = true
        credited = 0
        cam.recenter(engine: engine)
        withAnimation(.smooth) { phase = .menu }
        updateCameraControls()
        startCamera()
        showMenuHint()
    }

    private func enterShop() {
        guard phase == .menu, !showSettings else { return }
        cam.recenter(engine: engine)
        shopSelected = min(max(equipped, 0), ballSkins.count - 1)
        withAnimation(.smooth) { phase = .shop }
    }

    private func exitShop() {
        cam.recenter(engine: engine)
        withAnimation(.smooth) { phase = .menu }
    }

    private func retry() {
        let slider = engine.target
        engine.reset()
        engine.target = slider
        engine.holding = false
        engine.running = true
        credited = 0
        cam.recenter(engine: engine)
        withAnimation(.smooth) { phase = .playing }
        startCamera()
    }

    private func beginPlay() {
        guard phase == .menu, !showSettings else { return }
        engine.holding = false
        engine.running = true
        withAnimation(.smooth) { phase = .playing }
    }

    private func pauseGame() {
        guard phase == .playing else { return }
        bankSync()
        engine.paused = true
        withAnimation(.smooth) { phase = .paused }
    }

    private func resumeGame() {
        guard phase == .paused else { return }
        engine.paused = false
        cam.recenter(engine: engine)
        withAnimation(.smooth) { phase = .playing }
    }

    private func finish() {
        guard phase == .playing else { return }
        bankSync()
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

    private func startCamera() {
        guard !demo else { return }
        if cam.authorization == .notDetermined {
            cam.requestAccess(engine: engine)
        } else {
            cam.start(engine: engine)
        }
    }
}
