import UIKit
import AudioToolbox

/// Haptics and sounds in one place, so Settings can scale or mute them.
enum Feedback {
    /// 0 off, 1 soft, 2 strong.
    static var hapticLevel = 2
    static var soundOn = true

    enum Sound: UInt32 {
        case floor = 1057, pickup = 1104, dash = 1105, crash = 1053
    }

    static func play(_ sound: Sound) {
        guard soundOn else { return }
        AudioServicesPlaySystemSound(sound.rawValue)
    }

    static func select() {
        guard hapticLevel > 0 else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .rigid) {
        guard hapticLevel > 0 else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: hapticLevel == 1 ? 0.45 : 1)
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        switch hapticLevel {
        case 2: UINotificationFeedbackGenerator().notificationOccurred(type)
        case 1: UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.6)
        default: break
        }
    }
}
