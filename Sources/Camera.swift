import SwiftUI
import AVFoundation
import AVKit

/// Keeps a camera session running without preview, recording or storage.
/// The session exists only so the system delivers Camera Control events.
final class CameraService: NSObject, ObservableObject, AVCaptureSessionControlsDelegate {
    @Published var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var overlayCount = 0

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "aperture.camera")
    private var configured = false
    // Camera-queue state, touched only on `queue`. Every notification hops onto `queue` first,
    // so it is ordered with start() and stop().
    private var wantsRunning = false
    private var generation = 0            // bumped whenever the intent changes; stale retries check it
    private var restartAttempts = 0       // budget for automatic restarts after a media services reset
    private var lastManualStart = Date.distantPast
    private static let maxRestartAttempts = 3
    private static let stableSeconds = 10.0
    @Published var cameraStopped = false
    private var steerSlider: AVCaptureSlider?
    private var menuPicker: AVCaptureIndexPicker?
    private var categoryPicker: AVCaptureIndexPicker?
    private var itemPickers: [AVCaptureIndexPicker] = []
    private var rowPicker: AVCaptureIndexPicker?
    private var speedSlider: AVCaptureSlider?
    private var hapticsPicker: AVCaptureIndexPicker?
    private var soundPicker: AVCaptureIndexPicker?
    private var difficultyPicker: AVCaptureIndexPicker?

    // Screen state mirrored onto the controls. Camera queue only.
    private var menuIndex = 0
    private var shopCategory = 0
    private var shopIndexes = [0, 0, 0]
    private var settingsRow = 0
    private var sensitivity: Float = 4
    private var hapticLevel = 2
    private var soundOn = true
    private var difficulty = 1

    var onMenuPick: ((Int) -> Void)?
    var onShopCategory: ((Int) -> Void)?
    var onShopPick: ((Int) -> Void)?
    var onSettingsRow: ((Int) -> Void)?
    var onSensitivity: ((Double) -> Void)?
    var onHapticLevel: ((Int) -> Void)?
    var onSound: ((Bool) -> Void)?
    var onDifficulty: ((Int) -> Void)?
    private weak var gameEngine: Engine?

    /// Each screen exposes only its own controls (the system allows only a few at a time).
    enum ControlMode { case steer, none, shop, menu, settings }
    private var mode: ControlMode = .menu

    static let menuTitles = ["Play", "Daily", "Shop", "Stats", "Settings"]
    static let settingsRows = ["Steering", "Haptics", "Sound", "Difficulty", "Close"]

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main) { [weak self] _ in
            self?.cameraStopped = false
            // A restart only counts as recovered after the session stayed up for a while.
            self?.queue.async {
                guard let self = self else { return }
                let gen = self.generation
                self.queue.asyncAfter(deadline: .now() + Self.stableSeconds) {
                    if self.generation == gen, self.wantsRunning, self.session.isRunning { self.restartAttempts = 0 }
                }
            }
        }
        // Recovery as in Apple's AVCam sample: restart automatically only after a media services reset;
        // an interruption resumes by itself when it ends; anything else waits for the next explicit start.
        NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let code = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
            self?.queue.async { self?.handleRuntimeError(code) }
        }
        NotificationCenter.default.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.queue.async {
                guard let self = self, self.wantsRunning, !self.session.isRunning, !self.session.isInterrupted else { return }
                self.session.startRunning()
            }
        }
    }

    func requestAccess(engine: Engine) {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.authorization = AVCaptureDevice.authorizationStatus(for: .video)
                self.start(engine: engine)
            }
        }
    }

    /// resetBudget is true for lifecycle starts (foreground, menu, retry). The per-screen check passes false,
    /// so it can never refill the automatic restart budget.
    func start(engine: Engine, resetBudget: Bool = true) {
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        guard authorization == .authorized else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
            if !self.wantsRunning { self.generation += 1 }
            self.wantsRunning = true
            if resetBudget { self.restartAttempts = 0 }
            else if !self.configured || self.session.isRunning || self.session.isInterrupted { return }
            else if Date().timeIntervalSince(self.lastManualStart) < 3 { return }
            self.lastManualStart = Date()
            if !self.configured {
                self.configure(engine: engine)
                self.configured = true
            }
            // Keep the control value in line with the game after a restart.
            if !self.session.isRunning {
                if let s = self.steerSlider { s.value = Float(engine.rawSteer) }
                self.session.startRunning()
            }
        }
    }

    /// Puts the control back to the middle. Called only on menu, retry and resume, never during a round.
    func recenter(engine: Engine) {
        queue.async { [weak self] in
            guard let self = self, let s = self.steerSlider else { return }
            engine.rawSteer = 0.5
            s.value = 0.5
        }
    }

    /// Shows only the entry that fits the current screen. Controls may be added and removed while the session runs.
    func setMode(_ newMode: ControlMode) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.mode = newMode
            self.applyMode()
        }
    }

    /// Keeps the Camera Control pickers in line with a touch selection in the Shop.
    func syncShop(category: Int, index: Int) {
        queue.async { [weak self] in
            guard let self = self, (0..<3).contains(category) else { return }
            let changed = self.shopCategory != category
            self.shopCategory = category
            self.shopIndexes[category] = index
            if self.itemPickers.indices.contains(category), self.itemPickers[category].selectedIndex != index {
                self.itemPickers[category].selectedIndex = index
            }
            if let c = self.categoryPicker, c.selectedIndex != category { c.selectedIndex = category }
            if changed { self.applyMode() }
        }
    }

    func syncMenu(index: Int) {
        queue.async { [weak self] in
            self?.menuIndex = index
            self?.menuPicker?.selectedIndex = index
        }
    }

    func syncSettingsRow(_ row: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.settingsRow = row
            if let p = self.rowPicker, p.selectedIndex != row { p.selectedIndex = row }
            self.applyMode()
        }
    }

    /// Touch and hardware controls share the same saved Settings values.
    func syncSettings(sensitivity: Double, hapticLevel: Int, sound: Bool, difficulty: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.sensitivity = Float(sensitivity)
            self.hapticLevel = hapticLevel
            self.soundOn = sound
            self.difficulty = difficulty
            self.speedSlider?.value = Float(sensitivity)
            self.hapticsPicker?.selectedIndex = hapticLevel
            self.soundPicker?.selectedIndex = sound ? 1 : 0
            self.difficultyPicker?.selectedIndex = difficulty
        }
    }

    /// Runs on the camera queue. Never changes the live steering value while playing.
    private func applyMode() {
        guard session.supportsControls, let slider = steerSlider, let menu = menuPicker,
              let category = categoryPicker, itemPickers.count == 3, let row = rowPicker,
              let speed = speedSlider, let haptics = hapticsPicker, let sound = soundPicker,
              let difficultyPicker = difficultyPicker else { return }
        let all: [AVCaptureControl] = [slider, menu, category, row, speed, haptics, sound, difficultyPicker] + itemPickers
        let wanted: [AVCaptureControl]
        switch mode {
        case .steer: wanted = [slider]
        case .none: wanted = []
        case .menu: wanted = [menu]
        case .shop: wanted = [category, itemPickers[min(max(shopCategory, 0), 2)]]
        case .settings:
            switch settingsRow {
            case 0: wanted = [row, speed]
            case 1: wanted = [row, haptics]
            case 2: wanted = [row, sound]
            case 3: wanted = [row, difficultyPicker]
            default: wanted = [row]
            }
        }
        for c in all where !wanted.contains(where: { $0 === c }) && session.controls.contains(where: { $0 === c }) {
            session.removeControl(c)
        }
        for control in wanted where !session.controls.contains(where: { $0 === control }) {
            if control === slider {
                gameEngine?.rawSteer = 0.5
                slider.value = 0.5
            } else if control === menu {
                menu.selectedIndex = min(max(menuIndex, 0), Self.menuTitles.count - 1)
            } else if control === category {
                category.selectedIndex = min(max(shopCategory, 0), 2)
            } else if let i = itemPickers.firstIndex(where: { $0 === control }) {
                let count = ShopCategory(rawValue: i)?.items.count ?? 1
                itemPickers[i].selectedIndex = min(max(shopIndexes[i], 0), count - 1)
            } else if control === row {
                row.selectedIndex = min(max(settingsRow, 0), Self.settingsRows.count - 1)
            } else if control === speed {
                speed.value = sensitivity
            } else if control === haptics {
                haptics.selectedIndex = hapticLevel
            } else if control === sound {
                sound.selectedIndex = soundOn ? 1 : 0
            } else if control === difficultyPicker {
                difficultyPicker.selectedIndex = difficulty
            }
            if session.canAddControl(control) { session.addControl(control) }
        }
    }

    /// Camera queue. Restart only after a media services reset, and only within the budget.
    private func handleRuntimeError(_ code: AVError.Code?) {
        DispatchQueue.main.async { self.cameraStopped = true }
        guard wantsRunning, code == .mediaServicesWereReset, restartAttempts < Self.maxRestartAttempts else { return }
        restartAttempts += 1
        let gen = generation
        queue.asyncAfter(deadline: .now() + 0.4 * Double(restartAttempts)) { [weak self] in
            guard let self = self, self.generation == gen, self.wantsRunning,
                  !self.session.isRunning, !self.session.isInterrupted else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.wantsRunning = false
            self.generation += 1
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure(engine: Engine) {
        session.beginConfiguration()
        session.sessionPreset = .low
        // Keep the rear camera for this first power test. Front-camera control behavior
        // and relative energy use require a separate on-device comparison.
        let captureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
        if let device = captureDevice,
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            // A session still needs an output. Photo output is on-demand; no capture is made.
            let output = AVCapturePhotoOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
            } else {
                // Preserve the previously working output if photo output is unavailable.
                let fallback = AVCaptureVideoDataOutput()
                if session.canAddOutput(fallback) { session.addOutput(fallback) }
            }
            configureLowPowerDevice(device)
        }
        if session.supportsControls {
            let slider = AVCaptureSlider("Steer", symbolName: "arrow.left.and.right", in: 0...1, step: 0.001)
            slider.value = 0.5
            steerSlider = slider
            slider.setActionQueue(queue) { [weak self] value in
                guard self?.mode == .steer else { return }
                engine.steer(slider: CGFloat(value))
            }

            let menu = AVCaptureIndexPicker("Main Menu", symbolName: "list.bullet", localizedIndexTitles: Self.menuTitles)
            menu.setActionQueue(queue) { [weak self] index in
                guard let self = self, self.mode == .menu else { return }
                self.menuIndex = index
                DispatchQueue.main.async { self.onMenuPick?(index) }
            }
            menuPicker = menu

            let category = AVCaptureIndexPicker("Shop", symbolName: "bag.fill", localizedIndexTitles: ShopCategory.allCases.map { $0.title })
            category.setActionQueue(queue) { [weak self] index in
                guard let self = self, self.mode == .shop else { return }
                self.shopCategory = index
                self.applyMode()
                DispatchQueue.main.async { self.onShopCategory?(index) }
            }
            categoryPicker = category
            itemPickers = ShopCategory.allCases.map { cat in
                let picker = AVCaptureIndexPicker(cat.title, symbolName: cat.symbol, localizedIndexTitles: cat.items.map { $0.name })
                picker.setActionQueue(queue) { [weak self] index in
                    guard let self = self, self.mode == .shop, self.shopCategory == cat.rawValue else { return }
                    // Selection only. Buying always needs the hold on screen.
                    self.shopIndexes[cat.rawValue] = index
                    DispatchQueue.main.async { self.onShopPick?(index) }
                }
                return picker
            }

            let row = AVCaptureIndexPicker("Settings", symbolName: "gearshape.fill", localizedIndexTitles: Self.settingsRows)
            row.setActionQueue(queue) { [weak self] index in
                guard let self = self, self.mode == .settings else { return }
                self.settingsRow = index
                self.applyMode()
                DispatchQueue.main.async { self.onSettingsRow?(index) }
            }
            rowPicker = row
            let speed = AVCaptureSlider("Speed", symbolName: "arrow.left.and.right", in: 1...7, step: 0.1)
            speed.value = sensitivity
            speed.setActionQueue(queue) { [weak self] value in
                guard let self = self, self.mode == .settings else { return }
                self.sensitivity = value
                DispatchQueue.main.async { self.onSensitivity?(Double(value)) }
            }
            speedSlider = speed
            let haptics = AVCaptureIndexPicker("Haptics", symbolName: "waveform", localizedIndexTitles: Profile.hapticNames)
            haptics.selectedIndex = hapticLevel
            haptics.setActionQueue(queue) { [weak self] index in
                guard let self = self, self.mode == .settings else { return }
                self.hapticLevel = index
                DispatchQueue.main.async { self.onHapticLevel?(index) }
            }
            hapticsPicker = haptics
            let sound = AVCaptureIndexPicker("Sound", symbolName: "speaker.wave.2.fill", localizedIndexTitles: ["Off", "On"])
            sound.selectedIndex = soundOn ? 1 : 0
            sound.setActionQueue(queue) { [weak self] index in
                guard let self = self, self.mode == .settings else { return }
                self.soundOn = index == 1
                DispatchQueue.main.async { self.onSound?(index == 1) }
            }
            soundPicker = sound
            let diff = AVCaptureIndexPicker("Difficulty", symbolName: "speedometer", localizedIndexTitles: Profile.levelNames)
            diff.selectedIndex = difficulty
            diff.setActionQueue(queue) { [weak self] index in
                guard let self = self, self.mode == .settings else { return }
                self.difficulty = index
                DispatchQueue.main.async { self.onDifficulty?(index) }
            }
            difficultyPicker = diff
            gameEngine = engine
            applyMode()
        }
        session.commitConfiguration()
        if session.supportsControls {
            session.setControlsDelegate(self, queue: queue)
        }
    }

    /// Must run on the camera queue, inside the session configuration transaction.
    /// Use the exact supported duration, never a rounded integer frames-per-second value.
    private func configureLowPowerDevice(_ device: AVCaptureDevice) {
        let candidates = device.formats.filter {
            let subtype = CMFormatDescriptionGetMediaSubType($0.formatDescription)
            return (subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                    subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) &&
                !$0.videoSupportedFrameRateRanges.isEmpty
        }
        let format = candidates.min { a, b in
            let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            let areaA = Int64(da.width) * Int64(da.height)
            let areaB = Int64(db.width) * Int64(db.height)
            if areaA != areaB { return areaA < areaB }
            let fpsA = a.videoSupportedFrameRateRanges.map(\.minFrameRate).min() ?? .infinity
            let fpsB = b.videoSupportedFrameRateRanges.map(\.minFrameRate).min() ?? .infinity
            return fpsA < fpsB
        }
        guard let format = format,
              let range = format.videoSupportedFrameRateRanges.min(by: { $0.minFrameRate < $1.minFrameRate }),
              range.maxFrameDuration.isValid, range.maxFrameDuration.seconds.isFinite,
              range.maxFrameDuration.seconds > 0 else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            // Setting activeFormat changes the session preset to inputPriority.
            device.activeFormat = format
            let duration = range.maxFrameDuration
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            device.automaticallyAdjustsVideoHDREnabled = false
            if format.isVideoHDRSupported { device.isVideoHDREnabled = false }
        } catch {
            // A denied configuration lock leaves the existing low preset in place.
            // Do not sacrifice Camera Control just to apply this power experiment.
        }
    }

    // MARK: AVCaptureSessionControlsDelegate
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        DispatchQueue.main.async { self.overlayCount += 1 }
    }
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {}
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {}
}
