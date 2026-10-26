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
            if !self.session.isRunning { self.session.startRunning() }
        }
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
            let slider = AVCaptureSlider("Steer", symbolName: "arrow.left.and.right", in: 0...1)
            slider.value = 0.5
            slider.setActionQueue(queue) { value in
                engine.target = CGFloat(value)
                DispatchQueue.main.async { engine.onSteer?(CGFloat(value)) }
            }
            if session.canAddControl(slider) { session.addControl(slider) }
            // A second control. A double light press on Camera Control switches between controls.
            let picker = AVCaptureIndexPicker("Speed", symbolName: "speedometer", localizedIndexTitles: Engine.levelNames)
            picker.selectedIndex = 1
            picker.setActionQueue(queue) { index in
                engine.level = index
            }
            if session.canAddControl(picker) { session.addControl(picker) }
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
            if event.phase == .ended {
                DispatchQueue.main.async { engine.pressHandler?() }
            }
        }
        view.addInteraction(interaction)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
