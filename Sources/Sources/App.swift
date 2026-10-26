import SwiftUI
import AVFoundation
import AVKit

enum CameraMode: String, CaseIterable, Identifiable {
    case off = "Off"
    case hidden = "Hidden"
    case preview = "Preview"
    var id: String { rawValue }
}

struct LogEntry: Identifiable {
    let id = UUID()
    let time: Date
    let text: String
}

final class CameraModel: NSObject, ObservableObject, AVCaptureSessionControlsDelegate {
    @Published var mode: CameraMode = .off
    @Published var useOutput = true
    @Published var useZoomControl = true
    @Published var interceptEnabled = true
    @Published var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var isRunning = false
    @Published var supportsControls = false
    @Published var pressBegan = 0
    @Published var pressEnded = 0
    @Published var controlEvents = 0
    @Published var log: [LogEntry] = []

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.session")

    override init() {
        super.init()
        NotificationCenter.default.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main) { [weak self] _ in
            self?.isRunning = true
            self?.add("session started")
        }
        NotificationCenter.default.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: session, queue: .main) { [weak self] _ in
            self?.isRunning = false
            self?.add("session stopped")
        }
        NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] note in
            let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self?.add("session error: \(err?.localizedDescription ?? "unknown")")
        }
    }

    func add(_ text: String) {
        log.insert(LogEntry(time: Date(), text: text), at: 0)
        if log.count > 60 { log.removeLast() }
    }

    func clear() {
        log.removeAll()
        pressBegan = 0
        pressEnded = 0
        controlEvents = 0
    }

    func record(phase: AVCaptureEventPhase) {
        switch phase {
        case .began:
            pressBegan += 1
            add("button event: began")
        case .ended:
            pressEnded += 1
            add("button event: ended")
        case .cancelled:
            add("button event: cancelled")
        @unknown default:
            add("button event: unknown phase")
        }
    }

    func apply() {
        authorization = AVCaptureDevice.authorizationStatus(for: .video)
        if mode == .off {
            stop()
            return
        }
        switch authorization {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.authorization = AVCaptureDevice.authorizationStatus(for: .video)
                    self.add(granted ? "camera access granted" : "camera access denied")
                    if granted && self.mode != .off { self.start() }
                }
            }
        default:
            add("camera access is denied. Allow it in Settings.")
        }
    }

    private func start() {
        let withOutput = useOutput
        let withZoom = useZoomControl
        queue.async { [weak self] in
            guard let self = self else { return }
            let session = self.session
            if session.isRunning { session.stopRunning() }
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            session.controls.forEach { session.removeControl($0) }
            session.sessionPreset = .low
            var msg = "configured"
            if let device = AVCaptureDevice.default(for: .video),
               let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
                if withOutput {
                    let output = AVCaptureVideoDataOutput()
                    if session.canAddOutput(output) { session.addOutput(output) }
                }
                if withZoom && session.supportsControls {
                    let slider = AVCaptureSystemZoomSlider(device: device) { [weak self] factor in
                        DispatchQueue.main.async {
                            self?.controlEvents += 1
                            self?.add("zoom slider moved: \(String(format: "%.2f", Double(factor)))")
                        }
                    }
                    if session.canAddControl(slider) { session.addControl(slider) }
                    session.setControlsDelegate(self, queue: self.queue)
                }
                msg = "configured (output: \(withOutput), zoom control: \(withZoom && session.supportsControls))"
            } else {
                msg = "no camera input available"
            }
            session.commitConfiguration()
            let supports = session.supportsControls
            DispatchQueue.main.async {
                self.supportsControls = supports
                self.add(msg)
            }
            session.startRunning()
        }
    }

    private func stop() {
        queue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: AVCaptureSessionControlsDelegate
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        DispatchQueue.main.async { self.controlEvents += 1; self.add("controls: active (light press)") }
    }
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        DispatchQueue.main.async { self.add("controls: entering fullscreen") }
    }
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        DispatchQueue.main.async { self.add("controls: leaving fullscreen") }
    }
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        DispatchQueue.main.async { self.add("controls: inactive") }
    }
}

struct CaptureEventView: UIViewRepresentable {
    let model: CameraModel
    let enabled: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let interaction = AVCaptureEventInteraction { event in
            let phase = event.phase
            DispatchQueue.main.async { model.record(phase: phase) }
        }
        interaction.isEnabled = enabled
        view.addInteraction(interaction)
        context.coordinator.interaction = interaction
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.interaction?.isEnabled = enabled
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var interaction: AVCaptureEventInteraction? }
}

struct PreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewUIView {
        let v = PreviewUIView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

struct ContentView: View {
    @StateObject private var model = CameraModel()
    @Environment(\.scenePhase) private var scenePhase

    private var authText: String {
        switch model.authorization {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Camera permission", value: authText)
                    LabeledContent("Camera session running", value: model.isRunning ? "Yes" : "No")
                    LabeledContent("Session controls supported", value: model.supportsControls ? "Yes" : "No / not checked")
                    LabeledContent("Button interception", value: model.interceptEnabled ? "On" : "Off")
                }
                Section("Setup") {
                    Picker("Camera", selection: $model.mode) {
                        ForEach(CameraMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: model.mode) { _, _ in model.apply() }
                    Toggle("Video output (frames discarded)", isOn: $model.useOutput)
                        .onChange(of: model.useOutput) { _, _ in if model.mode != .off { model.apply() } }
                    Toggle("Zoom slider control", isOn: $model.useZoomControl)
                        .onChange(of: model.useZoomControl) { _, _ in if model.mode != .off { model.apply() } }
                    Toggle("Intercept button events", isOn: $model.interceptEnabled)
                }
                if model.mode == .preview {
                    Section {
                        PreviewView(session: model.session)
                            .frame(height: 180)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                Section("Result") {
                    LabeledContent("Button events: began", value: "\(model.pressBegan)")
                    LabeledContent("Button events: ended", value: "\(model.pressEnded)")
                    LabeledContent("Light press / swipe events", value: "\(model.controlEvents)")
                    Button("Clear counters and log", role: .destructive) { model.clear() }
                }
                Section {
                    Text("Press Camera Control fully, lightly and with a swipe. A full press, the volume-down button and the Action button all arrive as the same button event, so test each one alone. Light press and swipe events only come from Camera Control.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Log") {
                    if model.log.isEmpty {
                        Text("No events yet").foregroundStyle(.secondary)
                    }
                    ForEach(model.log) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(entry.time, format: .dateTime.hour().minute().second())
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Text(entry.text).font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("Camera Control Test")
            .background(CaptureEventView(model: model, enabled: model.interceptEnabled).allowsHitTesting(false))
            .onChange(of: scenePhase) { _, phase in
                model.add("app is \(phase)")
            }
        }
    }
}

@main
struct CameraControlTestApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
