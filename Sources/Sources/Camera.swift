import SwiftUI
import AVFoundation
import AVKit

/// Keeps a camera session running without preview, recording or storage.
/// The session exists only so the system delivers Camera Control events.
final class CameraService: NSObject, ObservableObject, AVCaptureSessionControlsDelegate {
    @Published var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var running = false
    @Published var controlsInfo = "Controls: not set up yet"
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
    private var speedPicker: AVCaptureIndexPicker?
    private var shopPicker: AVCaptureIndexPicker?
    private var menuPicker: AVCaptureIndexPicker?
    private var settingsSpeed: AVCaptureSlider?
    private var hapticsPicker: AVCaptureIndexPicker?
    private var menuIndex = 0
    private var sensitivity: Float = 4
    private var hapticsEnabled = true
    var onMenuPick: ((Int) -> Void)?
    var onSensitivity: ((Double) -> Void)?
    var onHaptics: ((Bool) -> Void)?
    private var shopIndex = 0
    private weak var gameEngine: Engine?

    /// Each screen exposes only its own controls. Menu actions share one named picker.
    enum ControlMode { case steer, speed, shop, menu, settings }
    private var mode: ControlMode = .menu

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main) { [weak self] _ in
            self?.running = true
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
        NotificationCenter.default.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: session, queue: .main) { [weak self] _ in
            self?.running = false
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
    func setMode(_ newMode: ControlMode, shopIndex: Int = 0) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.mode = newMode
            self.shopIndex = shopIndex
            self.applyMode()
        }
    }

    /// Keeps the Camera Control ball picker in line with a touch selection.
    func syncShop(index: Int) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.shopIndex = index
            if let p = self.shopPicker, p.selectedIndex != index { p.selectedIndex = index }
        }
    }

    func syncMenu(index: Int) {
        queue.async { [weak self] in
            self?.menuIndex = index
            self?.menuPicker?.selectedIndex = index
        }
    }

    /// Touch and hardware controls share the same saved Settings values.
    func syncSettings(sensitivity: Double, haptics: Bool) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.sensitivity = Float(sensitivity)
            self.hapticsEnabled = haptics
            self.settingsSpeed?.value = Float(sensitivity)
            self.hapticsPicker?.selectedIndex = haptics ? 1 : 0
        }
    }

    /// Runs on the camera queue. Never changes the live steering value while playing.
    private func applyMode() {
        guard session.supportsControls, let slider = steerSlider, let speed = speedPicker,
              let ball = shopPicker, let menu = menuPicker,
              let sensitivity = settingsSpeed, let haptics = hapticsPicker else { return }
        let all: [AVCaptureControl] = [slider, speed, ball, menu, sensitivity, haptics]
        let wanted: [AVCaptureControl]
        switch mode {
        case .steer: wanted = [slider]
        case .speed: wanted = [] // Game speed is fixed; no picker.
        case .shop: wanted = [ball]
        case .menu: wanted = [menu]
        case .settings: wanted = [sensitivity, haptics]
        }
        for c in all where !wanted.contains(where: { $0 === c }) && session.controls.contains(where: { $0 === c }) {
            session.removeControl(c)
        }
        for control in wanted where !session.controls.contains(where: { $0 === control }) {
            if control === slider {
                gameEngine?.rawSteer = 0.5
                slider.value = 0.5
            } else if control === speed {
                speed.selectedIndex = min(max(gameEngine?.level ?? 1, 0), Engine.levelNames.count - 1)
            } else if control === ball {
                ball.selectedIndex = min(max(shopIndex, 0), ballSkins.count - 1)
            } else if control === menu {
                menu.selectedIndex = min(max(menuIndex, 0), 2)
            } else if control === sensitivity {
                sensitivity.value = self.sensitivity
            } else if control === haptics {
                haptics.selectedIndex = hapticsEnabled ? 1 : 0
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
                // Relative mapping: the ball moves by the slider delta times the gain.
                // A swipe delivers roughly a fixed number of steps, so the delta shrinks with the step size.
                // stepScale keeps the same feel as the earlier 0.005 step.
                let delta = CGFloat(value) - engine.rawSteer
                engine.rawSteer = CGFloat(value)
                if !engine.paused {
                    engine.target = min(max(engine.target + delta * Engine.steerGain * Engine.stepScale, 0), 1)
                }
                DispatchQueue.main.async { engine.onSteer?(CGFloat(value)) }
            }
            let picker = AVCaptureIndexPicker("Speed", symbolName: "speedometer", localizedIndexTitles: Engine.levelNames)
            picker.selectedIndex = 1
            picker.setActionQueue(queue) { [weak self] index in
                guard self?.mode == .speed else { return }
                engine.level = index
            }
            speedPicker = picker
            let ball = AVCaptureIndexPicker("Ball", symbolName: "circle.fill", localizedIndexTitles: ballSkins.map { $0.name })
            ball.selectedIndex = 0
            ball.setActionQueue(queue) { [weak self] index in
                guard self?.mode == .shop else { return }
                // Selection only. Buying always needs the hold on screen.
                DispatchQueue.main.async { engine.onShopPick?(index) }
            }
            shopPicker = ball
            let menu = AVCaptureIndexPicker("Main Menu", symbolName: "list.bullet", localizedIndexTitles: ["Play", "Shop", "Settings"])
            menu.setActionQueue(queue) { [weak self] index in
                guard let self = self, self.mode == .menu else { return }
                self.menuIndex = index
                DispatchQueue.main.async { self.onMenuPick?(index) }
            }
            menuPicker = menu
            let sensitivity = AVCaptureSlider("Speed", symbolName: "arrow.left.and.right", in: 1...7, step: 0.1)
            sensitivity.value = self.sensitivity
            sensitivity.setActionQueue(queue) { [weak self] value in
                guard let self = self, self.mode == .settings else { return }
                self.sensitivity = value
                DispatchQueue.main.async { self.onSensitivity?(Double(value)) }
            }
            settingsSpeed = sensitivity
            let haptics = AVCaptureIndexPicker("Haptics", symbolName: "waveform", localizedIndexTitles: ["Off", "On"])
            haptics.selectedIndex = hapticsEnabled ? 1 : 0
            haptics.setActionQueue(queue) { [weak self] index in
                guard let self = self, self.mode == .settings else { return }
                self.hapticsEnabled = index == 1
                DispatchQueue.main.async { self.onHaptics?(index == 1) }
            }
            hapticsPicker = haptics
            gameEngine = engine
            applyMode()
        }
        session.commitConfiguration()
        let info: String
        if session.supportsControls {
            session.setControlsDelegate(self, queue: queue)
            info = "Camera Control: \(session.controls.count) of \(session.maxControlsCount) controls registered"
        } else {
            info = "Camera Control: not supported on this device"
        }
        DispatchQueue.main.async { self.controlsInfo = info }
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

/// Receives full presses of Camera Control (and other capture buttons).
struct CaptureEventView: UIViewRepresentable {
    let engine: Engine

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let interaction = AVCaptureEventInteraction { event in
            switch event.phase {
            case .began:
                DispatchQueue.main.async { engine.pressBegan?() }
            case .ended:
                DispatchQueue.main.async { engine.pressHandler?() }
            default:
                DispatchQueue.main.async { engine.pressCancel?() }
            }
        }
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
