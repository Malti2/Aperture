import SwiftUI

/// Lightning balance on top, pause and dash while playing.
struct HUDView: View {
    let engine: Engine
    let bank: Int
    let playing: Bool
    let onPause: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Label("\(bank)", systemImage: "bolt.fill")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .glassEffect(.regular, in: .capsule)
                    Spacer()
                    if playing {
                        Button(action: onPause) {
                            Image(systemName: "pause.fill").frame(width: 38, height: 38)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 62)
            Spacer()
            if playing {
                TimelineView(.periodic(from: .now, by: 0.05)) { _ in
                    Button {
                        engine.dash()
                    } label: {
                        ZStack {
                            Circle()
                                .trim(from: 0, to: engine.charge)
                                .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 44, height: 44)
                            Image(systemName: "bolt.fill").font(.title3)
                        }
                        .frame(width: 60, height: 60)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .padding(.bottom, 40)
                }
            }
        }
    }
}
