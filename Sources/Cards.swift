import SwiftUI

let menuTitles = ["Play", "Shop", "Settings"]

struct MenuCard: View {
    let best: Int
    let cameraStopped: Bool
    let selection: Int
    let hintVisible: Bool
    let onSettings: () -> Void
    let onShop: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Text("Aperture")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                if best > 0 {
                    Text("Best \(best)").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape.fill").font(.title3).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    Button(action: onShop) {
                        Label("Shop", systemImage: "circle.hexagongrid.fill")
                            .font(.headline)
                            .padding(.horizontal, 6)
                            .frame(height: 44)
                    }
                    .buttonStyle(.glass)
                }
                Text(cameraStopped ? "Camera stopped" : "Camera on, not recorded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(28)
            .frame(maxWidth: 320)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .offset(y: -56)
            GeometryReader { geo in
                if hintVisible {
                    Label(selection == 0 ? "Click to play" : "Click to open " + menuTitles[selection], systemImage: "arrow.right")
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
    let onBack: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Crashed").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("\(score)").font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
            Text("Best \(best)").font(.headline.monospacedDigit()).foregroundStyle(.secondary)
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
        .frame(maxWidth: 320)
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
        }
        .padding(28)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
    }
}

struct SettingsSheet: View {
    @Binding var steerGain: Double
    @Binding var haptics: Bool
    let onBack: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        Text("Steering speed")
                        Slider(value: $steerGain, in: 1.0...7.0, step: 0.1) {
                            Text("Steering speed")
                        } minimumValueLabel: {
                            Text("Slower")
                        } maximumValueLabel: {
                            Text("Faster")
                        }
                    }
                    Toggle("Haptics", isOn: $haptics)
                }
            }
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
