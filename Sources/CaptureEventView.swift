import SwiftUI
import AVKit

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
