import SwiftUI

struct BallSkin {
    let name: String
    let color: Color
    let cost: Int
}

/// Prototype prices. Not final.
let ballSkins: [BallSkin] = [
    BallSkin(name: "White", color: .white, cost: 0),
    BallSkin(name: "Light Blue", color: Color(red: 0.35, green: 0.62, blue: 0.95), cost: 150),
    BallSkin(name: "Red", color: Color(red: 0.85, green: 0.30, blue: 0.30), cost: 300),
    BallSkin(name: "Golden Orange", color: Color(red: 0.95, green: 0.68, blue: 0.25), cost: 450),
    BallSkin(name: "Mint Green", color: Color(red: 0.30, green: 0.80, blue: 0.55), cost: 600),
    BallSkin(name: "Violet", color: Color(red: 0.62, green: 0.45, blue: 0.95), cost: 800)
]
