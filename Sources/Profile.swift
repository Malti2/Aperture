import SwiftUI

struct Achievement: Identifiable {
    let id: String
    let title: String
    let detail: String
    let reward: Int
}

let allAchievements: [Achievement] = [
    Achievement(id: "first", title: "First Run", detail: "Finish a round", reward: 20),
    Achievement(id: "floors25", title: "Climber", detail: "Pass 25 floors in one round", reward: 30),
    Achievement(id: "floors50", title: "Skyscraper", detail: "Pass 50 floors in one round", reward: 60),
    Achievement(id: "score500", title: "Warm Up", detail: "Score 500", reward: 30),
    Achievement(id: "score1500", title: "In The Zone", detail: "Score 1500", reward: 80),
    Achievement(id: "dash3", title: "Triple Dash", detail: "Dash 3 times in one round", reward: 30),
    Achievement(id: "combo4", title: "Flow State", detail: "Reach the x4 multiplier", reward: 40),
    Achievement(id: "collector", title: "Collector", detail: "Pick up 10 power-ups", reward: 40),
    Achievement(id: "shield", title: "Close Call", detail: "Survive a hit with a shield", reward: 30),
    Achievement(id: "regular", title: "Regular", detail: "Play 25 rounds", reward: 50),
    Achievement(id: "daily", title: "Daily Driver", detail: "Finish a daily challenge round", reward: 30)
]

struct RoundResult {
    let score: Int
    let floors: Int
    let dashes: Int
    let maxMultiplier: Int
    let pickups: Int
    let shieldSaves: Int
    let seconds: Double
    let daily: Bool
    let level: Int
}

/// Everything that is saved on the device: balance, shop, settings, stats and achievements.
final class Profile: ObservableObject {
    static let ownedKeys = ["owned", "ownedTrails", "ownedThemes"]
    static let equippedKeys = ["equipped", "equippedTrail", "equippedTheme"]
    static let levelNames = ["Calm", "Normal", "Fast"]
    static let hapticNames = ["Off", "Soft", "Strong"]

    private let d = UserDefaults.standard

    @Published var bank: Int { didSet { d.set(bank, forKey: "bank") } }
    @Published private(set) var owned: [Set<Int>] {
        didSet {
            for (i, key) in Profile.ownedKeys.enumerated() {
                d.set(owned[i].sorted().map(String.init).joined(separator: ","), forKey: key)
            }
        }
    }
    @Published private(set) var equipped: [Int] {
        didSet { for (i, key) in Profile.equippedKeys.enumerated() { d.set(equipped[i], forKey: key) } }
    }

    // Settings. The old range ended at 4.0, so the key is versioned.
    @Published var steerGain: Double { didSet { d.set(steerGain, forKey: "steerGainV2") } }
    @Published var hapticLevel: Int {
        didSet { d.set(hapticLevel, forKey: "hapticLevel"); Feedback.hapticLevel = hapticLevel }
    }
    @Published var soundOn: Bool {
        didSet { d.set(soundOn, forKey: "soundOn"); Feedback.soundOn = soundOn }
    }
    @Published var difficulty: Int { didSet { d.set(difficulty, forKey: "difficulty") } }

    // Stats
    @Published private(set) var bests: [Int]
    @Published private(set) var dailyBest: Int
    @Published private(set) var runs: Int
    @Published private(set) var totalFloors: Int
    @Published private(set) var totalPickups: Int
    @Published private(set) var playSeconds: Double
    @Published private(set) var unlocked: Set<String>

    init() {
        let d = UserDefaults.standard
        bank = d.integer(forKey: "bank")
        owned = Profile.ownedKeys.map { key in
            let raw = d.string(forKey: key) ?? "0"
            return Set(raw.split(separator: ",").compactMap { Int($0) }).union([0])
        }
        equipped = Profile.equippedKeys.map { d.integer(forKey: $0) }
        steerGain = d.object(forKey: "steerGainV2") as? Double ?? 4.0
        if let level = d.object(forKey: "hapticLevel") as? Int {
            hapticLevel = level
        } else if let old = d.object(forKey: "haptics") as? Bool {
            hapticLevel = old ? 2 : 0
        } else {
            hapticLevel = 2
        }
        soundOn = d.object(forKey: "soundOn") as? Bool ?? true
        difficulty = min(max(d.object(forKey: "difficulty") as? Int ?? 1, 0), 2)
        bests = [d.integer(forKey: "best_0"), d.object(forKey: "best_1") as? Int ?? d.integer(forKey: "best"), d.integer(forKey: "best_2")]
        dailyBest = d.integer(forKey: "dailyBest_\(Profile.dailyKey)")
        runs = d.integer(forKey: "runs")
        totalFloors = d.integer(forKey: "totalFloors")
        totalPickups = d.integer(forKey: "totalPickups")
        playSeconds = d.double(forKey: "playSeconds")
        unlocked = Set((d.string(forKey: "achievements") ?? "").split(separator: ",").map(String.init))
        Feedback.hapticLevel = hapticLevel
        Feedback.soundOn = soundOn
    }

    // MARK: Daily challenge

    /// yyyyMMdd of today, the same for everyone on the same day.
    static var dailyKey: Int {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    static var dailySeed: UInt64 { UInt64(dailyKey) &* 2654435761 }

    func refreshDaily() {
        dailyBest = d.integer(forKey: "dailyBest_\(Profile.dailyKey)")
    }

    // MARK: Shop

    /// Demo and test helper: hands out an item without paying.
    func grant(_ c: ShopCategory, _ i: Int) { owned[c.rawValue].insert(i) }

    func owns(_ c: ShopCategory, _ i: Int) -> Bool { owned[c.rawValue].contains(i) }
    func equippedIndex(_ c: ShopCategory) -> Int { min(max(equipped[c.rawValue], 0), c.items.count - 1) }

    func equip(_ c: ShopCategory, _ i: Int) {
        guard owns(c, i) else { return }
        equipped[c.rawValue] = i
    }

    /// Pays and equips. False when already owned or too expensive.
    @discardableResult
    func buy(_ c: ShopCategory, _ i: Int) -> Bool {
        let cost = c.items[i].cost
        guard !owns(c, i), bank >= cost else { return false }
        bank -= cost
        owned[c.rawValue].insert(i)
        equipped[c.rawValue] = i
        return true
    }

    // MARK: Rounds

    var best: Int { bests[difficulty] }

    private func earned(_ id: String, _ r: RoundResult) -> Bool {
        switch id {
        case "first": return runs >= 1
        case "floors25": return r.floors >= 25
        case "floors50": return r.floors >= 50
        case "score500": return r.score >= 500
        case "score1500": return r.score >= 1500
        case "dash3": return r.dashes >= 3
        case "combo4": return r.maxMultiplier >= 4
        case "collector": return totalPickups >= 10
        case "shield": return r.shieldSaves >= 1
        case "regular": return runs >= 25
        case "daily": return r.daily
        default: return false
        }
    }

    /// Saves stats and best scores, pays out new achievements. Returns whether it is a new best and what unlocked.
    func record(_ r: RoundResult) -> (newBest: Bool, unlocked: [Achievement]) {
        runs += 1
        totalFloors += r.floors
        totalPickups += r.pickups
        playSeconds += r.seconds
        d.set(runs, forKey: "runs")
        d.set(totalFloors, forKey: "totalFloors")
        d.set(totalPickups, forKey: "totalPickups")
        d.set(playSeconds, forKey: "playSeconds")

        var newBest = false
        if r.daily {
            if r.score > dailyBest {
                dailyBest = r.score
                d.set(dailyBest, forKey: "dailyBest_\(Profile.dailyKey)")
                newBest = true
            }
        } else if r.score > bests[r.level] {
            bests[r.level] = r.score
            d.set(r.score, forKey: "best_\(r.level)")
            newBest = true
        }

        let fresh = allAchievements.filter { !unlocked.contains($0.id) && earned($0.id, r) }
        if !fresh.isEmpty {
            for a in fresh {
                unlocked.insert(a.id)
                bank += a.reward
            }
            d.set(unlocked.sorted().joined(separator: ","), forKey: "achievements")
        }
        return (newBest, fresh)
    }
}
