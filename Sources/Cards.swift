import SwiftUI

struct MenuCard: View {
    let best: Int
    let levelName: String
    let cameraStopped: Bool
    let selection: Int
    let hintVisible: Bool
    let onSettings: () -> Void
    let onShop: () -> Void
    let onStats: () -> Void
    let onDaily: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Text("Aperture")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                Text(best > 0 ? "\(levelName) · Best \(best)" : levelName)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button(action: onSettings) {
                            Image(systemName: "gearshape.fill").font(.title3).frame(width: 44, height: 44)
                                .accessibilityLabel("Settings")
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        Button(action: onStats) {
                            Image(systemName: "chart.bar.fill").font(.title3).frame(width: 44, height: 44)
                                .accessibilityLabel("Stats")
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        Button(action: onDaily) {
                            Image(systemName: "calendar").font(.title3).frame(width: 44, height: 44)
                                .accessibilityLabel("Daily challenge")
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        Button(action: onShop) {
                            Image(systemName: "circle.hexagongrid.fill").font(.title3).frame(width: 44, height: 44)
                                .accessibilityLabel("Shop")
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                    }
                }
                Text(cameraStopped ? "Camera stopped" : "Camera on, not recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 360)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .offset(y: -56)
            GeometryReader { geo in
                if hintVisible {
                    Label(selection == 0 ? "Click to play" : "Click to open " + CameraService.menuTitles[selection], systemImage: "arrow.right")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: Capsule())
                        .fixedSize()
                        // Right edge stays clear of the system label, whatever the text length.
                        .frame(width: geo.size.width - 126, alignment: .trailing)
                        .position(x: (geo.size.width - 126) / 2, y: geo.size.height * 0.662)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

struct OverCard: View {
    let score: Int
    let best: Int
    let newBest: Bool
    let daily: Bool
    let unlocked: [Achievement]
    let onBack: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(daily ? "Daily" : "Crashed").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(score)").font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
            Text(newBest ? "New best" : "Best \(best)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(newBest ? Color(red: 1.0, green: 0.82, blue: 0.30) : .secondary)
            ForEach(unlocked) { a in
                HStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                    Text(a.title)
                    Spacer(minLength: 4)
                    Image(systemName: "bolt.fill")
                    Text("+\(a.reward)").monospacedDigit()
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: Capsule())
            }
            HStack(spacing: 12) {
                Button("Back", action: onBack)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                Button("Retry", action: onRetry)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(maxWidth: 340)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}

struct PauseOverlay: View {
    let onResume: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Text("Paused")
                .font(.system(size: 40, weight: .bold, design: .rounded))
            SwipeToContinue(onDone: onResume)
                .frame(maxWidth: 300)
            Text("or click Camera Control")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}

/// The highlighted row is the active one: tap a row to pick it, Camera Control then changes its value.
struct SettingsSheet: View {
    @ObservedObject var profile: Profile
    @Binding var row: Int
    let onBack: () -> Void

    private func rowBackground(_ i: Int) -> some View {
        (row == i ? Color.white.opacity(0.14) : Color.clear)
    }

    var body: some View {
        NavigationStack {
            Form {
                VStack(alignment: .leading) {
                    Text("Steering speed")
                    Slider(value: $profile.steerGain, in: 1.0...7.0, step: 0.1) {
                        Text("Steering speed")
                    } minimumValueLabel: {
                        Text("Slower")
                    } maximumValueLabel: {
                        Text("Faster")
                    }
                }
                .listRowBackground(rowBackground(0))
                .onTapGesture { row = 0 }
                VStack(alignment: .leading) {
                    Text("Haptics")
                    Picker("Haptics", selection: $profile.hapticLevel) {
                        ForEach(0..<Profile.hapticNames.count, id: \.self) { Text(Profile.hapticNames[$0]).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(rowBackground(1))
                .onTapGesture { row = 1 }
                Toggle("Sound", isOn: $profile.soundOn)
                    .listRowBackground(rowBackground(2))
                    .onTapGesture { row = 2 }
                VStack(alignment: .leading) {
                    Text("Difficulty")
                    Picker("Difficulty", selection: $profile.difficulty) {
                        ForEach(0..<Profile.levelNames.count, id: \.self) { Text(Profile.levelNames[$0]).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(rowBackground(3))
                .onTapGesture { row = 3 }
            }
            .onChange(of: profile.steerGain) { _, _ in row = 0 }
            .onChange(of: profile.hapticLevel) { _, _ in row = 1 }
            .onChange(of: profile.soundOn) { _, _ in row = 2 }
            .onChange(of: profile.difficulty) { _, _ in row = 3 }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Back", action: onBack)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}
