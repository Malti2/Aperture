import SwiftUI

/// Lifetime stats, best scores and achievements.
struct StatsView: View {
    @ObservedObject var profile: Profile
    let onBack: () -> Void

    private var playTime: String {
        let total = Int(profile.playSeconds)
        return total >= 3600 ? "\(total / 3600)h \(total % 3600 / 60)m" : "\(total / 60)m \(total % 60)s"
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(spacing: 0) {
                Text("Stats")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .padding(.top, 118)
                    .padding(.bottom, 10)
                List {
                    Section("Best") {
                        ForEach(0..<Profile.levelNames.count, id: \.self) { i in
                            stat(Profile.levelNames[i], "\(profile.bests[i])")
                        }
                        stat("Daily today", "\(profile.dailyBest)")
                    }
                    Section("Total") {
                        stat("Rounds", "\(profile.runs)")
                        stat("Floors", "\(profile.totalFloors)")
                        stat("Power-ups", "\(profile.totalPickups)")
                        stat("Play time", playTime)
                    }
                    Section("Achievements \(profile.unlocked.count)/\(allAchievements.count)") {
                        ForEach(allAchievements) { a in
                            let done = profile.unlocked.contains(a.id)
                            HStack(spacing: 12) {
                                Image(systemName: done ? "trophy.fill" : "lock.fill")
                                    .foregroundStyle(done ? Color(red: 1.0, green: 0.82, blue: 0.30) : .secondary)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(a.title).font(.headline)
                                    Text(a.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                    Text("\(a.reward)").monospacedDigit()
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .opacity(done ? 1 : 0.7)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                HStack {
                    Text("Click Camera Control to go back")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Back", action: onBack)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 14)
                .padding(.bottom, 30)
            }
        }
    }
}
