import SwiftUI

struct ShopItem {
    let name: String
    let cost: Int
    let color: Color
    var rainbow = false
}

struct Theme {
    let name: String
    let cost: Int
    let top: Color
    let bottom: Color
    let accent: Color
}

private func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

/// Prototype prices. Not final.
let ballSkins: [ShopItem] = [
    ShopItem(name: "White", cost: 0, color: .white),
    ShopItem(name: "Light Blue", cost: 150, color: rgb(0.35, 0.62, 0.95)),
    ShopItem(name: "Red", cost: 300, color: rgb(0.85, 0.30, 0.30)),
    ShopItem(name: "Golden Orange", cost: 450, color: rgb(0.95, 0.68, 0.25)),
    ShopItem(name: "Mint Green", cost: 600, color: rgb(0.30, 0.80, 0.55)),
    ShopItem(name: "Violet", cost: 800, color: rgb(0.62, 0.45, 0.95))
]

let trailSkins: [ShopItem] = [
    ShopItem(name: "Classic", cost: 0, color: .white),
    ShopItem(name: "Aqua", cost: 120, color: rgb(0.42, 0.80, 1.0)),
    ShopItem(name: "Rose", cost: 240, color: rgb(1.0, 0.50, 0.70)),
    ShopItem(name: "Lime", cost: 360, color: rgb(0.70, 1.0, 0.35)),
    ShopItem(name: "Gold", cost: 500, color: rgb(1.0, 0.82, 0.30)),
    ShopItem(name: "Rainbow", cost: 700, color: rgb(0.85, 0.55, 1.0), rainbow: true)
]

let themes: [Theme] = [
    Theme(name: "Midnight", cost: 0, top: rgb(0.03, 0.03, 0.07), bottom: rgb(0.07, 0.08, 0.16), accent: rgb(0.42, 0.80, 1.0)),
    Theme(name: "Sunset", cost: 200, top: rgb(0.10, 0.04, 0.08), bottom: rgb(0.28, 0.10, 0.14), accent: rgb(1.0, 0.62, 0.40)),
    Theme(name: "Forest", cost: 350, top: rgb(0.02, 0.07, 0.05), bottom: rgb(0.05, 0.17, 0.12), accent: rgb(0.45, 0.95, 0.65)),
    Theme(name: "Mono", cost: 500, top: rgb(0.04, 0.04, 0.04), bottom: rgb(0.14, 0.14, 0.14), accent: rgb(0.90, 0.90, 0.90)),
    Theme(name: "Aurora", cost: 800, top: rgb(0.04, 0.03, 0.12), bottom: rgb(0.04, 0.20, 0.22), accent: rgb(0.75, 0.55, 1.0))
]

enum ShopCategory: Int, CaseIterable {
    case ball, trail, theme

    var title: String { ["Balls", "Trails", "Themes"][rawValue] }
    var symbol: String { ["circle.fill", "sparkles", "paintpalette.fill"][rawValue] }
    var items: [ShopItem] {
        switch self {
        case .ball: return ballSkins
        case .trail: return trailSkins
        case .theme: return themes.map { ShopItem(name: $0.name, cost: $0.cost, color: $0.accent) }
        }
    }
}
