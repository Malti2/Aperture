import QuartzCore

/// Drives game logic once per display frame, separate from drawing.
final class GameLoop: NSObject {
    var onTick: ((TimeInterval) -> Void)?
    private var link: CADisplayLink?

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func tick(_ l: CADisplayLink) {
        onTick?(l.timestamp)
    }
}
