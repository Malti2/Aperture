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
    private var steerSlider: AVCaptureSlider?
    private var speedPicker: AVCaptureIndexPicker?
    private var shopPicker: AVCaptureIndexPicker?
    private var shopIndex = 0
    private weak var gameEngine: Engine?

    /// Which Camera Control entry is shown. Steer while playing, a ball picker in the shop, Speed everywhere else.
    enum ControlMode { case steer, speed, shop }
    private var mode: ControlMode = .speed

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main) { [weak self] _ in
            self?.running = true
        }
        NotificationCenter.default.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: session, queue: .main) { [weak self] _ in
            self?.running = false
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

    func start(engine: Engine) {
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        guard authorization == .authorized else { return }
        queue.async { [weak self] in
            guard let self = self else { return }
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

    /// Runs on the camera queue.
    private func applyMode() {
        guard session.supportsControls, let slider = steerSlider, let speed = speedPicker, let ball = shopPicker else { return }
        let all: [AVCaptureControl] = [slider, speed, ball]
        let wanted: AVCaptureControl
        switch mode {
        case .steer: wanted = slider
        case .speed: wanted = speed
        case .shop: wanted = ball
        }
        for c in all where c !== wanted && session.controls.contains(where: { $0 === c }) {
            session.removeControl(c)
        }
        guard !session.controls.contains(where: { $0 === wanted }) else { return }
        switch mode {
        case .steer:
            // A fresh slider starts in the middle, so steering stays relative to this moment.
            gameEngine?.rawSteer = 0.5
            slider.value = 0.5
        case .speed:
            speed.selectedIndex = min(max(gameEngine?.level ?? 1, 0), Engine.levelNames.count - 1)
        case .shop:
            ball.selectedIndex = min(max(shopIndex, 0), ballSkins.count - 1)
        }
        if session.canAddControl(wanted) { session.addControl(wanted) }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure(engine: Engine) {
        session.beginConfiguration()
        session.sessionPreset = .low
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            if session.canAddOutput(output) { session.addOutput(output) }
        }
        if session.supportsControls {
            let slider = AVCaptureSlider("Steer", symbolName: "arrow.left.and.right", in: 0...1, step: 0.001)
            slider.value = 0.5
            steerSlider = slider
            slider.setActionQueue(queue) { value in
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
            picker.setActionQueue(queue) { index in
                engine.level = index
            }
            speedPicker = picker
            let ball = AVCaptureIndexPicker("Ball", symbolName: "circle.fill", localizedIndexTitles: ballSkins.map { $0.name })
            ball.selectedIndex = 0
            ball.setActionQueue(queue) { index in
                // Selection only. Buying always needs the hold on screen.
                DispatchQueue.main.async { engine.onShopPick?(index) }
            }
            shopPicker = ball
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
