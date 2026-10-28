import SwiftUI

/// Lightning balance on top, status chips, pause and dash while playing.
struct HUDView: View {
    let engine: Engine
    let bank: Int
    let playing: Bool
    let onPause: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 10) {
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
                    if playing {
                        TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                            statusRow
                        }
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

    private func chip(_ symbol: String, _ text: String?, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            if let text { Text(text).monospacedDigit() }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if engine.multiplier > 1 {
                chip("flame.fill", "x\(engine.multiplier)", Color(red: 1.0, green: 0.68, blue: 0.30))
            }
            if engine.shield { chip(PowerUp.shield.symbol, nil, PowerUp.shield.color) }
            if engine.magnetLeft > 0 { chip(PowerUp.magnet.symbol, String(format: "%.0f", ceil(engine.magnetLeft)), PowerUp.magnet.color) }
            if engine.slowLeft > 0 { chip(PowerUp.slow.symbol, String(format: "%.0f", ceil(engine.slowLeft)), PowerUp.slow.color) }
            Spacer()
        }
        .frame(height: 32)
    }
}
