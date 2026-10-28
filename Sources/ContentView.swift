import SwiftUI

enum Phase { case menu, shop, stats, playing, paused, over }

/// Screen flow: menu, shop, stats, playing, paused, over. Drawing and the other screens live in their own views.
struct ContentView: View {
    @StateObject private var cam = CameraService()
    @StateObject private var profile = Profile()
    @State private var engine = Engine()
    @State private var loop = GameLoop()
    @State private var shopCommands = ShopCommands()
    @State private var phase: Phase = .menu
    @State private var isDaily = false
    @State private var lastScore = 0
    @State private var lastBest = 0
    @State private var newBest = false
    @State private var newAchievements: [Achievement] = []
    @State private var endedAt = Date.distantPast
    @State private var pausedAt = Date.distantPast
    @State private var statsAt = Date.distantPast
    @State private var showSettings = false
    @State private var settingsRow = 0
    @State private var menuSelection = 0
    @State private var menuHintVisible = false
    @State private var menuHintToken = 0
    @State private var shopCategory = 0
    @State private var shopSelected: Int? = nil
    @State private var credited = 0
    @Environment(\.scenePhase) private var scenePhase

    private let demo = CommandLine.arguments.contains("-demo")
    private let autoplay = CommandLine.arguments.contains("-autoplay")
    private let demoPaused = CommandLine.arguments.contains("-paused")
    private let demoSettings = CommandLine.arguments.contains("-settings")
    private let demoShop = CommandLine.arguments.contains("-shop")
    private let demoCycle = CommandLine.arguments.contains("-cycle")

    var body: some View {
        ZStack {
            PlayfieldView(engine: engine, phase: phase,
                          ball: ballSkins[profile.equippedIndex(.ball)],
                          trailSkin: trailSkins[profile.equippedIndex(.trail)],
                          theme: themes[profile.equippedIndex(.theme)],
                          onDrag: handleDrag)
            HUDView(engine: engine, bank: profile.bank, playing: phase == .playing, onPause: pauseGame)
            switch phase {
            case .menu:
                MenuCard(best: profile.best, levelName: Profile.levelNames[profile.difficulty],
                         cameraStopped: cam.cameraStopped, selection: menuSelection,
                         hintVisible: menuHintVisible && !showSettings,
                         onSettings: openSettings, onShop: enterShop, onStats: enterStats,
                         onDaily: { beginPlay(daily: true) })
            case .shop:
                ShopView(profile: profile, initialCategory: shopCategory, initialSelection: shopSelected,
                         commands: shopCommands, demoCycle: demo && demoShop && demoCycle, skipEntryDelay: demo,
                         onSelect: { category, index in
                             shopCategory = category
                             cam.syncShop(category: category, index: index)
                         },
                         onBack: exitShop)
            case .stats:
                StatsView(profile: profile, onBack: exitStats)
            case .over:
                OverCard(score: lastScore, best: lastBest, newBest: newBest, daily: isDaily,
                         unlocked: newAchievements, onBack: enterMenu, onRetry: retry)
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
            SettingsSheet(profile: profile, row: $settingsRow) { showSettings = false }
                .background(CaptureEventView(engine: engine).allowsHitTesting(false))
        }
        .onChange(of: profile.steerGain) { _, v in
            Engine.steerGain = CGFloat(v)
            syncCameraSettings()
        }
        .onChange(of: profile.hapticLevel) { _, _ in syncCameraSettings() }
        .onChange(of: profile.soundOn) { _, _ in syncCameraSettings() }
        .onChange(of: profile.difficulty) { _, _ in syncCameraSettings() }
        .onChange(of: settingsRow) { _, row in cam.syncSettingsRow(row) }
        .onChange(of: phase) { _, new in
            updateIdleTimer()
            updateCameraControls()
            if new == .menu { showMenuHint() } else { hideMenuHint() }
        }
        .onChange(of: cam.overlayCount) { _, _ in
            if phase == .menu && !showSettings { showMenuHint() }
        }
        .onChange(of: menuSelection) { _, index in
            cam.syncMenu(index: index)
            showMenuHint()
        }
        .onChange(of: showSettings) { _, open in
            updateIdleTimer()
            if open {
                settingsRow = 0
                cam.syncSettingsRow(0)
                hideMenuHint()
            } else {
                showMenuHint()
            }
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

    private func syncCameraSettings() {
        cam.syncSettings(sensitivity: profile.steerGain, hapticLevel: profile.hapticLevel,
                         sound: profile.soundOn, difficulty: profile.difficulty)
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
            profile.bank += s - credited
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
        Engine.steerGain = CGFloat(profile.steerGain)
        loop.onTick = { [engine] now in engine.step(now) }
        loop.start()
        engine.onEnd = { DispatchQueue.main.async { finish() } }
        engine.onDash = {
            Feedback.impact(.rigid)
            Feedback.play(.dash)
        }
        engine.onFloor = {
            Feedback.play(.floor)
            DispatchQueue.main.async { bankSync() }
        }
        engine.onPickup = { _ in
            Feedback.impact(.medium)
            Feedback.play(.pickup)
        }
        engine.onShieldBreak = {
            Feedback.notify(.warning)
            Feedback.play(.crash)
        }
        engine.pressHandler = { handlePress() }
        engine.pressBegan = { shopCommands.pressBegan?() }
        engine.pressCancel = { shopCommands.pressCancel?() }

        cam.onMenuPick = { index in
            guard phase == .menu, !showSettings, (0..<CameraService.menuTitles.count).contains(index) else { return }
            menuSelection = index
        }
        cam.onShopPick = { index in shopCommands.select?(index) }
        cam.onSensitivity = { value in
            guard showSettings else { return }
            profile.steerGain = min(max((value * 10).rounded() / 10, 1), 7)
        }
        cam.onHapticLevel = { value in
            guard showSettings else { return }
            profile.hapticLevel = min(max(value, 0), 2)
        }
        cam.onSound = { value in
            guard showSettings else { return }
            profile.soundOn = value
        }
        cam.onDifficulty = { value in
            guard showSettings else { return }
            profile.difficulty = min(max(value, 0), 2)
        }
        syncCameraSettings()
        enterMenu()
        if demoShop && demo {
            profile.bank = demoCycle ? 900 : 172
            profile.grant(.ball, 1)
            shopSelected = 2
            phase = .shop
        }
        if demoSettings { openSettings() }
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
        guard scenePhase != .background else { return }
        if showSettings { return }
        switch phase {
        case .playing: engine.dash()
        case .menu:
            switch menuSelection {
            case 1: beginPlay(daily: true)
            case 2: enterShop()
            case 3: enterStats()
            case 4: openSettings()
            default: beginPlay()
            }
        case .paused: if Date().timeIntervalSince(pausedAt) > 0.6 { resumeGame() }
        case .shop: shopCommands.pressEnded?()
        case .stats: if Date().timeIntervalSince(statsAt) > 0.6 { exitStats() }
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
            case .stats, .paused, .over: mode = .none
            }
        }
        cam.setMode(mode)
        // Every screen change also checks the session (never refills the restart budget).
        if !demo && phase != .over && scenePhase != .background && cam.authorization == .authorized {
            cam.start(engine: engine, resetBudget: false)
        }
    }

    /// Course settings for the next round. The daily challenge always runs on Normal with the day's seed.
    private func configureRound() {
        engine.level = isDaily ? 1 : profile.difficulty
        engine.seed = isDaily ? Profile.dailySeed : nil
    }

    private func resetEngine() {
        let slider = engine.target
        engine.reset()
        engine.target = slider
    }

    private func enterMenu() {
        menuSelection = 0
        cam.syncMenu(index: 0)
        isDaily = false
        configureRound()
        resetEngine()
        engine.running = false
        engine.holding = true
        credited = 0
        cam.recenter(engine: engine)
        withAnimation(.smooth) { phase = .menu }
        updateCameraControls()
        startCamera()
        showMenuHint()
    }

    private func openSettings() {
        guard phase == .menu else { return }
        showSettings = true
    }

    private func enterShop() {
        guard phase == .menu, !showSettings else { return }
        cam.recenter(engine: engine)
        shopSelected = nil
        withAnimation(.smooth) { phase = .shop }
    }

    private func exitShop() {
        cam.recenter(engine: engine)
        shopSelected = nil
        withAnimation(.smooth) { phase = .menu }
    }

    private func enterStats() {
        guard phase == .menu, !showSettings else { return }
        profile.refreshDaily()
        statsAt = Date()
        withAnimation(.smooth) { phase = .stats }
    }

    private func exitStats() {
        withAnimation(.smooth) { phase = .menu }
    }

    private func retry() {
        configureRound()
        resetEngine()
        engine.holding = false
        engine.running = true
        credited = 0
        cam.recenter(engine: engine)
        withAnimation(.smooth) { phase = .playing }
        startCamera()
    }

    private func beginPlay(daily: Bool = false) {
        guard phase == .menu, !showSettings else { return }
        isDaily = daily
        profile.refreshDaily()
        configureRound()
        // The daily course has to start from the seed, so it never reuses the idle menu course.
        if daily { resetEngine() }
        credited = 0
        engine.holding = false
        engine.running = true
        withAnimation(.smooth) { phase = .playing }
    }

    private func pauseGame() {
        guard phase == .playing else { return }
        bankSync()
        engine.paused = true
        pausedAt = Date()
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
        let result = RoundResult(score: Int(engine.score), floors: engine.floors, dashes: engine.dashes,
                                 maxMultiplier: engine.maxMultiplier, pickups: engine.collected,
                                 shieldSaves: engine.shieldSaves, seconds: engine.playTime,
                                 daily: isDaily, level: engine.level)
        let outcome = profile.record(result)
        lastScore = result.score
        lastBest = isDaily ? profile.dailyBest : profile.bests[engine.level]
        newBest = outcome.newBest
        newAchievements = outcome.unlocked
        endedAt = Date()
        Feedback.notify(.error)
        Feedback.play(.crash)
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
